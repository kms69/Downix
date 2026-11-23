//
//  BandwidthManagementView.swift
//  Download Manager for Mac - Feature #10: Advanced Bandwidth Management UI
//
//  Created on February 16, 2026
//

import SwiftUI
import Charts

struct BandwidthManagementView: View {
    @StateObject private var bandwidthManager = BandwidthManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Global").tag(0)
                Text("Schedules").tag(1)
                Text("Network").tag(2)
                Text("Rules").tag(3)
                Text("Statistics").tag(4)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Tab content
            TabView(selection: $selectedTab) {
                GlobalLimitsView()
                    .tag(0)
                
                SchedulesView()
                    .tag(1)
                
                NetworkConfigView()
                    .tag(2)
                
                RulesView()
                    .tag(3)
                
                StatisticsView()
                    .tag(4)
            }
            .tabViewStyle(.automatic)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Global Limits View

struct GlobalLimitsView: View {
    @StateObject private var bandwidthManager = BandwidthManager.shared
    @State private var showingProfilePicker = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Quick Profiles
                GroupBox("Quick Profiles") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                        ForEach(bandwidthManager.profiles.filter { $0.isPredefined }) { profile in
                            ProfileCard(profile: profile) {
                                bandwidthManager.applyProfile(profile)
                            }
                        }
                    }
                    .padding()
                }
                
                // Manual Configuration
                GroupBox("Manual Configuration") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Enable Global Speed Limit", isOn: Binding(
                            get: { bandwidthManager.globalLimit.isEnabled },
                            set: { enabled in
                                var limit = bandwidthManager.globalLimit
                                limit.isEnabled = enabled
                                bandwidthManager.setGlobalLimit(limit)
                            }
                        ))
                        
                        if bandwidthManager.globalLimit.isEnabled {
                            VStack(alignment: .leading, spacing: 12) {
                                // Download Speed
                                SpeedSlider(
                                    title: "Download Speed",
                                    icon: "arrow.down.circle",
                                    speed: Binding(
                                        get: { bandwidthManager.globalLimit.downloadSpeed },
                                        set: { speed in
                                            var limit = bandwidthManager.globalLimit
                                            limit.downloadSpeed = speed
                                            bandwidthManager.setGlobalLimit(limit)
                                        }
                                    )
                                )
                                
                                // Upload Speed
                                SpeedSlider(
                                    title: "Upload Speed",
                                    icon: "arrow.up.circle",
                                    speed: Binding(
                                        get: { bandwidthManager.globalLimit.uploadSpeed },
                                        set: { speed in
                                            var limit = bandwidthManager.globalLimit
                                            limit.uploadSpeed = speed
                                            bandwidthManager.setGlobalLimit(limit)
                                        }
                                    )
                                )
                            }
                        }
                    }
                    .padding()
                }
                
                // Current Network Info
                GroupBox("Current Network") {
                    HStack {
                        Image(systemName: bandwidthManager.currentNetworkType.icon)
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(bandwidthManager.currentNetworkType.rawValue)
                                .font(.headline)
                            
                            if bandwidthManager.currentNetworkType.isMetered {
                                Text("Metered Connection")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Spacer()
                        
                        if bandwidthManager.activeLimit.isEnabled {
                            VStack(alignment: .trailing) {
                                Text("Active Limit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(bandwidthManager.activeLimit.formattedDownloadSpeed())
                                    .font(.headline)
                            }
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
}

// MARK: - Schedules View

struct SchedulesView: View {
    @StateObject private var bandwidthManager = BandwidthManager.shared
    @State private var showingScheduleEditor = false
    @State private var editingSchedule: BandwidthTimeSchedule?
    
    var body: some View {
        VStack {
            if bandwidthManager.schedules.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "No Schedules",
                    message: "Create time-based bandwidth schedules"
                ) {
                    Button("Create Schedule") {
                        showingScheduleEditor = true
                    }
                }
            } else {
                List {
                    ForEach(bandwidthManager.schedules) { schedule in
                        ScheduleRow(schedule: schedule, onEdit: {
                            editingSchedule = schedule
                            showingScheduleEditor = true
                        }, onDelete: {
                            bandwidthManager.deleteSchedule(schedule)
                        }, onToggle: {
                            var updated = schedule
                            updated.isEnabled.toggle()
                            bandwidthManager.updateSchedule(updated)
                        })
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Add Schedule") {
                        showingScheduleEditor = true
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingScheduleEditor) {
            ScheduleEditorView(schedule: editingSchedule) { schedule in
                if let existing = editingSchedule {
                    var updated = schedule
                    bandwidthManager.updateSchedule(updated)
                } else {
                    bandwidthManager.addSchedule(schedule)
                }
                editingSchedule = nil
            }
        }
    }
}

// MARK: - Network Config View

struct NetworkConfigView: View {
    @StateObject private var bandwidthManager = BandwidthManager.shared
    
    var body: some View {
        List {
            ForEach(bandwidthManager.networkConfigurations) { config in
                NetworkConfigRow(config: config) { updated in
                    bandwidthManager.updateNetworkConfiguration(updated)
                }
            }
        }
        .padding()
    }
}

// MARK: - Rules View

struct RulesView: View {
    @StateObject private var bandwidthManager = BandwidthManager.shared
    @State private var showingRuleEditor = false
    @State private var editingRule: BandwidthRule?
    
    var body: some View {
        VStack {
            if bandwidthManager.rules.isEmpty {
                EmptyStateView(
                    icon: "slider.horizontal.3",
                    title: "No Rules",
                    message: "Create custom bandwidth allocation rules"
                ) {
                    Button("Create Rule") {
                        showingRuleEditor = true
                    }
                }
            } else {
                List {
                    ForEach(bandwidthManager.rules.sorted(by: { $0.priority > $1.priority })) { rule in
                        RuleRow(rule: rule, onEdit: {
                            editingRule = rule
                            showingRuleEditor = true
                        }, onDelete: {
                            bandwidthManager.deleteRule(rule)
                        }, onToggle: {
                            var updated = rule
                            updated.isEnabled.toggle()
                            bandwidthManager.updateRule(updated)
                        })
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Add Rule") {
                        showingRuleEditor = true
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingRuleEditor) {
            // Rule editor would go here
            Text("Rule Editor (To be implemented)")
        }
    }
}

// MARK: - Statistics View

struct StatisticsView: View {
    @StateObject private var bandwidthManager = BandwidthManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Statistics Cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                    BandwidthStatCard(
                        title: "Downloaded",
                        value: bandwidthManager.statistics.formattedTotalDownloaded,
                        icon: "arrow.down.circle.fill",
                        color: .blue
                    )
                    
                    BandwidthStatCard(
                        title: "Uploaded",
                        value: bandwidthManager.statistics.formattedTotalUploaded,
                        icon: "arrow.up.circle.fill",
                        color: .green
                    )
                    
                    BandwidthStatCard(
                        title: "Peak Download",
                        value: bandwidthManager.statistics.formattedPeakDownloadSpeed,
                        icon: "speedometer",
                        color: .orange
                    )
                    
                    BandwidthStatCard(
                        title: "Avg Download",
                        value: bandwidthManager.statistics.formattedAverageDownloadSpeed,
                        icon: "gauge",
                        color: .purple
                    )
                }
                
                // Download Speed Graph
                GroupBox("Download Speed") {
                    if #available(macOS 13.0, *) {
                        SpeedChart(
                            dataPoints: bandwidthManager.statistics.downloadSpeedHistory,
                            color: .blue
                        )
                        .frame(height: 200)
                    } else {
                        SimpleSpeedGraph(
                            dataPoints: bandwidthManager.statistics.downloadSpeedHistory,
                            color: .blue
                        )
                        .frame(height: 200)
                    }
                }
                
                // Upload Speed Graph
                GroupBox("Upload Speed") {
                    if #available(macOS 13.0, *) {
                        SpeedChart(
                            dataPoints: bandwidthManager.statistics.uploadSpeedHistory,
                            color: .green
                        )
                        .frame(height: 200)
                    } else {
                        SimpleSpeedGraph(
                            dataPoints: bandwidthManager.statistics.uploadSpeedHistory,
                            color: .green
                        )
                        .frame(height: 200)
                    }
                }
                
                // Reset Button
                HStack {
                    Spacer()
                    Button("Reset Statistics") {
                        bandwidthManager.resetStatistics()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding()
        }
    }
}

// MARK: - Supporting Views

struct ProfileCard: View {
    let profile: BandwidthProfile
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack {
                Image(systemName: profile.icon)
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                
                Text(profile.name)
                    .font(.headline)
                
                if profile.downloadSpeed > 0 {
                    Text("↓ \(ByteCountFormatter.string(fromByteCount: profile.downloadSpeed, countStyle: .binary))/s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Unlimited")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct SpeedSlider: View {
    let title: String
    let icon: String
    @Binding var speed: Int64
    
    // Speed presets in bytes/sec
    private let presets: [Int64] = [
        0, // Unlimited
        100_000, // 100 KB/s
        500_000, // 500 KB/s
        1_000_000, // 1 MB/s
        5_000_000, // 5 MB/s
        10_000_000, // 10 MB/s
        50_000_000, // 50 MB/s
        100_000_000 // 100 MB/s
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Text(formattedSpeed)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Slider(
                value: Binding(
                    get: { Double(presets.firstIndex(of: speed) ?? 0) },
                    set: { speed = presets[Int($0)] }
                ),
                in: 0...Double(presets.count - 1),
                step: 1
            )
        }
    }
    
    private var formattedSpeed: String {
        if speed == 0 {
            return "Unlimited"
        }
        return ByteCountFormatter.string(fromByteCount: speed, countStyle: .binary) + "/s"
    }
}

struct ScheduleRow: View {
    let schedule: BandwidthTimeSchedule
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Toggle("", isOn: .constant(schedule.isEnabled))
                .labelsHidden()
                .onChange(of: schedule.isEnabled) { _ in onToggle() }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label(schedule.formattedTimeRange(), systemImage: "clock")
                    Label(schedule.formattedDays(), systemImage: "calendar")
                    Label(schedule.limit.formattedDownloadSpeed(), systemImage: "arrow.down")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if schedule.isActive() {
                Text("ACTIVE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

struct NetworkConfigRow: View {
    let config: BandwidthNetworkConfiguration
    let onUpdate: (BandwidthNetworkConfiguration) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: config.networkType.icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(config.networkType.rawValue)
                    .font(.headline)
                
                if config.limit.isEnabled {
                    Text("Limit: \(config.limit.formattedDownloadSpeed())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No limit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("Auto-apply", isOn: Binding(
                get: { config.autoApply },
                set: { value in
                    var updated = config
                    updated.autoApply = value
                    onUpdate(updated)
                }
            ))
            
            if config.networkType.isMetered {
                Toggle("Allow downloads", isOn: Binding(
                    get: { config.allowMeteredDownloads },
                    set: { value in
                        var updated = config
                        updated.allowMeteredDownloads = value
                        onUpdate(updated)
                    }
                ))
            }
        }
        .padding(.vertical, 8)
    }
}

struct RuleRow: View {
    let rule: BandwidthRule
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Toggle("", isOn: .constant(rule.isEnabled))
                .labelsHidden()
                .onChange(of: rule.isEnabled) { _ in onToggle() }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rule.name)
                        .font(.headline)
                    
                    Text("Priority: \(rule.priority)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Text(rule.condition.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Limit: \(rule.limit.formattedDownloadSpeed())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

struct BandwidthStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

@available(macOS 13.0, *)
struct SpeedChart: View {
    let dataPoints: [SpeedDataPoint]
    let color: Color
    
    var body: some View {
        if dataPoints.isEmpty {
            Text("No data yet")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(dataPoints) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Speed", point.speedMBps)
                    )
                    .foregroundStyle(color)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .padding()
        }
    }
}

struct SimpleSpeedGraph: View {
    let dataPoints: [SpeedDataPoint]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            if dataPoints.isEmpty {
                Text("No data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxSpeed = dataPoints.map { $0.speed }.max() ?? 1
                let width = geometry.size.width
                let height = geometry.size.height
                let stepX = width / CGFloat(max(dataPoints.count - 1, 1))
                
                Path { path in
                    for (index, point) in dataPoints.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(point.speed) / CGFloat(maxSpeed) * height)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, lineWidth: 2)
            }
        }
        .padding()
    }
}

struct ScheduleEditorView: View {
    let schedule: BandwidthTimeSchedule?
    let onSave: (BandwidthTimeSchedule) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedDays: Set<Int>
    @State private var downloadSpeed: Int64
    @State private var uploadSpeed: Int64
    @State private var priority: Int
    
    init(schedule: BandwidthTimeSchedule?, onSave: @escaping (BandwidthTimeSchedule) -> Void) {
        self.schedule = schedule
        self.onSave = onSave
        
        _name = State(initialValue: schedule?.name ?? "New Schedule")
        _startTime = State(initialValue: schedule?.startTime ?? Date())
        _endTime = State(initialValue: schedule?.endTime ?? Date().addingTimeInterval(3600))
        _selectedDays = State(initialValue: schedule?.daysOfWeek ?? [1, 2, 3, 4, 5, 6, 7])
        _downloadSpeed = State(initialValue: schedule?.limit.downloadSpeed ?? 1_000_000)
        _uploadSpeed = State(initialValue: schedule?.limit.uploadSpeed ?? 500_000)
        _priority = State(initialValue: schedule?.priority ?? 5)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(schedule == nil ? "New Schedule" : "Edit Schedule")
                .font(.title)
            
            Form {
                TextField("Name", text: $name)
                
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                
                // Days of week selector
                HStack {
                    ForEach(1...7, id: \.self) { day in
                        let dayName = ["S", "M", "T", "W", "T", "F", "S"][day - 1]
                        Button(dayName) {
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedDays.contains(day) ? .blue : .gray)
                    }
                }
                
                Stepper("Priority: \(priority)", value: $priority, in: 1...10)
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save") {
                    let newSchedule = BandwidthTimeSchedule(
                        id: schedule?.id ?? UUID(),
                        name: name,
                        isEnabled: schedule?.isEnabled ?? true,
                        startTime: startTime,
                        endTime: endTime,
                        daysOfWeek: selectedDays,
                        limit: BandwidthLimit(
                            isEnabled: true,
                            downloadSpeed: downloadSpeed,
                            uploadSpeed: uploadSpeed
                        ),
                        priority: priority
                    )
                    onSave(newSchedule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || selectedDays.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: action) {
                Label("Get Started", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct BandwidthManagementView_Previews: PreviewProvider {
    static var previews: some View {
        BandwidthManagementView()
    }
}
#endif
