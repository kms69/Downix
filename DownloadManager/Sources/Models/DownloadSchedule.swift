//
//  DownloadSchedule.swift
//  Download Manager for Mac - Feature #3: Download Scheduler
//
//  Created on February 15, 2026
//

import Foundation

/// Schedule type for downloads
enum ScheduleType: String, Codable, CaseIterable {
    case immediate = "Start Immediately"
    case once = "Once (specific time)"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .immediate: return "play.fill"
        case .once: return "calendar"
        case .daily: return "calendar.badge.clock"
        case .weekly: return "calendar.circle"
        case .monthly: return "calendar.badge.plus"
        case .custom: return "calendar.badge.exclamationmark"
        }
    }
}

/// Days of the week for recurring schedules
enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    
    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }
    
    var fullName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}

/// Schedule configuration for a download
struct DownloadSchedule: Codable, Identifiable {
    let id: UUID
    var type: ScheduleType
    
    // One-time schedule
    var scheduledDate: Date?
    
    // Recurring schedules
    var startTime: Date?
    var endTime: Date?
    var weekdays: Set<Weekday>?
    var dayOfMonth: Int? // 1-31 for monthly
    
    // Bandwidth management
    var bandwidthLimit: Int64? // bytes per second, nil = unlimited
    
    // Stop conditions
    var stopAfterCompletion: Bool = false
    var actionAfterCompletion: PostDownloadAction = .none
    
    // Status
    var isEnabled: Bool = true
    var lastRun: Date?
    var nextRun: Date?
    
    init(type: ScheduleType = .immediate) {
        self.id = UUID()
        self.type = type
        
        if type == .immediate {
            self.scheduledDate = Date()
        }
    }
    
    /// Check if schedule should run at given date
    func shouldRun(at date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        
        switch type {
        case .immediate:
            return true
            
        case .once:
            guard let scheduledDate = scheduledDate else { return false }
            // Check if we're within 1 minute of scheduled time
            return abs(date.timeIntervalSince(scheduledDate)) < 60
            
        case .daily:
            guard let startTime = startTime else { return false }
            return isTimeMatch(date: date, targetTime: startTime)
            
        case .weekly:
            guard let startTime = startTime,
                  let weekdays = weekdays else { return false }
            
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: date)
            
            if let targetWeekday = Weekday(rawValue: weekday),
               weekdays.contains(targetWeekday) {
                return isTimeMatch(date: date, targetTime: startTime)
            }
            return false
            
        case .monthly:
            guard let startTime = startTime,
                  let dayOfMonth = dayOfMonth else { return false }
            
            let calendar = Calendar.current
            let day = calendar.component(.day, from: date)
            
            if day == dayOfMonth {
                return isTimeMatch(date: date, targetTime: startTime)
            }
            return false
            
        case .custom:
            // Custom logic can be extended
            return false
        }
    }
    
    /// Check if the time of day matches (within 1 minute)
    private func isTimeMatch(date: Date, targetTime: Date) -> Bool {
        let calendar = Calendar.current
        
        let dateComponents = calendar.dateComponents([.hour, .minute], from: date)
        let targetComponents = calendar.dateComponents([.hour, .minute], from: targetTime)
        
        return dateComponents.hour == targetComponents.hour &&
               dateComponents.minute == targetComponents.minute
    }
    
    /// Calculate next run date
    mutating func calculateNextRun() {
        let calendar = Calendar.current
        let now = Date()
        
        switch type {
        case .immediate:
            nextRun = now
            
        case .once:
            nextRun = scheduledDate
            
        case .daily:
            guard let startTime = startTime else { return }
            
            let components = calendar.dateComponents([.hour, .minute], from: startTime)
            var nextDate = calendar.date(bySettingHour: components.hour ?? 0,
                                        minute: components.minute ?? 0,
                                        second: 0,
                                        of: now) ?? now
            
            // If time has passed today, schedule for tomorrow
            if nextDate <= now {
                nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? now
            }
            
            nextRun = nextDate
            
        case .weekly:
            guard let startTime = startTime,
                  let weekdays = weekdays,
                  !weekdays.isEmpty else { return }
            
            let components = calendar.dateComponents([.hour, .minute], from: startTime)
            let currentWeekday = calendar.component(.weekday, from: now)
            
            // Find next matching weekday
            var daysToAdd = 0
            for day in 0...7 {
                let checkDate = calendar.date(byAdding: .day, value: day, to: now) ?? now
                let checkWeekday = calendar.component(.weekday, from: checkDate)
                
                if let targetWeekday = Weekday(rawValue: checkWeekday),
                   weekdays.contains(targetWeekday) {
                    
                    var nextDate = calendar.date(bySettingHour: components.hour ?? 0,
                                                minute: components.minute ?? 0,
                                                second: 0,
                                                of: checkDate) ?? now
                    
                    if nextDate > now {
                        nextRun = nextDate
                        return
                    }
                }
            }
            
        case .monthly:
            guard let startTime = startTime,
                  let dayOfMonth = dayOfMonth else { return }
            
            let components = calendar.dateComponents([.hour, .minute], from: startTime)
            
            // Try this month first
            var dateComponents = calendar.dateComponents([.year, .month], from: now)
            dateComponents.day = dayOfMonth
            dateComponents.hour = components.hour
            dateComponents.minute = components.minute
            
            if var nextDate = calendar.date(from: dateComponents) {
                if nextDate <= now {
                    // Move to next month
                    nextDate = calendar.date(byAdding: .month, value: 1, to: nextDate) ?? now
                }
                nextRun = nextDate
            }
            
        case .custom:
            nextRun = nil
        }
    }
    
    /// Human-readable description
    var description: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        
        switch type {
        case .immediate:
            return "Start immediately"
            
        case .once:
            if let date = scheduledDate {
                return "Once on \(formatter.string(from: date))"
            }
            return "Once (not configured)"
            
        case .daily:
            if let time = startTime {
                formatter.dateStyle = .none
                return "Daily at \(formatter.string(from: time))"
            }
            return "Daily (not configured)"
            
        case .weekly:
            if let time = startTime, let days = weekdays, !days.isEmpty {
                formatter.dateStyle = .none
                let dayNames = days.sorted(by: { $0.rawValue < $1.rawValue })
                    .map { $0.shortName }
                    .joined(separator: ", ")
                return "Weekly on \(dayNames) at \(formatter.string(from: time))"
            }
            return "Weekly (not configured)"
            
        case .monthly:
            if let time = startTime, let day = dayOfMonth {
                formatter.dateStyle = .none
                return "Monthly on day \(day) at \(formatter.string(from: time))"
            }
            return "Monthly (not configured)"
            
        case .custom:
            return "Custom schedule"
        }
    }
}

/// Actions to perform after download completion
enum PostDownloadAction: String, Codable, CaseIterable {
    case none = "None"
    case shutdown = "Shutdown Mac"
    case sleep = "Sleep"
    case hibernate = "Hibernate"
    case closeApp = "Close Application"
    case runScript = "Run Script"
    
    var icon: String {
        switch self {
        case .none: return "minus.circle"
        case .shutdown: return "power"
        case .sleep: return "moon.fill"
        case .hibernate: return "moon.zzz.fill"
        case .closeApp: return "xmark.app"
        case .runScript: return "terminal"
        }
    }

    static var macCases: [PostDownloadAction] {
        [.none, .shutdown, .sleep, .closeApp, .runScript]
    }

    static var compactCases: [PostDownloadAction] {
        [.none, .sleep, .shutdown]
    }
}

/// Bandwidth schedule for time-based speed limiting
struct BandwidthSchedule: Codable, Identifiable {
    let id: UUID
    var name: String
    var startTime: Date
    var endTime: Date
    var bandwidthLimit: Int64 // bytes per second
    var weekdays: Set<Weekday>
    var isEnabled: Bool = true
    
    init(name: String, startTime: Date, endTime: Date, bandwidthLimit: Int64, weekdays: Set<Weekday> = Set(Weekday.allCases)) {
        self.id = UUID()
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.bandwidthLimit = bandwidthLimit
        self.weekdays = weekdays
    }
    
    /// Check if schedule is active at given time
    func isActive(at date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        
        guard let currentWeekday = Weekday(rawValue: weekday),
              weekdays.contains(currentWeekday) else {
            return false
        }
        
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let currentMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        
        // Handle overnight schedules
        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes <= endMinutes
        } else {
            return currentMinutes >= startMinutes || currentMinutes <= endMinutes
        }
    }
    
    var formattedBandwidth: String {
        return ByteCountFormatter.string(fromByteCount: bandwidthLimit, countStyle: .file) + "/s"
    }
}

// MARK: - Extensions

extension DownloadTask {
    /// Schedule for this download
    var schedule: DownloadSchedule? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.schedule) as? DownloadSchedule
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.schedule, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    /// Whether this task is scheduled
    var isScheduled: Bool {
        schedule != nil && schedule?.type != .immediate
    }

    /// Action to take when *this specific download* finishes (overrides queue-level action).
    var postDownloadAction: PostDownloadAction? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.postDownloadAction) as? PostDownloadAction
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.postDownloadAction, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    /// The ID of the SchedulerQueue this task belongs to, if any.
    var schedulerQueueID: UUID? {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.schedulerQueueID) as? UUID
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.schedulerQueueID, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private struct AssociatedKeys {
        static var schedule            = "schedule"
        static var postDownloadAction  = "postDownloadAction"
        static var schedulerQueueID    = "schedulerQueueID"
    }
}
