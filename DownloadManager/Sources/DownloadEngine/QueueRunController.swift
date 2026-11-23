//
//  QueueRunController.swift
//  Download Manager for Mac
//
//  IDM-style queue scheduling on top of SchedulerQueueManager:
//    • "Start download at" – one-shot start date/time; files wait until then
//    • "Stop download at"  – optional stop date/time for a running queue
//    • "Start Now"         – begin immediately, ignoring the start time
//    • one-time processing – a finished file leaves the queue
//    • completion action   – Sleep / Shutdown fire ONLY when the queue's last
//                            file finishes during a run. A manual Stop (or a
//                            stop-time stop) disarms the run, so nothing fires.
//

import Foundation
import Combine

@MainActor
final class QueueRunController: ObservableObject {

    static let shared = QueueRunController()

    static let mainQueueName = "Main Download Queue"

    private let manager = SchedulerQueueManager.shared
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    /// Files completed during the current run (runtime only).
    private var completedInRun: [UUID: Int] = [:]

    /// Bumped on every change so SwiftUI views refresh.
    @Published private(set) var revision = 0

    private init() {}

    private func log(_ message: String) { print("[Queue] \(message)") }

    // MARK: - Lifecycle

    /// Call once at launch.
    func start() {
        guard timer == nil else { return }
        manager.pruneMissing(keeping: Set(DownloadManager.shared.downloadTasks.map { $0.id }))
        normalizeDefaultQueue()
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    /// The default queue is called "Main Download Queue" and is always first.
    private func normalizeDefaultQueue() {
        if let i = manager.queues.firstIndex(where: { $0.name == "Main Queue" }) {
            var q = manager.queues[i]
            q.name = Self.mainQueueName
            manager.updateQueue(q)
        }
        if !manager.queues.contains(where: { $0.name == Self.mainQueueName }) {
            var q = SchedulerQueue(name: Self.mainQueueName, colorHex: "#007AFF")
            q.isScheduleEnabled = false
            manager.queues.insert(q, at: 0)
            manager.save()
        }
    }

    var defaultQueue: SchedulerQueue? {
        manager.queues.first(where: { $0.name == Self.mainQueueName }) ?? manager.queues.first
    }

    /// Files added to the manager go to the Main Download Queue unless the
    /// user picked another queue.
    func assignToDefaultQueueIfNeeded(_ taskID: UUID) {
        guard manager.queue(for: taskID) == nil, let q = defaultQueue else { return }
        manager.assignTask(taskID, to: q.id)
    }

    // MARK: - Queries

    func queue(_ id: UUID) -> SchedulerQueue? { manager.queues.first { $0.id == id } }

    func isWaitingForStart(_ q: SchedulerQueue) -> Bool { q.startAtEnabled == true && q.startAt != nil }
    func isRunning(_ q: SchedulerQueue) -> Bool { q.armed == true }

    /// Used by SchedulerQueueManager.canStart: files in a queue that is waiting
    /// for its start time must not begin yet.
    func blocksStart(_ q: SchedulerQueue) -> Bool { isWaitingForStart(q) }

    func members(of q: SchedulerQueue) -> [DownloadTask] {
        q.taskIDs.compactMap { id in DownloadManager.shared.downloadTasks.first { $0.id == id } }
    }

    private func unfinished(_ q: SchedulerQueue, excluding id: UUID? = nil) -> [DownloadTask] {
        members(of: q).filter {
            $0.id != id && ($0.state == .downloading || $0.state == .waiting || $0.state == .paused)
        }
    }

    // MARK: - User actions

    /// Save the schedule from the Scheduler window.
    func apply(queueID: UUID,
               startEnabled: Bool, startAt: Date,
               stopEnabled: Bool, stopAt: Date,
               action: PostDownloadAction) {
        guard var q = queue(queueID) else { return }
        q.startAtEnabled = startEnabled
        q.startAt = startAt
        q.stopAtEnabled = stopEnabled
        q.stopAt = stopAt
        q.postQueueAction = (action == .sleep || action == .shutdown) ? action : .none
        // A completion action only applies to a queue that is set to run.
        if startEnabled { q.armed = true }
        manager.updateQueue(q)
        log("scheduler saved for '\(q.name)': start=\(startEnabled ? "\(startAt)" : "off") stop=\(stopEnabled ? "\(stopAt)" : "off") action=\(q.postQueueAction.rawValue)")
        changed()
        tick()
    }

    /// "Start Now": ignore the start time and process the queue immediately.
    func startNow(queueID: UUID) {
        begin(queueID, reason: "Start Now")
    }

    /// Manual "Stop": halt the queue. Completion actions will NOT trigger.
    func stopManually(queueID: UUID) {
        halt(queueID, reason: "stopped manually")
        manager.powerActionDidFail("queue stopped manually")
    }

    // MARK: - Queue membership

    /// Move downloads into a queue. If that queue is waiting for its start time,
    /// downloads that are already running are paused until the queue starts.
    func move(_ taskIDs: [UUID], to queueID: UUID) {
        guard let target = queue(queueID) else { return }
        let dm = DownloadManager.shared
        for id in taskIDs {
            guard let task = dm.downloadTasks.first(where: { $0.id == id }),
                  task.videoTaskID == nil else { continue }
            manager.assignTask(id, to: queueID)
            task.schedulerQueueID = queueID
            if isWaitingForStart(target), task.state == .downloading {
                Task { await dm.pauseDownload(task, byScheduler: true) }
            }
        }
        log("moved \(taskIDs.count) download(s) to '\(target.name)'")
        dm.processQueue()
        changed()
    }

    /// Take a download out of a queue (it returns to the Main Download Queue).
    func remove(_ taskID: UUID, from queueID: UUID) {
        if let q = queue(queueID), q.name == Self.mainQueueName {
            manager.removeTask(taskID, fromQueue: queueID)
        } else if let main = defaultQueue {
            move([taskID], to: main.id)
        }
        changed()
    }

    /// Downloads that could still be added to a queue.
    func addableDownloads(for queueID: UUID) -> [DownloadTask] {
        let inQueue = Set(queue(queueID)?.taskIDs ?? [])
        return DownloadManager.shared.downloadTasks.filter {
            $0.videoTaskID == nil && !inQueue.contains($0.id)
                && $0.state != .completed && $0.state != .cancelled
        }
    }

    // MARK: - Run control

    private func begin(_ id: UUID, reason: String) {
        guard var q = queue(id) else { return }
        q.startAtEnabled = false            // one-time: the start time is consumed
        q.armed = true
        manager.updateQueue(q)
        completedInRun[id] = 0
        log("queue '\(q.name)' starting (\(reason)); completion action = \(q.postQueueAction.rawValue)")

        let dm = DownloadManager.shared
        for task in members(of: q) where task.state == .paused || task.state == .failed {
            Task { await dm.resumeDownload(task) }
        }
        dm.processQueue()
        changed()
    }

    private func halt(_ id: UUID, reason: String) {
        guard var q = queue(id) else { return }
        q.armed = false                     // disarm FIRST so nothing can fire
        q.startAtEnabled = false
        manager.updateQueue(q)
        log("queue '\(q.name)' \(reason); completion action disarmed")

        let dm = DownloadManager.shared
        for task in members(of: q) {
            switch task.state {
            case .downloading:
                Task { await dm.stopDownload(task) }
            case .waiting:
                task.state = .paused
                task.manuallyHeld = true
            default: break
            }
        }
        dm.saveTaskList()
        changed()
    }

    // MARK: - Timer

    private func tick() {
        let now = Date()
        for q in manager.queues {
            if q.startAtEnabled == true, let s = q.startAt, now >= s {
                if q.stopAtEnabled == true, let e = q.stopAt, now >= e {
                    var skipped = q
                    skipped.startAtEnabled = false
                    manager.updateQueue(skipped)
                    log("queue '\(q.name)' start time passed together with its stop time; not starting")
                } else {
                    begin(q.id, reason: "scheduled start time reached")
                }
            }
        }
        for q in manager.queues {
            if q.armed == true, q.stopAtEnabled == true, let e = q.stopAt, now >= e {
                var stopped = q
                stopped.stopAtEnabled = false
                manager.updateQueue(stopped)
                halt(q.id, reason: "stop time reached")
            }
        }
        refreshKeepAwake()
    }

    /// Keep the Mac from idle-sleeping while a start time is pending or a run
    /// is in progress; otherwise a 2 AM schedule could never start.
    private func refreshKeepAwake() {
        let need = manager.queues.contains {
            isWaitingForStart($0) || (isRunning($0) && !unfinished($0).isEmpty)
        }
        if need, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "Download Manager queue is scheduled or running")
            log("keep-awake activity started")
        } else if !need { releaseKeepAwake() }
    }

    func releaseKeepAwake() {
        if let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
            log("keep-awake activity released")
        }
    }

    // MARK: - Download events (called from DownloadManager)

    /// Runs after SchedulerQueueManager.taskDidComplete (which already fired
    /// the completion action if this was the last file of an armed queue).
    func taskDidFinish(_ task: DownloadTask) {
        guard let q = manager.queue(for: task.id) else { return }
        completedInRun[q.id, default: 0] += 1
        manager.removeTask(task.id, fromQueue: q.id)       // one-time processing
        if let fresh = queue(q.id), fresh.armed == true, unfinished(fresh).isEmpty {
            var done = fresh
            done.armed = false
            manager.updateQueue(done)
            log("queue '\(fresh.name)' finished its run")
        }
        refreshKeepAwake()
        changed()
    }

    /// If the very last file of a run fails, the queue is still finished.
    func taskDidFail(_ task: DownloadTask) {
        guard let q = manager.queue(for: task.id), q.armed == true else { return }
        guard unfinished(q, excluding: task.id).isEmpty,
              (completedInRun[q.id] ?? 0) > 0 else { return }
        var done = q
        done.armed = false
        manager.updateQueue(done)
        log("queue '\(q.name)' finished (last file failed); completion action = \(q.postQueueAction.rawValue)")
        if q.postQueueAction == .sleep || q.postQueueAction == .shutdown {
            releaseKeepAwake()
            manager.requestPowerAction(q.postQueueAction, triggeredBy: task.id)
        }
        changed()
    }

    private func changed() { revision &+= 1 }
}
