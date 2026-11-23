//
//  SegmentDownloader.swift
//  Download Manager for Mac
//
//  Multi-threaded (HTTP Range) downloader with REAL pause / resume.
//
//  Design
//  ------
//  * Every segment streams into its own stable file:  <work dir>/seg_<i>.part
//    The number of bytes already downloaded is simply the size of that file, so
//    pause, stop, app quit and relaunch all keep the data and resume continues
//    with `Range: bytes=<start+have>-<end>`.
//  * A tiny `meta.json` records the file size / ETag / segment count. If the
//    server file changed since the partial data was written, it is discarded.
//  * The engine NEVER decides the task state on its own (except "completed").
//    Pause / stop / cancel are owned by DownloadManager; the engine only stops
//    (throws CancellationError) when asked. This removes the old races where a
//    late async state write overwrote the user's action.
//  * Each segment retries transient failures with exponential back-off.
//  * Optional global speed limit through `BandwidthGate`.
//

import Foundation

// MARK: - Errors

enum SegmentError: Error {
    case invalidResponse
    case invalidURL
    case fileNotFound
    case insufficientSpace
    case networkError
    case permissionDenied
    case cancelled
    case badStatus(Int)
    case rangeNotHonored
    case incomplete(expected: Int64, actual: Int64)
}

extension SegmentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:  return "The server sent an invalid response."
        case .invalidURL:       return "The download URL is invalid."
        case .fileNotFound:     return "The file was not found."
        case .insufficientSpace:return "Not enough free disk space."
        case .networkError:     return "A network error occurred."
        case .permissionDenied: return "Permission denied while writing the file."
        case .cancelled:        return "The download was cancelled."
        case .badStatus(let c): return "The server answered with HTTP \(c)."
        case .rangeNotHonored:  return "The server does not support resuming this download."
        case .incomplete(let e, let a):
            return "The connection closed early (\(a) of \(e) bytes)."
        }
    }
}

// MARK: - Global speed limit (thread-safe, readable from any thread)

/// DownloadManager is @MainActor, but the engine runs on background threads.
/// This tiny lock-protected box carries the limit across that boundary.
final class BandwidthGate: @unchecked Sendable {
    static let shared = BandwidthGate()

    private let lock = NSLock()
    private var _limit: Int64?
    private var _active: Int = 1
    private var _taskLimits: [UUID: Int64] = [:]

    /// Global limit in bytes/second, nil = unlimited.
    var limit: Int64? {
        get { lock.lock(); defer { lock.unlock() }; return _limit }
        set { lock.lock(); _limit = newValue; lock.unlock() }
    }

    /// Number of downloads currently running (the limit is shared between them).
    var activeDownloads: Int {
        get { lock.lock(); defer { lock.unlock() }; return _active }
        set { lock.lock(); _active = max(1, newValue); lock.unlock() }
    }

    /// Bytes/second ONE download may use right now, nil = unlimited.
    var perDownloadRate: Int64? {
        lock.lock(); defer { lock.unlock() }
        guard let l = _limit, l > 0 else { return nil }
        return max(1, l / Int64(max(1, _active)))
    }

    /// Live per-download cap chosen in the progress window. nil clears it.
    func setTaskLimit(_ bytesPerSecond: Int64?, for taskId: UUID) {
        lock.lock(); defer { lock.unlock() }
        if let bytes = bytesPerSecond, bytes > 0 {
            _taskLimits[taskId] = bytes
        } else {
            _taskLimits.removeValue(forKey: taskId)
        }
    }

    func taskLimit(for taskId: UUID) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        return _taskLimits[taskId]
    }
}

/// Paces all segments of one download to the current per-download rate.
final class RateLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var nextFree: TimeInterval = 0
    /// Limit captured at start (e.g. from its schedule), bytes/second.
    private let taskLimit: Int64?
    /// Reads the progress window's live limit on every reserve.
    private let taskId: UUID?

    init(taskID: UUID? = nil, taskLimit: Int64? = nil) {
        self.taskId = taskID
        self.taskLimit = taskLimit
    }

    /// True while any speed limit applies (a low speed is then intended, not a stall).
    var isLimiting: Bool {
        let shared = BandwidthGate.shared.perDownloadRate
        let live = taskId.flatMap { BandwidthGate.shared.taskLimit(for: $0) }
        return shared != nil || (live ?? taskLimit) != nil
    }

    /// Registers `bytes` as received and returns how long the caller should
    /// pause before receiving more (0 = no pause).
    func reserve(bytes: Int) -> TimeInterval {
        let shared = BandwidthGate.shared.perDownloadRate
        let live = taskId.flatMap { BandwidthGate.shared.taskLimit(for: $0) }
        let rate: Int64
        switch (shared, live ?? taskLimit) {
        case let (g?, t?): rate = min(g, t)
        case let (g?, nil): rate = g
        case let (nil, t?): rate = t
        default: return 0
        }
        guard rate > 0 else { return 0 }
        lock.lock(); defer { lock.unlock() }
        let now = Date().timeIntervalSinceReferenceDate
        if nextFree < now - 0.5 { nextFree = now - 0.5 }   // allow ≤0.5 s burst
        nextFree += Double(bytes) / Double(rate)
        return max(0, nextFree - now)
    }
}

// MARK: - Progress aggregation

final class ProgressTracker: @unchecked Sendable {
    struct Snapshot {
        let segments: [Int64]
        let total: Int64
        let speed: Int64
    }

    private let lock = NSLock()
    private var perSegment: [Int64]
    private var lastPublish: TimeInterval = 0
    private var lastTime: TimeInterval
    private var lastBytes: Int64
    private var smoothed: Double = 0

    init(initial: [Int64]) {
        perSegment = initial.isEmpty ? [0] : initial
        lastBytes = perSegment.reduce(0, +)
        lastTime = Date().timeIntervalSinceReferenceDate
    }

    func set(index: Int, bytes: Int64) {
        lock.lock(); defer { lock.unlock() }
        if index < perSegment.count { perSegment[index] = bytes }
    }

    /// Adds received bytes. Returns a snapshot at most every 0.25 s.
    func add(index: Int, delta: Int64) -> Snapshot? {
        lock.lock(); defer { lock.unlock() }
        if index < perSegment.count { perSegment[index] += delta }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastPublish >= 0.25 else { return nil }
        return makeSnapshot(now: now)
    }

    func current() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return makeSnapshot(now: Date().timeIntervalSinceReferenceDate)
    }

    private func makeSnapshot(now: TimeInterval) -> Snapshot {
        let total = perSegment.reduce(0, +)
        let dt = now - lastTime
        if dt > 0.05 {
            let inst = max(0, Double(total - lastBytes) / dt)
            smoothed = smoothed == 0 ? inst : smoothed * 0.6 + inst * 0.4
            lastTime = now
            lastBytes = total
        }
        lastPublish = now
        return Snapshot(segments: perSegment, total: total, speed: Int64(max(0, smoothed)))
    }
}

// MARK: - SegmentDownloader

/// Hands out the indices of the chunks still to download, one at a time.
final class ChunkQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Int]
    init(_ items: [Int]) { self.items = items }
    func next() -> Int? {
        lock.lock(); defer { lock.unlock() }
        return items.isEmpty ? nil : items.removeFirst()
    }
}

final class SegmentDownloader: @unchecked Sendable {

    // Tunables
    private static let minSegmentedSize: Int64 = 1_024 * 1_024      // below this: single stream
    private static let minSegmentBytes: Int64  = 512 * 1_024        // never make segments smaller
    private static let maxSegments = 32
    private static let maxAttempts = 4                              // 1 try + 3 retries
    private static let defaultUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // Immutable snapshot of what we need from the task (read on the main actor in init)
    private let downloadTask: DownloadTask
    private let originalURL: URL
    private let headers: [String: String]
    private let workDirectory: URL

    // Stop handling
    private let lock = NSLock()
    private var stopRequested = false
    private var sessions: [SegmentSession] = []
    private var restartedSessions = Set<ObjectIdentifier>()   // cancelled on purpose to reconnect
    private let limiter: RateLimiter

    /// Folder that keeps the partial data of a download between runs.
    static func workDirectory(for id: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DownloadManager", isDirectory: true)
            .appendingPathComponent("Partial", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Remove all partial data of a download (used when the task is deleted).
    static func discardPartialData(for id: UUID) {
        try? FileManager.default.removeItem(at: workDirectory(for: id))
    }

    init(downloadTask: DownloadTask) {
        self.downloadTask = downloadTask
        self.originalURL = downloadTask.url
        self.headers = downloadTask.requestHeaders
        self.workDirectory = SegmentDownloader.workDirectory(for: downloadTask.id)
        self.limiter = RateLimiter(taskID: downloadTask.id, taskLimit: downloadTask.bandwidthLimit)
    }

    // MARK: Public API

    /// Runs until the file is complete. Throws `CancellationError` when
    /// paused / stopped / cancelled; any other error is a real failure.
    func start() async throws {
        try throwIfStopped()
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let probe = try await probeServer()
        try throwIfStopped()

        await MainActor.run {
            if probe.size > 0 { downloadTask.totalBytes = probe.size }
            downloadTask.supportsResume = probe.supportsRanges
            if let name = probe.suggestedName,
               downloadTask.filename == downloadTask.url.lastPathComponent {
                downloadTask.filename = name
            }
        }

        if probe.supportsRanges && probe.size >= Self.minSegmentedSize {
            do {
                try await runSegmented(url: probe.finalURL, probe: probe)
            } catch SegmentError.rangeNotHonored {
                // The server ignored Range after all → plain single stream from scratch.
                wipePartialFiles()
                await MainActor.run {
                    downloadTask.supportsResume = false
                    downloadTask.segments = []
                }
                try await runSingle(url: probe.finalURL, probe: probe, canResume: false)
            }
        } else {
            try await runSingle(url: probe.finalURL, probe: probe, canResume: probe.supportsRanges)
        }
    }

    /// Stop the transfer but KEEP the partial data so it can be resumed.
    func pause() { requestStop() }

    /// Stop the transfer and DELETE the partial data.
    func cancel() {
        requestStop()
        try? FileManager.default.removeItem(at: workDirectory)
    }

    // MARK: Stop helpers

    private func requestStop() {
        lock.lock()
        stopRequested = true
        let running = sessions
        lock.unlock()
        for s in running { s.cancel() }
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopRequested
    }

    private func throwIfStopped() throws {
        if isStopped || Task.isCancelled { throw CancellationError() }
    }

    private func track(_ s: SegmentSession) {
        lock.lock(); sessions.append(s); lock.unlock()
    }

    private func untrack(_ s: SegmentSession) {
        lock.lock()
        sessions.removeAll { $0 === s }
        restartedSessions.remove(ObjectIdentifier(s))
        lock.unlock()
    }

    private func wasRestarted(_ s: SegmentSession) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return restartedSessions.contains(ObjectIdentifier(s))
    }

    /// Drops every open connection; each range reopens from the bytes already on disk.
    private func reconnectAll() {
        lock.lock()
        let running = sessions
        for s in running { restartedSessions.insert(ObjectIdentifier(s)) }
        lock.unlock()
        for s in running { s.cancel() }
    }

    /// Reconnects when a fast download suddenly crawls (see reconnectAll).
    private func watchSpeed(tracker: ProgressTracker, size: Int64) async {
        var peak = 0.0
        var slowSince: Date?
        var lastRestart = Date.distantPast
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if isStopped || Task.isCancelled { return }
            let snap = tracker.current()
            let speed = Double(snap.speed)
            peak = max(speed, peak * 0.97)                       // remembers ~1 minute
            let remaining = size - snap.total
            guard !limiter.isLimiting, remaining > 1_000_000, peak > 150_000 else { slowSince = nil; continue }
            if speed < peak * 0.25 {
                if slowSince == nil { slowSince = Date() }
                if Date().timeIntervalSince(slowSince!) >= 8,
                   Date().timeIntervalSince(lastRestart) >= 30 {
                    YtDlpLog.log("download: speed fell from \(Int(peak / 1024)) to \(Int(speed / 1024)) KB/s, reconnecting")
                    reconnectAll()
                    lastRestart = Date()
                    slowSince = nil
                }
            } else {
                slowSince = nil
            }
        }
    }

    // MARK: Request building

    private func makeRequest(url: URL, range: String?, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 60
        req.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        // No transparent gzip: it would make byte offsets / lengths meaningless.
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let originHost = originalURL.host?.lowercased()
        let targetHost = url.host?.lowercased()
        for (key, value) in headers {
            if key.caseInsensitiveCompare("Cookie") == .orderedSame {
                // Only send the site's cookies to that site (not to a CDN it redirected to).
                if let o = originHost, let t = targetHost,
                   t == o || t.hasSuffix("." + o) || o.hasSuffix("." + t) {
                    req.setValue(value, forHTTPHeaderField: key)
                }
            } else {
                req.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let range { req.setValue(range, forHTTPHeaderField: "Range") }
        return req
    }

    // MARK: Server probe

    private struct ProbeResult {
        var size: Int64
        var supportsRanges: Bool
        var validator: String?
        var finalURL: URL
        var suggestedName: String?
    }

    /// A 403 from a signed CDN link is often transient (proxy exit changes between
    /// connections): try a few more times on a fresh connection before giving up.
    private func probeServer() async throws -> ProbeResult {
        var attempt = 0
        while true {
            do { return try await probeServerOnce() }
            catch let SegmentError.badStatus(code) where code == 403 && attempt < 5 {
                attempt += 1
                try await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private func probeServerOnce() async throws -> ProbeResult {
        let cfg = ProxySession.makeConfiguration(base: .ephemeral)
        cfg.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        var headResult: ProbeResult?
        var lastError: Error?

        for method in ["HEAD", "GET"] {
            try throwIfStopped()
            let range = method == "GET" ? "bytes=0-0" : nil
            let request = makeRequest(url: originalURL, range: range, method: method)
            do {
                // `bytes(for:)` returns as soon as headers arrive, so a server that
                // ignores Range never makes us buffer the whole file in memory.
                let (stream, response) = try await session.bytes(for: request)
                stream.task.cancel()

                guard let http = response as? HTTPURLResponse else { continue }
                let code = http.statusCode
                guard code == 200 || code == 206 else {
                    lastError = SegmentError.badStatus(code)
                    continue
                }

                var size: Int64 = 0
                if let cr = http.value(forHTTPHeaderField: "Content-Range"),
                   let slash = cr.lastIndex(of: "/"),
                   let total = Int64(cr[cr.index(after: slash)...]) {
                    size = total
                } else if method == "HEAD" || code == 200 {
                    size = Int64(http.value(forHTTPHeaderField: "Content-Length") ?? "") ?? 0
                }

                let acceptRanges = (http.value(forHTTPHeaderField: "Accept-Ranges") ?? "")
                    .lowercased().contains("bytes")
                let ranges = method == "GET" ? (code == 206) : (acceptRanges && size > 0)

                var validator = http.value(forHTTPHeaderField: "ETag")
                if validator == nil { validator = http.value(forHTTPHeaderField: "Last-Modified") }
                if let v = validator, v.hasPrefix("W/") { validator = String(v.dropFirst(2)) }

                let result = ProbeResult(
                    size: size,
                    supportsRanges: ranges,
                    validator: validator,
                    finalURL: http.url ?? originalURL,
                    suggestedName: Self.filename(fromContentDisposition:
                        http.value(forHTTPHeaderField: "Content-Disposition"))
                )

                if method == "HEAD" {
                    headResult = result          // keep, but confirm ranges with a GET
                    continue
                }
                var final = result
                if final.size == 0, let h = headResult { final.size = h.size }
                if final.suggestedName == nil { final.suggestedName = headResult?.suggestedName }
                return final
            } catch {
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    throw CancellationError()
                }
                lastError = error
                continue
            }
        }

        if var h = headResult {
            // GET probe failed but HEAD worked: we can still download, just not segmented.
            h.supportsRanges = false
            return h
        }
        throw lastError ?? SegmentError.invalidResponse
    }

    // MARK: Meta (validates that partial data still matches the server file)

    private struct Meta: Codable {
        var totalBytes: Int64
        var validator: String?
        var segmentCount: Int          // 0 = single stream
    }

    private var metaURL: URL { workDirectory.appendingPathComponent("meta.json") }

    /// Returns the meta to use. If partial data on disk belongs to a different
    /// version of the file (or a different layout) it is wiped first.
    private func loadOrResetMeta(probe: ProbeResult, segmentCount: Int) -> Meta {
        if let data = try? Data(contentsOf: metaURL),
           let m = try? JSONDecoder().decode(Meta.self, from: data),
           m.totalBytes == probe.size,
           m.validator == nil || probe.validator == nil || m.validator == probe.validator,
           (segmentCount == 0) == (m.segmentCount == 0) {
            return m
        }
        wipePartialFiles()
        let m = Meta(totalBytes: probe.size, validator: probe.validator, segmentCount: segmentCount)
        if let data = try? JSONEncoder().encode(m) {
            try? data.write(to: metaURL, options: .atomic)
        }
        return m
    }

    private func wipePartialFiles() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil) else { return }
        for item in items where item.pathExtension == "part" || item.lastPathComponent == "merged.tmp" {
            try? fm.removeItem(at: item)
        }
    }

    // MARK: Segmented download

    private func runSegmented(url: URL, probe: ProbeResult) async throws {
        let requestedSegments = await MainActor.run { downloadTask.numberOfSegments }
        let configured = max(1, min(Self.maxSegments, requestedSegments))
        let byMinSize = Int(max(1, probe.size / Self.minSegmentBytes))
        let workers = min(configured, byMinSize)               // parallel connections

        // Many small chunks instead of one big range per connection: a free connection
        // takes the next chunk, so the end of the file is shared instead of one slow tail.
        // (A half-finished download keeps the chunk layout it started with.)
        let chunkTarget = workers <= 1 ? 1
            : min(workers * 8, max(workers, Int(probe.size / (2 * 1_024 * 1_024))))
        let meta = loadOrResetMeta(probe: probe, segmentCount: chunkTarget)
        let count = max(1, meta.segmentCount)
        let activeWorkers = max(1, min(workers, count))
        let ranges = Self.plan(size: probe.size, count: count)
        let partURLs = (0..<count).map { workDirectory.appendingPathComponent("seg_\($0).part") }

        // Bytes already on disk (survives pause / quit / relaunch).
        var initial = [Int64](repeating: 0, count: count)
        for i in 0..<count {
            let length = ranges[i].end - ranges[i].start + 1
            var have = Self.fileSize(partURLs[i])
            if have > length {
                try? FileManager.default.removeItem(at: partURLs[i])
                have = 0
            }
            initial[i] = have
        }

        let tracker = ProgressTracker(initial: initial)
        var segs: [DownloadSegment] = []
        for i in 0..<count {
            var s = DownloadSegment(segmentIndex: i, startByte: ranges[i].start, endByte: ranges[i].end)
            s.downloadedBytes = initial[i]
            s.isComplete = initial[i] >= ranges[i].end - ranges[i].start + 1
            segs.append(s)
        }
        let initialTotal = initial.reduce(0, +)
        let snapshotSegs = segs
        let watchdog = Task { [self] in await self.watchSpeed(tracker: tracker, size: probe.size) }
        defer { watchdog.cancel() }
        await MainActor.run {
            downloadTask.segments = snapshotSegs
            downloadTask.downloadedBytes = initialTotal
            if probe.size > 0 { downloadTask.progress = Double(initialTotal) / Double(probe.size) }
        }

        let queue = ChunkQueue((0..<count).filter { !segs[$0].isComplete })
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<activeWorkers {
                group.addTask { [self] in
                    while let i = queue.next() {
                        let r = ranges[i]
                        try await self.downloadRange(index: i, start: r.start, end: r.end,
                                                     file: partURLs[i], url: url, tracker: tracker)
                    }
                }
            }
            for try await _ in group { }
        }

        try throwIfStopped()
        publish(tracker.current())
        try await complete(parts: partURLs, size: probe.size)
    }

    /// Downloads one byte range into `file`, appending to what is already there.
    private func downloadRange(index: Int, start: Int64, end: Int64,
                               file: URL, url: URL, tracker: ProgressTracker) async throws {
        let length = end - start + 1
        var attempt = 0

        while true {
            try throwIfStopped()

            let have = Self.fileSize(file)
            if have == length { return }
            if have > length {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            tracker.set(index: index, bytes: have)

            let from = start + have
            let request = makeRequest(url: url, range: "bytes=\(from)-\(end)")
            let session = SegmentSession(fileURL: file, requestedStart: from,
                                         truncate: false, limiter: limiter) { [weak self] delta in
                guard let self else { return }
                if let snap = tracker.add(index: index, delta: delta) { self.publish(snap) }
            }
            track(session)
            defer { untrack(session) }

            do {
                try await withTaskCancellationHandler {
                    try await session.run(request: request)
                } onCancel: {
                    session.cancel()
                }
                let now = Self.fileSize(file)
                if now == length { return }
                throw SegmentError.incomplete(expected: length, actual: now)
            } catch {
                if wasRestarted(session) && !isStopped && !Task.isCancelled { continue }   // deliberate reconnect
                if error is CancellationError || isStopped || Task.isCancelled {
                    throw CancellationError()
                }
                attempt += 1
                guard attempt < Self.maxAttempts, Self.isRetryable(error) else { throw error }
                // 1 s, 2 s, 4 s … (Task.sleep throws CancellationError when stopped)
                let seconds = pow(2.0, Double(attempt - 1))
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    // MARK: Single-stream download

    private func runSingle(url: URL, probe: ProbeResult, canResume: Bool) async throws {
        _ = loadOrResetMeta(probe: probe, segmentCount: 0)
        let file = workDirectory.appendingPathComponent("single.part")
        let knownSize = probe.size
        // Resuming a stream of unknown length is not safe → start over.
        let resumable = canResume && knownSize > 0
        if !resumable { try? FileManager.default.removeItem(at: file) }

        await MainActor.run { downloadTask.segments = [] }

        var attempt = 0
        while true {
            try throwIfStopped()

            let have = Self.fileSize(file)
            if knownSize > 0 && have == knownSize { break }
            if knownSize > 0 && have > knownSize {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            let resuming = resumable && have > 0
            let tracker = ProgressTracker(initial: [resuming ? have : 0])
            let request = makeRequest(url: url, range: resuming ? "bytes=\(have)-" : nil)
            let session = SegmentSession(fileURL: file,
                                         requestedStart: resuming ? have : nil,
                                         truncate: !resuming, limiter: limiter) { [weak self] delta in
                guard let self else { return }
                if let snap = tracker.add(index: 0, delta: delta) { self.publish(snap) }
            }
            track(session)
            defer { untrack(session) }

            do {
                try await withTaskCancellationHandler {
                    try await session.run(request: request)
                } onCancel: {
                    session.cancel()
                }
                let now = Self.fileSize(file)
                if knownSize > 0 && now != knownSize {
                    throw SegmentError.incomplete(expected: knownSize, actual: now)
                }
                break
            } catch {
                if error is CancellationError || isStopped || Task.isCancelled {
                    throw CancellationError()
                }
                attempt += 1
                guard attempt < Self.maxAttempts, Self.isRetryable(error) else { throw error }
                let seconds = pow(2.0, Double(attempt - 1))
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }

        try await complete(parts: [file], size: Self.fileSize(file))
    }

    // MARK: Completion (merge → move into place → tell the manager)

    private func complete(parts: [URL], size: Int64) async throws {
        try throwIfStopped()

        let (destDir, filename) = await MainActor.run {
            (downloadTask.destinationPath, downloadTask.filename)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let finalURL = destDir.appendingPathComponent(filename)

        // One part → move it. Several parts → stream-merge (never load a segment into RAM).
        let source: URL
        if parts.count == 1 {
            source = parts[0]
        } else {
            let merged = workDirectory.appendingPathComponent("merged.tmp")
            try Self.merge(parts: parts, into: merged)
            source = merged
        }
        try throwIfStopped()

        if fm.fileExists(atPath: finalURL.path) { try fm.removeItem(at: finalURL) }
        do {
            try fm.moveItem(at: source, to: finalURL)
        } catch {
            try fm.copyItem(at: source, to: finalURL)
            try? fm.removeItem(at: source)
        }
        try? fm.removeItem(at: workDirectory)

        await MainActor.run {
            if size > 0 {
                downloadTask.downloadedBytes = size
                if downloadTask.totalBytes == 0 { downloadTask.totalBytes = size }
            }
            DownloadManager.shared.downloadDidComplete(taskId: downloadTask.id)
        }
    }

    private static func merge(parts: [URL], into output: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: output)
        guard fm.createFile(atPath: output.path, contents: nil) else {
            throw SegmentError.permissionDenied
        }
        let out = try FileHandle(forWritingTo: output)
        defer { try? out.close() }

        for part in parts {
            let input = try FileHandle(forReadingFrom: part)
            defer { try? input.close() }
            while true {
                let chunk: Data? = try autoreleasepool { try input.read(upToCount: 4 * 1_024 * 1_024) }
                guard let data = chunk, !data.isEmpty else { break }
                try out.write(contentsOf: data)
            }
        }
    }

    // MARK: Progress publishing

    private func publish(_ snap: ProgressTracker.Snapshot) {
        let task = downloadTask
        Task { @MainActor in
            // A late update must never resurrect progress/speed after pause or stop.
            guard task.state == .downloading else { return }
            for i in task.segments.indices where i < snap.segments.count {
                task.segments[i].downloadedBytes = snap.segments[i]
                let len = task.segments[i].endByte - task.segments[i].startByte + 1
                task.segments[i].isComplete = snap.segments[i] >= len
            }
            task.downloadedBytes = snap.total
            if task.totalBytes > 0 {
                task.progress = min(1.0, Double(snap.total) / Double(task.totalBytes))
            }
            task.speed = snap.speed
            task.updateTimeRemaining()
        }
    }

    // MARK: Static helpers

    static func plan(size: Int64, count: Int) -> [(start: Int64, end: Int64)] {
        let n = max(1, count)
        let base = size / Int64(n)
        return (0..<n).map { i in
            let s = Int64(i) * base
            let e = (i == n - 1) ? size - 1 : s + base - 1
            return (start: s, end: e)
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func isRetryable(_ error: Error) -> Bool {
        if let e = error as? SegmentError {
            switch e {
            case .badStatus(let c): return c == 403 || c == 408 || c == 429 || (500...599).contains(c)
            case .incomplete:       return true
            default:                return false
            }
        }
        let ns = error as NSError
        if ns.domain == "kCFErrorDomainCFNetwork" {
            // 300 connection lost, 304 / 310 proxy connection failure, 311 bad CONNECT reply
            return [300, 304, 310, 311].contains(ns.code)
        }
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorDNSLookupFailed,
             NSURLErrorCannotFindHost,
             NSURLErrorResourceUnavailable,
             NSURLErrorSecureConnectionFailed,
             NSURLErrorBadServerResponse,
             NSURLErrorCannotParseResponse,
             NSURLErrorDataNotAllowed:
            return true
        default:
            return false
        }
    }

    /// Parses `filename*=UTF-8''my%20file.zip` and `filename="my file.zip"`.
    private static func filename(fromContentDisposition header: String?) -> String? {
        guard let header else { return nil }

        func clean(_ raw: String) -> String? {
            var v = raw
            if let semi = v.firstIndex(of: ";") { v = String(v[..<semi]) }
            v = v.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
            return v.isEmpty ? nil : v
        }
        func sanitize(_ name: String) -> String? {
            let last = (name as NSString).lastPathComponent
                .replacingOccurrences(of: ":", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return last.isEmpty || last == "." || last == ".." ? nil : last
        }

        if let r = header.range(of: "filename*=", options: .caseInsensitive),
           var v = clean(String(header[r.upperBound...])) {
            if let q = v.range(of: "''") { v = String(v[q.upperBound...]) }
            if let decoded = v.removingPercentEncoding, let name = sanitize(decoded) { return name }
        }
        if let r = header.range(of: "filename=", options: .caseInsensitive),
           let v = clean(String(header[r.upperBound...])) {
            let decoded = v.removingPercentEncoding ?? v
            return sanitize(decoded)
        }
        return nil
    }
}

// MARK: - SegmentSession
//
// One URLSession data task streaming into one file (append mode).
// Delegate callbacks run on a private serial queue, so the file handle and
// buffer are only ever touched from that queue.

private final class SegmentSession: NSObject, URLSessionDataDelegate {

    private let fileURL: URL
    private let requestedStart: Int64?      // non-nil → a Range request was sent
    private let truncate: Bool              // start the file from empty
    private let limiter: RateLimiter
    private let onBytes: (Int64) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var cancelled = false
    private var failure: Error?

    // Delegate-queue only
    private var handle: FileHandle?
    private var buffer = Data()
    private let flushThreshold = 256 * 1_024

    init(fileURL: URL, requestedStart: Int64?, truncate: Bool,
         limiter: RateLimiter, onBytes: @escaping (Int64) -> Void) {
        self.fileURL = fileURL
        self.requestedStart = requestedStart
        self.truncate = truncate
        self.limiter = limiter
        self.onBytes = onBytes
    }

    func run(request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock()
            if cancelled {
                lock.unlock()
                c.resume(throwing: CancellationError())
                return
            }
            continuation = c

            let config = ProxySession.makeConfiguration()
            // A heavily throttled transfer can leave long gaps between reads.
            config.timeoutIntervalForRequest = 600
            config.timeoutIntervalForResource = 0
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            config.httpShouldSetCookies = (request.value(forHTTPHeaderField: "Cookie") == nil)

            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let s = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            let t = s.dataTask(with: request)
            session = s
            dataTask = t
            lock.unlock()
            t.resume()
        }
    }

    /// Safe to call from any thread, any number of times, even before `run`.
    func cancel() {
        lock.lock()
        cancelled = true
        let t = dataTask
        lock.unlock()
        t?.cancel()
    }

    private func fail(_ error: Error) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
    }

    // MARK: Response

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            fail(SegmentError.invalidResponse)
            completionHandler(.cancel)
            return
        }
        let code = http.statusCode

        if let start = requestedStart {
            if code == 200 {                       // server ignored our Range header
                fail(SegmentError.rangeNotHonored)
                completionHandler(.cancel)
                return
            }
            guard code == 206 else {
                fail(SegmentError.badStatus(code))
                completionHandler(.cancel)
                return
            }
            if let cr = http.value(forHTTPHeaderField: "Content-Range"),
               let got = Self.rangeStart(cr), got != start {
                fail(SegmentError.rangeNotHonored)
                completionHandler(.cancel)
                return
            }
        } else if code != 200 {
            fail(SegmentError.badStatus(code))
            completionHandler(.cancel)
            return
        }

        do {
            try openFile()
        } catch {
            fail(error)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    private func openFile() throws {
        let fm = FileManager.default
        if truncate || !fm.fileExists(atPath: fileURL.path) {
            guard fm.createFile(atPath: fileURL.path, contents: nil) else {
                throw SegmentError.permissionDenied
            }
        }
        let h = try FileHandle(forWritingTo: fileURL)
        if truncate {
            try h.truncate(atOffset: 0)
        } else {
            _ = try h.seekToEnd()
        }
        handle = h
    }

    // MARK: Data

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        if buffer.count >= flushThreshold {
            do {
                try flush()
            } catch {
                fail(error)
                dataTask.cancel()
                return
            }
        }
        // Block this serial delegate queue in small slices to backpressure the
        // socket. Suspending the data task instead wedges the transfer.
        // Count each slice only after its delay so the meter shows the real
        // paced rate rather than the server's burst.
        var remaining = data.count
        while remaining > 0 {
            let slice = min(remaining, 16 * 1024)
            let delay = limiter.reserve(bytes: slice)
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            onBytes(Int64(slice))
            remaining -= slice
        }
    }

    private func flush() throws {
        guard !buffer.isEmpty, let h = handle else { return }
        try h.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: Completion

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Always flush what we have: a paused download must keep every received byte.
        var flushError: Error?
        do { try flush() } catch { flushError = error }
        try? handle?.close()
        handle = nil
        session.finishTasksAndInvalidate()

        lock.lock()
        let stored = failure
        let c = continuation
        continuation = nil
        lock.unlock()

        if let stored { c?.resume(throwing: stored); return }
        if let flushError { c?.resume(throwing: flushError); return }
        if let error {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                c?.resume(throwing: CancellationError())
            } else {
                c?.resume(throwing: error)
            }
            return
        }
        c?.resume()
    }

    // MARK: Helpers

    /// "bytes 100-199/1000" → 100
    private static func rangeStart(_ header: String) -> Int64? {
        let parts = header.split(separator: " ")
        guard parts.count == 2,
              let span = parts[1].split(separator: "/").first else { return nil }
        let ends = span.split(separator: "-")
        guard ends.count == 2 else { return nil }
        return Int64(ends[0])
    }
}
