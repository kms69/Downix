//
//  SchedulerQueue.swift
//  Download Manager for Mac
//
//  Named scheduler queue model — like Internet Download Manager's scheduler.
//  Each queue has its own schedule window, speed limit, concurrency cap,
//  and a post-completion action (sleep, shutdown, quit, …).
//

import Foundation

// MARK: - SchedulerQueue

/// A named download queue with its own schedule, speed limit, and completion action.
struct SchedulerQueue: Identifiable, Codable, Equatable, Hashable {

    // MARK: Identity
    let id: UUID
    var name: String
    /// Hex color string, e.g. "#007AFF"
    var colorHex: String

    // MARK: Schedule window
    /// When false the queue is always active (no time restriction).
    var isScheduleEnabled: Bool
    var startTime: Date
    var stopTime: Date
    /// Days of the week on which the schedule window is active.
    var weekdays: Set<Weekday>

    // MARK: Limits
    var maxSimultaneousDownloads: Int
    /// nil = unlimited
    var bandwidthLimitBytesPerSec: Int64?

    // MARK: Completion
    /// Action to perform after ALL downloads in this queue finish.
    var postQueueAction: PostDownloadAction

    // MARK: IDM-style one-shot schedule (all optional so saved queues still load)
    /// "Start download at" checkbox + date/time. Consumed when the queue starts.
    var startAtEnabled: Bool?
    var startAt: Date?
    /// "Stop download at" checkbox + date/time.
    var stopAtEnabled: Bool?
    var stopAt: Date?
    /// True while the queue is in a run (scheduled or Start Now). The completion
    /// action only fires for an armed queue; a manual Stop disarms it.
    var armed: Bool?

    // MARK: Runtime state
    var isEnabled: Bool
    var isPaused: Bool

    // MARK: Downloads
    var taskIDs: [UUID]

    // MARK: Metadata
    var createdAt: Date
    var modifiedAt: Date

    // MARK: - Init

    init(name: String, colorHex: String = "#007AFF") {
        let now = Date()
        let cal = Calendar.current

        self.id = UUID()
        self.name = name
        self.colorHex = colorHex

        self.isScheduleEnabled = false
        self.startTime = cal.date(bySettingHour: 9,  minute: 0, second: 0, of: now) ?? now
        self.stopTime  = cal.date(bySettingHour: 23, minute: 0, second: 0, of: now) ?? now
        self.weekdays = Set(Weekday.allCases)

        self.maxSimultaneousDownloads = 3
        self.bandwidthLimitBytesPerSec = nil

        self.postQueueAction = .none

        self.isEnabled = true
        self.isPaused = false

        self.taskIDs = []

        self.createdAt = now
        self.modifiedAt = now
    }

    // MARK: - Computed helpers

    var formattedBandwidth: String {
        guard let limit = bandwidthLimitBytesPerSec else { return "Unlimited" }
        return ByteCountFormatter.string(fromByteCount: limit, countStyle: .file) + "/s"
    }

    var scheduleTimeRange: String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return "\(fmt.string(from: startTime)) – \(fmt.string(from: stopTime))"
    }

    /// Returns true when downloads in this queue should be actively running right now.
    func isInScheduleWindow(at date: Date = Date()) -> Bool {
        guard isScheduleEnabled else { return true }

        let cal = Calendar.current
        let weekdayNum = cal.component(.weekday, from: date)
        guard let currentWeekday = Weekday(rawValue: weekdayNum),
              weekdays.contains(currentWeekday) else { return false }

        let sm = minutesFromMidnight(startTime)
        let em = minutesFromMidnight(stopTime)
        let cm = minutesFromMidnight(date)

        if sm <= em {
            return cm >= sm && cm <= em
        } else {
            // Overnight window, e.g. 23:00 – 08:00
            return cm >= sm || cm <= em
        }
    }

    private func minutesFromMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: - Hashable / Equatable (by id)
    static func == (lhs: SchedulerQueue, rhs: SchedulerQueue) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
