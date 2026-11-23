import Foundation
import UserNotifications

// MARK: - Notification Type

/// Types of notifications the app can send
public enum NotificationType: String, Codable, CaseIterable {
    case downloadStarted = "Download Started"
    case downloadProgress = "Download Progress"
    case downloadCompleted = "Download Completed"
    case downloadFailed = "Download Failed"
    case downloadPaused = "Download Paused"
    case queueCompleted = "Queue Completed"
    case batchCompleted = "Batch Completed"
    case lowDiskSpace = "Low Disk Space"
    case speedThreshold = "Speed Threshold"
    case dailySummary = "Daily Summary"
    case weeklySummary = "Weekly Summary"
    
    var icon: String {
        switch self {
        case .downloadStarted: return "arrow.down.circle"
        case .downloadProgress: return "clock.arrow.circlepath"
        case .downloadCompleted: return "checkmark.circle.fill"
        case .downloadFailed: return "xmark.circle.fill"
        case .downloadPaused: return "pause.circle"
        case .queueCompleted: return "checkmark.circle.fill"
        case .batchCompleted: return "checkmark.square.fill"
        case .lowDiskSpace: return "externaldrive.fill.badge.exclamationmark"
        case .speedThreshold: return "speedometer"
        case .dailySummary: return "calendar"
        case .weeklySummary: return "calendar.badge.clock"
        }
    }
    
    var category: String {
        switch self {
        case .downloadCompleted, .queueCompleted, .batchCompleted:
            return "DOWNLOAD_COMPLETE"
        case .downloadFailed:
            return "DOWNLOAD_ERROR"
        case .downloadProgress, .speedThreshold:
            return "DOWNLOAD_PROGRESS"
        default:
            return "GENERAL"
        }
    }
    
    var defaultEnabled: Bool {
        switch self {
        case .downloadProgress: return false // Too frequent
        case .downloadPaused: return false
        default: return true
        }
    }
}

// MARK: - Notification Sound

/// Available notification sounds
public enum NotificationSound: String, Codable, CaseIterable {
    case defaultSound = "Default"
    case glass = "Glass"
    case hero = "Hero"
    case ping = "Ping"
    case pop = "Pop"
    case submarine = "Submarine"
    case bell = "Bell"
    case bloink = "Bloink"
    case funk = "Funk"
    case purr = "Purr"
    case silence = "Silent"
    
    var systemName: String? {
        switch self {
        case .defaultSound: return "default"
        case .silence: return nil
        default: return "\(rawValue).aiff"
        }
    }
    
    var sound: UNNotificationSound? {
        switch self {
        case .defaultSound: return .default
        case .silence: return nil
        default:
            if let name = systemName {
                return UNNotificationSound(named: UNNotificationSoundName(rawValue: name))
            }
            return nil
        }
    }
}

// MARK: - Notification Priority

/// Priority levels for notifications
public enum NotificationPriority: Int, Codable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    
    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .low: return .passive
        case .normal: return .active
        case .high: return .timeSensitive
        case .critical: return .critical
        }
    }
}

// MARK: - Notification Action

/// Actions available in notifications
public struct NotificationAction: Codable, Identifiable {
    public let id: String
    public var title: String
    public var icon: String?
    public var destructive: Bool
    public var foreground: Bool
    
    public init(
        id: String,
        title: String,
        icon: String? = nil,
        destructive: Bool = false,
        foreground: Bool = true
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.destructive = destructive
        self.foreground = foreground
    }
    
    func toUNNotificationAction() -> UNNotificationAction {
        var options: UNNotificationActionOptions = []
        if destructive { options.insert(.destructive) }
        if foreground { options.insert(.foreground) }
        
        return UNNotificationAction(
            identifier: id,
            title: title,
            options: options
        )
    }
    
    // Predefined actions
    static let openDownload = NotificationAction(
        id: "OPEN_DOWNLOAD",
        title: "Open",
        icon: "folder"
    )
    
    static let showInFinder = NotificationAction(
        id: "SHOW_IN_FINDER",
        title: "Show in Finder",
        icon: "magnifyingglass"
    )
    
    static let retry = NotificationAction(
        id: "RETRY",
        title: "Retry",
        icon: "arrow.clockwise"
    )
    
    static let cancel = NotificationAction(
        id: "CANCEL",
        title: "Cancel",
        icon: "xmark",
        destructive: true
    )
    
    static let resume = NotificationAction(
        id: "RESUME",
        title: "Resume",
        icon: "play.fill"
    )
    
    static let viewDetails = NotificationAction(
        id: "VIEW_DETAILS",
        title: "View Details",
        icon: "info.circle"
    )
}

// MARK: - Notification Settings

/// Configuration for notification behavior
public struct NotificationSettings: Codable {
    public var enabledTypes: Set<NotificationType>
    public var soundEnabled: Bool
    public var sound: NotificationSound
    public var badgeEnabled: Bool
    public var bannerEnabled: Bool
    public var alertStyle: AlertStyle
    
    // Progress notification settings
    public var progressInterval: TimeInterval // Minimum seconds between progress notifications
    public var progressThreshold: Double // Minimum progress change (0.0-1.0) to trigger notification
    
    // Speed threshold notification
    public var speedThresholdEnabled: Bool
    public var speedThreshold: Int64 // Bytes per second
    
    // Summary settings
    public var dailySummaryTime: Date // Time of day to send daily summary
    public var weeklySummaryDay: Int // Day of week (1=Sunday, 7=Saturday)
    public var weeklySummaryTime: Date
    public var summaryMinimumDownloads: Int // Minimum downloads to trigger summary
    
    // Do Not Disturb
    public var doNotDisturbEnabled: Bool
    public var doNotDisturbStart: Date // Time of day
    public var doNotDisturbEnd: Date // Time of day
    
    public enum AlertStyle: String, Codable {
        case none = "None"
        case banner = "Banner"
        case alert = "Alert"
    }
    
    public init() {
        self.enabledTypes = Set(NotificationType.allCases.filter { $0.defaultEnabled })
        self.soundEnabled = true
        self.sound = .defaultSound
        self.badgeEnabled = true
        self.bannerEnabled = true
        self.alertStyle = .banner
        self.progressInterval = 60 // 1 minute
        self.progressThreshold = 0.25 // 25%
        self.speedThresholdEnabled = false
        self.speedThreshold = 100_000 // 100 KB/s
        
        // Default to 9 AM for daily summary
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        self.dailySummaryTime = calendar.date(from: components) ?? Date()
        
        self.weeklySummaryDay = 1 // Sunday
        self.weeklySummaryTime = self.dailySummaryTime
        self.summaryMinimumDownloads = 1
        
        self.doNotDisturbEnabled = false
        self.doNotDisturbStart = calendar.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
        self.doNotDisturbEnd = calendar.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    }
    
    public func isEnabled(_ type: NotificationType) -> Bool {
        enabledTypes.contains(type)
    }
    
    public mutating func setEnabled(_ type: NotificationType, enabled: Bool) {
        if enabled {
            enabledTypes.insert(type)
        } else {
            enabledTypes.remove(type)
        }
    }
    
    public func isInDoNotDisturb() -> Bool {
        guard doNotDisturbEnabled else { return false }
        
        let calendar = Calendar.current
        let now = Date()
        let currentTime = calendar.dateComponents([.hour, .minute], from: now)
        let startTime = calendar.dateComponents([.hour, .minute], from: doNotDisturbStart)
        let endTime = calendar.dateComponents([.hour, .minute], from: doNotDisturbEnd)
        
        let currentMinutes = (currentTime.hour ?? 0) * 60 + (currentTime.minute ?? 0)
        let startMinutes = (startTime.hour ?? 0) * 60 + (startTime.minute ?? 0)
        let endMinutes = (endTime.hour ?? 0) * 60 + (endTime.minute ?? 0)
        
        if startMinutes <= endMinutes {
            // Same day range (e.g., 9 AM - 5 PM)
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Overnight range (e.g., 10 PM - 8 AM)
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }
}

// MARK: - Notification Content

/// Content for a notification
public struct NotificationContent: Codable, Identifiable {
    public let id: UUID
    public var type: NotificationType
    public var title: String
    public var body: String
    public var subtitle: String?
    public var priority: NotificationPriority
    public var actions: [NotificationAction]
    public var data: [String: String] // Additional data
    public var scheduledDate: Date?
    public var delivered: Bool
    public var deliveredDate: Date?
    
    public init(
        id: UUID = UUID(),
        type: NotificationType,
        title: String,
        body: String,
        subtitle: String? = nil,
        priority: NotificationPriority = .normal,
        actions: [NotificationAction] = [],
        data: [String: String] = [:],
        scheduledDate: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.subtitle = subtitle
        self.priority = priority
        self.actions = actions
        self.data = data
        self.scheduledDate = scheduledDate
        self.delivered = false
        self.deliveredDate = nil
    }
    
    // Predefined notification templates
    static func downloadStarted(filename: String, size: String) -> NotificationContent {
        NotificationContent(
            type: .downloadStarted,
            title: "Download Started",
            body: "\(filename) (\(size))",
            priority: .low,
            actions: [.cancel, .viewDetails]
        )
    }
    
    static func downloadCompleted(filename: String, duration: String) -> NotificationContent {
        NotificationContent(
            type: .downloadCompleted,
            title: "Download Complete",
            body: "\(filename) finished in \(duration)",
            priority: .high,
            actions: [.openDownload, .showInFinder]
        )
    }
    
    static func downloadFailed(filename: String, error: String) -> NotificationContent {
        NotificationContent(
            type: .downloadFailed,
            title: "Download Failed",
            body: "\(filename)\n\(error)",
            priority: .high,
            actions: [.retry, .cancel]
        )
    }
    
    static func downloadProgress(filename: String, progress: Int, speed: String, eta: String) -> NotificationContent {
        NotificationContent(
            type: .downloadProgress,
            title: "Downloading",
            body: "\(filename)\n\(progress)% • \(speed) • ETA: \(eta)",
            priority: .low
        )
    }
    
    static func queueCompleted(count: Int, totalSize: String, duration: String) -> NotificationContent {
        NotificationContent(
            type: .queueCompleted,
            title: "Queue Complete",
            body: "\(count) download\(count == 1 ? "" : "s") completed (\(totalSize)) in \(duration)",
            priority: .high,
            actions: [.showInFinder, .viewDetails]
        )
    }
    
    static func dailySummary(downloads: Int, totalSize: String, avgSpeed: String) -> NotificationContent {
        NotificationContent(
            type: .dailySummary,
            title: "Daily Download Summary",
            body: "\(downloads) downloads • \(totalSize) total • \(avgSpeed) avg speed",
            subtitle: "Last 24 hours",
            priority: .normal,
            actions: [.viewDetails]
        )
    }
    
    static func weeklySummary(downloads: Int, totalSize: String, avgSpeed: String) -> NotificationContent {
        NotificationContent(
            type: .weeklySummary,
            title: "Weekly Download Summary",
            body: "\(downloads) downloads • \(totalSize) total • \(avgSpeed) avg speed",
            subtitle: "Last 7 days",
            priority: .normal,
            actions: [.viewDetails]
        )
    }
    
    static func lowDiskSpace(available: String, required: String) -> NotificationContent {
        NotificationContent(
            type: .lowDiskSpace,
            title: "Low Disk Space",
            body: "Only \(available) available. \(required) required for pending downloads.",
            priority: .critical,
            actions: [.viewDetails]
        )
    }
    
    static func speedThreshold(currentSpeed: String, threshold: String) -> NotificationContent {
        NotificationContent(
            type: .speedThreshold,
            title: "Low Download Speed",
            body: "Current: \(currentSpeed) (threshold: \(threshold))",
            priority: .low,
            actions: [.viewDetails]
        )
    }
}

// MARK: - Notification History

/// Historical record of sent notifications
public struct NotificationHistory: Codable, Identifiable {
    public let id: UUID
    public var content: NotificationContent
    public var sentDate: Date
    public var interacted: Bool
    public var actionTaken: String?
    
    public init(
        id: UUID = UUID(),
        content: NotificationContent,
        sentDate: Date = Date(),
        interacted: Bool = false,
        actionTaken: String? = nil
    ) {
        self.id = id
        self.content = content
        self.sentDate = sentDate
        self.interacted = interacted
        self.actionTaken = actionTaken
    }
}

// MARK: - Notification Statistics

/// Statistics about notifications
public struct NotificationStatistics: Codable {
    public var totalSent: Int
    public var totalInteracted: Int
    public var byType: [NotificationType: Int]
    public var byPriority: [NotificationPriority: Int]
    public var lastSentDate: Date?
    public var averageResponseTime: TimeInterval?
    
    public init() {
        self.totalSent = 0
        self.totalInteracted = 0
        self.byType = [:]
        self.byPriority = [:]
        self.lastSentDate = nil
        self.averageResponseTime = nil
    }
    
    public var interactionRate: Double {
        guard totalSent > 0 else { return 0 }
        return Double(totalInteracted) / Double(totalSent)
    }
    
    public mutating func recordNotification(_ content: NotificationContent) {
        totalSent += 1
        byType[content.type, default: 0] += 1
        byPriority[content.priority, default: 0] += 1
        lastSentDate = Date()
    }
    
    public mutating func recordInteraction(responseTime: TimeInterval) {
        totalInteracted += 1
        
        if let current = averageResponseTime {
            averageResponseTime = (current * Double(totalInteracted - 1) + responseTime) / Double(totalInteracted)
        } else {
            averageResponseTime = responseTime
        }
    }
}
