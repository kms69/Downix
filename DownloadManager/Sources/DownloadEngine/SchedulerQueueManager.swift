//
//  SchedulerQueueManager.swift
//  Download Manager for Mac
//
//  Manages all named scheduler queues and their assigned downloads.
//  Persists queues to UserDefaults and integrates with DownloadManager.
//

import Foundation
import Combine

@MainActor
class SchedulerQueueManager: ObservableObject {

    static let shared = SchedulerQueueManager()

    @Published var queues: [SchedulerQueue] = []

    private let storageKey = "schedulerQueuesV2"
    private var timer: Timer?
    private let windowCheckInterval: TimeInterval = 60

    private struct PendingPowerAction {
        let action: PostDownloadAction
        let requestedBy: UUID
        let requestedAt: Date
    }

    private var pendingPowerAction: PendingPowerAction?
    private var powerActionTimer: Timer?
    private var lastPowerGateBlockers: String?

    private init() {
        loadQueues()
        if queues.isEmpty {
            setupDefaultQueues()
        }
        startWindowMonitoring()
    }

    deinit {
        timer?.invalidate()
        powerActionTimer?.invalidate()
    }

    // MARK: - Queue CRUD

    /// Add a new queue. Returns the created queue.
    @discardableResult
    func addQueue(_ queue: SchedulerQueue) -> SchedulerQueue {
        var q = queue
        q.modifiedAt = Date()
        queues.append(q)
        save()
        return q
    }

    /// Update an existing queue (matched by id).
    func updateQueue(_ queue: SchedulerQueue) {
        guard let idx = queues.firstIndex(where: { $0.id == queue.id }) else { return }
        var q = queue
        q.modifiedAt = Date()
        queues[idx] = q
        save()
    }

    /// Delete a queue. Downloads that were in it are *not* deleted.
    func deleteQueue(_ queue: SchedulerQueue) {
        queues.removeAll { $0.id == queue.id }
        save()
    }

    /// Reorder the queues list (e.g. from drag-and-drop).
    func moveQueues(fromOffsets source: IndexSet, toOffset destination: Int) {
        queues.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Task↔Queue assignment

    /// Assign a download to a queue, removing it from any previous queue first.
    func assignTask(_ taskID: UUID, to queueID: UUID) {
        // Remove from all other queues
        for i in queues.indices {
            queues[i].taskIDs.removeAll { $0 == taskID }
        }
        // Add to target queue (avoid duplicates)
        if let i = queues.firstIndex(where: { $0.id == queueID }) {
            if !queues[i].taskIDs.contains(taskID) {
                queues[i].taskIDs.append(taskID)
            }
            queues[i].modifiedAt = Date()
        }
        save()
    }

    /// Remove a download from a specific queue.
    func removeTask(_ taskID: UUID, fromQueue queueID: UUID) {
        guard let i = queues.firstIndex(where: { $0.id == queueID }) else { return }
        queues[i].taskIDs.removeAll { $0 == taskID }
        queues[i].modifiedAt = Date()
        save()
    }

    /// Drop queue entries whose download no longer exists (removed / cleared),
    /// so a queue's count matches what is really in it.
    func pruneMissing(keeping existing: Set<UUID>) {
        var changed = false
        for i in queues.indices {
            let kept = queues[i].taskIDs.filter { existing.contains($0) }
            if kept.count != queues[i].taskIDs.count {
                queues[i].taskIDs = kept
                changed = true
            }
        }
        if changed { save() }
    }

    /// Remove a download from every queue it appears in.
    func removeTaskFromAllQueues(_ taskID: UUID) {
        for i in queues.indices {
            queues[i].taskIDs.removeAll { $0 == taskID }
        }
        save()
    }

    /// Move a download from its current queue to a different one.
    func moveTask(_ taskID: UUID, toQueue targetQueueID: UUID) {
        assignTask(taskID, to: targetQueueID)
    }

    enum MoveDirection { case top, up, down, bottom }

    /// Reorder files inside a queue. The chosen files move together and keep their relative order.
    func move(_ ids: Set<UUID>, in queueID: UUID, _ direction: MoveDirection) {
        guard let qi = queues.firstIndex(where: { $0.id == queueID }) else { return }
        var list = queues[qi].taskIDs
        guard list.contains(where: { ids.contains($0) }) else { return }
        switch direction {
        case .top:
            list = list.filter { ids.contains($0) } + list.filter { !ids.contains($0) }
        case .bottom:
            list = list.filter { !ids.contains($0) } + list.filter { ids.contains($0) }
        case .up:
            var i = 1
            while i < list.count {
                if ids.contains(list[i]) && !ids.contains(list[i - 1]) { list.swapAt(i, i - 1) }
                i += 1
            }
        case .down:
            var i = list.count - 2
            while i >= 0 {
                if ids.contains(list[i]) && !ids.contains(list[i + 1]) { list.swapAt(i, i + 1) }
                i -= 1
            }
        }
        queues[qi].taskIDs = list
        queues[qi].modifiedAt = Date()
        save()
    }

    /// Position of a download inside its queue (0 = first); nil when it is in no queue.
    func position(of taskID: UUID) -> Int? {
        for q in queues {
            if let i = q.taskIDs.firstIndex(of: taskID) { return i }
        }
        return nil
    }

    /// Return the queue that owns a given task, if any.
    func queue(for taskID: UUID) -> SchedulerQueue? {
        queues.first { $0.taskIDs.contains(taskID) }
    }

    // MARK: - Schedule window monitoring

    private func startWindowMonitoring() {
        timer = Timer.scheduledTimer(
            withTimeInterval: windowCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateScheduleWindows()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        // Defer: evaluating windows calls DownloadManager.processQueue(), which
        // asks SchedulerQueueManager.shared.canStart(...). Doing that inside
        // init re-enters the singleton and crashes libdispatch.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.evaluateScheduleWindows()
        }
    }

    /// Pause/resume queues based on their current schedule window.
    /// Tasks paused by the window are NOT marked as user-paused, so only those
    /// come back when the window opens; downloads the user paused stay paused.
    func evaluateScheduleWindows() {
        let dm = DownloadManager.shared
        for i in queues.indices {
            let q = queues[i]
            guard q.isEnabled && q.isScheduleEnabled else { continue }

            let inWindow = q.isInScheduleWindow()

            // Activate tasks in window
            if inWindow && !q.isPaused {
                for taskID in q.taskIDs {
                    if let task = dm.downloadTasks.first(where: { $0.id == taskID }),
                       task.state == .paused, !task.manuallyHeld {
                        Task { await dm.resumeDownload(task) }
                    }
                }
            }

            // Pause tasks outside window
            if !inWindow {
                for taskID in q.taskIDs {
                    if let task = dm.downloadTasks.first(where: { $0.id == taskID }),
                       task.state == .downloading {
                        Task { await dm.pauseDownload(task, byScheduler: true) }
                    }
                }
            }
        }
        dm.processQueue()
    }

    // MARK: - Start gate (used by DownloadManager.processQueue)

    /// May this waiting task start right now? False when its queue is paused,
    /// disabled, outside its schedule window, or already at its parallel limit.
    func canStart(_ task: DownloadTask) -> Bool {
        guard let q = queue(for: task.id) else { return true }
        if !q.isEnabled || q.isPaused { return false }
        if QueueRunController.shared.blocksStart(q) { return false }   // waiting for "Start download at"
        if q.isScheduleEnabled && !q.isInScheduleWindow() { return false }

        let dm = DownloadManager.shared
        let running = dm.downloadTasks.filter {
            $0.state == .downloading && q.taskIDs.contains($0.id)
        }.count
        return running < max(1, q.maxSimultaneousDownloads)
    }

    // MARK: - Post-completion actions

    /// Called by DownloadManager whenever a download completes.
    /// Runs the per-download action and, if the whole queue is done, the queue action.
    func taskDidComplete(_ task: DownloadTask) {
        let dm = DownloadManager.shared
        PowerActionLog.log(
            "completion: task=\"\(task.filename)\" perDownloadAction="
                + "\(task.postDownloadAction?.rawValue ?? "none")"
        )

        // Per-download action chosen in "Add Download" / compact progress window.
        if let action = task.postDownloadAction, action != .none {
            task.postDownloadAction = nil          // fire once
            if performPostDownloadAction(action, excludingTaskID: task.id) { return }
        }

        // Queue-level action ("after all downloads in this queue finish").
        // Only an armed queue (scheduled run / Start Now) fires its action; a manual Stop disarms it.
        guard let q = queue(for: task.id), q.postQueueAction != .none, q.armed == true else { return }
        let members = dm.downloadTasks.filter { q.taskIDs.contains($0.id) }
        // A paused member will not finish on its own; counting it here would keep
        // the queue-level action from ever firing (same rule as the power gate).
        let unfinished = members.contains { member in
            switch member.state {
            case .downloading:
                return true
            case .waiting:
                return !member.isHeldForSchedule && q.isEnabled && !q.isPaused
            case .paused, .completed, .failed, .cancelled:
                return false
            }
        }
        PowerActionLog.log(
            "queue finished check: queue=\"\(q.name)\" action=\"\(q.postQueueAction.rawValue)\" "
                + "members=\(members.count) unfinished=\(unfinished)"
        )
        if !unfinished && members.contains(where: { $0.state == .completed }) {
            let action = q.postQueueAction
            PowerActionLog.log("queue finished: queue=\"\(q.name)\" — running \"\(action.rawValue)\"")
            if (action == .sleep || action == .shutdown) {
                requestPowerAction(action, triggeredBy: task.id)
            } else {
                DownloadScheduler.shared.perform(action, reason: "queue-finished")
            }
            if let index = queues.firstIndex(where: { $0.id == q.id }) {
                queues[index].armed = false
                save()
            }
        }
    }

    @discardableResult
    func performPostDownloadAction(_ action: PostDownloadAction, excludingTaskID id: UUID) -> Bool {
        guard action != .none else { return false }

        if action == .sleep || action == .shutdown {
            requestPowerAction(action, triggeredBy: id)
            return true
        }

        let destructive = (action == .hibernate)
        let fileBusy = DownloadManager.shared.downloadTasks.contains {
            $0.id != id && ($0.state == .downloading || ($0.state == .waiting && !$0.isHeldForSchedule))
        }
        let videoBusy = VideoDownloadManager.shared.videoTasks.contains {
            guard $0.id != id else { return false }
            switch $0.state {
            case .pending, .fetchingMetadata, .ready, .downloading, .paused, .converting:
                return true
            case .completed, .failed, .cancelled:
                return false
            }
        }
        if destructive && (fileBusy || videoBusy) { return false }
        DownloadScheduler.shared.perform(action, reason: "per-download")
        return true
    }

    // MARK: - Queue-completion power actions

    func requestPowerAction(_ action: PostDownloadAction, triggeredBy taskID: UUID) {
        guard action == .sleep || action == .shutdown else { return }
        if let pending = pendingPowerAction {
            if pending.action == action { return }
            PowerActionLog.log(
                "pending power action: replacing \"\(pending.action.rawValue)\" with \"\(action.rawValue)\""
            )
        }
        PowerActionLog.log("pending power action armed: \"\(action.rawValue)\" (task \(taskID))")
        pendingPowerAction = PendingPowerAction(
            action: action,
            requestedBy: taskID,
            requestedAt: Date()
        )
        startPowerActionMonitoring()
        evaluatePendingPowerAction()
    }

    func powerActionDidFail(_ reason: String) {
        // A user stop/cancel/remove disarms every queue; a plain failure does not
        // (the queue still finishes and the action still runs).
        if !reason.contains("failed") {
            for i in queues.indices where queues[i].armed == true { queues[i].armed = false }
            save()
        }
        let hasPending = pendingPowerAction != nil
        let hasRequestedAction = DownloadManager.shared.downloadTasks.contains {
            $0.postDownloadAction == .sleep || $0.postDownloadAction == .shutdown
        } || VideoDownloadManager.shared.videoTasks.contains {
            $0.postDownloadAction == .sleep || $0.postDownloadAction == .shutdown
        }
        guard hasPending || hasRequestedAction else { return }
        PowerActionLog.log("power action cancelled: \(reason)")

        for task in DownloadManager.shared.downloadTasks {
            if task.postDownloadAction == .sleep || task.postDownloadAction == .shutdown {
                task.postDownloadAction = nil
            }
        }
        for task in VideoDownloadManager.shared.videoTasks {
            if task.postDownloadAction == .sleep || task.postDownloadAction == .shutdown {
                task.postDownloadAction = .none
            }
        }
        clearPendingPowerAction()
    }

    private func startPowerActionMonitoring() {
        powerActionTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluatePendingPowerAction()
            }
        }
        powerActionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func evaluatePendingPowerAction() {
        guard let pending = pendingPowerAction else {
            powerActionTimer?.invalidate()
            powerActionTimer = nil
            return
        }

        let blockers = powerActionBlockers()
        if !blockers.isEmpty {
            let summary = blockers.joined(separator: ", ")
            if summary != lastPowerGateBlockers {
                lastPowerGateBlockers = summary
                PowerActionLog.log(
                    "power action \"\(pending.action.rawValue)\" waiting for \(blockers.count) "
                        + "transfer(s): \(summary)"
                )
            }
            return
        }
        lastPowerGateBlockers = nil

        guard hasCompletedDownload(since: pending.requestedAt) || hasAnyCompletedDownload else {
            PowerActionLog.log("power action dropped: no download finished since it was requested")
            clearPendingPowerAction()
            return
        }

        let action = pending.action
        clearPendingPowerAction()
        // "Queue finished" — this is the event the power action waits for.
        PowerActionLog.log("QUEUE FINISHED — executing \"\(action.rawValue)\"")
        DownloadScheduler.shared.perform(action, reason: "queue-finished")
    }

    /// Transfers that will finish on their own. Paused items are deliberately
    /// idle: they never complete by themselves, so counting them would block the
    /// power action forever. A task parked in a paused/disabled queue is idle too.
    private func powerActionBlockers() -> [String] {
        var blockers: [String] = []

        for task in DownloadManager.shared.downloadTasks {
            if task.isHeldForSchedule { continue }
            switch task.state {
            case .downloading:
                blockers.append("\(task.filename) [downloading]")
            case .waiting:
                if let q = queue(for: task.id), !q.isEnabled || q.isPaused { continue }
                blockers.append("\(task.filename) [waiting]")
            case .paused, .completed, .failed, .cancelled:
                continue
            }
        }

        for task in VideoDownloadManager.shared.videoTasks {
            switch task.state {
            case .pending, .fetchingMetadata, .ready, .downloading, .converting:
                let name = task.metadata?.title ?? task.preferredTitle ?? task.url.lastPathComponent
                blockers.append("\(name) [video \(task.state.rawValue)]")
            case .paused, .completed, .failed, .cancelled:
                continue
            }
        }

        return blockers
    }

    private func hasCompletedDownload(since date: Date) -> Bool {
        DownloadManager.shared.downloadTasks.contains {
            $0.state == .completed && ($0.completedAt ?? .distantPast) >= date
        } || VideoDownloadManager.shared.videoTasks.contains {
            $0.state == .completed && ($0.completedAt ?? .distantPast) >= date
        }
    }

    private var hasAnyCompletedDownload: Bool {
        DownloadManager.shared.downloadTasks.contains { $0.state == .completed }
            || VideoDownloadManager.shared.videoTasks.contains { $0.state == .completed }
    }

    private func clearPendingPowerAction() {
        pendingPowerAction = nil
        lastPowerGateBlockers = nil
        powerActionTimer?.invalidate()
        powerActionTimer = nil
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(queues) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadQueues() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SchedulerQueue].self, from: data)
        else { return }
        queues = decoded
    }

    // MARK: - Default queues

    private func setupDefaultQueues() {
        var main = SchedulerQueue(name: QueueRunController.mainQueueName, colorHex: "#007AFF")
        main.maxSimultaneousDownloads = 3
        main.isScheduleEnabled = false

        var nights = SchedulerQueue(name: "Night Schedule", colorHex: "#34C759")
        nights.maxSimultaneousDownloads = 5
        nights.isScheduleEnabled = true
        let cal = Calendar.current
        let now = Date()
        nights.startTime = cal.date(bySettingHour: 23, minute: 0, second: 0, of: now) ?? now
        nights.stopTime  = cal.date(bySettingHour:  8, minute: 0, second: 0, of: now) ?? now
        nights.weekdays = Set(Weekday.allCases)
        nights.postQueueAction = .sleep

        queues = [main, nights]
        save()
    }

    // MARK: - Statistics helpers

    struct QueueStats {
        let totalDownloads: Int
        let activeDownloads: Int
        let completedDownloads: Int
        let failedDownloads: Int
    }

    func stats(for queue: SchedulerQueue) -> QueueStats {
        let dm = DownloadManager.shared
        let tasks = queue.taskIDs.compactMap { id in
            dm.downloadTasks.first { $0.id == id }
        }
        return QueueStats(
            totalDownloads: tasks.count,
            activeDownloads: tasks.filter { $0.state == .downloading }.count,
            completedDownloads: tasks.filter { $0.state == .completed }.count,
            failedDownloads: tasks.filter { $0.state == .failed }.count
        )
    }
}
