//
//  SchedulerIntegration.swift
//  Download Manager for Mac - Feature #3: Scheduler Integration
//
//  Created on February 15, 2026
//

import Foundation

/// Extension to DownloadManager for scheduling support
extension DownloadManager {
    
    // MARK: - Scheduled Downloads
    
    /// Add a download with a schedule
    @discardableResult
    func addScheduledDownload(
        url: URL,
        destinationPath: URL? = nil,
        filename: String? = nil,
        numberOfSegments: Int? = nil,
        priority: DownloadPriority = .normal,
        category: DownloadCategory? = nil,
        schedule: DownloadSchedule
    ) -> DownloadTask {
        
        let destination = destinationPath ?? defaultSaveLocation
        let segments = numberOfSegments ?? defaultNumberOfSegments
        let name = filename ?? url.lastPathComponent
        
        let task = DownloadTask(
            url: url,
            destinationPath: destination,
            filename: name,
            numberOfSegments: segments
        )
        
        // Set priority and category
        task.priority = priority
        task.category = category ?? DownloadCategory.detect(from: name)
        
        // Register the task first, then let the scheduler hold it until its time.
        downloadTasks.append(task)
        saveTaskList()
        DownloadScheduler.shared.addScheduledDownload(task, schedule: schedule)

        return task
    }
    
    /// Schedule an existing download
    func scheduleDownload(_ task: DownloadTask, schedule: DownloadSchedule) {
        DownloadScheduler.shared.addScheduledDownload(task, schedule: schedule)
    }
    
    /// Remove schedule from a download
    func removeSchedule(from task: DownloadTask) {
        DownloadScheduler.shared.removeScheduledDownload(task)
    }
    
    /// Update schedule for a download
    func updateSchedule(for task: DownloadTask, schedule: DownloadSchedule) {
        DownloadScheduler.shared.updateSchedule(for: task, schedule: schedule)
    }
    
    /// Enable/disable schedule
    func setScheduleEnabled(_ enabled: Bool, for task: DownloadTask) {
        DownloadScheduler.shared.setScheduleEnabled(enabled, for: task)
    }
    
    // MARK: - Bandwidth Schedules
    
    /// Add a bandwidth schedule
    func addBandwidthSchedule(_ schedule: BandwidthSchedule) {
        DownloadScheduler.shared.addBandwidthSchedule(schedule)
    }
    
    /// Remove a bandwidth schedule
    func removeBandwidthSchedule(_ schedule: BandwidthSchedule) {
        DownloadScheduler.shared.removeBandwidthSchedule(schedule)
    }
    
    /// Update a bandwidth schedule
    func updateBandwidthSchedule(_ schedule: BandwidthSchedule) {
        DownloadScheduler.shared.updateBandwidthSchedule(schedule)
    }
    
    /// Get all bandwidth schedules
    var bandwidthSchedules: [BandwidthSchedule] {
        DownloadScheduler.shared.bandwidthSchedules
    }
    
    /// Get current active bandwidth limit
    var currentBandwidthLimit: Int64? {
        DownloadScheduler.shared.currentBandwidthLimit
    }
    
    // MARK: - Scheduled Downloads Query
    
    /// Get all scheduled downloads
    var scheduledDownloads: [DownloadTask] {
        downloadTasks.filter { $0.isScheduled }
    }
    
    /// Get downloads scheduled for today
    var downloadsScheduledForToday: [DownloadTask] {
        DownloadScheduler.shared.tasksScheduledForToday()
    }
    
    /// Get upcoming scheduled downloads
    func upcomingScheduledDownloads(days: Int = 7) -> [DownloadTask] {
        DownloadScheduler.shared.upcomingTasks(days: days)
    }
    
    /// Get next scheduled download
    var nextScheduledDownload: DownloadTask? {
        DownloadScheduler.shared.nextScheduledTask
    }
    
    // MARK: - Quick Schedule Helpers
    
    /// Schedule download for later today
    func scheduleForLater(_ task: DownloadTask, hoursFromNow hours: Int) {
        let scheduledDate = Calendar.current.date(byAdding: .hour, value: hours, to: Date()) ?? Date()
        
        var schedule = DownloadSchedule(type: .once)
        schedule.scheduledDate = scheduledDate
        
        scheduleDownload(task, schedule: schedule)
    }
    
    /// Schedule download for tonight (8 PM, or tomorrow if past)
    func scheduleForTonight(_ task: DownloadTask) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var tonight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: today) ?? Date()
        if tonight <= Date() {
            tonight = calendar.date(byAdding: .day, value: 1, to: tonight) ?? tonight
        }
        
        var schedule = DownloadSchedule(type: .once)
        schedule.scheduledDate = tonight
        
        scheduleDownload(task, schedule: schedule)
    }
    
    /// Schedule download for tomorrow morning (2 AM)
    func scheduleForTomorrow(_ task: DownloadTask) {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowMorning = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: tomorrow) ?? Date()
        
        var schedule = DownloadSchedule(type: .once)
        schedule.scheduledDate = tomorrowMorning
        
        scheduleDownload(task, schedule: schedule)
    }
    
    /// Schedule recurring download (daily at specific time)
    func scheduleDailyDownload(_ task: DownloadTask, at time: Date) {
        var schedule = DownloadSchedule(type: .daily)
        schedule.startTime = time
        schedule.calculateNextRun()
        
        scheduleDownload(task, schedule: schedule)
    }
    
    /// Schedule weekly download
    func scheduleWeeklyDownload(_ task: DownloadTask, on weekdays: Set<Weekday>, at time: Date) {
        var schedule = DownloadSchedule(type: .weekly)
        schedule.startTime = time
        schedule.weekdays = weekdays
        schedule.calculateNextRun()
        
        scheduleDownload(task, schedule: schedule)
    }
}
