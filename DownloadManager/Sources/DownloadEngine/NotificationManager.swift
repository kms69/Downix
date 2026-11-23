import Foundation
import UserNotifications
import Combine
import AppKit

@MainActor
public class NotificationManager: NSObject, ObservableObject {
    public static let shared = NotificationManager()
    
    @Published public var settings: NotificationSettings
    @Published public var history: [NotificationHistory]
    @Published public var statistics: NotificationStatistics
    @Published public var authorizationStatus: UNAuthorizationStatus
    @Published public var pendingNotifications: [NotificationContent]
    
    private let center: UNUserNotificationCenter?
    private var progressTracker: [UUID: (lastNotified: Date, lastProgress: Double)]
    private var dailySummaryTimer: Timer?
    private var weeklySummaryTimer: Timer?
    
    private let maxHistorySize = 1000
    private let settingsKey = "NotificationSettings"
    private let historyKey = "NotificationHistory"
    private let statisticsKey = "NotificationStatistics"
    
    private override init() {
        // UNUserNotificationCenter requires a bundle identifier; guard against bare executable runs
        if Bundle.main.bundleIdentifier != nil {
            self.center = UNUserNotificationCenter.current()
        } else {
            self.center = nil
        }
        self.settings = NotificationSettings()
        self.history = []
        self.statistics = NotificationStatistics()
        self.authorizationStatus = .notDetermined
        self.pendingNotifications = []
        self.progressTracker = [:]
        
        super.init()
        
        center?.delegate = self
        loadSettings()
        loadHistory()
        loadStatistics()
        checkAuthorizationStatus()
        setupNotificationCategories()
        scheduleSummaryNotifications()
    }
    
    // MARK: - Authorization
    
    public func requestAuthorization() async throws {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        guard let center = center else { return }
        let granted = try await center.requestAuthorization(options: options)
        
        await MainActor.run {
            authorizationStatus = granted ? .authorized : .denied
        }
    }
    
    public func checkAuthorizationStatus() {
        Task {
            guard let center = center else { return }
            let settings = await center.notificationSettings()
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    // MARK: - Send Notifications
    
    public func sendNotification(_ content: NotificationContent) {
        guard settings.isEnabled(content.type) else { return }
        guard authorizationStatus == .authorized else { return }
        guard !settings.isInDoNotDisturb() else { return }
        
        // Create notification content
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = content.title
        notificationContent.body = content.body
        if let subtitle = content.subtitle {
            notificationContent.subtitle = subtitle
        }
        notificationContent.categoryIdentifier = content.type.category
        notificationContent.interruptionLevel = content.priority.interruptionLevel
        
        // Add sound
        if settings.soundEnabled, let sound = settings.sound.sound {
            notificationContent.sound = sound
        }
        
        // Add badge
        if settings.badgeEnabled {
            notificationContent.badge = NSNumber(value: pendingNotifications.count + 1)
        }
        
        // Add user info
        var userInfo = content.data
        userInfo["notificationId"] = content.id.uuidString
        userInfo["type"] = content.type.rawValue
        notificationContent.userInfo = userInfo
        
        // Create trigger
        let trigger: UNNotificationTrigger?
        if let scheduledDate = content.scheduledDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: scheduledDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = nil // Immediate delivery
        }
        
        // Create request
        let request = UNNotificationRequest(
            identifier: content.id.uuidString,
            content: notificationContent,
            trigger: trigger
        )
        
        // Schedule notification
        center?.add(request) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error scheduling notification: \(error.localizedDescription)")
                } else {
                    var updatedContent = content
                    updatedContent.delivered = true
                    updatedContent.deliveredDate = Date()
                    
                    // Record in history
                    let historyItem = NotificationHistory(content: updatedContent)
                    self.history.insert(historyItem, at: 0)
                    
                    // Limit history size
                    if self.history.count > self.maxHistorySize {
                        self.history = Array(self.history.prefix(self.maxHistorySize))
                    }
                    
                    // Update statistics
                    self.statistics.recordNotification(content)
                    
                    self.saveHistory()
                    self.saveStatistics()
                }
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    public func notifyDownloadStarted(taskId: UUID, filename: String, size: String) {
        let content = NotificationContent.downloadStarted(filename: filename, size: size)
        var mutableContent = content
        mutableContent.data["taskId"] = taskId.uuidString
        sendNotification(mutableContent)
    }
    
    public func notifyDownloadCompleted(taskId: UUID, filename: String, duration: String, filePath: String) {
        let content = NotificationContent.downloadCompleted(filename: filename, duration: duration)
        var mutableContent = content
        mutableContent.data["taskId"] = taskId.uuidString
        mutableContent.data["filePath"] = filePath
        sendNotification(mutableContent)
    }
    
    public func notifyDownloadFailed(taskId: UUID, filename: String, error: String) {
        let content = NotificationContent.downloadFailed(filename: filename, error: error)
        var mutableContent = content
        mutableContent.data["taskId"] = taskId.uuidString
        sendNotification(mutableContent)
    }
    
    public func notifyDownloadProgress(taskId: UUID, filename: String, progress: Double, speed: String, eta: String) {
        // Check if we should send progress notification
        guard shouldNotifyProgress(taskId: taskId, progress: progress) else { return }
        
        let progressPercent = Int(progress * 100)
        let content = NotificationContent.downloadProgress(
            filename: filename,
            progress: progressPercent,
            speed: speed,
            eta: eta
        )
        var mutableContent = content
        mutableContent.data["taskId"] = taskId.uuidString
        sendNotification(mutableContent)
    }
    
    public func notifyQueueCompleted(count: Int, totalSize: String, duration: String) {
        let content = NotificationContent.queueCompleted(count: count, totalSize: totalSize, duration: duration)
        sendNotification(content)
    }
    
    public func notifyDailySummary(downloads: Int, totalSize: String, avgSpeed: String) {
        guard downloads >= settings.summaryMinimumDownloads else { return }
        let content = NotificationContent.dailySummary(downloads: downloads, totalSize: totalSize, avgSpeed: avgSpeed)
        sendNotification(content)
    }
    
    public func notifyWeeklySummary(downloads: Int, totalSize: String, avgSpeed: String) {
        guard downloads >= settings.summaryMinimumDownloads else { return }
        let content = NotificationContent.weeklySummary(downloads: downloads, totalSize: totalSize, avgSpeed: avgSpeed)
        sendNotification(content)
    }
    
    public func notifyLowDiskSpace(available: String, required: String) {
        let content = NotificationContent.lowDiskSpace(available: available, required: required)
        sendNotification(content)
    }
    
    public func notifySpeedThreshold(currentSpeed: String, threshold: String) {
        guard settings.speedThresholdEnabled else { return }
        let content = NotificationContent.speedThreshold(currentSpeed: currentSpeed, threshold: threshold)
        sendNotification(content)
    }
    
    // MARK: - Progress Tracking
    
    private func shouldNotifyProgress(taskId: UUID, progress: Double) -> Bool {
        let now = Date()
        
        if let tracker = progressTracker[taskId] {
            // Check time interval
            let timeSinceLastNotification = now.timeIntervalSince(tracker.lastNotified)
            guard timeSinceLastNotification >= settings.progressInterval else {
                return false
            }
            
            // Check progress change
            let progressChange = abs(progress - tracker.lastProgress)
            guard progressChange >= settings.progressThreshold else {
                return false
            }
        }
        
        // Update tracker
        progressTracker[taskId] = (lastNotified: now, lastProgress: progress)
        return true
    }
    
    public func clearProgressTracker(taskId: UUID) {
        progressTracker.removeValue(forKey: taskId)
    }
    
    // MARK: - Notification Management
    
    public func cancelNotification(id: UUID) {
        center?.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
    
    public func cancelAllNotifications() {
        center?.removeAllPendingNotificationRequests()
        pendingNotifications.removeAll()
    }
    
    public func getPendingNotifications() {
        center?.getPendingNotificationRequests { [weak self] requests in
            Task { @MainActor in
                guard let self = self else { return }
                // Update pending notifications list
                print("Pending notifications: \(requests.count)")
            }
        }
    }
    
    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }
    
    public func clearStatistics() {
        statistics = NotificationStatistics()
        saveStatistics()
    }
    
    // MARK: - Notification Categories
    
    private func setupNotificationCategories() {
        let completeCategory = UNNotificationCategory(
            identifier: "DOWNLOAD_COMPLETE",
            actions: [
                NotificationAction.openDownload.toUNNotificationAction(),
                NotificationAction.showInFinder.toUNNotificationAction()
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let errorCategory = UNNotificationCategory(
            identifier: "DOWNLOAD_ERROR",
            actions: [
                NotificationAction.retry.toUNNotificationAction(),
                NotificationAction.cancel.toUNNotificationAction()
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let progressCategory = UNNotificationCategory(
            identifier: "DOWNLOAD_PROGRESS",
            actions: [
                NotificationAction.viewDetails.toUNNotificationAction()
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let generalCategory = UNNotificationCategory(
            identifier: "GENERAL",
            actions: [
                NotificationAction.viewDetails.toUNNotificationAction()
            ],
            intentIdentifiers: [],
            options: []
        )
        
        center?.setNotificationCategories([completeCategory, errorCategory, progressCategory, generalCategory])
    }
    
    // MARK: - Summary Scheduling
    
    private func scheduleSummaryNotifications() {
        // Daily summary
        dailySummaryTimer?.invalidate()
        let dailyInterval = calculateTimeUntilDailySummary()
        dailySummaryTimer = Timer.scheduledTimer(withTimeInterval: dailyInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendDailySummary()
            }
        }
        
        // Weekly summary
        weeklySummaryTimer?.invalidate()
        let weeklyInterval = calculateTimeUntilWeeklySummary()
        weeklySummaryTimer = Timer.scheduledTimer(withTimeInterval: weeklyInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendWeeklySummary()
            }
        }
    }
    
    private func calculateTimeUntilDailySummary() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        let summaryTime = calendar.dateComponents([.hour, .minute], from: settings.dailySummaryTime)
        
        var nextSummary = calendar.date(bySettingHour: summaryTime.hour ?? 9, minute: summaryTime.minute ?? 0, second: 0, of: now) ?? now
        
        if nextSummary <= now {
            nextSummary = calendar.date(byAdding: .day, value: 1, to: nextSummary) ?? now
        }
        
        return max(nextSummary.timeIntervalSince(now), 60) // At least 1 minute
    }
    
    private func calculateTimeUntilWeeklySummary() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        
        // Calculate next occurrence of the specified weekday
        var nextSummary = now
        let currentWeekday = calendar.component(.weekday, from: now)
        let targetWeekday = settings.weeklySummaryDay
        
        var daysToAdd = targetWeekday - currentWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7
        }
        
        nextSummary = calendar.date(byAdding: .day, value: daysToAdd, to: now) ?? now
        
        let summaryTime = calendar.dateComponents([.hour, .minute], from: settings.weeklySummaryTime)
        nextSummary = calendar.date(bySettingHour: summaryTime.hour ?? 9, minute: summaryTime.minute ?? 0, second: 0, of: nextSummary) ?? now
        
        return max(nextSummary.timeIntervalSince(now), 60)
    }
    
    private func sendDailySummary() {
        // This would be called by the timer or external trigger
        // For now, it's a placeholder that would gather stats from DownloadManager
        // notifyDailySummary(downloads: 10, totalSize: "1.2 GB", avgSpeed: "2.5 MB/s")
    }
    
    private func sendWeeklySummary() {
        // Similar to daily summary
        // notifyWeeklySummary(downloads: 50, totalSize: "8.5 GB", avgSpeed: "2.8 MB/s")
    }
    
    // MARK: - Persistence
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            settings = decoded
        }
    }
    
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([NotificationHistory].self, from: data) {
            history = decoded
        }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    private func loadStatistics() {
        if let data = UserDefaults.standard.data(forKey: statisticsKey),
           let decoded = try? JSONDecoder().decode(NotificationStatistics.self, from: data) {
            statistics = decoded
        }
    }
    
    private func saveStatistics() {
        if let encoded = try? JSONEncoder().encode(statistics) {
            UserDefaults.standard.set(encoded, forKey: statisticsKey)
        }
    }
    
    public func updateSettings(_ newSettings: NotificationSettings) {
        settings = newSettings
        saveSettings()
        scheduleSummaryNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handleNotificationResponse(response)
            completionHandler()
        }
    }
    
    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        guard let notificationId = userInfo["notificationId"] as? String,
              let uuid = UUID(uuidString: notificationId) else {
            return
        }
        
        // Record interaction
        if let index = history.firstIndex(where: { $0.content.id == uuid }) {
            history[index].interacted = true
            history[index].actionTaken = actionIdentifier
            
            if let sentDate = history[index].sentDate as Date? {
                let responseTime = Date().timeIntervalSince(sentDate)
                statistics.recordInteraction(responseTime: responseTime)
            }
            
            saveHistory()
            saveStatistics()
        }
        
        // Handle action
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // User tapped notification
            handleDefaultAction(userInfo: userInfo)
            
        case "OPEN_DOWNLOAD":
            handleOpenDownload(userInfo: userInfo)
            
        case "SHOW_IN_FINDER":
            handleShowInFinder(userInfo: userInfo)
            
        case "RETRY":
            handleRetry(userInfo: userInfo)
            
        case "CANCEL":
            handleCancel(userInfo: userInfo)
            
        case "RESUME":
            handleResume(userInfo: userInfo)
            
        case "VIEW_DETAILS":
            handleViewDetails(userInfo: userInfo)
            
        default:
            break
        }
    }
    
    private func handleDefaultAction(userInfo: [AnyHashable: Any]) {
        // Open app to main view
        print("Notification tapped: \(userInfo)")
    }
    
    private func handleOpenDownload(userInfo: [AnyHashable: Any]) {
        if let filePath = userInfo["filePath"] as? String {
            let url = URL(fileURLWithPath: filePath)
            NSWorkspace.shared.open(url)
        }
    }
    
    private func handleShowInFinder(userInfo: [AnyHashable: Any]) {
        if let filePath = userInfo["filePath"] as? String {
            let url = URL(fileURLWithPath: filePath)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    
    private func handleRetry(userInfo: [AnyHashable: Any]) {
        if let taskIdString = userInfo["taskId"] as? String,
           let taskId = UUID(uuidString: taskIdString) {
            // Would call DownloadManager.shared.retryDownload(taskId: taskId)
            print("Retry download: \(taskId)")
        }
    }
    
    private func handleCancel(userInfo: [AnyHashable: Any]) {
        if let taskIdString = userInfo["taskId"] as? String,
           let taskId = UUID(uuidString: taskIdString) {
            // Would call DownloadManager.shared.cancelDownload(taskId: taskId)
            print("Cancel download: \(taskId)")
        }
    }
    
    private func handleResume(userInfo: [AnyHashable: Any]) {
        if let taskIdString = userInfo["taskId"] as? String,
           let taskId = UUID(uuidString: taskIdString) {
            // Would call DownloadManager.shared.resumeDownload(taskId: taskId)
            print("Resume download: \(taskId)")
        }
    }
    
    private func handleViewDetails(userInfo: [AnyHashable: Any]) {
        // Navigate to details view
        print("View details: \(userInfo)")
    }
}
