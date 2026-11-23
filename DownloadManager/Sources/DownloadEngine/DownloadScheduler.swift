//
//  DownloadScheduler.swift
//  Download Manager for Mac - Feature #3: Scheduler Engine
//
//  Created on February 15, 2026
//
//  Scheduled downloads are stored on the tasks themselves (and persisted by
//  DownloadManager), so they survive relaunch. A scheduled task waits as
//  `.paused` + `isHeldForSchedule` until its time arrives; then the scheduler
//  force-starts it. If the app was closed / the Mac asleep at the due time, the
//  run is caught up as soon as the app is active again.
//

import Foundation
import Combine
import AppKit

/// Parses "500KB", "1.5 MB", "2mb/s" or a bare number (KB/s) into bytes/second.
enum BandwidthParser {
    static func parse(_ text: String) -> Int64? {
        let s = text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/s", with: "")
            .replacingOccurrences(of: "ps", with: "")
        guard !s.isEmpty else { return nil }

        let units: [(String, Double)] = [
            ("gb", 1_073_741_824), ("mb", 1_048_576), ("kb", 1_024),
            ("g", 1_073_741_824), ("m", 1_048_576), ("k", 1_024), ("b", 1)
        ]
        for (suffix, multiplier) in units where s.hasSuffix(suffix) {
            guard let value = Double(String(s.dropLast(suffix.count))), value > 0 else { return nil }
            return Int64(value * multiplier)
        }
        if let value = Double(s), value > 0 { return Int64(value * 1_024) }   // bare number = KB/s
        return nil
    }
}

/// Main scheduler that monitors and executes scheduled downloads
@MainActor
class DownloadScheduler: ObservableObject {

    static let shared = DownloadScheduler()

    @Published var scheduledTasks: [DownloadTask] = []
    @Published var bandwidthSchedules: [BandwidthSchedule] = []
    @Published var currentBandwidthLimit: Int64? = nil

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var postActionTokens: [UUID: AnyCancellable] = [:]
    private let checkInterval: TimeInterval = 15
    /// Last limit WE applied, so we never overwrite a limit set by someone else.
    private var lastScheduleLimit: Int64? = nil

    private init() {
        startMonitoring()

        // A sleeping Mac misses timer ticks: check again the moment it wakes up.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkSchedules()
                    self?.checkBandwidthSchedules()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Monitoring

    /// Start the scheduler monitoring
    func startMonitoring() {
        stopMonitoring()

        let t = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSchedules()
                self?.checkBandwidthSchedules()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Check right away (after init has finished).
        Task { @MainActor [weak self] in
            self?.checkSchedules()
            self?.checkBandwidthSchedules()
        }
    }

    /// Stop the scheduler monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Restoring after launch

    /// Called once by DownloadManager with every restored task that has a schedule.
    func restoreScheduledTasks(_ tasks: [DownloadTask]) {
        for task in tasks where !scheduledTasks.contains(where: { $0.id == task.id }) {
            guard let schedule = task.schedule, schedule.type != .immediate else { continue }
            scheduledTasks.append(task)
        }
        checkSchedules()   // catch up anything that came due while the app was closed
    }

    // MARK: - Schedule Management

    /// Attach a schedule to a download. The download then waits for its time.
    func addScheduledDownload(_ task: DownloadTask, schedule: DownloadSchedule) {
        var updated = schedule
        updated.isEnabled = true
        updated.lastRun = nil
        updated.calculateNextRun()
        task.schedule = updated

        if schedule.type == .immediate {
            executeTask(task)
            return
        }

        if !scheduledTasks.contains(where: { $0.id == task.id }) {
            scheduledTasks.append(task)
        }
        holdForSchedule(task)
        DownloadManager.shared.saveTaskList()
    }

    /// Remove a scheduled download (the download itself stays in the list).
    func removeScheduledDownload(_ task: DownloadTask) {
        scheduledTasks.removeAll { $0.id == task.id }
        postActionTokens[task.id]?.cancel()
        postActionTokens.removeValue(forKey: task.id)
        task.schedule = nil
        if task.isHeldForSchedule {
            task.isHeldForSchedule = false
            task.manuallyHeld = true          // stays paused until the user resumes it
        }
        DownloadManager.shared.saveTaskList()
    }

    /// Update schedule for a task
    func updateSchedule(for task: DownloadTask, schedule: DownloadSchedule) {
        var updated = schedule
        updated.calculateNextRun()
        task.schedule = updated
        if !scheduledTasks.contains(where: { $0.id == task.id }) { scheduledTasks.append(task) }
        if task.state != .downloading && task.state != .completed { holdForSchedule(task) }
        DownloadManager.shared.saveTaskList()
    }

    /// Enable/disable a schedule
    func setScheduleEnabled(_ enabled: Bool, for task: DownloadTask) {
        guard var schedule = task.schedule else { return }
        schedule.isEnabled = enabled
        if enabled { schedule.calculateNextRun() }
        task.schedule = schedule
        objectWillChange.send()
        DownloadManager.shared.saveTaskList()
    }

    /// Park the task until its schedule fires. It shows as Paused (so the user can
    /// still press Resume to start it early) but no automatic resumer touches it.
    private func holdForSchedule(_ task: DownloadTask) {
        let dm = DownloadManager.shared
        task.isHeldForSchedule = true
        task.manuallyHeld = true
        switch task.state {
        case .downloading:
            Task { @MainActor in
                await dm.pauseDownload(task, byScheduler: false)
                task.isHeldForSchedule = true
            }
        case .waiting, .failed, .cancelled:
            task.state = .paused
        default:
            break
        }
    }

    // MARK: - Schedule Checking

    /// Runs every few seconds and on wake. A schedule is due when its `nextRun`
    /// is in the past — so a missed run is caught up, not skipped.
    func checkSchedules() {
        let now = Date()

        for task in scheduledTasks {
            guard var schedule = task.schedule, schedule.isEnabled else { continue }
            if task.state == .downloading { continue }

            switch schedule.type {
            case .immediate, .custom:
                continue

            case .once:
                guard schedule.lastRun == nil,
                      let when = schedule.scheduledDate, now >= when,
                      task.state != .completed else { continue }
                schedule.lastRun = now
                schedule.nextRun = nil
                schedule.isEnabled = false          // one-shot: done after this run
                task.schedule = schedule
                executeTask(task)

            case .daily, .weekly, .monthly:
                guard let due = schedule.nextRun, now >= due else { continue }
                schedule.lastRun = now
                schedule.calculateNextRun()         // → next occurrence after now
                // Safety: a schedule that cannot produce a future time (e.g. weekly with
                // no weekday selected) must switch off, not fire on every check.
                if let next = schedule.nextRun, next > now {
                    // fine
                } else {
                    schedule.nextRun = nil
                    schedule.isEnabled = false
                }
                task.schedule = schedule
                if task.state == .completed { requeueForRecurringRun(task) }
                executeTask(task)
            }
        }
        objectWillChange.send()
    }

    /// A recurring schedule re-downloads the file: reset the finished task first.
    private func requeueForRecurringRun(_ task: DownloadTask) {
        task.progress = 0
        task.downloadedBytes = 0
        task.completedAt = nil
        task.error = nil
        task.state = .paused
    }

    /// Execute a scheduled task
    private func executeTask(_ task: DownloadTask) {
        if let limit = task.schedule?.bandwidthLimit {
            task.bandwidthLimit = limit        // honoured by the engine (per download)
        }

        task.isHeldForSchedule = false
        task.manuallyHeld = false
        if let action = task.schedule?.actionAfterCompletion,
           action == .sleep || action == .shutdown {
            task.postDownloadAction = action
        }
        DownloadManager.shared.startDownload(task)
        DownloadManager.shared.saveTaskList()

        if let schedule = task.schedule, schedule.actionAfterCompletion != .none {
            schedulePostDownloadAction(schedule.actionAfterCompletion, for: task)
        }
    }

    // MARK: - Bandwidth Management

    /// Add a bandwidth schedule
    func addBandwidthSchedule(_ schedule: BandwidthSchedule) {
        bandwidthSchedules.append(schedule)
        checkBandwidthSchedules()
    }

    /// Remove a bandwidth schedule
    func removeBandwidthSchedule(_ schedule: BandwidthSchedule) {
        bandwidthSchedules.removeAll { $0.id == schedule.id }
        checkBandwidthSchedules()
    }

    /// Update bandwidth schedule
    func updateBandwidthSchedule(_ schedule: BandwidthSchedule) {
        if let index = bandwidthSchedules.firstIndex(where: { $0.id == schedule.id }) {
            bandwidthSchedules[index] = schedule
        }
        checkBandwidthSchedules()
    }

    /// Apply the most restrictive ACTIVE bandwidth schedule to the engine.
    /// Only touches the global limit when the schedule result actually changes.
    func checkBandwidthSchedules() {
        let activeSchedules = bandwidthSchedules.filter { $0.isActive() }
        let minLimit = activeSchedules.map { $0.bandwidthLimit }.min()

        if currentBandwidthLimit != minLimit { currentBandwidthLimit = minLimit }

        if minLimit == lastScheduleLimit { return }      // nothing changed → don't touch the engine
        lastScheduleLimit = minLimit
        DownloadManager.shared.globalBandwidthLimit = minLimit
    }

    // MARK: - Post-Download Actions

    /// Schedule action to perform after download completes
    private func schedulePostDownloadAction(_ action: PostDownloadAction, for task: DownloadTask) {
        // Replace any existing observer for this task (prevents duplicate runs + leaks)
        postActionTokens[task.id]?.cancel()
        postActionTokens[task.id] = task.$state
            .sink { [weak self] state in
                guard let self else { return }
                if state == .completed {
                    self.performPostDownloadAction(action, for: task)
                    self.postActionTokens[task.id]?.cancel()
                    self.postActionTokens.removeValue(forKey: task.id)
                } else if state == .failed || state == .cancelled {
                    self.postActionTokens[task.id]?.cancel()
                    self.postActionTokens.removeValue(forKey: task.id)
                }
            }
    }

    /// Perform post-download action
    private func performPostDownloadAction(_ action: PostDownloadAction, for task: DownloadTask) {
        if action == .sleep || action == .shutdown {
            SchedulerQueueManager.shared.requestPowerAction(action, triggeredBy: task.id)
            return
        }
        guard let schedule = task.schedule else { return }

        let hasOtherActiveDownloads = DownloadManager.shared.downloadTasks
            .contains { $0.id != task.id && $0.state == .downloading }

        // "Only when all downloads complete" is optional; without it, act right away.
        if schedule.stopAfterCompletion && hasOtherActiveDownloads { return }
        perform(action)
    }

    /// Run a system action (also used by SchedulerQueueManager for queue / per-download actions).
    func perform(_ action: PostDownloadAction, reason: String = "scheduler") {
        PowerActionLog.log("perform: action=\"\(action.rawValue)\" reason=\(reason)")
        switch action {
        case .none:      break
        case .shutdown:  SystemPowerActions.shutdown()
        case .sleep:     SystemPowerActions.sleep()
        case .hibernate: SystemPowerActions.sleep()
        case .closeApp:  closeApplication()
        case .runScript: runCustomScript()
        }
    }

    // MARK: - System Actions

    private func closeApplication() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func runCustomScript() {
        let path = UserDefaults.standard.string(forKey: "schedulerCustomScript") ?? ""
        guard !path.isEmpty else {
            print("Custom script requested but no path set (prefs key schedulerCustomScript).")
            return
        }
        // Run off the main thread: never block the UI while a script runs.
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = [path]
            do {
                try proc.run()
                proc.waitUntilExit()
                print("Custom script exited: \(proc.terminationStatus)")
            } catch {
                print("Custom script failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Statistics

    /// Get scheduled downloads count
    var scheduledCount: Int {
        scheduledTasks.filter { $0.schedule?.type != .immediate }.count
    }

    /// Get next scheduled download
    var nextScheduledTask: DownloadTask? {
        scheduledTasks
            .filter { $0.schedule?.isEnabled == true && $0.state != .completed }
            .min { task1, task2 in
                guard let next1 = task1.schedule?.nextRun else { return false }
                guard let next2 = task2.schedule?.nextRun else { return true }
                return next1 < next2
            }
    }

    /// Get tasks scheduled for today
    func tasksScheduledForToday() -> [DownloadTask] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? Date()

        return scheduledTasks.filter { task in
            guard let nextRun = task.schedule?.nextRun else { return false }
            return nextRun >= today && nextRun < tomorrow
        }
    }

    /// Get upcoming scheduled tasks (next 7 days)
    func upcomingTasks(days: Int = 7) -> [DownloadTask] {
        let calendar = Calendar.current
        let now = Date()
        let future = calendar.date(byAdding: .day, value: days, to: now) ?? now

        return scheduledTasks.filter { task in
            guard let nextRun = task.schedule?.nextRun,
                  task.schedule?.isEnabled == true else { return false }
            return nextRun >= now && nextRun <= future
        }
        .sorted { task1, task2 in
            guard let next1 = task1.schedule?.nextRun else { return false }
            guard let next2 = task2.schedule?.nextRun else { return true }
            return next1 < next2
        }
    }
}

// MARK: - Extensions

extension DownloadTask {
    /// Per-task bandwidth limit (bytes/second), honoured by the engine.
    var bandwidthLimit: Int64? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.bandwidthLimit) as? Int64
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.bandwidthLimit, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private struct AssociatedKeys {
        static var bandwidthLimit = "bandwidthLimit"
    }
}
