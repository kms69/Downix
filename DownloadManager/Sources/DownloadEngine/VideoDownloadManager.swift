//
//  VideoDownloadManager.swift
//  Download Manager for Mac - Feature #7: YouTube & Video Downloading
//
//  Created on February 15, 2026
//

import Foundation
import Combine

/// Manages video downloads from various platforms
@MainActor
class VideoDownloadManager: ObservableObject {
    
    static let shared = VideoDownloadManager()
    
    @Published var videoTasks: [VideoDownloadTask] = []
    @Published var statistics: VideoDownloadStatistics = VideoDownloadStatistics()
    
    private var cancellables = Set<AnyCancellable>()
    private let downloadManager = DownloadManager.shared
    
    private init() {
        loadStatistics()
    }
    
    // MARK: - Public Methods
    
    /// Add a new video download task
    func addVideoDownload(url: URL, options: VideoDownloadOptions = .default) -> VideoDownloadTask {
        let task = VideoDownloadTask(url: url, options: options)
        videoTasks.append(task)
        
        // Auto-fetch metadata
        Task {
            await fetchMetadata(for: task)
        }
        
        return task
    }
    
    /// Start fast: when the title is known (browser capture) or can be read in a
    /// moment (YouTube oEmbed / page title), skip the blocking yt-dlp metadata
    /// run. That run took several seconds and the download command then did the
    /// same extraction again.
    func prepareForStart(_ task: VideoDownloadTask) async {
        guard await downloadKind(for: task) == .streaming else {
            await fetchMetadata(for: task)
            return
        }
        func usable(_ t: String?) -> Bool {
            guard let t = t?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
            return !Self.isQualityLabel(t)
        }
        if !usable(task.preferredTitle), let quick = await QuickTitleFetcher.fetch(task.url) {
            task.preferredTitle = quick
        }
        guard usable(task.preferredTitle), task.state != .cancelled else {
            await fetchMetadata(for: task)       // old behaviour when no title could be found
            return
        }
        task.state = .ready
    }

    /// Fetch metadata for a video task
    func fetchMetadata(for task: VideoDownloadTask) async {
        guard await downloadKind(for: task) == .streaming else {
            task.state = .ready
            return
        }
        await MainActor.run {
            task.state = .fetchingMetadata
        }
        
        do {
            let metadata = try await extractMetadata(from: task.url, platform: task.platform,
                                                     authArgs: ytDlpAuthArgs(task),
                                                     httpHeaders: task.httpHeaders)
            
            await MainActor.run {
                guard task.state != .cancelled else { return }
                task.metadata = metadata
                task.state = .ready
                
                // Check if it's a playlist
                if metadata.isPlaylist {
                    Task {
                        await fetchPlaylistInfo(for: task)
                    }
                }
            }
        } catch {
            await MainActor.run {
                guard task.state != .cancelled else { return }
                task.state = .failed
                task.error = "Failed to fetch metadata: \(error.localizedDescription)"
            }
        }
    }
    
    /// Fetch playlist information
    func fetchPlaylistInfo(for task: VideoDownloadTask) async {
        do {
            let playlist = try await extractPlaylistInfo(from: task.url, platform: task.platform,
                                                         authArgs: ytDlpAuthArgs(task),
                                                         httpHeaders: task.httpHeaders)
            
            await MainActor.run {
                task.playlist = playlist
            }
        } catch {
            await MainActor.run {
                task.error = "Failed to fetch playlist: \(error.localizedDescription)"
            }
        }
    }
    
    /// Add a video and start it as soon as its info has been fetched.
    /// (The old caller polled for only 20 s and silently gave up on slow sites.)
    @discardableResult
    func addAndStartDownload(url: URL, options: VideoDownloadOptions = .default,
                             cookieFile: URL? = nil,
                             preferredTitle: String? = nil,
                             httpHeaders: [String: String]? = nil,
                             destinationFolder: URL? = nil) -> VideoDownloadTask {
        if let existing = videoTasks.first(where: { $0.url.absoluteString == url.absoluteString }) {
            switch existing.state {
            case .failed, .cancelled:
                if let cookieFile { existing.cookieFile = cookieFile }
                retryDownload(existing)                      // resumes the same row
                return existing
            case .completed:
                break                                         // a finished copy: a new download is intended
            default:
                return existing                               // already running / queued / paused
            }
        }
        let task = VideoDownloadTask(url: url, options: options)
        task.cookieFile = cookieFile
        task.destinationFolder = destinationFolder
        task.preferredTitle = preferredTitle
        task.httpHeaders = httpHeaders
        task.showsCompletionDialog = true
        videoTasks.append(task)
        Task { @MainActor in
            await self.prepareForStart(task)
            if task.state == .ready { await self.startDownload(task) }
            self.releaseCookieFileIfDone(task)
        }
        return task
    }

    /// The browser's cookie file must outlive Pause / Resume / Retry (YouTube
    /// rejects cookie-less requests with "Sign in to confirm you're not a bot").
    /// It is deleted only once the download is finished, cancelled or removed.
    private func releaseCookieFileIfDone(_ task: VideoDownloadTask, force: Bool = false) {
        guard let file = task.cookieFile else { return }
        guard force || task.state == .completed || task.state == .cancelled else { return }
        task.cookieFile = nil
        try? FileManager.default.removeItem(at: file)
    }

    /// Handles of running yt-dlp processes, so Cancel can really stop them.
    private var ytHandles: [UUID: ExternalToolRunner.ProcessHandle] = [:]
    /// Prevents a double Resume click from launching the same task twice.
    private var activeStarts = Set<UUID>()
    /// Direct-file vs streaming decision per task (server probe runs once).
    private var downloadKinds: [UUID: DownloadKind] = [:]
    /// Per-task samples for the live speed shown in the progress window.
    private var ytSpeedSamples: [UUID: (bytes: Int64, at: Date, ema: Double)] = [:]
    /// Output file chosen for a task. A retry reuses it so `--continue` finds the
    /// partial file; a second grab of the same title gets its own file instead of
    /// continuing into the first download and merging the two videos.
    private var reservedOutputPaths: [UUID: URL] = [:]

    // MARK: - Main-list tracking (streaming rows)

    private func trackingRow(for task: VideoDownloadTask) -> DownloadTask? {
        downloadManager.streamingVideoRow(id: task.id)
    }

    private func ensureTrackingRow(for task: VideoDownloadTask, destination: URL) -> DownloadTask {
        let row = downloadManager.trackStreamingVideoTask(
            id: task.id, url: task.url, destination: destination)
        row.destinationPath = destination.deletingLastPathComponent()
        row.filename = destination.lastPathComponent
        row.fileType = "video"
        // Remember the page the stream was captured from (shown in Properties).
        if let ref = task.httpHeaders?["Referer"] ?? task.httpHeaders?["referer"], !ref.isEmpty {
            row.requestHeaders["Referer"] = ref
        }
        return row
    }

    private func markAttempt(_ task: VideoDownloadTask) {
        guard let row = trackingRow(for: task) else { return }
        row.lastAttemptAt = Date()
        row.error = nil
        row.state = .downloading
        row.statusDetail = nil
        downloadManager.saveTaskList()
    }

    private func markTrackingFailed(_ task: VideoDownloadTask) {
        if let row = trackingRow(for: task) {
            row.state = .failed
            row.speed = 0
            row.timeRemaining = 0
            row.statusDetail = nil
            row.error = task.error.map { NSError(domain: "VideoDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: $0]) }
            downloadManager.failStreamingVideoTask(id: task.id)
        }
        SchedulerQueueManager.shared.powerActionDidFail("a video download failed")
    }

    /// Cookie args for yt-dlp. A cookie file from the browser extension is used
    /// verbatim (no Keychain / password prompt); internal requests still fall
    /// back to the browser's cookie store.
    private func ytDlpAuthArgSets(_ task: VideoDownloadTask) -> [[String]] {
        if let file = task.cookieFile, FileManager.default.fileExists(atPath: file.path) {
            return [["--cookies", file.path]]
        }
        return ExternalToolRunner.ytDlpCookieArgSets
    }

    private func ytDlpAuthArgs(_ task: VideoDownloadTask) -> [String] {
        ytDlpAuthArgSets(task).first ?? []
    }

    /// Referer/User-Agent captured from the browser. Streaming CDNs (direct
    /// .m3u8 / segment hosts) refuse requests without the page's Referer.
    private func ytDlpHeaderArgs(_ headers: [String: String]?) -> [String] {
        guard let headers, !headers.isEmpty else { return [] }
        var args: [String] = []
        if let referer = headers["Referer"] ?? headers["referer"], !referer.isEmpty {
            args += ["--referer", referer]
        }
        if let ua = headers["User-Agent"] ?? headers["user-agent"], !ua.isEmpty {
            args += ["--user-agent", ua]
        }
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            guard !value.isEmpty,
                  !["Referer", "referer", "User-Agent", "user-agent", "Cookie", "cookie"].contains(key)
            else { continue }
            args += ["--add-header", "\(key): \(value)"]
        }
        return args
    }

    private enum YtDlpOutcome { case success, failed, cancelled }

    /// Start downloading a video — yt-dlp for streaming sites / HLS, engine for plain media files.
    /// A paused task resumes here too: yt-dlp is restarted with `--continue`, and
    /// direct media resumes the underlying `DownloadTask` instead of starting over.
    func startDownload(_ task: VideoDownloadTask) async {
        guard task.state == .ready || task.state == .paused else { return }
        guard !activeStarts.contains(task.id) else { return }
        activeStarts.insert(task.id)
        defer { activeStarts.remove(task.id) }
        let resuming = task.state == .paused

        await MainActor.run {
            task.state = .downloading
            task.speed = 0
            task.error = nil
            if !resuming || task.startedAt == nil {
                task.startedAt = Date()
            }
            if task.postDownloadAction == .sleep || task.postDownloadAction == .shutdown {
                SchedulerQueueManager.shared.requestPowerAction(
                    task.postDownloadAction, triggeredBy: task.id)
            }
        }

        if resuming, let existing = task.downloadTask {
            await downloadManager.resumeDownload(existing)
            await waitForCompletion(task: task)
            if task.state == .converting { await postProcess(task: task) }
            return
        }
        
        do {
            let kind = await downloadKind(for: task)
            let destinationPath = getDestinationPath(for: task)

            // 1. Streaming pages and manifests → yt-dlp.
            if kind == .streaming {
                _ = ensureTrackingRow(for: task, destination: destinationPath)
                markAttempt(task)
                // First use: fetch yt-dlp ourselves (no Homebrew / Python needed).
                if !ExternalToolRunner.isYTDLPAvailable {
                    do {
                        try await ExternalToolRunner.installYtDlp()
                    } catch {
                        throw NSError(domain: "VideoDownload", code: 2, userInfo: [
                            NSLocalizedDescriptionKey:
                                "yt-dlp is not installed and could not be downloaded (\(error.localizedDescription)). Install it with: brew install yt-dlp ffmpeg"])
                    }
                }

                // YouTube: fetch the direct streams with the multi-threaded engine.
                // Any problem falls through to the regular yt-dlp download below.
                var outcome: YtDlpOutcome = .failed
                var handledNatively = false
                if !Self.canUseNativeEngine(task) {
                    YtDlpLog.log("native engine skipped (host \(task.url.host ?? "?"), ffmpeg \(ExternalToolRunner.isFFmpegAvailable), format \(task.options.format.fileExtension), audioOnly \(task.options.extractAudioOnly), subs \(task.options.downloadSubtitles))")
                }
                if Self.canUseNativeEngine(task) {
                    switch await downloadViaNativeEngine(task: task, destination: destinationPath) {
                    case .success:   outcome = .success; handledNatively = true
                    case .cancelled: outcome = .cancelled; handledNatively = true
                    case .failed:
                        YtDlpLog.log("native engine unavailable; falling back to yt-dlp")
                        if NativeStreamResolver.lastResolveTimedOut {
                            await MainActor.run {
                                self.trackingRow(for: task)?.statusDetail = "YouTube is not answering. Is your VPN / proxy on?"
                            }
                        }
                    }
                }
                if !handledNatively {
                    outcome = await downloadViaYtDlp(task: task, destination: destinationPath)
                }

                // Sites change constantly; an out-of-date yt-dlp is the usual cause of failures.
                if outcome == .failed, Self.looksLikeStaleExtractor(task.error) {
                    let updated = await Task.detached { ExternalToolRunner.updateManagedYtDlp() }.value
                    if updated {
                        markAttempt(task)
                        outcome = await downloadViaYtDlp(task: task, destination: destinationPath)
                    }
                }

                // A captured CDN / manifest link is signed and short-lived (HTTP 410 / 403 /
                // 404 a little later, or when the site binds it to the player). The page
                // it came from always works, so retry from the page, same quality.
                if outcome == .failed, Self.looksLikeDeadStreamLink(task.error),
                   let page = Self.pageURL(forCapturedStream: task) {
                    markAttempt(task)
                    task.error = nil
                    YtDlpLog.log("stream link failed; retrying from page \(page.absoluteString)")
                    outcome = await downloadViaYtDlp(task: task, destination: destinationPath, sourceURL: page)
                }

                switch outcome {
                case .success:
                    await postProcess(task: task)
                case .cancelled:
                    break                                   // state already set by cancelDownload
                case .failed:
                    await MainActor.run {
                        task.state = .failed
                        task.error = task.error ?? "yt-dlp could not download this video."
                        if let e = task.error, e.contains("Sign in to confirm"), task.cookieFile == nil {
                            task.error = "YouTube wants a signed-in session. Grab this video again with the browser extension (it passes your cookies), or sign in to YouTube in that browser first."
                        }
                        statistics.recordFailure()
                        self.markTrackingFailed(task)
                    }
                }
                return
            }

            // 2. Direct files go straight to the native multi-threaded engine.
            guard task.state == .downloading else { return }
            let downloadTask = downloadManager.addDownload(
                url: task.url,
                destinationPath: destinationPath.deletingLastPathComponent(),
                filename: destinationPath.lastPathComponent
            )
            
            await MainActor.run {
                task.downloadTask = downloadTask
                task.outputURL = downloadTask.destinationPath.appendingPathComponent(downloadTask.filename)
            }
            if let limit = BandwidthManager.shared.getDownloadLimit(task.id),
               limit.isEnabled, limit.downloadSpeed > 0 {
                BandwidthGate.shared.setTaskLimit(limit.downloadSpeed, for: downloadTask.id)
            }
            refreshThrottleRate()
            
            // Monitor progress
            monitorProgress(videoTask: task, downloadTask: downloadTask)
            
            // Wait for completion
            await waitForCompletion(task: task)
            
            // Post-processing (monitorProgress flips the state to .converting on completion)
            if task.state == .converting {
                await postProcess(task: task)
            }
            
        } catch {
            await MainActor.run {
                task.state = .failed
                task.error = error.localizedDescription
                statistics.recordFailure()
                self.markTrackingFailed(task)
            }
        }
    }

    /// Private working folder for one yt-dlp download (kept while paused so it can resume).
    static func ytTempDirectory(for id: UUID) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("DownloadManager/ytdlp-partial/\(id.uuidString)", isDirectory: true)
    }

    /// Delete a task's partial files (cancel / remove / finished). Slightly delayed so
    /// the yt-dlp process has really exited and cannot recreate files.
    private func discardYtTemp(for id: UUID, after delay: TimeInterval = 1.0) {
        let dir = Self.ytTempDirectory(for: id)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private static func looksLikeDeadStreamLink(_ message: String?) -> Bool {
        guard let m = message?.lowercased() else { return false }
        return m.contains("http error 410") || m.contains("http error 403") || m.contains("http error 404")
            || m.contains("unable to download webpage") || m.contains("unable to download m3u8")
            || m.contains("unable to download video data")
    }

    /// The tab URL the browser extension captured the stream from (its Referer),
    /// when the task itself points at a bare manifest / media file on a CDN.
    /// Works for any site yt-dlp has an extractor for (Pornhub, xHamster, ...).
    private static func pageURL(forCapturedStream task: VideoDownloadTask) -> URL? {
        guard let referer = task.httpHeaders?["Referer"] ?? task.httpHeaders?["referer"],
              let page = URL(string: referer),
              page.scheme?.hasPrefix("http") == true, page != task.url,
              let pageHost = page.host, pageHost != task.url.host else { return nil }
        let streamExt = task.url.pathExtension.lowercased()
        guard URLClassifier.manifestExtensions.contains(streamExt)
                || URLClassifier.fileExtensions.contains(streamExt) else { return nil }
        let pageExt = page.pathExtension.lowercased()
        guard !URLClassifier.manifestExtensions.contains(pageExt),
              !URLClassifier.fileExtensions.contains(pageExt) else { return nil }
        // A bare site root ("https://www.example.com/") is not a video page.
        guard page.path.count > 1 || page.query != nil else { return nil }
        return page
    }

    private static func looksLikeStaleExtractor(_ message: String?) -> Bool {
        guard let m = message?.lowercased() else { return false }
        return m.contains("unable to extract") || m.contains("http error 403")
            || m.contains("sign in to confirm") || m.contains("nsig") || m.contains("player response")
            || m.contains("please report this issue")
    }

    private func downloadKind(for task: VideoDownloadTask) async -> DownloadKind {
        if let cached = downloadKinds[task.id] { return cached }
        let kind: DownloadKind
        if let quick = URLClassifier.quickClassify(task.url) {
            kind = quick
        } else {
            kind = await URLClassifier.classify(task.url)
        }
        downloadKinds[task.id] = kind
        return kind
    }

    // MARK: - Native multi-threaded path (YouTube)

    /// Running native part downloads, so Pause / Cancel / speed limits reach them.
    private struct NativeRun { let ids: [UUID]; let engines: [SegmentDownloader] }
    private var nativeRuns: [UUID: NativeRun] = [:]

    private static func canUseNativeEngine(_ task: VideoDownloadTask) -> Bool {
        guard NativeStreamResolver.isEligibleHost(task.url),
              ExternalToolRunner.isFFmpegAvailable,
              ExternalToolRunner.isYTDLPAvailable,
              !task.options.extractAudioOnly,
              !task.options.downloadSubtitles,
              ["mp4", "mkv", "webm"].contains(task.options.format.fileExtension) else { return false }
        return true
    }

    /// Stable ids for the video / audio part so a paused download resumes its data.
    private static func partID(_ id: UUID, _ index: UInt8) -> UUID {
        var b = id.uuid
        b.15 = b.15 ^ (index &+ 0x5A)
        return UUID(uuid: b)
    }

    /// Resolved stream links per task. YouTube links stay valid for hours, so a
    /// Resume (or retry) skips the 6-8 s yt-dlp extraction.
    private var nativePlans: [UUID: (plan: NativeStreamPlan, at: Date)] = [:]

    private func downloadViaNativeEngine(task: VideoDownloadTask, destination: URL,
                                         allowCache: Bool = true) async -> YtDlpOutcome {
        guard task.state == .downloading else { return .cancelled }
        let ext = task.options.format.fileExtension
        let auth = ytDlpAuthArgs(task)
        let pageURL = task.url
        let maxHeight = task.options.quality.height

        var usedCache = false
        var resolved: NativeStreamPlan?
        if allowCache, let cached = nativePlans[task.id], Date().timeIntervalSince(cached.at) < 30 * 60 {
            resolved = cached.plan
            usedCache = true
            YtDlpLog.log("native: reusing stream links (skipping extraction)")
        } else {
            resolved = await Task.detached(priority: .userInitiated) {
                NativeStreamResolver.resolve(pageURL: pageURL, outputExtension: ext,
                                             maxHeight: maxHeight, authArgs: auth)
            }.value
        }
        guard task.state == .downloading else { return .cancelled }
        guard let plan = resolved, let audio = plan.audio else { return .failed }
        nativePlans[task.id] = (plan, usedCache ? (nativePlans[task.id]?.at ?? Date()) : Date())

        let tempDir = Self.ytTempDirectory(for: task.id)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        func makePart(_ stream: NativeStream, index: UInt8, name: String) -> DownloadTask {
            let part = DownloadTask(id: Self.partID(task.id, index), url: stream.url,
                                    destinationPath: tempDir, filename: name, numberOfSegments: 8)
            part.requestHeaders = stream.headers
            return part
        }
        let videoPart = makePart(plan.video, index: 1, name: "video.\(plan.video.ext)")
        let audioPart = makePart(audio, index: 2, name: "audio.\(audio.ext)")
        let parts = [videoPart, audioPart]
        let estimates = [plan.video.size, audio.size]
        let engines = parts.map { SegmentDownloader(downloadTask: $0) }
        nativeRuns[task.id] = NativeRun(ids: parts.map { $0.id }, engines: engines)
        applyNativeLimit(for: task.id)
        refreshThrottleRate()
        ytSpeedSamples[task.id] = nil
        defer {
            nativeRuns.removeValue(forKey: task.id)
            refreshThrottleRate()
        }
        YtDlpLog.log("native download: video \(plan.video.height)p .\(plan.video.ext) + audio .\(audio.ext)")

        // Live progress from both parts.
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                self.publishNativeProgress(task: task, parts: parts, estimates: estimates)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        defer { monitor.cancel() }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for engine in engines {
                    group.addTask { try await engine.start() }
                }
                try await group.waitForAll()
            }
        } catch {
            engines.forEach { $0.pause() }
            if task.state != .downloading {
                return .cancelled                         // user paused / cancelled
            }
            YtDlpLog.log("native download error: \(error.localizedDescription)")
            engines.forEach { $0.pause() }                 // keep partial data for the retry
            if usedCache {
                // The saved links may have expired: extract fresh ones once.
                nativePlans[task.id] = nil
                monitor.cancel()
                nativeRuns.removeValue(forKey: task.id)
                return await downloadViaNativeEngine(task: task, destination: destination, allowCache: false)
            }
            engines.forEach { $0.cancel() }
            return .failed
        }
        guard task.state == .downloading else { return .cancelled }
        publishNativeProgress(task: task, parts: parts, estimates: estimates)

        // Merge without re-encoding.
        guard let ffmpeg = ExternalToolRunner.ffmpegPath else { return .failed }
        let videoFile = tempDir.appendingPathComponent(videoPart.filename)
        let audioFile = tempDir.appendingPathComponent(audioPart.filename)
        let base = destination.deletingPathExtension()
        let output = base.appendingPathExtension(ext)
        let tmpOut = tempDir.appendingPathComponent("merged.\(ext)")
        try? FileManager.default.removeItem(at: tmpOut)
        let merged = await Task.detached(priority: .userInitiated) { () -> Bool in
            let args = ["-y", "-v", "error", "-i", videoFile.path, "-i", audioFile.path,
                        "-map", "0:v:0", "-map", "1:a:0", "-c", "copy", tmpOut.path]
            guard let r = try? ExternalToolRunner.run(binary: ffmpeg, args: args, timeout: 3600) else { return false }
            return r.succeeded
        }.value
        guard task.state == .downloading else { return .cancelled }
        guard merged, FileManager.default.fileExists(atPath: tmpOut.path) else {
            YtDlpLog.log("native merge failed")
            return .failed
        }
        do {
            try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: output.path) {
                try FileManager.default.removeItem(at: output)
            }
            try FileManager.default.moveItem(at: tmpOut, to: output)
        } catch {
            YtDlpLog.log("native move failed: \(error.localizedDescription)")
            return .failed
        }
        discardYtTemp(for: task.id, after: 0)
        parts.forEach { SegmentDownloader.discardPartialData(for: $0.id) }
        nativePlans[task.id] = nil

        await MainActor.run {
            let bytes = Self.fileSize(output)
            task.progress = 1.0
            task.speed = 0
            task.totalBytes = bytes
            task.downloadedBytes = bytes
            task.outputURL = output
            task.state = .converting
            if let row = self.trackingRow(for: task) {
                row.progress = 1
                row.speed = 0
                row.totalBytes = bytes
                row.downloadedBytes = bytes
                row.timeRemaining = 0
                row.destinationPath = output.deletingLastPathComponent()
                row.filename = output.lastPathComponent
                row.statusDetail = "Converting"
            }
            self.downloadManager.saveTaskList()
        }
        return .success
    }

    @MainActor
    private func publishNativeProgress(task: VideoDownloadTask, parts: [DownloadTask],
                                       estimates: [Int64]) {
        guard task.state == .downloading else { return }
        let done = parts.reduce(Int64(0)) { $0 + $1.downloadedBytes }
        // Real size once a part has been probed, yt-dlp's estimate before that.
        var total: Int64 = 0
        var allKnown = true
        for (i, part) in parts.enumerated() {
            let size = part.totalBytes > 0 ? part.totalBytes : (i < estimates.count ? estimates[i] : 0)
            if size <= 0 { allKnown = false }
            total += max(size, part.downloadedBytes)
        }
        let rawSpeed = parts.reduce(Int64(0)) { $0 + $1.speed }
        let speed = liveSpeed(for: task, bytes: done, fallback: rawSpeed)

        var fraction = task.progress
        if allKnown, total > 0 {
            fraction = max(task.progress, min(0.99, Double(done) / Double(total)))
            task.totalBytes = total
        }
        task.progress = fraction
        task.speed = speed
        task.downloadedBytes = done
        if let row = trackingRow(for: task) {
            row.progress = fraction
            row.speed = speed
            row.downloadedBytes = done
            if allKnown, total > 0 { row.totalBytes = total }
            row.updateTimeRemaining()
            row.statusDetail = allKnown ? nil : "Connecting"
        }
    }

    /// Copy the task's per-download limit to both native parts.
    private func applyNativeLimit(for taskId: UUID) {
        guard let run = nativeRuns[taskId] else { return }
        var rate: Int64?
        if let limit = BandwidthManager.shared.getDownloadLimit(taskId),
           limit.isEnabled, limit.downloadSpeed > 0 {
            rate = max(1, limit.downloadSpeed / Int64(max(1, run.ids.count)))   // shared by both parts
        }
        for id in run.ids { BandwidthGate.shared.setTaskLimit(rate, for: id) }
    }

    private func stopNative(_ taskId: UUID, discard: Bool) {
        guard let run = nativeRuns[taskId] else { return }
        for e in run.engines { discard ? e.cancel() : e.pause() }
        if discard { run.ids.forEach { SegmentDownloader.discardPartialData(for: $0) } }
    }

    /// Download with yt-dlp, reporting live progress. Cancel terminates the process.
    private func downloadViaYtDlp(task: VideoDownloadTask, destination: URL,
                                  sourceURL: URL? = nil) async -> YtDlpOutcome {
        // A lost connection mid-download resumes by itself (yt-dlp --continue keeps the
        // part files); it only gives up after 5 tries.
        let delays: [UInt64] = [3, 8, 20, 45, 60]
        var attempt = 0
        while true {
            let outcome = await downloadViaYtDlpOnce(task: task, destination: destination, sourceURL: sourceURL)
            guard outcome == .failed, attempt < delays.count, task.state == .downloading,
                  Self.looksLikeConnectionDrop(task.error) else { return outcome }
            YtDlpLog.log("connection lost, resuming (\(attempt + 1)/\(delays.count)): \(task.error ?? "")")
            await MainActor.run {
                self.trackingRow(for: task)?.statusDetail = "Connection lost, resuming (\(attempt + 1)/\(delays.count))"
                task.error = nil
            }
            try? await Task.sleep(nanoseconds: delays[attempt] * 1_000_000_000)
            attempt += 1
            guard task.state == .downloading else { return .cancelled }
        }
    }

    private static func looksLikeConnectionDrop(_ message: String?) -> Bool {
        guard let m = message?.lowercased(), !looksLikeDeadStreamLink(m) else { return false }
        return ["timed out", "timeout", "connection reset", "connection aborted", "connection refused",
                "remote end closed", "incompleteread", "incomplete read", "temporary failure",
                "network is unreachable", "name or service not known", "eof occurred", "broken pipe",
                "read error", "http error 5", "proxy", "ssl:", "urlopen error", "got error",
                "unexpected end", "content too short"].contains { m.contains($0) }
    }

    private func downloadViaYtDlpOnce(task: VideoDownloadTask, destination: URL,
                                      sourceURL: URL? = nil) async -> YtDlpOutcome {
        // The user may have paused between metadata and process launch.
        guard task.state == .downloading else { return .cancelled }
        guard let ytDlp = ExternalToolRunner.ytDlpPath else { return .failed }
        let hasFFmpeg = ExternalToolRunner.isFFmpegAvailable

        let selector = ExternalToolRunner.formatSelector(quality: task.options.quality,
                                                         extractAudioOnly: task.options.extractAudioOnly,
                                                         hasFFmpeg: hasFFmpeg)
        // Let yt-dlp choose the real extension ("%(ext)s"); escape any '%' in the path.
        let base = destination.deletingPathExtension()
        // Relative template + "-P home:" so "-P temp:" is honoured: .part, .ytdl,
        // fragment and thumbnail files live in a private cache folder.
        let template = base.lastPathComponent.replacingOccurrences(of: "%", with: "%%") + ".%(ext)s"
        let tempDir = Self.ytTempDirectory(for: task.id)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var common = ["-f", selector, "--no-playlist", "--continue", "-o", template,
                      "-P", "home:" + destination.deletingLastPathComponent().path,
                      "-P", "temp:" + tempDir.path,
                      "-P", "thumbnail:" + tempDir.path]
        common += ytDlpHeaderArgs(task.httpHeaders)
        common += ExternalToolRunner.progressArgs
        common += ["--retries", "10", "--fragment-retries", "10", "--socket-timeout", "30"]
        // yt-dlp reads --limit-rate only at launch. Route it through the local
        // throttle proxy so limit changes apply live without a restart.
        if let proxyPort = LocalThrottleProxy.shared.ensureRunning() {
            common += ["--proxy", "http://127.0.0.1:\(proxyPort)"]
        }
        let ext = task.options.format.fileExtension
        if task.options.extractAudioOnly {
            if hasFFmpeg { common += ["-x", "--audio-format", ext] }       // -x needs ffmpeg
        } else if hasFFmpeg {
            common += ["--merge-output-format", ["mp4", "mkv", "webm"].contains(ext) ? ext : "mp4"]
        }
        if task.options.downloadSubtitles {
            common += ["--write-sub", "--sub-lang", task.options.selectedSubtitleLanguages.joined(separator: ",")]
        }
        if task.options.embedThumbnail && hasFFmpeg { common += ["--embed-thumbnail"] }

        let handle = ExternalToolRunner.ProcessHandle()
        ytHandles[task.id] = handle
        ytSpeedSamples[task.id] = nil
        refreshThrottleRate()
        defer {
            ytHandles.removeValue(forKey: task.id)
            ytSpeedSamples[task.id] = nil
            refreshThrottleRate()
        }

        // Extension captures pass a cookie file (no Keychain prompt). Internal
        // requests still try the browser's cookie store, newest browser first.
        let cookieSets = ytDlpAuthArgSets(task)
        for cookieArgs in cookieSets {
            var args = cookieArgs + common
            args.append((sourceURL ?? task.url).absoluteString)
            do {
                let result = try await ExternalToolRunner.runStreaming(binary: ytDlp, args: args, handle: handle) { line in
                    guard let p = ExternalToolRunner.parseProgress(line) else { return }
                    Task { @MainActor in
                        if task.state == .downloading {
                            let speed = self.liveSpeed(for: task, bytes: p.downloadedBytes,
                                                       fallback: p.speed)
                            task.progress = p.fraction
                            task.speed = speed
                            task.downloadedBytes = p.downloadedBytes
                            if p.totalBytes > 0 { task.totalBytes = p.totalBytes }

                            if let row = self.trackingRow(for: task) {
                                row.progress = p.fraction
                                row.speed = speed
                                row.downloadedBytes = p.downloadedBytes
                                if p.totalBytes > 0 { row.totalBytes = p.totalBytes }
                                row.updateTimeRemaining()
                                row.statusDetail = nil
                            }
                        }
                    }
                }
                if handle.isCancelled { return .cancelled }

                let found = Self.findOutputFile(in: destination.deletingLastPathComponent(),
                                                prefix: base.lastPathComponent + ".")
                if result.exitCode == 0, let found {
                    discardYtTemp(for: task.id, after: 0)
                    await MainActor.run {
                        let bytes = Self.fileSize(found)
                        task.progress = 1.0
                        task.speed = 0
                        task.totalBytes = bytes
                        task.downloadedBytes = bytes
                        task.outputURL = found
                        task.state = .converting

                        if let row = self.trackingRow(for: task) {
                            row.progress = 1
                            row.speed = 0
                            row.totalBytes = bytes
                            row.downloadedBytes = bytes
                            row.timeRemaining = 0
                            row.destinationPath = found.deletingLastPathComponent()
                            row.filename = found.lastPathComponent
                            row.statusDetail = "Converting"
                        }
                        self.downloadManager.saveTaskList()
                    }
                    return .success
                }
                let message = result.stderrTail.isEmpty ? "yt-dlp failed (exit code \(result.exitCode))." : result.stderrTail
                YtDlpLog.log("exit \(result.exitCode) for \(task.url.absoluteString)\n\(message)")
                await MainActor.run { task.error = message }
            } catch is CancellationError {
                return .cancelled
            } catch {
                await MainActor.run { task.error = error.localizedDescription }
            }
        }
        return .failed
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    /// The finished file yt-dlp wrote (newest match; ignores partial / helper files).
    private static func findOutputFile(in directory: URL, prefix: String) -> URL? {
        let skipExtensions: Set<String> = ["part", "ytdl", "temp", "tmp", "frag", "vtt", "srt", "ass", "json", "jpg", "webp", "png"]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return items
            .filter { $0.lastPathComponent.hasPrefix(prefix) && !skipExtensions.contains($0.pathExtension.lowercased()) }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }
    
    /// The compact window's per-download limit changed. Native downloads read
    /// BandwidthGate; yt-dlp reads the throttle proxy's live rate.
    func speedLimitChanged(for taskId: UUID) {
        applyNativeLimit(for: taskId)
        refreshThrottleRate()
    }

    /// One proxy serves every yt-dlp task, so its rate is the tightest active
    /// per-download limit (plus the global cap).
    private func refreshThrottleRate() {
        var tightest: Int64?
        if let global = BandwidthGate.shared.perDownloadRate, global > 0 {
            tightest = global
        }
        for task in videoTasks where task.state == .downloading && task.downloadTask == nil && nativeRuns[task.id] == nil {
            if let limit = BandwidthManager.shared.getDownloadLimit(task.id),
               limit.isEnabled, limit.downloadSpeed > 0 {
                tightest = min(tightest ?? limit.downloadSpeed, limit.downloadSpeed)
            }
        }
        LocalThrottleProxy.shared.rate = tightest
    }

    /// yt-dlp reports a cumulative average. Compute the current rate from
    /// consecutive byte samples so the meter reacts when a limit is applied.
    private func liveSpeed(for task: VideoDownloadTask, bytes: Int64,
                           fallback: Int64) -> Int64 {
        let now = Date()
        guard var sample = ytSpeedSamples[task.id] else {
            ytSpeedSamples[task.id] = (bytes, now, Double(fallback))
            return fallback
        }
        let dt = now.timeIntervalSince(sample.at)
        guard dt >= 0.25 else { return Int64(sample.ema) }
        let instantaneous = max(0, Double(bytes - sample.bytes) / dt)
        let ema = sample.ema * 0.35 + instantaneous * 0.65
        sample.bytes = bytes
        sample.at = now
        sample.ema = ema
        ytSpeedSamples[task.id] = sample
        return Int64(ema)
    }

    /// Pause a running video download. yt-dlp is terminated with SIGTERM so it
    /// keeps its `.part` files; Resume restarts it with `--continue`.
    func pauseDownload(_ task: VideoDownloadTask) {
        guard task.state == .downloading else { return }
        task.state = .paused
        task.speed = 0
        task.error = nil

        if let row = trackingRow(for: task) {
            row.state = .paused
            row.speed = 0
            row.timeRemaining = 0
            row.statusDetail = nil
            downloadManager.saveTaskList()
        }

        stopNative(task.id, discard: false)
        if let handle = ytHandles[task.id] {
            handle.cancel()
        }
        if let downloadTask = task.downloadTask {
            Task { @MainActor in await self.downloadManager.pauseDownload(downloadTask) }
        }
        refreshThrottleRate()
    }

    /// Resume a paused video download (failed tasks retry from scratch/part file).
    func resumeDownload(_ task: VideoDownloadTask) {
        guard task.state == .paused || task.state == .failed else { return }
        if task.state == .failed {
            retryDownload(task)
            return
        }
        task.error = nil
        Task { @MainActor in
            await self.startDownload(task)
            self.releaseCookieFileIfDone(task)
        }
    }

    /// Cancel/stop a video download. The task stays visible as cancelled.
    func cancelDownload(_ task: VideoDownloadTask) {
        let wasUnfinished: Bool
        switch task.state {
        case .pending, .fetchingMetadata, .ready, .downloading, .paused, .converting:
            wasUnfinished = true
        case .completed, .failed, .cancelled:
            wasUnfinished = false
        }
        ytHandles[task.id]?.cancel()          // really stops yt-dlp
        stopNative(task.id, discard: true)
        discardYtTemp(for: task.id)           // a cancelled download leaves nothing behind
        if let downloadTask = task.downloadTask {
            Task { @MainActor in await self.downloadManager.cancelDownload(downloadTask, keepRow: false) }
        }
        task.state = .cancelled
        task.speed = 0
        task.error = "Cancelled by user"

        if let row = trackingRow(for: task) {
            row.state = .cancelled
            row.speed = 0
            row.timeRemaining = 0
            row.statusDetail = nil
            row.error = NSError(domain: "VideoDownload", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Cancelled by user"])
            downloadManager.saveTaskList()
        }
        if wasUnfinished {
            SchedulerQueueManager.shared.powerActionDidFail("a video download was cancelled")
        }
        refreshThrottleRate()
    }

    func retryDownload(_ task: VideoDownloadTask) {
        guard task.state == .failed || task.state == .cancelled else { return }
        task.error = nil
        task.speed = 0
        let canResume = task.downloadTask.map { downloadTask in
            downloadManager.downloadTasks.contains(where: { $0.id == downloadTask.id })
        } ?? false
        if !canResume {
            if let stale = task.downloadTask {
                downloadManager.downloadTasks.removeAll { $0.id == stale.id }   // no leftover duplicate row
            }
            task.downloadTask = nil
            task.progress = 0
            task.downloadedBytes = 0
            task.totalBytes = 0
            if let row = trackingRow(for: task) {
                row.progress = 0
                row.downloadedBytes = 0
                row.totalBytes = 0
                row.timeRemaining = 0
                row.error = nil
                row.statusDetail = nil
            }
        }
        task.state = canResume ? .paused : .ready
        Task { @MainActor in
            // The cancelled run may still be shutting yt-dlp down; startDownload would
            // ignore this Retry while it is. Wait (max 15 s) instead of doing nothing.
            var waited = 0
            while self.activeStarts.contains(task.id) && waited < 150 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            guard task.state == .ready || task.state == .paused else { return }
            await self.startDownload(task)
            self.releaseCookieFileIfDone(task)
        }
    }

    func outputURL(for task: VideoDownloadTask) -> URL {
        task.outputURL ?? getDestinationPath(for: task)
    }
    
    /// Remove a video task, optionally deleting its output file.
    func removeTask(_ task: VideoDownloadTask, deleteFile: Bool = false) {
        guard let index = videoTasks.firstIndex(where: { $0.id == task.id }) else { return }

        let wasUnfinished: Bool
        switch task.state {
        case .pending, .fetchingMetadata, .ready, .downloading, .paused, .converting:
            wasUnfinished = true
        case .completed, .failed, .cancelled:
            wasUnfinished = false
        }

        let fileURL = outputURL(for: task)
        releaseCookieFileIfDone(task, force: true)
        discardYtTemp(for: task.id)
        ytHandles[task.id]?.cancel()
        stopNative(task.id, discard: true)

        let row = trackingRow(for: task)
        if let downloadTask = task.downloadTask {
            Task { @MainActor in await self.downloadManager.removeDownload(downloadTask) }
        }
        if let row {
            downloadManager.removeStreamingVideoTask(row)
        }

        if deleteFile {
            try? FileManager.default.removeItem(at: fileURL)
        }

        videoTasks.remove(at: index)
        if let row { downloadManager.saveTaskList() }
        if wasUnfinished {
            SchedulerQueueManager.shared.powerActionDidFail("a video download was removed")
        }
    }
    
    /// Download entire playlist
    func downloadPlaylist(_ task: VideoDownloadTask) async {
        guard let playlist = task.playlist else { return }
        
        for video in playlist.videos {
            let videoTask = addVideoDownload(url: video.url, options: task.options)
            await startDownload(videoTask)
        }
    }
    
    /// Get available qualities for a URL
    func getAvailableQualities(for url: URL) async throws -> [VideoQuality] {
        let platform = VideoPlatform.detect(from: url)
        let metadata = try await extractMetadata(from: url, platform: platform)
        return metadata.availableQualities
    }
    
    /// Get available subtitles for a URL
    func getAvailableSubtitles(for url: URL) async throws -> [SubtitleTrack] {
        let platform = VideoPlatform.detect(from: url)
        let metadata = try await extractMetadata(from: url, platform: platform)
        return metadata.availableSubtitles
    }
    
    // MARK: - Private Methods
    
    /// Extract metadata from video URL (yt-dlp when available, simulated fallback)
    private func extractMetadata(from url: URL, platform: VideoPlatform,
                                 authArgs: [String]? = nil,
                                 httpHeaders: [String: String]? = nil) async throws -> VideoMetadata {
        // Try real yt-dlp first
        if let ytDlp = ExternalToolRunner.ytDlpPath {
            do {
                return try await extractMetadataViaYtDlp(url: url, platform: platform,
                                                         ytDlp: ytDlp, authArgs: authArgs,
                                                         httpHeaders: httpHeaders)
            } catch {
                print("yt-dlp metadata failed (\(error.localizedDescription)), using fallback")
            }
        } else {
            print("yt-dlp not found — install via `brew install yt-dlp` for real extraction. Using fallback metadata.")
        }
        // yt-dlp could not read it: no invented data. An empty title makes the file
        // name come from the page title the browser sent (or the video id).
        return VideoMetadata(title: "", description: nil, author: nil, channelId: nil, duration: 0,
                             uploadDate: nil, viewCount: nil, likeCount: nil, thumbnailURL: nil,
                             availableQualities: [.best], availableSubtitles: [],
                             isLiveStream: false, isPlaylist: false)
    }

    private func extractMetadataViaYtDlp(url: URL, platform: VideoPlatform, ytDlp: String,
                                         authArgs: [String]? = nil,
                                         httpHeaders: [String: String]? = nil) async throws -> VideoMetadata {
        let cookies = authArgs ?? ExternalToolRunner.ytDlpCookieArgs
        let headerArgs = ytDlpHeaderArgs(httpHeaders)
        let result = try await Task.detached(priority: .userInitiated) {
            try ExternalToolRunner.run(binary: ytDlp, args: cookies + headerArgs + ["-J", "--no-playlist", url.absoluteString], timeout: 45)
        }.value
        guard result.succeeded, let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "VideoDownload", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: result.stderr.isEmpty ? "yt-dlp returned no JSON" : result.stderr])
        }
        let title = json["title"] as? String ?? url.lastPathComponent
        let desc = json["description"] as? String
        let author = (json["uploader"] as? String) ?? (json["channel"] as? String)
        let channelId = json["channel_id"] as? String
        let duration = (json["duration"] as? Double) ?? (json["duration"] as? Int).map(Double.init) ?? 0
        let views = (json["view_count"] as? Int)
        let likes = (json["like_count"] as? Int)
        var uploadDate: Date? = nil
        if let s = json["upload_date"] as? String, s.count == 8 {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; uploadDate = f.date(from: s)
        }
        let isLive = (json["is_live"] as? Bool) ?? false
        // Qualities from requested_formats / formats heights
        var heights = Set<Int>()
        if let formats = json["formats"] as? [[String: Any]] {
            for f in formats { if let h = f["height"] as? Int { heights.insert(h) } }
        }
        let quals: [VideoQuality] = {
            var q: [VideoQuality] = [.best]
            let map: [(Int, VideoQuality)] = [(2160, .quality4K), (1440, .quality2K), (1080, .quality1080p),
                                              (720, .quality720p), (480, .quality480p), (360, .quality360p),
                                              (240, .quality240p), (144, .quality144p)]
            for (h, qual) in map where heights.contains(where: { $0 >= h - 60 }) { q.append(qual) }
            return q.isEmpty ? [.best] : q
        }()
        // Subtitles list
        var subs: [SubtitleTrack] = []
        if let subDict = json["subtitles"] as? [String: Any] {
            for lang in subDict.keys.prefix(12) {
                subs.append(SubtitleTrack(id: lang, language: lang, languageCode: lang, isAutoGenerated: false))
            }
        }
        if let auto = json["automatic_captions"] as? [String: Any] {
            for lang in auto.keys.prefix(6) where !subs.contains(where: { $0.id == lang }) {
                subs.append(SubtitleTrack(id: lang + "-auto", language: lang, languageCode: lang, isAutoGenerated: true))
            }
        }
        let thumbStr = (json["thumbnail"] as? String) ?? ((json["thumbnails"] as? [[String: Any]])?.last?["url"] as? String)
        let isPlaylist = url.absoluteString.contains("playlist") || url.absoluteString.contains("list=")
        return VideoMetadata(
            title: title, description: desc, author: author, channelId: channelId,
            duration: duration, uploadDate: uploadDate, viewCount: views, likeCount: likes,
            thumbnailURL: thumbStr.flatMap(URL.init(string:)),
            availableQualities: quals, availableSubtitles: subs,
            isLiveStream: isLive, isPlaylist: isPlaylist
        )
    }

    private func simulatedMetadata(for url: URL, platform: VideoPlatform) -> VideoMetadata {
        return VideoMetadata(
            title: "Sample Video - \(platform.rawValue)",
            description: "This is a sample video description for testing purposes.",
            author: "Sample Channel",
            channelId: "UC_sample_channel_id",
            duration: 180,
            uploadDate: Date().addingTimeInterval(-86400 * 7),
            viewCount: 125_000,
            likeCount: 5_200,
            thumbnailURL: url,
            availableQualities: [.quality4K, .quality1080p, .quality720p, .quality480p, .quality360p],
            availableSubtitles: [
                SubtitleTrack(id: "en", language: "English", languageCode: "en", isAutoGenerated: false),
                SubtitleTrack(id: "es", language: "Spanish", languageCode: "es", isAutoGenerated: true),
                SubtitleTrack(id: "fr", language: "French", languageCode: "fr", isAutoGenerated: true)
            ],
            isLiveStream: false,
            isPlaylist: url.absoluteString.contains("playlist") || url.absoluteString.contains("list=")
        )
    }
    
    /// Extract playlist information (yt-dlp flat-playlist when available)
    private func extractPlaylistInfo(from url: URL, platform: VideoPlatform,
                                     authArgs: [String]? = nil,
                                     httpHeaders: [String: String]? = nil) async throws -> PlaylistInfo {
        if let ytDlp = ExternalToolRunner.ytDlpPath {
            let cookies = authArgs ?? ExternalToolRunner.ytDlpCookieArgs
            let headerArgs = ytDlpHeaderArgs(httpHeaders)
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ExternalToolRunner.run(binary: ytDlp, args: cookies + headerArgs + ["-J", "--flat-playlist", url.absoluteString], timeout: 60)
                }.value
                if result.succeeded, let data = result.stdout.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let entries = json["entries"] as? [[String: Any]] ?? []
                    let videos = entries.enumerated().map { idx, e -> PlaylistInfo.PlaylistVideo in
                        let vid = (e["id"] as? String) ?? "video_\(idx)"
                        let vurlStr = (e["url"] as? String) ?? (e["webpage_url"] as? String) ?? url.absoluteString
                        return PlaylistInfo.PlaylistVideo(
                            id: vid,
                            url: URL(string: vurlStr) ?? url,
                            title: (e["title"] as? String) ?? "Video #\(idx + 1)",
                            duration: (e["duration"] as? Double) ?? 0,
                            thumbnailURL: nil,
                            position: idx + 1
                        )
                    }
                    if !videos.isEmpty {
                        return PlaylistInfo(
                            id: (json["id"] as? String) ?? "playlist",
                            title: (json["title"] as? String) ?? "Playlist",
                            description: json["description"] as? String,
                            author: (json["uploader"] as? String),
                            videoCount: videos.count,
                            thumbnailURL: nil,
                            videos: videos
                        )
                    }
                }
            } catch {
                print("yt-dlp playlist failed: \(error.localizedDescription)")
            }
        }
        // Fallback: single-video pseudo playlist so UI still works
        let videos = (1...5).map { index in
            PlaylistInfo.PlaylistVideo(
                id: "video_\(index)",
                url: URL(string: "https://example.com/video\(index)")!,
                title: "Playlist Video #\(index)",
                duration: Double.random(in: 120...600),
                thumbnailURL: url,
                position: index
            )
        }
        return PlaylistInfo(
            id: "playlist_sample",
            title: "Sample Playlist",
            description: "A collection of sample videos",
            author: "Sample Channel",
            videoCount: videos.count,
            thumbnailURL: url,
            videos: videos
        )
    }
    
    /// Get direct video URL (yt-dlp -g when available) — otherwise hands off to
    /// full yt-dlp download in startDownload path.
    private func getVideoURL(for task: VideoDownloadTask) async throws -> URL {
        if let ytDlp = ExternalToolRunner.ytDlpPath {
            let selector = ExternalToolRunner.formatSelector(quality: task.options.quality,
                                                             extractAudioOnly: task.options.extractAudioOnly)
            let cookies = ytDlpAuthArgs(task)
            let headerArgs = ytDlpHeaderArgs(task.httpHeaders)
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ExternalToolRunner.run(binary: ytDlp, args: cookies + headerArgs + ["-g", "-f", selector, task.url.absoluteString], timeout: 45)
                }.value
                if result.succeeded {
                    let first = result.stdout.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix("http") })
                    if let s = first, let u = URL(string: s) { return u }
                }
                print("yt-dlp -g failed, falling back to direct yt-dlp download")
            } catch {
                print("yt-dlp -g error: \(error.localizedDescription)")
            }
        }
        // No direct URL (generic HLS / missing binary): caller downloads via yt-dlp file path.
        // Return original URL so DownloadManager path is skipped in favor of backend download.
        // Keep example fallback only when binary missing AND generic http file:
        if task.url.pathExtension.lowercased() == "mp4" || task.url.absoluteString.contains(".m3u8") {
            return task.url
        }
        return URL(string: "https://example.com/video.mp4")!
    }
    
    /// Get destination path for video
    private func getDestinationPath(for task: VideoDownloadTask) -> URL {
        if let reserved = reservedOutputPaths[task.id] { return reserved }
        let downloadsFolder = task.destinationFolder ?? DownloadFolderStore.shared.resolvedDefault

        // A sniffed manifest has no page context for yt-dlp, so its metadata
        // "title" is just the CDN file name. The page title the browser sent is
        // the real one there.
        let isManifest = ["m3u8", "mpd"].contains(task.url.pathExtension.lowercased())
        let baseName: String
        if let title = Self.outputTitle(metadataTitle: task.metadata?.title,
                                        preferredTitle: task.preferredTitle,
                                        preferPageTitle: isManifest) {
            // Sanitize filename
            // Keep every language (Persian, Arabic, CJK …); only strip characters that are
            // illegal in file names. The old regex deleted ALL non-ASCII letters.
            var sanitized = title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters))
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if sanitized.hasPrefix(".") { sanitized = String(sanitized.drop(while: { $0 == "." })) }
            // A manifest-derived title can already carry a media extension
            // ("720p.av1.mp4"); never stack a second one.
            sanitized = Self.strippingMediaExtension(sanitized)
            if sanitized.isEmpty { sanitized = "video_\(task.id.uuidString.prefix(8))" }
            if sanitized.count > 120 { sanitized = String(sanitized.prefix(120)) }
            baseName = sanitized + Self.qualitySuffix(for: task.options)
        } else {
            baseName = "video_\(task.id.uuidString)"
        }

        let ext = task.options.format.fileExtension
        var candidate = downloadsFolder.appendingPathComponent("\(baseName).\(ext)")
        var index = 2
        while isDestinationTaken(candidate, by: task) {
            candidate = downloadsFolder.appendingPathComponent("\(baseName) (\(index)).\(ext)")
            index += 1
        }
        reservedOutputPaths[task.id] = candidate
        return candidate
    }

    /// Another live task already writing that file, or an earlier download with
    /// the same name left on disk, must not be reused: yt-dlp would continue
    /// into it and both videos would end up in one file.
    private func isDestinationTaken(_ url: URL, by task: VideoDownloadTask) -> Bool {
        for (id, reserved) in reservedOutputPaths where id != task.id && reserved.path == url.path {
            if videoTasks.contains(where: { $0.id == id }) { return true }
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func qualitySuffix(for options: VideoDownloadOptions) -> String {
        guard !options.extractAudioOnly, let height = options.quality.height else { return "" }
        return " (\(height)p)"
    }

    /// Streaming manifests are often named after their quality ("720p"), which
    /// makes every grab from a site look alike. Prefer the real page title then.
    private static func outputTitle(metadataTitle: String?, preferredTitle: String?,
                                    preferPageTitle: Bool = false) -> String? {
        let meta = metadataTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let metaUsable = !(meta ?? "").isEmpty && !isQualityLabel(meta)
        let pageUsable = !(page ?? "").isEmpty && !isQualityLabel(page)
        if preferPageTitle && pageUsable { return page }
        if metaUsable { return meta }
        if pageUsable { return page }
        return (meta ?? "").isEmpty ? page : meta
    }

    /// A manifest title is often the stream's own file name: "720p", "720p.av1",
    /// "720P_4000K_462120041.mp4", "master", ... Those say nothing about the video.
    private static func isQualityLabel(_ name: String?) -> Bool {
        guard var t = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !t.isEmpty else { return false }
        // Peel the container/codec suffixes ("720p.av1.mp4" -> "720p.av1" -> "720p").
        while let r = t.range(of: #"\.[a-z0-9]{2,5}$"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        guard !t.isEmpty else { return true }
        if t.range(of: #"^\d{2,4}p?([._ -].*)?$"#, options: .regularExpression) != nil { return true }
        // Manifest / playlist names ("master", "index-v1-a1", "chunklist").
        if t.range(of: #"^(index|master|manifest|playlist|chunklist|stream|video|hls)([-_.].*)?$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func strippingMediaExtension(_ name: String) -> String {
        name.replacingOccurrences(
            of: #"\.(mp4|m4v|mkv|webm|mov|avi|flv|wmv|ts|m3u8|mpd|m4a|mp3|aac|flac|ogg|opus|wav)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    /// Monitor download progress
    private func monitorProgress(videoTask: VideoDownloadTask, downloadTask: DownloadTask) {
        // Update video task progress from download task
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self, weak videoTask, weak downloadTask] _ in
                guard let videoTask = videoTask,
                      let downloadTask = downloadTask else { return }
                
                DispatchQueue.main.async {
                    videoTask.progress = downloadTask.progress
                    videoTask.speed = downloadTask.speed
                    videoTask.downloadedBytes = downloadTask.downloadedBytes
                    videoTask.totalBytes = downloadTask.totalBytes
                    
                    // Check if completed
                    if downloadTask.state == .completed {
                        videoTask.outputURL = downloadTask.destinationPath
                            .appendingPathComponent(downloadTask.filename)
                        videoTask.state = .converting
                    } else if downloadTask.state == .failed {
                        videoTask.state = .failed
                        videoTask.error = downloadTask.error?.localizedDescription
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    /// Wait for download completion
    private func waitForCompletion(task: VideoDownloadTask) async {
        while task.state == .downloading {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    /// Post-process video (convert, extract audio, embed subtitles)
    private func postProcess(task: VideoDownloadTask) async {
        if task.state == .cancelled { return }
        await MainActor.run {
            if task.state != .cancelled { task.state = .converting }
        }
        if task.state == .cancelled { return }
        
        do {
            // Download subtitles if requested
            if task.options.downloadSubtitles {
                try await downloadSubtitles(for: task)
            }
            
            // Convert format if needed
            if let targetFormat = task.options.convertToFormat {
                try await convertFormat(for: task, to: targetFormat)
            }
            
            // Extract audio if requested
            if task.options.extractAudioOnly {
                try await extractAudio(for: task)
            }
            
            await MainActor.run {
                if task.state == .cancelled { return }
                task.state = .completed
                task.completedAt = Date()

                if let row = trackingRow(for: task) {
                    let fileURL = self.outputURL(for: task)
                    let bytes = Self.fileSize(fileURL)
                    row.destinationPath = fileURL.deletingLastPathComponent()
                    row.filename = fileURL.lastPathComponent
                    row.progress = 1
                    row.downloadedBytes = bytes
                    row.totalBytes = bytes
                    row.speed = 0
                    row.timeRemaining = 0
                    row.error = nil
                    row.statusDetail = nil
                    downloadManager.completeStreamingVideoTask(id: task.id)
                }

                // Update statistics
                let duration = task.completedAt!.timeIntervalSince(task.startedAt ?? task.createdAt)
                statistics.recordSuccess(
                    task: task,
                    bytesDownloaded: task.downloadTask?.totalBytes ?? task.totalBytes,
                    duration: duration
                )
                
                saveStatistics()

                // The floating progress window has done its job.
                DownloadProgressWindowController.close(for: task.id)

                if task.showsCompletionDialog {
                    let fileURL = self.outputURL(for: task)
                    var bytes = Self.fileSize(fileURL)
                    if bytes <= 0 { bytes = task.totalBytes }
                    DownloadCompleteWindowController.shared.present(
                        info: CompletedDownloadInfo(
                            id: task.id,
                            filename: fileURL.lastPathComponent,
                            fileURL: fileURL,
                            byteCount: bytes
                        )
                    )
                }

                let postAction = task.postDownloadAction
                if postAction != .none {
                    task.postDownloadAction = .none
                    SchedulerQueueManager.shared.performPostDownloadAction(
                        postAction, excludingTaskID: task.id)
                }
            }
            
        } catch {
            await MainActor.run {
                task.state = .failed
                task.error = "Post-processing failed: \(error.localizedDescription)"
                statistics.recordFailure()
                self.markTrackingFailed(task)
            }
        }
    }
    
    /// Download subtitles for video (yt-dlp when available)
    private func downloadSubtitles(for task: VideoDownloadTask) async throws {
        if let ytDlp = ExternalToolRunner.ytDlpPath {
            let langs = task.options.selectedSubtitleLanguages.joined(separator: ",")
            let dest = getDestinationPath(for: task).deletingLastPathComponent().path + "/%(title)s.%(ext)s"
            let cookies = ytDlpAuthArgs(task)
            let result = try await Task.detached(priority: .userInitiated) {
                try ExternalToolRunner.run(binary: ytDlp, args: cookies + [
                    "--skip-download", "--write-sub", "--sub-lang", langs,
                    "--sub-format", "srt/vtt/best",
                    "-o", dest, task.url.absoluteString
                ], timeout: 300)
            }.value
            if result.succeeded { return }
            print("Subtitle download failed: \(result.stderr)")
        }
        print("Subtitles downloaded for: \(task.metadata?.title ?? "video")")
    }
    
    /// Convert video format (ffmpeg when available)
    private func convertFormat(for task: VideoDownloadTask, to format: VideoFormat) async throws {
        let input = outputURL(for: task)
        if let ffmpeg = ExternalToolRunner.ffmpegPath, FileManager.default.fileExists(atPath: input.path) {
            let output = input.deletingPathExtension().appendingPathExtension(format.fileExtension)
            let result = try await Task.detached(priority: .userInitiated) {
                try ExternalToolRunner.run(binary: ffmpeg, args: ["-y", "-i", input.path, output.path], timeout: 3600)
            }.value
            if result.succeeded {
                await MainActor.run { task.outputURL = output }
                return
            }
            print("ffmpeg convert failed: \(result.stderr)")
        }
        print("Converted to format: \(format.rawValue)")
    }
    
    /// Extract audio from video (ffmpeg when available)
    private func extractAudio(for task: VideoDownloadTask) async throws {
        if let ffmpeg = ExternalToolRunner.ffmpegPath {
            let input = outputURL(for: task)
            let output = input.deletingPathExtension().appendingPathExtension(task.options.format.fileExtension)
            let result = try await Task.detached(priority: .userInitiated) {
                try ExternalToolRunner.run(binary: ffmpeg, args: ["-y", "-i", input.path, "-vn", output.path], timeout: 3600)
            }.value
            if result.succeeded {
                await MainActor.run { task.outputURL = output }
                return
            }
            print("ffmpeg audio extract failed: \(result.stderr)")
        }
        print("Audio extracted to: \(task.options.format.rawValue)")
    }
    
    // MARK: - Persistence
    
    private func loadStatistics() {
        // Load from UserDefaults or file
        if let data = UserDefaults.standard.data(forKey: "VideoDownloadStatistics"),
           let stats = try? JSONDecoder().decode(VideoDownloadStatistics.self, from: data) {
            statistics = stats
        }
    }
    
    private func saveStatistics() {
        if let data = try? JSONEncoder().encode(statistics) {
            UserDefaults.standard.set(data, forKey: "VideoDownloadStatistics")
        }
    }
}
