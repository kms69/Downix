//
//  DownloadManager.swift
//  Download Manager for Mac
//

import Foundation
import Combine

/// Main download manager - singleton that manages all downloads.
///
/// This class is the ONLY owner of a task's state. The engine (SegmentDownloader)
/// just does the transfer and throws `CancellationError` when told to stop, so a
/// late callback can never overwrite what the user asked for.
@MainActor
class DownloadManager: ObservableObject {

    static let shared = DownloadManager()

    @Published var downloadTasks: [DownloadTask] = []
    @Published var activeDownloads: Int = 0 {
        didSet { BandwidthGate.shared.activeDownloads = activeDownloads }
    }
    @Published var totalDownloadSpeed: Int64 = 0

    /// Global speed limit in bytes/second (nil = unlimited). Enforced by the engine.
    var globalBandwidthLimit: Int64? = nil {
        didSet { BandwidthGate.shared.limit = globalBandwidthLimit }
    }
    /// Safety ceiling only; the real limit is each queue's own "files at the same time".
    var maxConcurrentDownloads: Int = 32
    var defaultNumberOfSegments: Int = 8
    var defaultSaveLocation: URL
    var hasActiveDownloads: Bool { downloadTasks.contains { $0.state == .downloading } }

    private var segmentDownloaders: [UUID: SegmentDownloader] = [:]
    private var taskHandles: [UUID: Task<Void, Never>] = [:]
    /// Identifies the CURRENT run of a task so a stale run can never fail a newer one.
    private var runTokens: [UUID: UUID] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.defaultSaveLocation = DownloadFolderStore.shared.resolvedDefault
        loadTaskList()          // restore previous session
        startMonitoring()

        // Hand restored scheduled tasks to the scheduler once init has finished.
        Task { @MainActor [weak self] in
            guard let self else { return }
            DownloadScheduler.shared.restoreScheduledTasks(self.downloadTasks.filter { $0.schedule != nil })
        }
    }

    // MARK: - Public API

    @discardableResult
    func addDownload(url: URL,
                     destinationPath: URL? = nil,
                     filename: String? = nil,
                     numberOfSegments: Int? = nil,
                     headers: [String: String] = [:],
                     startImmediately: Bool = true,
                     priority: DownloadPriority = .normal,
                     category: DownloadCategory? = nil) -> DownloadTask {
        let destination = destinationPath ?? defaultSaveLocation
        let segs = numberOfSegments ?? defaultNumberOfSegments
        let task = DownloadTask(url: url, destinationPath: destination, filename: filename, numberOfSegments: segs)
        task.requestHeaders = headers
        task.priority = priority
        task.category = category ?? DownloadCategory.detect(from: task.filename)
        downloadTasks.append(task)
        QueueRunController.shared.assignToDefaultQueueIfNeeded(task.id)   // Main Download Queue unless the caller picks another
        saveTaskList()
        if startImmediately { processQueue() }
        return task
    }

    /// Queue slot of a restored streaming row that is being replaced by a fresh download (keyed by URL).
    private var pendingStreamQueue: [URL: (queueID: UUID, index: Int)] = [:]

    /// Register a main-list row for a streaming video handled by yt-dlp.
    /// The row is the single source of truth for the list UI; the video
    /// manager pushes status/progress/completion into it.
    @discardableResult
    func trackStreamingVideoTask(id: UUID, url: URL, destination: URL) -> DownloadTask {
        // (queue slot hand-over: see pendingStreamQueue)
        if let existing = downloadTasks.first(where: { $0.videoTaskID == id }) {
            return existing
        }
        let row = DownloadTask(
            url: url,
            destinationPath: destination.deletingLastPathComponent(),
            filename: destination.lastPathComponent
        )
        row.videoTaskID = id
        row.fileType = "video"
        row.state = .downloading
        row.lastAttemptAt = Date()
        downloadTasks.append(row)
        if let slot = pendingStreamQueue.removeValue(forKey: url) {
            let qm = SchedulerQueueManager.shared
            qm.assignTask(row.id, to: slot.queueID)
            if let qi = qm.queues.firstIndex(where: { $0.id == slot.queueID }),
               let cur = qm.queues[qi].taskIDs.firstIndex(of: row.id) {
                qm.queues[qi].taskIDs.remove(at: cur)
                qm.queues[qi].taskIDs.insert(row.id, at: min(slot.index, qm.queues[qi].taskIDs.count))
                qm.save()
            }
            row.schedulerQueueID = slot.queueID
        }
        saveTaskList()
        return row
    }

    func streamingVideoRow(id: UUID) -> DownloadTask? {
        downloadTasks.first { $0.videoTaskID == id }
    }

    /// Called by `VideoDownloadManager` after yt-dlp/post-processing finished.
    func completeStreamingVideoTask(id: UUID) {
        guard let row = streamingVideoRow(id: id) else { return }
        row.state = .completed
        row.completedAt = Date()
        row.progress = 1
        row.speed = 0
        row.timeRemaining = 0
        row.error = nil
        row.statusDetail = nil
        recordToHistory(task: row, status: .completed)
        saveTaskList()
        QueueRunController.shared.taskDidFinish(row)        // one-time processing: leave the queue
    }

    func failStreamingVideoTask(id: UUID) {
        guard let row = streamingVideoRow(id: id) else { return }
        row.state = .failed
        row.speed = 0
        row.timeRemaining = 0
        row.statusDetail = nil
        recordToHistory(task: row, status: .failed)
        saveTaskList()
    }

    /// Remove a streaming row without routing through the regular cancel path.
    func removeStreamingVideoTask(_ row: DownloadTask) {
        downloadTasks.removeAll { $0.id == row.id }
        saveTaskList()
    }

    /// The video task that owns this row, if it is a streaming video mirror.
    /// The video task behind a restored streaming row no longer exists after a relaunch:
    /// replace the row with a fresh download of the same page.
    private func restartRestoredStreaming(_ row: DownloadTask) {
        let url = row.url
        let folder = row.destinationPath
        // The replacement row is created later; remember the queue slot so it can take it over.
        let qm = SchedulerQueueManager.shared
        if let q = qm.queue(for: row.id), let idx = q.taskIDs.firstIndex(of: row.id) {
            pendingStreamQueue[url] = (q.id, idx)
        }
        downloadTasks.removeAll { $0.id == row.id }
        saveTaskList()
        _ = VideoDownloadManager.shared.addAndStartDownload(url: url, destinationFolder: folder)
    }

    private func linkedVideoTask(for task: DownloadTask) -> VideoDownloadTask? {
        guard let videoTaskID = task.videoTaskID else { return nil }
        return VideoDownloadManager.shared.videoTasks.first { $0.id == videoTaskID }
    }

    /// Force-start a task now (ignores the concurrency limit; used by the scheduler).
    func startDownload(_ task: DownloadTask) {
        guard task.state != .completed else { return }
        if let videoTask = linkedVideoTask(for: task) {
            VideoDownloadManager.shared.resumeDownload(videoTask)
            return
        }
        task.isHeldForSchedule = false
        beginDownload(task)
    }

    func pauseDownload(_ task: DownloadTask, byScheduler: Bool = false) async {
        if let videoTask = linkedVideoTask(for: task) {
            VideoDownloadManager.shared.pauseDownload(videoTask)
            return
        }
        guard task.state == .downloading else { return }
        stopEngine(for: task, keepPartialData: true)
        task.state = .paused
        task.speed = 0
        task.manuallyHeld = !byScheduler
        activeDownloads = max(0, activeDownloads - 1)
        saveTaskList()
        processQueue()
    }

    /// Queue the task to continue. It starts immediately when a slot is free.
    func resumeDownload(_ task: DownloadTask) async {
        if let videoTask = linkedVideoTask(for: task) {
            VideoDownloadManager.shared.resumeDownload(videoTask)
            return
        }
        if task.isRestoredStreaming { restartRestoredStreaming(task); return }
        guard task.state == .paused || task.state == .failed || task.state == .cancelled else { return }
        task.error = nil
        task.manuallyHeld = false
        task.isHeldForSchedule = false      // an explicit Resume starts a scheduled download early
        task.state = .waiting
        saveTaskList()
        processQueue()
    }

    func cancelDownload(_ task: DownloadTask, keepRow: Bool = true) async {
        if let videoTask = linkedVideoTask(for: task) {
            VideoDownloadManager.shared.cancelDownload(videoTask)
            return
        }
        let wasUnfinished = task.state == .downloading || task.state == .waiting || task.state == .paused
        let wasActive = task.state == .downloading
        stopEngine(for: task, keepPartialData: false)
        taskHandles.removeValue(forKey: task.id)
        if wasActive { activeDownloads = max(0, activeDownloads - 1) }
        task.state = .cancelled
        task.speed = 0
        if keepRow {
            // Stay in the list as "Cancelled" (Re-add to Queue / Remove are still there).
            task.progress = 0
            task.downloadedBytes = 0
            task.timeRemaining = 0
            task.statusDetail = nil
        } else {
            downloadTasks.removeAll { $0.id == task.id }
        }
        DownloadScheduler.shared.removeScheduledDownload(task)
        SegmentDownloader.discardPartialData(for: task.id)
        saveTaskList()
        if wasUnfinished {
            SchedulerQueueManager.shared.powerActionDidFail("a download was cancelled")
        }
        processQueue()
    }

    func removeDownload(_ task: DownloadTask) async {
        if let videoTask = linkedVideoTask(for: task) {
            VideoDownloadManager.shared.removeTask(videoTask)
            return
        }
        await cancelDownload(task)
        // Failed/cancelled tasks keep an error message and partial work files;
        // removing them must clear both, not silently leave the row behind.
        task.error = nil
        SegmentDownloader.discardPartialData(for: task.id)
        downloadTasks.removeAll { $0.id == task.id }
        saveTaskList()
    }

    /// `auto == true` is used by system actors (network monitor): those downloads
    /// are NOT marked as user-paused, so `resumeAll(onlyAutoPaused:)` can restore them.
    func pauseAll(auto: Bool = false) async {
        for task in downloadTasks where task.state == .downloading {
            await pauseDownload(task, byScheduler: auto)
        }
    }

    func resumeAll(onlyAutoPaused: Bool = false) async {
        for task in downloadTasks where task.state == .paused || (!onlyAutoPaused && task.state == .failed) {
            if task.videoTaskID != nil || task.isRestoredStreaming { continue }   // streaming rows are driven by the video manager
            if task.isHeldForSchedule { continue }              // waits for its own schedule
            if onlyAutoPaused && task.manuallyHeld { continue }
            await resumeDownload(task)
        }
    }

    func clearCompleted() async {
        let completed = downloadTasks.filter { $0.state == .completed }
        for row in completed where row.videoTaskID != nil {
            if let videoTask = linkedVideoTask(for: row) {
                VideoDownloadManager.shared.removeTask(videoTask)
            }
        }
        downloadTasks.removeAll { $0.state == .completed }
        saveTaskList()
    }

    /// Stop an active download but keep it (and its partial data) in the list.
    /// It shows as "Paused" (not "Failed"): the user stopped it on purpose.
    func stopDownload(_ task: DownloadTask) async {
        if let videoTask = linkedVideoTask(for: task) {
            VideoDownloadManager.shared.pauseDownload(videoTask)
            return
        }
        let wasActive = task.state == .downloading
        stopEngine(for: task, keepPartialData: true)
        if wasActive { activeDownloads = max(0, activeDownloads - 1) }
        task.state = .paused
        task.error = nil
        task.speed = 0
        task.manuallyHeld = true
        saveTaskList()
        if wasActive {
            SchedulerQueueManager.shared.powerActionDidFail("a download was stopped")
        }
        processQueue()
    }

    /// Start all waiting/paused downloads up to the concurrency limit
    func startQueue() {
        for task in downloadTasks where (task.state == .paused || task.state == .failed) && !task.isHeldForSchedule {
            if task.videoTaskID != nil || task.isRestoredStreaming { continue }
            task.error = nil
            task.manuallyHeld = false
            task.state = .waiting
        }
        saveTaskList()
        processQueue()
    }

    /// Pause all active downloads (stops the queue)
    func stopQueue() {
        Task { @MainActor in await pauseAll() }
    }

    /// Move a task to the front of its queue (it is the next one to start).
    func moveToFront(_ task: DownloadTask) {
        guard let idx = downloadTasks.firstIndex(where: { $0.id == task.id }) else { return }
        downloadTasks.remove(at: idx)
        downloadTasks.insert(task, at: 0)
        moveInQueue([task.id], .top)
    }

    /// Move a task to the end of its queue.
    func moveToEnd(_ task: DownloadTask) {
        guard let idx = downloadTasks.firstIndex(where: { $0.id == task.id }) else { return }
        downloadTasks.remove(at: idx)
        downloadTasks.append(task)
        moveInQueue([task.id], .bottom)
    }

    /// Reorder downloads inside their queues and let the engine pick the new start order.
    func moveInQueue(_ ids: Set<UUID>, _ direction: SchedulerQueueManager.MoveDirection) {
        let manager = SchedulerQueueManager.shared
        var perQueue: [UUID: Set<UUID>] = [:]
        for id in ids {
            if let q = manager.queue(for: id) { perQueue[q.id, default: []].insert(id) }
        }
        for (queueID, set) in perQueue { manager.move(set, in: queueID, direction) }
        saveTaskList()
        objectWillChange.send()
        processQueue()
    }

    /// Delete the downloaded file from disk then remove the task from the list
    func deleteFileAndRemove(_ task: DownloadTask) async {
        if let videoTask = linkedVideoTask(for: task) {
            let url = VideoDownloadManager.shared.outputURL(for: videoTask)
            VideoDownloadManager.shared.removeTask(videoTask)
            DownloadManager.deleteLeftovers(of: url)
            return
        }
        let url = task.fileURL
        await removeDownload(task)
        DownloadManager.deleteLeftovers(of: url)
    }

    /// Delete the output file and any partial/temporary siblings. Repeated a
    /// moment later because a just-cancelled yt-dlp/ffmpeg process can still
    /// recreate its .part file after the first pass.
    static func deleteLeftovers(of url: URL) {
        func sweep() {
            let fm = FileManager.default
            let p = url.path
            let stem = url.deletingPathExtension().path
            for path in [p, p + ".part", p + ".ytdl", p + ".download", p + ".tmp",
                         stem + ".part", stem + ".ytdl"] {
                if fm.fileExists(atPath: path) { try? fm.removeItem(atPath: path) }
            }
            // yt-dlp fragments: "<name>.f137.mp4.part", "<name>.f251.webm" ...
            let dir = url.deletingLastPathComponent()
            let base = url.deletingPathExtension().lastPathComponent
            if !base.isEmpty, let items = try? fm.contentsOfDirectory(atPath: dir.path) {
                for item in items where item.hasPrefix(base + ".f") && (item.hasSuffix(".part") || item.hasSuffix(".ytdl")) {
                    try? fm.removeItem(at: dir.appendingPathComponent(item))
                }
            }
        }
        sweep()
        for delay in [1.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sweep() }
        }
    }

    /// Re-add a cancelled download back to the queue
    func requeueDownload(_ task: DownloadTask) {
        if let videoTask = linkedVideoTask(for: task) {
            VideoDownloadManager.shared.retryDownload(videoTask)
            return
        }
        if task.isRestoredStreaming { restartRestoredStreaming(task); return }
        task.state = .waiting
        task.progress = 0
        task.downloadedBytes = 0
        task.retryCount = 0
        task.error = nil
        task.manuallyHeld = false
        processQueue()
    }

    // MARK: - Engine callbacks

    /// Called by the engine once the file is on disk. The manager sets the state.
    func downloadDidComplete(taskId: UUID) {
        guard let task = downloadTasks.first(where: { $0.id == taskId }) else { return }
        let wasActive = task.state == .downloading
        task.state = .completed
        task.completedAt = Date()
        task.progress = 1.0
        task.speed = 0
        task.timeRemaining = 0
        task.error = nil
        if wasActive { activeDownloads = max(0, activeDownloads - 1) }
        autoResumeAttempts[taskId] = nil
        autoResumeBaseline[taskId] = nil
        cleanup(taskId)
        recordToHistory(task: task, status: .completed)
        saveTaskList()
        if let handler = completionHandler {
            Task { await handler(task) }
        }
        SchedulerQueueManager.shared.taskDidComplete(task)   // per-download / per-queue "after completion" actions
        QueueRunController.shared.taskDidFinish(task)        // one-time processing: leave the queue
        processQueue()
    }

    func downloadDidFail(taskId: UUID) {
        guard let task = downloadTasks.first(where: { $0.id == taskId }) else { return }
        recordToHistory(task: task, status: .failed)
        saveTaskList()
        SchedulerQueueManager.shared.powerActionDidFail("a download failed")
        QueueRunController.shared.taskDidFail(task)
        if let err = task.error, let handler = errorHandler {
            Task { await handler(task, err) }
        }
        processQueue()
    }

    // MARK: - Private

    /// Stop the engine for a task. Optionally keeps the partial data for resuming.
    private func stopEngine(for task: DownloadTask, keepPartialData: Bool) {
        if let engine = segmentDownloaders[task.id] {
            if keepPartialData { engine.pause() } else { engine.cancel() }
        }
        // Keep the (cancelled) handle: a later run waits for it to finish
        // flushing its files before it touches them.
        taskHandles[task.id]?.cancel()
        segmentDownloaders.removeValue(forKey: task.id)
        runTokens.removeValue(forKey: task.id)
    }

    private func cleanup(_ id: UUID) {
        segmentDownloaders.removeValue(forKey: id)
        taskHandles.removeValue(forKey: id)
        runTokens.removeValue(forKey: id)
    }

    private func beginDownload(_ task: DownloadTask) {
        guard task.state != .downloading else { return }

        let previous = taskHandles[task.id]       // a paused/stopped run that may still be flushing
        previous?.cancel()

        let downloader = SegmentDownloader(downloadTask: task)
        let token = UUID()
        runTokens[task.id] = token
        segmentDownloaders[task.id] = downloader

        activeDownloads += 1
        task.state = .downloading
        task.error = nil
        task.statusDetail = nil
        task.lastAttemptAt = Date()
        task.manuallyHeld = false
        if let action = task.postDownloadAction, action == .sleep || action == .shutdown {
            SchedulerQueueManager.shared.requestPowerAction(action, triggeredBy: task.id)
        }
        saveTaskList()

        taskHandles[task.id] = Task.detached(priority: .userInitiated) { [weak self] in
            // Never run two engines on the same partial files at once.
            await previous?.value
            do {
                try await downloader.start()
            } catch is CancellationError {
                // Pause / stop / cancel won — the manager already set the state.
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.runTokens[task.id] == token,
                          task.state == .downloading else { return }
                    let ns = error as NSError
                    YtDlpLog.log("download error: \(task.filename) at \(task.downloadedBytes) bytes: \(ns.domain) \(ns.code) \(error.localizedDescription) retryable=\(SegmentDownloader.isRetryable(error))")
                    if self.scheduleAutoResume(task, after: error) { return }
                    task.state = .failed
                    task.error = error
                    task.speed = 0
                    self.activeDownloads = max(0, self.activeDownloads - 1)
                    self.cleanup(task.id)
                    self.downloadDidFail(taskId: task.id)
                }
            }
        }
    }

    // MARK: - Auto-resume of interrupted downloads

    /// Silent retries allowed per interruption streak.
    private static let maxAutoResumes = 6
    private static let autoResumeDelays: [TimeInterval] = [3, 10, 30, 60, 60, 120]
    private var autoResumeAttempts: [UUID: Int] = [:]
    private var autoResumeBaseline: [UUID: Int64] = [:]
    private var autoResumePending = Set<UUID>()

    /// A network error / timeout interrupted the download. Quietly resume it
    /// (up to 3 times, with growing pauses). Returns true when a retry was
    /// scheduled; false means the caller should mark the task failed. When
    /// resuming is impossible or the attempts run out, a notification is posted.
    private func scheduleAutoResume(_ task: DownloadTask, after error: Error) -> Bool {
        guard SegmentDownloader.isRetryable(error) else { return false }

        // Progress since the last failure → this is a fresh interruption.
        let baseline = autoResumeBaseline[task.id] ?? 0
        if task.downloadedBytes > baseline + 256 * 1024 { autoResumeAttempts[task.id] = 0 }
        autoResumeBaseline[task.id] = task.downloadedBytes

        // The server cannot continue a partial file: a restart would silently
        // throw the data away, so tell the user instead.
        if task.downloadedBytes > 0 && !task.supportsResume {
            notifyResumeFailed(task, reason: "The server does not support resuming. Open the app and restart the download.")
            return false
        }
        let attempt = (autoResumeAttempts[task.id] ?? 0) + 1
        if attempt > Self.maxAutoResumes {
            notifyResumeFailed(task, reason: "The connection kept failing after \(Self.maxAutoResumes) automatic retries.")
            return false
        }
        autoResumeAttempts[task.id] = attempt

        // Free the slot, keep the partial data, wait, then re-queue.
        activeDownloads = max(0, activeDownloads - 1)
        stopEngine(for: task, keepPartialData: true)
        task.state = .waiting
        task.speed = 0
        task.error = nil
        task.statusDetail = "Connection lost. Reconnecting (\(attempt)/\(Self.maxAutoResumes))…"
        task.isHeldForSchedule = true
        autoResumePending.insert(task.id)
        saveTaskList()

        let delay = Self.autoResumeDelays[min(attempt - 1, Self.autoResumeDelays.count - 1)]
        let id = task.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.autoResumePending.remove(id) != nil else { return }
            // The user may have paused / cancelled / removed it meanwhile.
            guard task.state == .waiting, task.isHeldForSchedule else { return }
            task.isHeldForSchedule = false
            self.processQueue()
        }
        return true
    }

    private func notifyResumeFailed(_ task: DownloadTask, reason: String) {
        autoResumeAttempts[task.id] = nil
        autoResumeBaseline[task.id] = nil
        NotificationManager.shared.notifyDownloadFailed(
            taskId: task.id, filename: task.filename, error: "Could not resume. " + reason)
    }

    private func startMonitoring() {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTotalSpeed()
                self?.processQueue()
            }
            .store(in: &cancellables)
    }

    private func updateTotalSpeed() {
        totalDownloadSpeed = downloadTasks
            .filter { $0.state == .downloading }
            .reduce(0) { $0 + $1.speed }
    }

    /// Start waiting tasks (highest priority first) while slots are free.
    /// Tasks held for a schedule, or whose scheduler queue is closed, stay waiting.
    internal func processQueue() {
        let waiting = downloadTasks.enumerated()
            .filter { $0.element.state == .waiting && $0.element.videoTaskID == nil && !$0.element.isRestoredStreaming }
            .sorted { a, b in
                if a.element.priority != b.element.priority {
                    return a.element.priority > b.element.priority
                }
                let pa = SchedulerQueueManager.shared.position(of: a.element.id) ?? Int.max
                let pb = SchedulerQueueManager.shared.position(of: b.element.id) ?? Int.max
                if pa != pb { return pa < pb }
                return a.offset < b.offset
            }
            .map { $0.element }

        for task in waiting {
            guard activeDownloads < maxConcurrentDownloads else { break }
            if task.isHeldForSchedule { continue }
            if !SchedulerQueueManager.shared.canStart(task) { continue }
            beginDownload(task)
        }
    }

    var formattedTotalSpeed: String {
        ByteCountFormatter.string(fromByteCount: totalDownloadSpeed, countStyle: .file) + "/s"
    }

    func getStatistics() -> DownloadSummary {
        let completed = downloadTasks.filter { $0.state == .completed }
        return DownloadSummary(
            totalDownloads: completed.count,
            totalBytesDownloaded: completed.reduce(0) { $0 + $1.totalBytes },
            activeDownloads: activeDownloads,
            currentSpeed: totalDownloadSpeed
        )
    }

    // MARK: - Persistence

    private struct PersistedTask: Codable {
        let id: UUID
        let url: URL
        let destinationPath: URL
        let filename: String
        let state: DownloadState
        let progress: Double
        let downloadedBytes: Int64
        let totalBytes: Int64
        let numberOfSegments: Int
        let createdAt: Date
        let completedAt: Date?
        let fileType: String?
        let mimeType: String?
        let retryCount: Int
        let lastAttemptAt: Date?
        // Added later — optional so older downloads.json files still load.
        let requestHeaders: [String: String]?
        let schedule: DownloadSchedule?
        let isHeldForSchedule: Bool?
        let manuallyHeld: Bool?
        let streamingVideo: Bool?
    }

    private var persistenceURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("DownloadManager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("downloads.json")
    }

    /// Save the current task list to disk. Active downloads are saved as .paused
    /// so they can be resumed on next launch (their partial data is on disk).
    /// Cookies are never persisted.
    func saveTaskList() {
        SchedulerQueueManager.shared.pruneMissing(keeping: Set(downloadTasks.map { $0.id }))
        // Unfinished streaming rows are kept too; after a relaunch Resume restarts
        // them from the page link (see restartRestoredStreaming).
        let persisted = downloadTasks
            .map { t in
            PersistedTask(
                id: t.id,
                url: t.url,
                destinationPath: t.destinationPath,
                filename: t.filename,
                state: t.state == .downloading ? .paused : t.state,
                progress: t.progress,
                downloadedBytes: t.downloadedBytes,
                totalBytes: t.totalBytes,
                numberOfSegments: t.numberOfSegments,
                createdAt: t.createdAt,
                completedAt: t.completedAt,
                fileType: t.fileType,
                mimeType: t.mimeType,
                retryCount: t.retryCount,
                lastAttemptAt: t.lastAttemptAt,
                requestHeaders: t.requestHeaders.filter { $0.key.caseInsensitiveCompare("Cookie") != .orderedSame },
                schedule: t.schedule,
                isHeldForSchedule: t.isHeldForSchedule,
                manuallyHeld: t.manuallyHeld,
                streamingVideo: t.videoTaskID != nil ? true : (t.isRestoredStreaming ? true : nil)
            )
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(persisted) {
            try? data.write(to: persistenceURL, options: .atomic)
        }
    }

    /// Load a previously-saved task list. In-progress tasks are restored as paused.
    private func loadTaskList() {
        guard let data = try? Data(contentsOf: persistenceURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let saved = try? dec.decode([PersistedTask].self, from: data) else { return }

        downloadTasks = saved.map { p in
            let task = DownloadTask(
                id: p.id,
                url: p.url,
                destinationPath: p.destinationPath,
                filename: p.filename,
                numberOfSegments: p.numberOfSegments
            )
            task.state         = p.state == .downloading ? .paused : p.state
            task.progress      = p.progress
            task.downloadedBytes = p.downloadedBytes
            task.totalBytes    = p.totalBytes
            task.createdAt     = p.createdAt
            task.completedAt   = p.completedAt
            task.fileType      = p.fileType
            task.mimeType      = p.mimeType
            task.retryCount    = p.retryCount
            task.lastAttemptAt = p.lastAttemptAt
            task.requestHeaders = p.requestHeaders ?? [:]
            task.schedule      = p.schedule
            task.isHeldForSchedule = p.isHeldForSchedule ?? false
            // A task that was running when the app quit was not paused by the user.
            task.manuallyHeld  = p.manuallyHeld ?? (p.state == .paused)
            if p.streamingVideo == true && p.state != .completed {
                task.isRestoredStreaming = true
                if task.state == .waiting || task.state == .downloading { task.state = .paused }
            }
            return task
        }
    }

    // MARK: - History recording

    private func recordToHistory(task: DownloadTask, status: DownloadHistoryStatus) {
        let completedAt = task.completedAt ?? Date()
        let duration = completedAt.timeIntervalSince(task.createdAt)
        let avgSpeed: Double = duration > 0 ? Double(task.totalBytes) / duration : 0

        let outputURL = task.fileURL
        let entry = DownloadHistoryEntry(
            url: task.url,
            fileName: task.filename,
            filePath: outputURL.path,
            fileSize: task.totalBytes,
            fileType: task.fileCategory.rawValue,
            mimeType: task.mimeType,
            startDate: task.createdAt,
            completionDate: completedAt,
            duration: duration,
            status: status,
            errorMessage: task.error?.localizedDescription,
            averageSpeed: avgSpeed,
            peakSpeed: avgSpeed,
            segmentsUsed: task.numberOfSegments,
            sourceWebsite: task.url.host
        )
        HistoryManager.shared.addEntry(entry)
    }
}

struct DownloadSummary {
    let totalDownloads: Int
    let totalBytesDownloaded: Int64
    let activeDownloads: Int
    let currentSpeed: Int64

    var formattedTotalBytes: String { ByteCountFormatter.string(fromByteCount: totalBytesDownloaded, countStyle: .file) }
    var formattedSpeed: String { ByteCountFormatter.string(fromByteCount: currentSpeed, countStyle: .file) + "/s" }
}
