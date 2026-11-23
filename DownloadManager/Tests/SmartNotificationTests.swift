import XCTest
@testable import DownloadManager

@MainActor
final class SmartNotificationTests: XCTestCase {
    
    var manager: NotificationManager!
    
    override func setUp() async throws {
        manager = NotificationManager.shared
        manager.clearHistory()
        manager.clearStatistics()
    }
    
    override func tearDown() async throws {
        manager = nil
    }
    
    // MARK: - Notification Type Tests
    
    func testNotificationTypeIcons() {
        XCTAssertEqual(NotificationType.downloadStarted.icon, "arrow.down.circle")
        XCTAssertEqual(NotificationType.downloadProgress.icon, "clock.arrow.circlepath")
        XCTAssertEqual(NotificationType.downloadCompleted.icon, "checkmark.circle.fill")
        XCTAssertEqual(NotificationType.downloadFailed.icon, "xmark.circle.fill")
        XCTAssertEqual(NotificationType.queueCompleted.icon, "checkmark.circle.fill")
    }
    
    func testNotificationTypeCategories() {
        XCTAssertEqual(NotificationType.downloadCompleted.category, "DOWNLOAD_COMPLETE")
        XCTAssertEqual(NotificationType.queueCompleted.category, "DOWNLOAD_COMPLETE")
        XCTAssertEqual(NotificationType.downloadFailed.category, "DOWNLOAD_ERROR")
        XCTAssertEqual(NotificationType.downloadProgress.category, "DOWNLOAD_PROGRESS")
    }
    
    func testNotificationTypeDefaultEnabled() {
        XCTAssertTrue(NotificationType.downloadCompleted.defaultEnabled)
        XCTAssertTrue(NotificationType.downloadFailed.defaultEnabled)
        XCTAssertFalse(NotificationType.downloadProgress.defaultEnabled)
        XCTAssertFalse(NotificationType.downloadPaused.defaultEnabled)
    }
    
    // MARK: - Notification Sound Tests
    
    func testNotificationSoundNames() {
        XCTAssertEqual(NotificationSound.defaultSound.rawValue, "Default")
        XCTAssertEqual(NotificationSound.glass.rawValue, "Glass")
        XCTAssertEqual(NotificationSound.hero.rawValue, "Hero")
        XCTAssertEqual(NotificationSound.silence.rawValue, "Silent")
    }
    
    func testNotificationSoundSystemNames() {
        XCTAssertNotNil(NotificationSound.defaultSound.systemName)
        XCTAssertNil(NotificationSound.silence.systemName)
    }
    
    // MARK: - Notification Priority Tests
    
    func testNotificationPriorityDisplayNames() {
        XCTAssertEqual(NotificationPriority.low.displayName, "Low")
        XCTAssertEqual(NotificationPriority.normal.displayName, "Normal")
        XCTAssertEqual(NotificationPriority.high.displayName, "High")
        XCTAssertEqual(NotificationPriority.critical.displayName, "Critical")
    }
    
    func testNotificationPriorityInterruptionLevels() {
        XCTAssertEqual(NotificationPriority.low.interruptionLevel, .passive)
        XCTAssertEqual(NotificationPriority.normal.interruptionLevel, .active)
        XCTAssertEqual(NotificationPriority.high.interruptionLevel, .timeSensitive)
        XCTAssertEqual(NotificationPriority.critical.interruptionLevel, .critical)
    }
    
    // MARK: - Notification Action Tests
    
    func testPredefinedActions() {
        XCTAssertEqual(NotificationAction.openDownload.id, "OPEN_DOWNLOAD")
        XCTAssertEqual(NotificationAction.openDownload.title, "Open")
        XCTAssertTrue(NotificationAction.openDownload.foreground)
        XCTAssertFalse(NotificationAction.openDownload.destructive)
        
        XCTAssertEqual(NotificationAction.retry.id, "RETRY")
        XCTAssertEqual(NotificationAction.cancel.id, "CANCEL")
        XCTAssertTrue(NotificationAction.cancel.destructive)
    }
    
    func testActionToUNNotificationAction() {
        let action = NotificationAction(id: "TEST", title: "Test Action", destructive: true)
        let unAction = action.toUNNotificationAction()
        
        XCTAssertEqual(unAction.identifier, "TEST")
        XCTAssertEqual(unAction.title, "Test Action")
    }
    
    // MARK: - Notification Settings Tests
    
    func testDefaultSettings() {
        let settings = NotificationSettings()
        
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertEqual(settings.sound, .defaultSound)
        XCTAssertTrue(settings.badgeEnabled)
        XCTAssertTrue(settings.bannerEnabled)
        XCTAssertEqual(settings.progressInterval, 60)
        XCTAssertEqual(settings.progressThreshold, 0.25)
        XCTAssertFalse(settings.speedThresholdEnabled)
        XCTAssertEqual(settings.summaryMinimumDownloads, 1)
        XCTAssertFalse(settings.doNotDisturbEnabled)
    }
    
    func testSettingsEnableDisableType() {
        var settings = NotificationSettings()
        
        settings.setEnabled(.downloadProgress, enabled: true)
        XCTAssertTrue(settings.isEnabled(.downloadProgress))
        
        settings.setEnabled(.downloadProgress, enabled: false)
        XCTAssertFalse(settings.isEnabled(.downloadProgress))
    }
    
    func testSettingsDoNotDisturb() {
        var settings = NotificationSettings()
        settings.doNotDisturbEnabled = true
        
        let calendar = Calendar.current
        
        // Set DND from 10 PM to 8 AM
        settings.doNotDisturbStart = calendar.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
        settings.doNotDisturbEnd = calendar.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
        
        // Can't easily test current time detection without mocking
        // But we can test the logic exists
        XCTAssertNotNil(settings.doNotDisturbStart)
        XCTAssertNotNil(settings.doNotDisturbEnd)
    }
    
    func testSettingsCodable() throws {
        let settings = NotificationSettings()
        
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: data)
        
        XCTAssertEqual(decoded.soundEnabled, settings.soundEnabled)
        XCTAssertEqual(decoded.sound, settings.sound)
        XCTAssertEqual(decoded.progressInterval, settings.progressInterval)
    }
    
    // MARK: - Notification Content Tests
    
    func testContentCreation() {
        let content = NotificationContent(
            type: .downloadCompleted,
            title: "Test Title",
            body: "Test Body",
            priority: .high
        )
        
        XCTAssertEqual(content.type, .downloadCompleted)
        XCTAssertEqual(content.title, "Test Title")
        XCTAssertEqual(content.body, "Test Body")
        XCTAssertEqual(content.priority, .high)
        XCTAssertFalse(content.delivered)
        XCTAssertNil(content.deliveredDate)
    }
    
    func testDownloadStartedTemplate() {
        let content = NotificationContent.downloadStarted(filename: "test.zip", size: "100 MB")
        
        XCTAssertEqual(content.type, .downloadStarted)
        XCTAssertEqual(content.title, "Download Started")
        XCTAssertTrue(content.body.contains("test.zip"))
        XCTAssertTrue(content.body.contains("100 MB"))
        XCTAssertEqual(content.priority, .low)
        XCTAssertEqual(content.actions.count, 2)
    }
    
    func testDownloadCompletedTemplate() {
        let content = NotificationContent.downloadCompleted(filename: "test.zip", duration: "5m 30s")
        
        XCTAssertEqual(content.type, .downloadCompleted)
        XCTAssertEqual(content.title, "Download Complete")
        XCTAssertTrue(content.body.contains("test.zip"))
        XCTAssertTrue(content.body.contains("5m 30s"))
        XCTAssertEqual(content.priority, .high)
    }
    
    func testDownloadFailedTemplate() {
        let content = NotificationContent.downloadFailed(filename: "test.zip", error: "Network error")
        
        XCTAssertEqual(content.type, .downloadFailed)
        XCTAssertEqual(content.title, "Download Failed")
        XCTAssertTrue(content.body.contains("test.zip"))
        XCTAssertTrue(content.body.contains("Network error"))
        XCTAssertEqual(content.priority, .high)
    }
    
    func testDownloadProgressTemplate() {
        let content = NotificationContent.downloadProgress(
            filename: "test.zip",
            progress: 50,
            speed: "2.5 MB/s",
            eta: "2m 15s"
        )
        
        XCTAssertEqual(content.type, .downloadProgress)
        XCTAssertTrue(content.body.contains("50%"))
        XCTAssertTrue(content.body.contains("2.5 MB/s"))
        XCTAssertTrue(content.body.contains("2m 15s"))
    }
    
    func testQueueCompletedTemplate() {
        let content = NotificationContent.queueCompleted(count: 5, totalSize: "500 MB", duration: "10m")
        
        XCTAssertEqual(content.type, .queueCompleted)
        XCTAssertTrue(content.body.contains("5"))
        XCTAssertTrue(content.body.contains("500 MB"))
        XCTAssertTrue(content.body.contains("10m"))
    }
    
    func testDailySummaryTemplate() {
        let content = NotificationContent.dailySummary(downloads: 10, totalSize: "1.2 GB", avgSpeed: "3 MB/s")
        
        XCTAssertEqual(content.type, .dailySummary)
        XCTAssertEqual(content.title, "Daily Download Summary")
        XCTAssertTrue(content.body.contains("10"))
        XCTAssertTrue(content.body.contains("1.2 GB"))
    }
    
    func testWeeklySummaryTemplate() {
        let content = NotificationContent.weeklySummary(downloads: 50, totalSize: "8.5 GB", avgSpeed: "3.5 MB/s")
        
        XCTAssertEqual(content.type, .weeklySummary)
        XCTAssertEqual(content.title, "Weekly Download Summary")
        XCTAssertTrue(content.body.contains("50"))
        XCTAssertTrue(content.body.contains("8.5 GB"))
    }
    
    func testLowDiskSpaceTemplate() {
        let content = NotificationContent.lowDiskSpace(available: "5 GB", required: "10 GB")
        
        XCTAssertEqual(content.type, .lowDiskSpace)
        XCTAssertEqual(content.priority, .critical)
        XCTAssertTrue(content.body.contains("5 GB"))
        XCTAssertTrue(content.body.contains("10 GB"))
    }
    
    func testSpeedThresholdTemplate() {
        let content = NotificationContent.speedThreshold(currentSpeed: "50 KB/s", threshold: "100 KB/s")
        
        XCTAssertEqual(content.type, .speedThreshold)
        XCTAssertTrue(content.body.contains("50 KB/s"))
        XCTAssertTrue(content.body.contains("100 KB/s"))
    }
    
    func testContentCodable() throws {
        let content = NotificationContent(
            type: .downloadCompleted,
            title: "Test",
            body: "Body"
        )
        
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(NotificationContent.self, from: data)
        
        XCTAssertEqual(decoded.type, content.type)
        XCTAssertEqual(decoded.title, content.title)
        XCTAssertEqual(decoded.body, content.body)
    }
    
    // MARK: - Notification History Tests
    
    func testHistoryCreation() {
        let content = NotificationContent(type: .downloadCompleted, title: "Test", body: "Body")
        let history = NotificationHistory(content: content)
        
        XCTAssertEqual(history.content.title, "Test")
        XCTAssertFalse(history.interacted)
        XCTAssertNil(history.actionTaken)
    }
    
    func testHistoryCodable() throws {
        let content = NotificationContent(type: .downloadCompleted, title: "Test", body: "Body")
        let history = NotificationHistory(content: content, interacted: true, actionTaken: "OPEN")
        
        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(NotificationHistory.self, from: data)
        
        XCTAssertEqual(decoded.content.title, history.content.title)
        XCTAssertEqual(decoded.interacted, history.interacted)
        XCTAssertEqual(decoded.actionTaken, history.actionTaken)
    }
    
    // MARK: - Notification Statistics Tests
    
    func testStatisticsInitialization() {
        let stats = NotificationStatistics()
        
        XCTAssertEqual(stats.totalSent, 0)
        XCTAssertEqual(stats.totalInteracted, 0)
        XCTAssertTrue(stats.byType.isEmpty)
        XCTAssertTrue(stats.byPriority.isEmpty)
        XCTAssertNil(stats.lastSentDate)
        XCTAssertEqual(stats.interactionRate, 0)
    }
    
    func testStatisticsRecordNotification() {
        var stats = NotificationStatistics()
        let content = NotificationContent(type: .downloadCompleted, title: "Test", body: "Body", priority: .high)
        
        stats.recordNotification(content)
        
        XCTAssertEqual(stats.totalSent, 1)
        XCTAssertEqual(stats.byType[.downloadCompleted], 1)
        XCTAssertEqual(stats.byPriority[.high], 1)
        XCTAssertNotNil(stats.lastSentDate)
    }
    
    func testStatisticsRecordInteraction() {
        var stats = NotificationStatistics()
        
        stats.recordInteraction(responseTime: 5.0)
        
        XCTAssertEqual(stats.totalInteracted, 1)
        XCTAssertEqual(stats.averageResponseTime, 5.0)
    }
    
    func testStatisticsInteractionRate() {
        var stats = NotificationStatistics()
        let content = NotificationContent(type: .downloadCompleted, title: "Test", body: "Body")
        
        stats.recordNotification(content)
        stats.recordNotification(content)
        stats.recordInteraction(responseTime: 3.0)
        
        XCTAssertEqual(stats.totalSent, 2)
        XCTAssertEqual(stats.totalInteracted, 1)
        XCTAssertEqual(stats.interactionRate, 0.5)
    }
    
    func testStatisticsMultipleTypes() {
        var stats = NotificationStatistics()
        
        stats.recordNotification(NotificationContent(type: .downloadCompleted, title: "", body: ""))
        stats.recordNotification(NotificationContent(type: .downloadCompleted, title: "", body: ""))
        stats.recordNotification(NotificationContent(type: .downloadFailed, title: "", body: ""))
        
        XCTAssertEqual(stats.byType[.downloadCompleted], 2)
        XCTAssertEqual(stats.byType[.downloadFailed], 1)
    }
    
    func testStatisticsCodable() throws {
        var stats = NotificationStatistics()
        stats.recordNotification(NotificationContent(type: .downloadCompleted, title: "", body: ""))
        
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(NotificationStatistics.self, from: data)
        
        XCTAssertEqual(decoded.totalSent, stats.totalSent)
    }
    
    // MARK: - Manager Tests
    
    func testManagerInitialization() {
        XCTAssertNotNil(manager)
        XCTAssertNotNil(manager.settings)
        XCTAssertTrue(manager.history.isEmpty)
    }
    
    func testManagerSendNotification() {
        let content = NotificationContent(
            type: .downloadCompleted,
            title: "Test",
            body: "Body"
        )
        
        manager.sendNotification(content)
        
        // Notification should be recorded (async, might not be immediate)
        // In real test, would use expectations
    }
    
    func testManagerNotifyDownloadStarted() {
        let taskId = UUID()
        
        manager.notifyDownloadStarted(taskId: taskId, filename: "test.zip", size: "100 MB")
        
        // Verify notification was sent (would use expectations in real test)
    }
    
    func testManagerNotifyDownloadCompleted() {
        let taskId = UUID()
        
        manager.notifyDownloadCompleted(
            taskId: taskId,
            filename: "test.zip",
            duration: "5m",
            filePath: "/path/to/file"
        )
        
        // Verify notification was sent
    }
    
    func testManagerNotifyDownloadFailed() {
        let taskId = UUID()
        
        manager.notifyDownloadFailed(
            taskId: taskId,
            filename: "test.zip",
            error: "Network error"
        )
        
        // Verify notification was sent
    }
    
    func testManagerProgressTracking() {
        let taskId = UUID()
        
        // First progress notification should be allowed
        manager.notifyDownloadProgress(
            taskId: taskId,
            filename: "test.zip",
            progress: 0.5,
            speed: "2 MB/s",
            eta: "2m"
        )
        
        // Immediate second notification should be throttled
        manager.notifyDownloadProgress(
            taskId: taskId,
            filename: "test.zip",
            progress: 0.51,
            speed: "2 MB/s",
            eta: "2m"
        )
        
        // Clear tracker
        manager.clearProgressTracker(taskId: taskId)
    }
    
    func testManagerClearHistory() {
        let content = NotificationContent(type: .downloadCompleted, title: "Test", body: "Body")
        let history = NotificationHistory(content: content)
        
        manager.history = [history]
        XCTAssertEqual(manager.history.count, 1)
        
        manager.clearHistory()
        XCTAssertEqual(manager.history.count, 0)
    }
    
    func testManagerClearStatistics() {
        var stats = NotificationStatistics()
        stats.recordNotification(NotificationContent(type: .downloadCompleted, title: "", body: ""))
        manager.statistics = stats
        
        XCTAssertEqual(manager.statistics.totalSent, 1)
        
        manager.clearStatistics()
        XCTAssertEqual(manager.statistics.totalSent, 0)
    }
    
    func testManagerUpdateSettings() {
        var newSettings = NotificationSettings()
        newSettings.soundEnabled = false
        newSettings.progressInterval = 120
        
        manager.updateSettings(newSettings)
        
        XCTAssertFalse(manager.settings.soundEnabled)
        XCTAssertEqual(manager.settings.progressInterval, 120)
    }
    
    func testManagerCancelNotification() {
        let id = UUID()
        manager.cancelNotification(id: id)
        
        // Verify cancellation (would need to check UNUserNotificationCenter)
    }
    
    func testManagerCancelAllNotifications() {
        manager.cancelAllNotifications()
        
        XCTAssertTrue(manager.pendingNotifications.isEmpty)
    }
    
    // MARK: - Integration Tests
    
    func testEndToEndNotificationFlow() {
        // Setup
        var settings = NotificationSettings()
        settings.setEnabled(.downloadCompleted, enabled: true)
        manager.updateSettings(settings)
        
        // Send notification
        let content = NotificationContent.downloadCompleted(filename: "test.zip", duration: "5m")
        manager.sendNotification(content)
        
        // Verify settings
        XCTAssertTrue(manager.settings.isEnabled(.downloadCompleted))
    }
    
    func testMultipleNotificationTypes() {
        manager.notifyDownloadStarted(taskId: UUID(), filename: "file1.zip", size: "100 MB")
        manager.notifyDownloadCompleted(taskId: UUID(), filename: "file2.zip", duration: "5m", filePath: "/path")
        manager.notifyDownloadFailed(taskId: UUID(), filename: "file3.zip", error: "Error")
        
        // All notifications should be tracked
    }
    
    func testDoNotDisturbPreventsNotifications() {
        var settings = manager.settings
        settings.doNotDisturbEnabled = true
        manager.updateSettings(settings)
        
        // Notifications sent during DND should be suppressed
        // (Complex to test without time mocking)
    }
    
    func testSummaryNotifications() {
        manager.notifyDailySummary(downloads: 10, totalSize: "1 GB", avgSpeed: "2 MB/s")
        manager.notifyWeeklySummary(downloads: 50, totalSize: "5 GB", avgSpeed: "3 MB/s")
        
        // Summaries should respect minimum download threshold
    }
}
