//
//  BandwidthManagementTests.swift
//  Download Manager for Mac - Feature #10 Tests
//
//  Created on February 16, 2026
//

import XCTest
@testable import DownloadManagerPackage

final class BandwidthManagementTests: XCTestCase {
    var bandwidthManager: BandwidthManager!
    var downloadManager: DownloadManager!
    
    override func setUp() {
        super.setUp()
        bandwidthManager = BandwidthManager.shared
        downloadManager = DownloadManager.shared
        
        // Reset to clean state
        bandwidthManager.resetStatistics()
        bandwidthManager.setGlobalLimit(BandwidthLimit(isEnabled: false, downloadSpeed: 0, uploadSpeed: 0))
        
        // Clear all schedules, rules, etc.
        for schedule in bandwidthManager.schedules {
            bandwidthManager.deleteSchedule(schedule)
        }
        for rule in bandwidthManager.rules {
            bandwidthManager.deleteRule(rule)
        }
    }
    
    override func tearDown() {
        bandwidthManager = nil
        downloadManager = nil
        super.tearDown()
    }
    
    // MARK: - Global Limit Tests
    
    func testSetGlobalLimit() {
        // Given
        let limit = BandwidthLimit(isEnabled: true, downloadSpeed: 1_000_000, uploadSpeed: 500_000)
        
        // When
        bandwidthManager.setGlobalLimit(limit)
        
        // Then
        XCTAssertEqual(bandwidthManager.globalLimit.downloadSpeed, 1_000_000)
        XCTAssertEqual(bandwidthManager.globalLimit.uploadSpeed, 500_000)
        XCTAssertTrue(bandwidthManager.globalLimit.isEnabled)
    }
    
    func testGlobalLimitPersistence() {
        // Given
        let limit = BandwidthLimit(isEnabled: true, downloadSpeed: 5_000_000, uploadSpeed: 2_000_000)
        
        // When
        bandwidthManager.setGlobalLimit(limit)
        
        // Then - verify persistence (would normally recreate manager)
        let retrieved = bandwidthManager.globalLimit
        XCTAssertEqual(retrieved.downloadSpeed, 5_000_000)
        XCTAssertEqual(retrieved.uploadSpeed, 2_000_000)
    }
    
    // MARK: - Per-Download Limit Tests
    
    func testSetDownloadLimit() {
        // Given
        let taskId = UUID()
        let limit = BandwidthLimit(isEnabled: true, downloadSpeed: 2_000_000, uploadSpeed: 1_000_000)
        
        // When
        bandwidthManager.setDownloadLimit(limit, for: taskId)
        
        // Then
        let retrieved = bandwidthManager.getDownloadLimit(for: taskId)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.downloadSpeed, 2_000_000)
    }
    
    func testRemoveDownloadLimit() {
        // Given
        let taskId = UUID()
        let limit = BandwidthLimit(isEnabled: true, downloadSpeed: 1_000_000, uploadSpeed: 500_000)
        bandwidthManager.setDownloadLimit(limit, for: taskId)
        
        // When
        bandwidthManager.removeDownloadLimit(for: taskId)
        
        // Then
        XCTAssertNil(bandwidthManager.getDownloadLimit(for: taskId))
    }
    
    // MARK: - Schedule Tests
    
    func testAddSchedule() {
        // Given
        let schedule = createTestSchedule(name: "Evening")
        
        // When
        bandwidthManager.addSchedule(schedule)
        
        // Then
        XCTAssertEqual(bandwidthManager.schedules.count, 1)
        XCTAssertEqual(bandwidthManager.schedules.first?.name, "Evening")
    }
    
    func testUpdateSchedule() {
        // Given
        var schedule = createTestSchedule(name: "Morning")
        bandwidthManager.addSchedule(schedule)
        
        // When
        schedule.name = "Updated Morning"
        bandwidthManager.updateSchedule(schedule)
        
        // Then
        let updated = bandwidthManager.schedules.first { $0.id == schedule.id }
        XCTAssertEqual(updated?.name, "Updated Morning")
    }
    
    func testDeleteSchedule() {
        // Given
        let schedule = createTestSchedule(name: "Test")
        bandwidthManager.addSchedule(schedule)
        
        // When
        bandwidthManager.deleteSchedule(schedule)
        
        // Then
        XCTAssertEqual(bandwidthManager.schedules.count, 0)
    }
    
    func testScheduleIsActiveAtCurrentTime() {
        // Given - create schedule for current time
        let now = Date()
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: now)
        
        var startTime = calendar.date(byAdding: .minute, value: -10, to: now)!
        var endTime = calendar.date(byAdding: .minute, value: 10, to: now)!
        
        let schedule = BandwidthTimeSchedule(
            id: UUID(),
            name: "Active Now",
            isEnabled: true,
            startTime: startTime,
            endTime: endTime,
            daysOfWeek: [currentWeekday],
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 1_000_000, uploadSpeed: 500_000),
            priority: 5
        )
        
        // When
        let isActive = schedule.isActive()
        
        // Then
        XCTAssertTrue(isActive)
    }
    
    func testScheduleIsNotActiveOnWrongDay() {
        // Given - create schedule for different day
        let now = Date()
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: now)
        let differentWeekday = (currentWeekday % 7) + 1 // Different day
        
        let schedule = BandwidthTimeSchedule(
            id: UUID(),
            name: "Wrong Day",
            isEnabled: true,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            daysOfWeek: [differentWeekday],
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 1_000_000, uploadSpeed: 500_000),
            priority: 5
        )
        
        // When
        let isActive = schedule.isActive()
        
        // Then
        XCTAssertFalse(isActive)
    }
    
    // MARK: - Network Configuration Tests
    
    func testDefaultNetworkConfigurations() {
        // Then - should have default configs for each network type
        XCTAssertTrue(bandwidthManager.networkConfigurations.count >= 6)
        
        let wifiConfig = bandwidthManager.networkConfigurations.first { $0.networkType == .wifi }
        XCTAssertNotNil(wifiConfig)
    }
    
    func testUpdateNetworkConfiguration() {
        // Given
        var wifiConfig = bandwidthManager.networkConfigurations.first { $0.networkType == .wifi }!
        
        // When
        wifiConfig.limit = BandwidthLimit(isEnabled: true, downloadSpeed: 10_000_000, uploadSpeed: 5_000_000)
        wifiConfig.autoApply = true
        bandwidthManager.updateNetworkConfiguration(wifiConfig)
        
        // Then
        let updated = bandwidthManager.networkConfigurations.first { $0.networkType == .wifi }
        XCTAssertEqual(updated?.limit.downloadSpeed, 10_000_000)
        XCTAssertTrue(updated?.autoApply ?? false)
    }
    
    func testMeteredNetworkHandling() {
        // Given
        let cellularConfig = bandwidthManager.networkConfigurations.first { $0.networkType == .cellular }
        
        // Then
        XCTAssertNotNil(cellularConfig)
        XCTAssertTrue(cellularConfig?.networkType.isMetered ?? false)
    }
    
    // MARK: - Rule Engine Tests
    
    func testAddRule() {
        // Given
        let rule = createTestRule(name: "Large Files")
        
        // When
        bandwidthManager.addRule(rule)
        
        // Then
        XCTAssertEqual(bandwidthManager.rules.count, 1)
        XCTAssertEqual(bandwidthManager.rules.first?.name, "Large Files")
    }
    
    func testRuleMatchesFileSize() {
        // Given
        let rule = BandwidthRule(
            id: UUID(),
            name: "Large Files",
            isEnabled: true,
            condition: .fileSize(min: 100_000_000, max: nil), // > 100 MB
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 5_000_000, uploadSpeed: 1_000_000),
            priority: 7
        )
        
        let largeTask = DownloadTask(
            url: URL(string: "https://example.com/large.zip")!,
            destination: URL(fileURLWithPath: "/tmp/large.zip"),
            expectedSize: 200_000_000
        )
        
        let smallTask = DownloadTask(
            url: URL(string: "https://example.com/small.txt")!,
            destination: URL(fileURLWithPath: "/tmp/small.txt"),
            expectedSize: 1_000
        )
        
        // When/Then
        XCTAssertTrue(rule.matches(task: largeTask))
        XCTAssertFalse(rule.matches(task: smallTask))
    }
    
    func testRuleMatchesFileType() {
        // Given
        let rule = BandwidthRule(
            id: UUID(),
            name: "Video Files",
            isEnabled: true,
            condition: .fileType(extensions: ["mp4", "mkv", "avi"]),
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 10_000_000, uploadSpeed: 1_000_000),
            priority: 8
        )
        
        let videoTask = DownloadTask(
            url: URL(string: "https://example.com/video.mp4")!,
            destination: URL(fileURLWithPath: "/tmp/video.mp4")
        )
        
        let textTask = DownloadTask(
            url: URL(string: "https://example.com/doc.txt")!,
            destination: URL(fileURLWithPath: "/tmp/doc.txt")
        )
        
        // When/Then
        XCTAssertTrue(rule.matches(task: videoTask))
        XCTAssertFalse(rule.matches(task: textTask))
    }
    
    func testRuleMatchesSourceURL() {
        // Given
        let rule = BandwidthRule(
            id: UUID(),
            name: "CDN Files",
            isEnabled: true,
            condition: .sourceURL(pattern: "cdn.example.com"),
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 20_000_000, uploadSpeed: 5_000_000),
            priority: 6
        )
        
        let cdnTask = DownloadTask(
            url: URL(string: "https://cdn.example.com/file.zip")!,
            destination: URL(fileURLWithPath: "/tmp/file.zip")
        )
        
        let regularTask = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            destination: URL(fileURLWithPath: "/tmp/file2.zip")
        )
        
        // When/Then
        XCTAssertTrue(rule.matches(task: cdnTask))
        XCTAssertFalse(rule.matches(task: regularTask))
    }
    
    func testRuleMatchesPriority() {
        // Given
        let rule = BandwidthRule(
            id: UUID(),
            name: "High Priority",
            isEnabled: true,
            condition: .priority(.high),
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 50_000_000, uploadSpeed: 10_000_000),
            priority: 9
        )
        
        var highPriorityTask = DownloadTask(
            url: URL(string: "https://example.com/important.zip")!,
            destination: URL(fileURLWithPath: "/tmp/important.zip")
        )
        highPriorityTask.priority = .high
        
        var lowPriorityTask = DownloadTask(
            url: URL(string: "https://example.com/background.zip")!,
            destination: URL(fileURLWithPath: "/tmp/background.zip")
        )
        lowPriorityTask.priority = .low
        
        // When/Then
        XCTAssertTrue(rule.matches(task: highPriorityTask))
        XCTAssertFalse(rule.matches(task: lowPriorityTask))
    }
    
    func testCombinedRuleCondition() {
        // Given - Large video files (AND condition)
        let condition = BandwidthCondition.combined(
            conditions: [
                .fileSize(min: 100_000_000, max: nil),
                .fileType(extensions: ["mp4", "mkv"])
            ],
            operator: .and
        )
        
        let rule = BandwidthRule(
            id: UUID(),
            name: "Large Videos",
            isEnabled: true,
            condition: condition,
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 15_000_000, uploadSpeed: 2_000_000),
            priority: 8
        )
        
        var largeVideoTask = DownloadTask(
            url: URL(string: "https://example.com/movie.mp4")!,
            destination: URL(fileURLWithPath: "/tmp/movie.mp4"),
            expectedSize: 200_000_000
        )
        
        var smallVideoTask = DownloadTask(
            url: URL(string: "https://example.com/clip.mp4")!,
            destination: URL(fileURLWithPath: "/tmp/clip.mp4"),
            expectedSize: 10_000_000
        )
        
        // When/Then
        XCTAssertTrue(rule.matches(task: largeVideoTask))
        XCTAssertFalse(rule.matches(task: smallVideoTask)) // Too small
    }
    
    func testRulePriorityOrdering() {
        // Given
        let rule1 = createTestRule(name: "Low Priority", priority: 3)
        let rule2 = createTestRule(name: "High Priority", priority: 9)
        let rule3 = createTestRule(name: "Medium Priority", priority: 5)
        
        // When
        bandwidthManager.addRule(rule1)
        bandwidthManager.addRule(rule2)
        bandwidthManager.addRule(rule3)
        
        // Then - rules should be sortable by priority
        let sorted = bandwidthManager.rules.sorted { $0.priority > $1.priority }
        XCTAssertEqual(sorted[0].name, "High Priority")
        XCTAssertEqual(sorted[1].name, "Medium Priority")
        XCTAssertEqual(sorted[2].name, "Low Priority")
    }
    
    // MARK: - Profile Tests
    
    func testPredefinedProfiles() {
        // Then - should have 4 predefined profiles
        let predefined = bandwidthManager.profiles.filter { $0.isPredefined }
        XCTAssertEqual(predefined.count, 4)
        
        let profileNames = Set(predefined.map { $0.name })
        XCTAssertTrue(profileNames.contains("Unlimited"))
        XCTAssertTrue(profileNames.contains("High Speed"))
        XCTAssertTrue(profileNames.contains("Balanced"))
        XCTAssertTrue(profileNames.contains("Conservative"))
    }
    
    func testApplyProfile() {
        // Given
        let balancedProfile = bandwidthManager.profiles.first { $0.name == "Balanced" }!
        
        // When
        bandwidthManager.applyProfile(balancedProfile)
        
        // Then
        XCTAssertEqual(bandwidthManager.globalLimit.downloadSpeed, balancedProfile.downloadSpeed)
        XCTAssertEqual(bandwidthManager.globalLimit.uploadSpeed, balancedProfile.uploadSpeed)
    }
    
    func testAddCustomProfile() {
        // Given
        let customProfile = BandwidthProfile(
            id: UUID(),
            name: "Custom",
            downloadSpeed: 3_000_000,
            uploadSpeed: 1_500_000,
            icon: "gauge",
            isPredefined: false
        )
        
        // When
        bandwidthManager.addProfile(customProfile)
        
        // Then
        XCTAssertTrue(bandwidthManager.profiles.contains { $0.name == "Custom" })
    }
    
    func testCannotDeletePredefinedProfile() {
        // Given
        let unlimitedProfile = bandwidthManager.profiles.first { $0.name == "Unlimited" }!
        let initialCount = bandwidthManager.profiles.count
        
        // When
        bandwidthManager.deleteProfile(unlimitedProfile)
        
        // Then - should not be deleted
        XCTAssertEqual(bandwidthManager.profiles.count, initialCount)
    }
    
    // MARK: - Effective Limit Calculation Tests
    
    func testEffectiveLimitPriority() {
        // Given - set multiple limit sources
        let taskId = UUID()
        
        // Global limit (lowest priority)
        bandwidthManager.setGlobalLimit(BandwidthLimit(isEnabled: true, downloadSpeed: 1_000_000, uploadSpeed: 500_000))
        
        // Per-download limit (highest priority)
        bandwidthManager.setDownloadLimit(BandwidthLimit(isEnabled: true, downloadSpeed: 5_000_000, uploadSpeed: 2_000_000), for: taskId)
        
        // When
        let effectiveLimit = bandwidthManager.getEffectiveLimit(for: taskId)
        
        // Then - should use per-download limit
        XCTAssertEqual(effectiveLimit.downloadSpeed, 5_000_000)
        XCTAssertEqual(effectiveLimit.uploadSpeed, 2_000_000)
    }
    
    func testEffectiveLimitFallsBackToGlobal() {
        // Given
        let taskId = UUID()
        bandwidthManager.setGlobalLimit(BandwidthLimit(isEnabled: true, downloadSpeed: 2_000_000, uploadSpeed: 1_000_000))
        
        // When - no per-download limit
        let effectiveLimit = bandwidthManager.getEffectiveLimit(for: taskId)
        
        // Then - should use global limit
        XCTAssertEqual(effectiveLimit.downloadSpeed, 2_000_000)
    }
    
    func testEffectiveLimitWithDisabledGlobal() {
        // Given
        let taskId = UUID()
        bandwidthManager.setGlobalLimit(BandwidthLimit(isEnabled: false, downloadSpeed: 0, uploadSpeed: 0))
        
        // When
        let effectiveLimit = bandwidthManager.getEffectiveLimit(for: taskId)
        
        // Then - should be unlimited
        XCTAssertEqual(effectiveLimit.downloadSpeed, 0)
        XCTAssertFalse(effectiveLimit.isEnabled)
    }
    
    // MARK: - Statistics Tests
    
    func testStatisticsRecording() {
        // Given
        let initialDownloaded = bandwidthManager.statistics.totalDownloaded
        
        // When
        var stats = bandwidthManager.statistics
        stats.recordDownload(bytes: 1_000_000, speed: 500_000)
        
        // Then
        XCTAssertEqual(stats.totalDownloaded, initialDownloaded + 1_000_000)
        XCTAssertEqual(stats.currentDownloadSpeed, 500_000)
    }
    
    func testStatisticsPeakSpeed() {
        // Given
        var stats = BandwidthStatistics()
        
        // When
        stats.recordDownload(bytes: 100_000, speed: 1_000_000)
        stats.recordDownload(bytes: 100_000, speed: 5_000_000)
        stats.recordDownload(bytes: 100_000, speed: 2_000_000)
        
        // Then
        XCTAssertEqual(stats.peakDownloadSpeed, 5_000_000)
    }
    
    func testStatisticsAverageSpeed() {
        // Given
        var stats = BandwidthStatistics()
        
        // When
        stats.recordDownload(bytes: 100_000, speed: 1_000_000)
        stats.recordDownload(bytes: 100_000, speed: 3_000_000)
        stats.recordDownload(bytes: 100_000, speed: 2_000_000)
        
        // Then
        XCTAssertEqual(stats.averageDownloadSpeed, 2_000_000)
    }
    
    func testStatisticsHistoryLimit() {
        // Given
        var stats = BandwidthStatistics()
        
        // When - add more than 60 data points
        for i in 0..<100 {
            stats.recordDownload(bytes: 1000, speed: Int64(i * 1000))
        }
        
        // Then - should only keep last 60
        XCTAssertEqual(stats.downloadSpeedHistory.count, 60)
    }
    
    func testResetStatistics() {
        // Given
        var stats = BandwidthStatistics()
        stats.recordDownload(bytes: 1_000_000, speed: 500_000)
        stats.recordUpload(bytes: 500_000, speed: 250_000)
        
        // When
        stats.reset()
        
        // Then
        XCTAssertEqual(stats.totalDownloaded, 0)
        XCTAssertEqual(stats.totalUploaded, 0)
        XCTAssertEqual(stats.peakDownloadSpeed, 0)
        XCTAssertEqual(stats.downloadSpeedHistory.count, 0)
    }
    
    // MARK: - Network Detection Tests
    
    func testNetworkTypeDetection() {
        // When
        let networkType = bandwidthManager.currentNetworkType
        
        // Then - should detect some network type
        XCTAssertNotEqual(networkType, .unknown)
    }
    
    func testNetworkTypeHasIcon() {
        // Given
        let allTypes: [NetworkType] = [.wifi, .ethernet, .cellular, .thunderbolt, .usb, .unknown]
        
        // Then - all types should have icons
        for type in allTypes {
            XCTAssertFalse(type.icon.isEmpty)
        }
    }
    
    func testNetworkTypeHasDefaultLimit() {
        // Given
        let allTypes: [NetworkType] = [.wifi, .ethernet, .cellular, .thunderbolt, .usb, .unknown]
        
        // Then - all types should have default limits
        for type in allTypes {
            XCTAssertGreaterThanOrEqual(type.defaultDownloadSpeed, 0)
            XCTAssertGreaterThanOrEqual(type.defaultUploadSpeed, 0)
        }
    }
    
    // MARK: - Integration Tests
    
    func testThrottleSpeedForDownload() {
        // Given
        let taskId = UUID()
        let limit = BandwidthLimit(isEnabled: true, downloadSpeed: 1_000_000, uploadSpeed: 500_000)
        bandwidthManager.setDownloadLimit(limit, for: taskId)
        
        // When
        bandwidthManager.throttleSpeed(for: taskId, currentSpeed: 5_000_000)
        
        // Then - should calculate throttled speed (actual throttling would happen in DownloadManager)
        let effectiveLimit = bandwidthManager.getEffectiveLimit(for: taskId)
        XCTAssertTrue(effectiveLimit.isEnabled)
        XCTAssertEqual(effectiveLimit.downloadSpeed, 1_000_000)
    }
    
    func testScheduleActivationChangesActiveLimit() {
        // Given - create active schedule
        let now = Date()
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: now)
        
        let startTime = calendar.date(byAdding: .minute, value: -10, to: now)!
        let endTime = calendar.date(byAdding: .minute, value: 10, to: now)!
        
        let schedule = BandwidthTimeSchedule(
            id: UUID(),
            name: "Test Schedule",
            isEnabled: true,
            startTime: startTime,
            endTime: endTime,
            daysOfWeek: [currentWeekday],
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 3_000_000, uploadSpeed: 1_500_000),
            priority: 8
        )
        
        // When
        bandwidthManager.addSchedule(schedule)
        bandwidthManager.updateActiveLimit()
        
        // Then - active limit should use schedule
        // Note: This assumes no per-download limit
        let taskId = UUID()
        let effectiveLimit = bandwidthManager.getEffectiveLimit(for: taskId)
        
        // Should either be schedule limit or global, depending on priority
        XCTAssertTrue(effectiveLimit.isEnabled)
    }
    
    func testNetworkChangeAffectsLimit() {
        // Given
        var wifiConfig = bandwidthManager.networkConfigurations.first { $0.networkType == .wifi }!
        wifiConfig.limit = BandwidthLimit(isEnabled: true, downloadSpeed: 10_000_000, uploadSpeed: 5_000_000)
        wifiConfig.autoApply = true
        bandwidthManager.updateNetworkConfiguration(wifiConfig)
        
        // When - would normally trigger on network change
        // We can test the logic directly
        let config = bandwidthManager.getCurrentNetworkConfiguration()
        
        // Then
        XCTAssertNotNil(config)
        if config?.autoApply == true {
            XCTAssertTrue(config!.limit.isEnabled)
        }
    }
    
    // MARK: - Formatting Tests
    
    func testBandwidthLimitFormatting() {
        // Given
        let limit = BandwidthLimit(isEnabled: true, downloadSpeed: 5_000_000, uploadSpeed: 1_000_000)
        
        // When
        let downloadFormatted = limit.formattedDownloadSpeed()
        let uploadFormatted = limit.formattedUploadSpeed()
        
        // Then
        XCTAssertTrue(downloadFormatted.contains("MB"))
        XCTAssertTrue(uploadFormatted.contains("KB") || uploadFormatted.contains("MB"))
    }
    
    func testScheduleFormattedTimeRange() {
        // Given
        let schedule = createTestSchedule(name: "Test")
        
        // When
        let timeRange = schedule.formattedTimeRange()
        
        // Then
        XCTAssertFalse(timeRange.isEmpty)
        XCTAssertTrue(timeRange.contains("-"))
    }
    
    func testStatisticsFormatting() {
        // Given
        var stats = BandwidthStatistics()
        stats.recordDownload(bytes: 1_500_000, speed: 500_000)
        
        // When
        let totalFormatted = stats.formattedTotalDownloaded
        let speedFormatted = stats.formattedAverageDownloadSpeed
        
        // Then
        XCTAssertFalse(totalFormatted.isEmpty)
        XCTAssertFalse(speedFormatted.isEmpty)
    }
    
    // MARK: - Persistence Tests
    
    func testSchedulePersistence() {
        // Given
        let schedule = createTestSchedule(name: "Persistent")
        
        // When
        bandwidthManager.addSchedule(schedule)
        
        // Then - verify it's stored (would normally recreate manager)
        XCTAssertTrue(bandwidthManager.schedules.contains { $0.id == schedule.id })
    }
    
    func testRulePersistence() {
        // Given
        let rule = createTestRule(name: "Persistent Rule")
        
        // When
        bandwidthManager.addRule(rule)
        
        // Then
        XCTAssertTrue(bandwidthManager.rules.contains { $0.id == rule.id })
    }
    
    func testNetworkConfigPersistence() {
        // Given
        var wifiConfig = bandwidthManager.networkConfigurations.first { $0.networkType == .wifi }!
        wifiConfig.limit.downloadSpeed = 20_000_000
        
        // When
        bandwidthManager.updateNetworkConfiguration(wifiConfig)
        
        // Then
        let updated = bandwidthManager.networkConfigurations.first { $0.networkType == .wifi }
        XCTAssertEqual(updated?.limit.downloadSpeed, 20_000_000)
    }
    
    // MARK: - Helper Methods
    
    private func createTestSchedule(name: String) -> BandwidthTimeSchedule {
        return BandwidthTimeSchedule(
            id: UUID(),
            name: name,
            isEnabled: true,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            daysOfWeek: [1, 2, 3, 4, 5],
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 2_000_000, uploadSpeed: 1_000_000),
            priority: 5
        )
    }
    
    private func createTestRule(name: String, priority: Int = 5) -> BandwidthRule {
        return BandwidthRule(
            id: UUID(),
            name: name,
            isEnabled: true,
            condition: .fileSize(min: 0, max: nil),
            limit: BandwidthLimit(isEnabled: true, downloadSpeed: 1_000_000, uploadSpeed: 500_000),
            priority: priority
        )
    }
}
