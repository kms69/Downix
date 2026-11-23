//
//  SchedulerView.swift
//  Download Manager for Mac - Feature #3: Scheduler UI
//
//  Created on February 15, 2026
//

import SwiftUI

/// Main scheduler view
struct SchedulerView: View {
    @ObservedObject var scheduler = DownloadScheduler.shared
    @ObservedObject var manager = DownloadManager.shared
    @State private var showingAddSchedule = false
    @State private var showingBandwidthSchedule = false
    @State private var selectedTab: SchedulerTab = .queues

    enum SchedulerTab {
        case queues, downloads, bandwidth, calendar
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            SchedulerToolbarView(
                selectedTab: $selectedTab,
                onAddSchedule: { showingAddSchedule = true },
                onAddBandwidth: { showingBandwidthSchedule = true }
            )
            
            Divider()
            
            // Content
            TabView(selection: $selectedTab) {
                SchedulerQueueView()
                    .tabItem {
                        Label("Queues", systemImage: "list.bullet.rectangle.portrait.fill")
                    }
                    .tag(SchedulerTab.queues)

                ScheduledDownloadsView()
                    .tabItem {
                        Label("Scheduled Downloads", systemImage: "calendar.badge.clock")
                    }
                    .tag(SchedulerTab.downloads)
                
                BandwidthSchedulesView()
                    .tabItem {
                        Label("Bandwidth Schedules", systemImage: "speedometer")
                    }
                    .tag(SchedulerTab.bandwidth)
                
                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .tag(SchedulerTab.calendar)
            }
        }
        .sheet(isPresented: $showingAddSchedule) {
            AddScheduleView()
        }
        .sheet(isPresented: $showingBandwidthSchedule) {
            AddBandwidthScheduleView()
        }
    }
}

// MARK: - Toolbar

struct SchedulerToolbarView: View {
    @Binding var selectedTab: SchedulerView.SchedulerTab
    let onAddSchedule: () -> Void
    let onAddBandwidth: () -> Void
    
    var body: some View {
        HStack {
            Spacer()

            if selectedTab == .downloads {
                Button(action: onAddSchedule) {
                    Label("Add Scheduled Download", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            } else if selectedTab == .bandwidth {
                Button(action: onAddBandwidth) {
                    Label("Add Bandwidth Schedule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            // Queues and Calendar tabs manage their own controls inline
        }
        .padding()
    }
}

// MARK: - Scheduled Downloads View

struct ScheduledDownloadsView: View {
    @ObservedObject var scheduler = DownloadScheduler.shared
    @ObservedObject var manager = DownloadManager.shared
    
    var upcomingTasks: [DownloadTask] {
        scheduler.upcomingTasks()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if upcomingTasks.isEmpty {
                EmptySchedulerView()
            } else {
                List {
                    Section("Upcoming Downloads (\(upcomingTasks.count))") {
                        ForEach(upcomingTasks) { task in
                            ScheduledDownloadRow(task: task)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct ScheduledDownloadRow: View {
    @ObservedObject var task: DownloadTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Icon
                Image(systemName: task.category.icon)
                    .foregroundColor(.accentColor)
                
                // Filename
                Text(task.filename)
                    .font(.headline)
                
                Spacer()
                
                // Schedule type badge
                if let schedule = task.schedule {
                    ScheduleTypeBadge(type: schedule.type)
                }
                
                // Enable/disable toggle
                if let schedule = task.schedule {
                    Toggle("", isOn: Binding(
                        get: { schedule.isEnabled },
                        set: { enabled in
                            DownloadScheduler.shared.setScheduleEnabled(enabled, for: task)
                        }
                    ))
                    .toggleStyle(.switch)
                }
            }
            
            // Schedule description
            if let schedule = task.schedule {
                Text(schedule.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Next run
                if let nextRun = schedule.nextRun {
                    HStack {
                        Image(systemName: "clock")
                        Text("Next run: \(nextRun, style: .relative)")
                    }
                    .font(.caption2)
                    .foregroundColor(.blue)
                }
                
                // Post-download action
                if schedule.actionAfterCompletion != .none {
                    HStack {
                        Image(systemName: schedule.actionAfterCompletion.icon)
                        Text("After completion: \(schedule.actionAfterCompletion.rawValue)")
                    }
                    .font(.caption2)
                    .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit Schedule") {
                // Edit schedule
            }
            
            Button("Remove Schedule") {
                DownloadScheduler.shared.removeScheduledDownload(task)
            }
            
            Divider()
            
            Button("Delete Download", role: .destructive) {
                Task { @MainActor in await DownloadManager.shared.removeDownload(task) }
            }
        }
    }
}

struct ScheduleTypeBadge: View {
    let type: ScheduleType
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
            Text(type.rawValue)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.2))
        .foregroundColor(badgeColor)
        .cornerRadius(4)
    }
    
    var badgeColor: Color {
        switch type {
        case .immediate: return .green
        case .once: return .blue
        case .daily: return .purple
        case .weekly: return .orange
        case .monthly: return .pink
        case .custom: return .gray
        }
    }
}

// MARK: - Bandwidth Schedules View

struct BandwidthSchedulesView: View {
    @ObservedObject var scheduler = DownloadScheduler.shared
    
    var body: some View {
        VStack(alignment: .leading) {
            // Current limit indicator
            if let currentLimit = scheduler.currentBandwidthLimit {
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundColor(.orange)
                    Text("Current limit: \(ByteCountFormatter.string(fromByteCount: currentLimit, countStyle: .file))/s")
                        .font(.headline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
            }
            
            if scheduler.bandwidthSchedules.isEmpty {
                EmptyBandwidthSchedulesView()
            } else {
                List {
                    ForEach(scheduler.bandwidthSchedules) { schedule in
                        BandwidthScheduleRow(schedule: schedule)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct BandwidthScheduleRow: View {
    var schedule: BandwidthSchedule
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(schedule.name)
                    .font(.headline)
                
                Spacer()
                
                // Active indicator
                if schedule.isActive() {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Toggle("", isOn: Binding(
                    get: { schedule.isEnabled },
                    set: { enabled in
                        var updatedSchedule = schedule
                        updatedSchedule.isEnabled = enabled
                        DownloadScheduler.shared.updateBandwidthSchedule(updatedSchedule)
                    }
                ))
                .toggleStyle(.switch)
            }
            
            HStack {
                Label(timeRangeString(), systemImage: "clock")
                Spacer()
                Label(schedule.formattedBandwidth, systemImage: "speedometer")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Weekdays
            HStack {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Text(day.shortName)
                        .font(.caption2)
                        .padding(4)
                        .background(schedule.weekdays.contains(day) ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(schedule.weekdays.contains(day) ? .white : .secondary)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    func timeRangeString() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: schedule.startTime)) - \(formatter.string(from: schedule.endTime))"
    }
}

// MARK: - Calendar View

struct CalendarView: View {
    @ObservedObject var scheduler = DownloadScheduler.shared
    @State private var selectedDate = Date()
    
    var body: some View {
        HSplitView {
            // Calendar
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
            
            // Downloads for selected date
            VStack(alignment: .leading) {
                Text("Scheduled for \(selectedDate, style: .date)")
                    .font(.headline)
                    .padding()
                
                if tasksForDate().isEmpty {
                    Spacer()
                    Text("No downloads scheduled for this day")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List(tasksForDate()) { task in
                        ScheduledDownloadRow(task: task)
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
    
    func tasksForDate() -> [DownloadTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? selectedDate
        
        return scheduler.scheduledTasks.filter { task in
            guard let nextRun = task.schedule?.nextRun else { return false }
            return nextRun >= startOfDay && nextRun < endOfDay
        }
    }
}

// MARK: - Add Schedule View

struct AddScheduleView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedType: ScheduleType = .once
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var selectedWeekdays: Set<Weekday> = []
    @State private var dayOfMonth = 1
    @State private var bandwidthLimit: String = ""
    @State private var postDownloadAction: PostDownloadAction = .none
    @State private var stopAfterCompletion = false
    @State private var urlString = ""
    @State private var existingTaskID: UUID? = nil
    @ObservedObject private var manager = DownloadManager.shared

    /// Existing downloads that can still be scheduled.
    private var schedulableTasks: [DownloadTask] {
        manager.downloadTasks.filter { $0.state != .completed && $0.state != .cancelled }
    }

    private var isValid: Bool {
        if selectedType == .custom { return false }
        if selectedType == .weekly && selectedWeekdays.isEmpty { return false }
        if existingTaskID != nil { return true }
        if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Schedule")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            Form {
                Section("Download") {
                    Picker("Schedule", selection: $existingTaskID) {
                        Text("A new download (enter URL below)").tag(UUID?.none)
                        ForEach(schedulableTasks) { task in
                            Text(task.filename).tag(Optional(task.id))
                        }
                    }
                    if existingTaskID == nil {
                        TextField("URL", text: $urlString, prompt: Text("https://example.com/file.zip"))
                    }
                }

                Picker("Schedule Type", selection: $selectedType) {
                    ForEach(ScheduleType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                
                switch selectedType {
                case .immediate:
                    Text("Download will start immediately")
                        .foregroundColor(.secondary)
                    
                case .once:
                    DatePicker("Date & Time", selection: $selectedDate)
                    
                case .daily:
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    
                case .weekly:
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    
                    VStack(alignment: .leading) {
                        Text("Days of week:")
                        HStack {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                Toggle(day.shortName, isOn: Binding(
                                    get: { selectedWeekdays.contains(day) },
                                    set: { isOn in
                                        if isOn {
                                            selectedWeekdays.insert(day)
                                        } else {
                                            selectedWeekdays.remove(day)
                                        }
                                    }
                                ))
                                .toggleStyle(.button)
                            }
                        }
                    }
                    
                case .monthly:
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    Stepper("Day of month: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                    
                case .custom:
                    Text("Custom schedules not yet implemented")
                        .foregroundColor(.secondary)
                }
                
                Section("Options") {
                    TextField("Bandwidth Limit (optional)", text: $bandwidthLimit)
                        .help("e.g., 1MB, 500KB")
                    
                    Picker("After completion", selection: $postDownloadAction) {
                        ForEach(PostDownloadAction.macCases, id: \.self) { action in
                            Label(action.rawValue, systemImage: action.icon)
                        }
                    }
                    
                    if postDownloadAction != .none {
                        Toggle("Only when all downloads complete", isOn: $stopAfterCompletion)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Add Schedule") {
                    addSchedule()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }
    
    func addSchedule() {
        var schedule = DownloadSchedule(type: selectedType)
        
        switch selectedType {
        case .once:
            schedule.scheduledDate = selectedDate
        case .daily:
            schedule.startTime = selectedTime
        case .weekly:
            schedule.startTime = selectedTime
            schedule.weekdays = selectedWeekdays
        case .monthly:
            schedule.startTime = selectedTime
            schedule.dayOfMonth = dayOfMonth
        case .immediate, .custom:
            break
        }
        
        schedule.actionAfterCompletion = postDownloadAction
        schedule.stopAfterCompletion = stopAfterCompletion
        
        // Parse bandwidth limit ("500KB", "1.5MB", "2 MB/s"; a bare number means KB/s)
        schedule.bandwidthLimit = BandwidthParser.parse(bandwidthLimit)

        schedule.calculateNextRun()

        // Attach the schedule to a real download: the one picked, or a new one.
        if let id = existingTaskID,
           let task = manager.downloadTasks.first(where: { $0.id == id }) {
            DownloadScheduler.shared.addScheduledDownload(task, schedule: schedule)
        } else if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            manager.addScheduledDownload(url: url, schedule: schedule)
        }
    }
}

// MARK: - Add Bandwidth Schedule View

struct AddBandwidthScheduleView: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var bandwidthLimit = ""
    @State private var selectedWeekdays: Set<Weekday> = Set(Weekday.allCases)
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Bandwidth Schedule")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            Form {
                TextField("Name", text: $name)
                
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                
                TextField("Bandwidth Limit (e.g., 1MB)", text: $bandwidthLimit)
                
                VStack(alignment: .leading) {
                    Text("Active on:")
                    HStack {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Toggle(day.shortName, isOn: Binding(
                                get: { selectedWeekdays.contains(day) },
                                set: { isOn in
                                    if isOn {
                                        selectedWeekdays.insert(day)
                                    } else {
                                        selectedWeekdays.remove(day)
                                    }
                                }
                            ))
                            .toggleStyle(.button)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Add") {
                    addBandwidthSchedule()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || bandwidthLimit.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
    
    func addBandwidthSchedule() {
        // Parse what the user typed ("500KB", "1.5MB"); fall back to 1 MB/s if unreadable.
        let limit: Int64 = BandwidthParser.parse(bandwidthLimit) ?? 1024 * 1024

        let schedule = BandwidthSchedule(
            name: name,
            startTime: startTime,
            endTime: endTime,
            bandwidthLimit: limit,
            weekdays: selectedWeekdays
        )
        
        DownloadScheduler.shared.addBandwidthSchedule(schedule)
    }
}

// MARK: - Empty Views

struct EmptySchedulerView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Scheduled Downloads")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Schedule downloads to start at specific times")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyBandwidthSchedulesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "speedometer")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Bandwidth Schedules")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Limit download speed during specific times")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview
// Note: Previews only work in Xcode projects, not SPM
// To use: Open in Xcode and add to SwiftUI preview canvas
