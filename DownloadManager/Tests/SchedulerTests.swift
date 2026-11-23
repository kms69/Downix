//
//  SchedulerTests.swift
//  Download Manager for Mac - Feature #3: Scheduler Tests
//
//  Created on February 15, 2026
//

import XCTest
@testable import DownloadManager

/// Test suite for Download Scheduler (Feature #3)
final class SchedulerTests: XCTestCase {
    
    var scheduler: DownloadScheduler!
    var manager: DownloadManager!
    
    override func setUp() {
        super.setUp()
        scheduler = DownloadScheduler.shared
        manager = DownloadManager.shared
        
        // Clear any existing schedules
        scheduler.scheduledTasks.removeAll()
        scheduler.bandwidthSchedules.removeAll()
    }
    
    override func tearDown() {
        scheduler.scheduledTasks.removeAll()
        scheduler.bandwidthSchedules.removeAll()
        scheduler.stop()
        super.tearDown()
    }
    
    // MARK: - Schedule Creation Tests
    
    func testScheduleCreationImmediate() {
        var schedule = DownloadSchedule(type: .immediate)
        XCTAssertEqual(schedule.type, .immediate)
        XCTAssertNotNil(schedule.scheduledDate)
        XCTAssertTrue(schedule.isEnabled)
    }
    
    func testScheduleCreationOnce() {
        var schedule = DownloadSchedule(type: .once)
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        schedule.scheduledDate = futureDate
        schedule.calculateNextRun()
        
        XCTAssertEqual(schedule.type, .once)
        XCTAssertEqual(schedule.nextRun, futureDate)
    }
    
    func testScheduleCreationDaily() {
        var schedule = DownloadSchedule(type: .daily)
        schedule.startTime = Date()
        schedule.calculateNextRun()
        
        XCTAssertEqual(schedule.type, .daily)
        XCTAssertNotNil(schedule.nextRun)
    }
    
    func testScheduleCreationWeekly() {
        var schedule = DownloadSchedule(type: .weekly)
        schedule.startTime = Date()
        schedule.weekdays = [.monday, .wednesday, .friday]
        schedule.calculateNextRun()
        
        XCTAssertEqual(schedule.type, .weekly)
        XCTAssertNotNil(schedule.nextRun)
        XCTAssertEqual(schedule.weekdays?.count, 3)
    }
    
    func testScheduleCreationMonthly() {
        var schedule = DownloadSchedule(type: .monthly)
        schedule.startTime = Date()
        schedule.dayOfMonth = 15
        schedule.calculateNextRun()
        
        XCTAssertEqual(schedule.type, .monthly)
        XCTAssertEqual(schedule.dayOfMonth, 15)
        XCTAssertNotNil(schedule.nextRun)
    }
    
    // MARK: - Next Run Calculation Tests
    
    func testNextRunImmediateSchedule() {
        var schedule = DownloadSchedule(type: .immediate)
        schedule.calculateNextRun()
        
        XCTAssertNotNil(schedule.nextRun)
        let diff = schedule.nextRun!.timeIntervalSince(Date())
        XCTAssertLessThan(abs(diff), 2) // Within 2 seconds of now
    }
    
    func testNextRunOnceSchedulePast() {
        var schedule = DownloadSchedule(type: .once)
        schedule.scheduledDate = Date().addingTimeInterval(-3600) // 1 hour ago
        schedule.calculateNextRun()
        
        XCTAssertNil(schedule.nextRun) // Past dates shouldn't have next run
    }
    
    func testNextRunOnceFuture() {
        var schedule = DownloadSchedule(type: .once)
        let futureDate = Date().addingTimeInterval(3600)
        schedule.scheduledDate = futureDate
        schedule.calculateNextRun()
        
        XCTAssertNotNil(schedule.nextRun)
        XCTAssertEqual(schedule.nextRun, futureDate)
    }
    
    func testNextRunDailySchedule() {
        var schedule = DownloadSchedule(type: .daily)
        
        // Set time to 2 PM today
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14
        components.minute = 0
        schedule.startTime = Calendar.current.date(from: components)!
        
        schedule.calculateNextRun()
        
        XCTAssertNotNil(schedule.nextRun)
        
        // Should be within next 24 hours
        let diff = schedule.nextRun!.timeIntervalSince(Date())
        XCTAssertGreaterThan(diff, 0)
        XCTAssertLessThan(diff, 86400) // Less than 24 hours
    }
    
    func testNextRunWeeklySchedule() {
        var schedule = DownloadSchedule(type: .weekly)
        schedule.startTime = Date()
        schedule.weekdays = [.monday]
        schedule.calculateNextRun()
        
        XCTAssertNotNil(schedule.nextRun)
        
        // Verify it's a Monday
        let weekday = Calendar.current.component(.weekday, from: schedule.nextRun!)
        XCTAssertEqual(weekday, 2) // Monday = 2 in Calendar.weekday
    }
    
    func testNextRunMonthlySchedule() {
        var schedule = DownloadSchedule(type: .monthly)
        schedule.startTime = Date()
        schedule.dayOfMonth = 15
        schedule.calculateNextRun()
        
        XCTAssertNotNil(schedule.nextRun)
        
        // Verify it's the 15th
        let day = Calendar.current.component(.day, from: schedule.nextRun!)
        XCTAssertEqual(day, 15)
    }
    
    // MARK: - Schedule Description Tests
    
    func testScheduleDescriptionImmediate() {
        let schedule = DownloadSchedule(type: .immediate)
        XCTAssertTrue(schedule.description.contains("immediately"))
    }
    
    func testScheduleDescriptionDaily() {
        var schedule = DownloadSchedule(type: .daily)
        schedule.startTime = Date()
        XCTAssertTrue(schedule.description.contains("daily"))
    }
    
    func testScheduleDescriptionWeekly() {
        var schedule = DownloadSchedule(type: .weekly)
        schedule.startTime = Date()
        schedule.weekdays = [.monday, .friday]
        let desc = schedule.description.lowercased()
        XCTAssertTrue(desc.contains("weekly") || desc.contains("mon") || desc.contains("fri"))
    }
    
    // MARK: - Bandwidth Schedule Tests
    
    func testBandwidthScheduleCreation() {
        let start = Date()
        let end = Date().addingTimeInterval(3600)
        let schedule = BandwidthSchedule(
            name: "Night Limit",
            startTime: start,
            endTime: end,
            bandwidthLimit: 1024 * 1024, // 1 MB/s
            weekdays: Set(Weekday.allCases)
        )
        
        XCTAssertEqual(schedule.name, "Night Limit")
        XCTAssertEqual(schedule.bandwidthLimit, 1024 * 1024)
        XCTAssertEqual(schedule.weekdays.count, 7)
        XCTAssertTrue(schedule.isEnabled)
    }
    
    func testBandwidthScheduleActive() {
        // Create schedule for current time
        let now = Date()
        let start = now.addingTimeInterval(-1800) // 30 min ago
        let end = now.addingTimeInterval(1800) // 30 min from now
        
        let schedule = BandwidthSchedule(
            name: "Test",
            startTime: start,
            endTime: end,
            bandwidthLimit: 512 * 1024
        )
        
        XCTAssertTrue(schedule.isActive())
    }
    
    func testBandwidthScheduleInactive() {
        // Create schedule for past time
        let now = Date()
        let start = now.addingTimeInterval(-7200) // 2 hours ago
        let end = now.addingTimeInterval(-3600) // 1 hour ago
        
        let schedule = BandwidthSchedule(
            name: "Test",
            startTime: start,
            endTime: end,
            bandwidthLimit: 512 * 1024
        )
        
        XCTAssertFalse(schedule.isActive())
    }
    
    func testBandwidthScheduleDisabled() {
        let now = Date()
        var schedule = BandwidthSchedule(
            name: "Test",
            startTime: now.addingTimeInterval(-1800),
            endTime: now.addingTimeInterval(1800),
            bandwidthLimit: 512 * 1024
        )
        
        schedule.isEnabled = false
        XCTAssertFalse(schedule.isActive())
    }
    
    func testBandwidthFormattedString() {
        let schedule = BandwidthSchedule(
            name: "Test",
            startTime: Date(),
            endTime: Date(),
            bandwidthLimit: 1024 * 1024
        )
        
        let formatted = schedule.formattedBandwidth
        XCTAssertTrue(formatted.contains("MB") || formatted.contains("1"))
    }
    
    // MARK: - Scheduler Integration Tests
    
    func testAddScheduledDownload() {
        let url = URL(string: "https://example.com/file.zip")!
        var schedule = DownloadSchedule(type: .once)
        schedule.scheduledDate = Date().addingTimeInterval(3600)
        schedule.calculateNextRun()
        
        let task = manager.addScheduledDownload(url: url, schedule: schedule)
        
        XCTAssertNotNil(task.schedule)
        XCTAssertEqual(task.schedule?.type, .once)
        XCTAssertTrue(scheduler.scheduledTasks.contains { $0.id == task.id })
    }
    
    func testScheduleForTonight() {
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.scheduleForTonight(url: url, hour: 23)
        
        XCTAssertNotNil(task.schedule)
        
        if let nextRun = task.schedule?.nextRun {
            let hour = Calendar.current.component(.hour, from: nextRun)
            XCTAssertEqual(hour, 23)
        }
    }
    
    func testScheduleForTomorrow() {
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.scheduleForTomorrow(url: url, hour: 2)
        
        XCTAssertNotNil(task.schedule)
        
        if let nextRun = task.schedule?.nextRun {
            let hour = Calendar.current.component(.hour, from: nextRun)
            XCTAssertEqual(hour, 2)
            
            // Should be tomorrow
            let daysDiff = Calendar.current.dateComponents([.day], from: Date(), to: nextRun).day ?? 0
            XCTAssertGreaterThanOrEqual(daysDiff, 1)
        }
    }
    
    func testScheduleDailyDownload() {
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.scheduleDailyDownload(url: url, hour: 10, minute: 30)
        
        XCTAssertNotNil(task.schedule)
        XCTAssertEqual(task.schedule?.type, .daily)
        
        if let nextRun = task.schedule?.nextRun {
            let components = Calendar.current.dateComponents([.hour, .minute], from: nextRun)
            XCTAssertEqual(components.hour, 10)
            XCTAssertEqual(components.minute, 30)
        }
    }
    
    func testAddBandwidthSchedule() {
        let schedule = BandwidthSchedule(
            name: "Work Hours",
            startTime: Date(),
            endTime: Date().addingTimeInterval(28800), // 8 hours
            bandwidthLimit: 500 * 1024 // 500 KB/s
        )
        
        scheduler.addBandwidthSchedule(schedule)
        
        XCTAssertEqual(scheduler.bandwidthSchedules.count, 1)
        XCTAssertEqual(scheduler.bandwidthSchedules.first?.name, "Work Hours")
    }
    
    func testRemoveBandwidthSchedule() {
        let schedule = BandwidthSchedule(
            name: "Test",
            startTime: Date(),
            endTime: Date(),
            bandwidthLimit: 1024
        )
        
        scheduler.addBandwidthSchedule(schedule)
        XCTAssertEqual(scheduler.bandwidthSchedules.count, 1)
        
        scheduler.removeBandwidthSchedule(schedule)
        XCTAssertEqual(scheduler.bandwidthSchedules.count, 0)
    }
    
    func testCurrentBandwidthLimit() {
        // Add an active bandwidth schedule
        let now = Date()
        let schedule = BandwidthSchedule(
            name: "Active Limit",
            startTime: now.addingTimeInterval(-1800),
            endTime: now.addingTimeInterval(1800),
            bandwidthLimit: 2 * 1024 * 1024 // 2 MB/s
        )
        
        scheduler.addBandwidthSchedule(schedule)
        
        let limit = scheduler.currentBandwidthLimit
        XCTAssertNotNil(limit)
        XCTAssertEqual(limit, 2 * 1024 * 1024)
    }
    
    func testNoCurrentBandwidthLimit() {
        // No active schedules
        let limit = scheduler.currentBandwidthLimit
        XCTAssertNil(limit)
    }
    
    // MARK: - Scheduler Engine Tests
    
    func testSchedulerStartStop() {
        scheduler.start()
        // Scheduler should be running
        // Note: Can't directly test timer state, but can verify it doesn't crash
        
        scheduler.stop()
        // Should stop gracefully
    }
    
    func testSetScheduleEnabled() {
        let url = URL(string: "https://example.com/test.zip")!
        var schedule = DownloadSchedule(type: .daily)
        schedule.startTime = Date()
        schedule.calculateNextRun()
        
        let task = manager.addScheduledDownload(url: url, schedule: schedule)
        
        XCTAssertTrue(task.schedule?.isEnabled ?? false)
        
        scheduler.setScheduleEnabled(false, for: task)
        XCTAssertFalse(task.schedule?.isEnabled ?? true)
        
        scheduler.setScheduleEnabled(true, for: task)
        XCTAssertTrue(task.schedule?.isEnabled ?? false)
    }
    
    func testRemoveScheduledDownload() {
        let url = URL(string: "https://example.com/test.zip")!
        let schedule = DownloadSchedule(type: .once)
        let task = manager.addScheduledDownload(url: url, schedule: schedule)
        
        XCTAssertTrue(scheduler.scheduledTasks.contains { $0.id == task.id })
        
        scheduler.removeScheduledDownload(task)
        XCTAssertFalse(scheduler.scheduledTasks.contains { $0.id == task.id })
    }
    
    func testUpcomingTasks() {
        // Add immediate schedule
        let url1 = URL(string: "https://example.com/file1.zip")!
        let schedule1 = DownloadSchedule(type: .immediate)
        _ = manager.addScheduledDownload(url: url1, schedule: schedule1)
        
        // Add future schedule
        let url2 = URL(string: "https://example.com/file2.zip")!
        var schedule2 = DownloadSchedule(type: .once)
        schedule2.scheduledDate = Date().addingTimeInterval(7200)
        schedule2.calculateNextRun()
        _ = manager.addScheduledDownload(url: url2, schedule: schedule2)
        
        let within2Hours = scheduler.upcomingTasks(within: 7200)
        XCTAssertEqual(within2Hours.count, 2)
        
        let within1Hour = scheduler.upcomingTasks(within: 3600)
        XCTAssertEqual(within1Hour.count, 1)
    }
    
    // MARK: - Post-Download Action Tests
    
    func testPostDownloadActionIcons() {
        XCTAssertEqual(PostDownloadAction.none.icon, "minus.circle")
        XCTAssertEqual(PostDownloadAction.shutdown.icon, "power")
        XCTAssertEqual(PostDownloadAction.sleep.icon, "moon.fill")
        XCTAssertEqual(PostDownloadAction.hibernate.icon, "moon.zzz.fill")
        XCTAssertEqual(PostDownloadAction.closeApp.icon, "xmark.app")
        XCTAssertEqual(PostDownloadAction.runScript.icon, "terminal")
    }
    
    func testScheduleWithPostDownloadAction() {
        var schedule = DownloadSchedule(type: .once)
        schedule.actionAfterCompletion = .shutdown
        schedule.stopAfterCompletion = true
        
        XCTAssertEqual(schedule.actionAfterCompletion, .shutdown)
        XCTAssertTrue(schedule.stopAfterCompletion)
    }
    
    // MARK: - Weekday Tests
    
    func testWeekdayNames() {
        XCTAssertEqual(Weekday.monday.shortName, "Mon")
        XCTAssertEqual(Weekday.tuesday.shortName, "Tue")
        XCTAssertEqual(Weekday.wednesday.shortName, "Wed")
        XCTAssertEqual(Weekday.thursday.shortName, "Thu")
        XCTAssertEqual(Weekday.friday.shortName, "Fri")
        XCTAssertEqual(Weekday.saturday.shortName, "Sat")
        XCTAssertEqual(Weekday.sunday.shortName, "Sun")
    }
    
    func testWeekdayFullNames() {
        XCTAssertEqual(Weekday.monday.fullName, "Monday")
        XCTAssertEqual(Weekday.friday.fullName, "Friday")
        XCTAssertEqual(Weekday.sunday.fullName, "Sunday")
    }
    
    func testWeekdayRawValues() {
        XCTAssertEqual(Weekday.sunday.rawValue, 1)
        XCTAssertEqual(Weekday.monday.rawValue, 2)
        XCTAssertEqual(Weekday.saturday.rawValue, 7)
    }
    
    // MARK: - Schedule Type Tests
    
    func testScheduleTypeIcons() {
        XCTAssertEqual(ScheduleType.immediate.icon, "play.fill")
        XCTAssertEqual(ScheduleType.once.icon, "calendar")
        XCTAssertEqual(ScheduleType.daily.icon, "calendar.badge.clock")
        XCTAssertEqual(ScheduleType.weekly.icon, "calendar.circle")
        XCTAssertEqual(ScheduleType.monthly.icon, "calendar.badge.plus")
        XCTAssertEqual(ScheduleType.custom.icon, "calendar.badge.exclamationmark")
    }
    
    func testScheduleTypeAllCases() {
        let allTypes = ScheduleType.allCases
        XCTAssertEqual(allTypes.count, 6)
        XCTAssertTrue(allTypes.contains(.immediate))
        XCTAssertTrue(allTypes.contains(.once))
        XCTAssertTrue(allTypes.contains(.daily))
        XCTAssertTrue(allTypes.contains(.weekly))
        XCTAssertTrue(allTypes.contains(.monthly))
        XCTAssertTrue(allTypes.contains(.custom))
    }
    
    // MARK: - Edge Cases
    
    func testScheduleWithInvalidWeekday() {
        var schedule = DownloadSchedule(type: .weekly)
        schedule.startTime = Date()
        schedule.weekdays = [] // Empty weekdays
        schedule.calculateNextRun()
        
        // Should handle gracefully
        XCTAssertNil(schedule.nextRun)
    }
    
    func testScheduleWithInvalidMonthDay() {
        var schedule = DownloadSchedule(type: .monthly)
        schedule.startTime = Date()
        schedule.dayOfMonth = 32 // Invalid day
        schedule.calculateNextRun()
        
        // May or may not set nextRun depending on implementation
        // Just verify it doesn't crash
    }
    
    func testMultipleBandwidthSchedulesOverlapping() {
        let now = Date()
        
        let schedule1 = BandwidthSchedule(
            name: "Limit 1",
            startTime: now.addingTimeInterval(-1800),
            endTime: now.addingTimeInterval(1800),
            bandwidthLimit: 1 * 1024 * 1024
        )
        
        let schedule2 = BandwidthSchedule(
            name: "Limit 2",
            startTime: now.addingTimeInterval(-900),
            endTime: now.addingTimeInterval(900),
            bandwidthLimit: 512 * 1024
        )
        
        scheduler.addBandwidthSchedule(schedule1)
        scheduler.addBandwidthSchedule(schedule2)
        
        // Should use the most restrictive one (first active)
        let limit = scheduler.currentBandwidthLimit
        XCTAssertNotNil(limit)
    }
}
