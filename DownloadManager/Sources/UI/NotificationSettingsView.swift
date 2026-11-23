import SwiftUI

@MainActor
struct NotificationSettingsView: View {
    @ObservedObject var manager = NotificationManager.shared
    @State private var selectedTab = 0
    @State private var showingAuthorizationAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Notifications")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Manage notification preferences and history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Authorization status
                authorizationBadge
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            
            // Tab bar
            Picker("Tab", selection: $selectedTab) {
                Text("Settings").tag(0)
                Text("Types").tag(1)
                Text("Schedule").tag(2)
                Text("History").tag(3)
                Text("Statistics").tag(4)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                generalSettingsView
                    .tag(0)
                
                notificationTypesView
                    .tag(1)
                
                scheduleSettingsView
                    .tag(2)
                
                historyView
                    .tag(3)
                
                statisticsView
                    .tag(4)
            }
            .tabViewStyle(.automatic)
        }
        .alert("Notification Authorization", isPresented: $showingAuthorizationAlert) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Notifications are not authorized. Please enable them in System Settings.")
        }
    }
    
    // MARK: - Authorization Badge
    
    private var authorizationBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: authorizationIcon)
                .foregroundColor(authorizationColor)
            
            Text(authorizationText)
                .font(.caption)
                .foregroundColor(authorizationColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(authorizationColor.opacity(0.1))
        )
        .onTapGesture {
            if manager.authorizationStatus != .authorized {
                showingAuthorizationAlert = true
            }
        }
    }
    
    private var authorizationIcon: String {
        switch manager.authorizationStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        case .provisional: return "clock.circle"
        case .ephemeral: return "clock.circle"
        @unknown default: return "circle"
        }
    }
    
    private var authorizationColor: Color {
        switch manager.authorizationStatus {
        case .authorized: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        case .provisional: return .blue
        case .ephemeral: return .blue
        @unknown default: return .gray
        }
    }
    
    private var authorizationText: String {
        switch manager.authorizationStatus {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not Set"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
    
    // MARK: - General Settings
    
    private var generalSettingsView: some View {
        Form {
            Section("Appearance") {
                Toggle("Show Banners", isOn: Binding(
                    get: { manager.settings.bannerEnabled },
                    set: { newValue in
                        var settings = manager.settings
                        settings.bannerEnabled = newValue
                        manager.updateSettings(settings)
                    }
                ))
                
                Toggle("Show Badge Count", isOn: Binding(
                    get: { manager.settings.badgeEnabled },
                    set: { newValue in
                        var settings = manager.settings
                        settings.badgeEnabled = newValue
                        manager.updateSettings(settings)
                    }
                ))
            }
            
            Section("Sound") {
                Toggle("Enable Sounds", isOn: Binding(
                    get: { manager.settings.soundEnabled },
                    set: { newValue in
                        var settings = manager.settings
                        settings.soundEnabled = newValue
                        manager.updateSettings(settings)
                    }
                ))
                
                if manager.settings.soundEnabled {
                    Picker("Sound", selection: Binding(
                        get: { manager.settings.sound },
                        set: { newValue in
                            var settings = manager.settings
                            settings.sound = newValue
                            manager.updateSettings(settings)
                        }
                    )) {
                        ForEach(NotificationSound.allCases, id: \.self) { sound in
                            Text(sound.rawValue).tag(sound)
                        }
                    }
                }
            }
            
            Section("Do Not Disturb") {
                Toggle("Enable Do Not Disturb", isOn: Binding(
                    get: { manager.settings.doNotDisturbEnabled },
                    set: { newValue in
                        var settings = manager.settings
                        settings.doNotDisturbEnabled = newValue
                        manager.updateSettings(settings)
                    }
                ))
                
                if manager.settings.doNotDisturbEnabled {
                    DatePicker("Start Time", selection: Binding(
                        get: { manager.settings.doNotDisturbStart },
                        set: { newValue in
                            var settings = manager.settings
                            settings.doNotDisturbStart = newValue
                            manager.updateSettings(settings)
                        }
                    ), displayedComponents: .hourAndMinute)
                    
                    DatePicker("End Time", selection: Binding(
                        get: { manager.settings.doNotDisturbEnd },
                        set: { newValue in
                            var settings = manager.settings
                            settings.doNotDisturbEnd = newValue
                            manager.updateSettings(settings)
                        }
                    ), displayedComponents: .hourAndMinute)
                    
                    if manager.settings.isInDoNotDisturb() {
                        Label("Currently in Do Not Disturb mode", systemImage: "moon.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Section("Progress Notifications") {
                Toggle("Enable Progress Updates", isOn: Binding(
                    get: { manager.settings.isEnabled(.downloadProgress) },
                    set: { newValue in
                        var settings = manager.settings
                        settings.setEnabled(.downloadProgress, enabled: newValue)
                        manager.updateSettings(settings)
                    }
                ))
                
                if manager.settings.isEnabled(.downloadProgress) {
                    HStack {
                        Text("Update Interval")
                        Spacer()
                        Text("\(Int(manager.settings.progressInterval))s")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { manager.settings.progressInterval },
                        set: { newValue in
                            var settings = manager.settings
                            settings.progressInterval = newValue
                            manager.updateSettings(settings)
                        }
                    ), in: 30...300, step: 30)
                    
                    HStack {
                        Text("Progress Threshold")
                        Spacer()
                        Text("\(Int(manager.settings.progressThreshold * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { manager.settings.progressThreshold },
                        set: { newValue in
                            var settings = manager.settings
                            settings.progressThreshold = newValue
                            manager.updateSettings(settings)
                        }
                    ), in: 0.1...0.5, step: 0.05)
                }
            }
            
            Section("Actions") {
                Button("Request Authorization") {
                    Task {
                        try? await manager.requestAuthorization()
                    }
                }
                .disabled(manager.authorizationStatus == .authorized)
                
                Button("Test Notification") {
                    let content = NotificationContent(
                        type: .downloadCompleted,
                        title: "Test Notification",
                        body: "This is a test notification from Download Manager",
                        priority: .normal
                    )
                    manager.sendNotification(content)
                }
                .disabled(manager.authorizationStatus != .authorized)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Notification Types
    
    private var notificationTypesView: some View {
        List {
            ForEach(NotificationType.allCases, id: \.self) { type in
                Toggle(isOn: Binding(
                    get: { manager.settings.isEnabled(type) },
                    set: { newValue in
                        var settings = manager.settings
                        settings.setEnabled(type, enabled: newValue)
                        manager.updateSettings(settings)
                    }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: type.icon)
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(type.rawValue)
                                .font(.body)
                            
                            Text(typeDescription(type))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    private func typeDescription(_ type: NotificationType) -> String {
        switch type {
        case .downloadStarted: return "When a download begins"
        case .downloadProgress: return "Regular progress updates"
        case .downloadCompleted: return "When a download finishes"
        case .downloadFailed: return "When a download fails"
        case .downloadPaused: return "When a download is paused"
        case .queueCompleted: return "When all downloads in queue finish"
        case .batchCompleted: return "When a batch operation completes"
        case .lowDiskSpace: return "When disk space is running low"
        case .speedThreshold: return "When speed falls below threshold"
        case .dailySummary: return "Daily download statistics"
        case .weeklySummary: return "Weekly download statistics"
        }
    }
    
    // MARK: - Schedule Settings
    
    private var scheduleSettingsView: some View {
        Form {
            Section("Daily Summary") {
                Toggle("Enable Daily Summary", isOn: Binding(
                    get: { manager.settings.isEnabled(.dailySummary) },
                    set: { newValue in
                        var settings = manager.settings
                        settings.setEnabled(.dailySummary, enabled: newValue)
                        manager.updateSettings(settings)
                    }
                ))
                
                if manager.settings.isEnabled(.dailySummary) {
                    DatePicker("Summary Time", selection: Binding(
                        get: { manager.settings.dailySummaryTime },
                        set: { newValue in
                            var settings = manager.settings
                            settings.dailySummaryTime = newValue
                            manager.updateSettings(settings)
                        }
                    ), displayedComponents: .hourAndMinute)
                }
            }
            
            Section("Weekly Summary") {
                Toggle("Enable Weekly Summary", isOn: Binding(
                    get: { manager.settings.isEnabled(.weeklySummary) },
                    set: { newValue in
                        var settings = manager.settings
                        settings.setEnabled(.weeklySummary, enabled: newValue)
                        manager.updateSettings(settings)
                    }
                ))
                
                if manager.settings.isEnabled(.weeklySummary) {
                    Picker("Summary Day", selection: Binding(
                        get: { manager.settings.weeklySummaryDay },
                        set: { newValue in
                            var settings = manager.settings
                            settings.weeklySummaryDay = newValue
                            manager.updateSettings(settings)
                        }
                    )) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Tuesday").tag(3)
                        Text("Wednesday").tag(4)
                        Text("Thursday").tag(5)
                        Text("Friday").tag(6)
                        Text("Saturday").tag(7)
                    }
                    
                    DatePicker("Summary Time", selection: Binding(
                        get: { manager.settings.weeklySummaryTime },
                        set: { newValue in
                            var settings = manager.settings
                            settings.weeklySummaryTime = newValue
                            manager.updateSettings(settings)
                        }
                    ), displayedComponents: .hourAndMinute)
                }
            }
            
            Section("Summary Criteria") {
                HStack {
                    Text("Minimum Downloads")
                    Spacer()
                    Text("\(manager.settings.summaryMinimumDownloads)")
                        .foregroundColor(.secondary)
                }
                
                Stepper("", value: Binding(
                    get: { manager.settings.summaryMinimumDownloads },
                    set: { newValue in
                        var settings = manager.settings
                        settings.summaryMinimumDownloads = newValue
                        manager.updateSettings(settings)
                    }
                ), in: 1...100)
                .labelsHidden()
            }
            
            Section("Speed Threshold") {
                Toggle("Enable Speed Alerts", isOn: Binding(
                    get: { manager.settings.speedThresholdEnabled },
                    set: { newValue in
                        var settings = manager.settings
                        settings.speedThresholdEnabled = newValue
                        manager.updateSettings(settings)
                    }
                ))
                
                if manager.settings.speedThresholdEnabled {
                    HStack {
                        Text("Threshold")
                        Spacer()
                        Text(formatSpeed(manager.settings.speedThreshold))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { Double(manager.settings.speedThreshold) },
                        set: { newValue in
                            var settings = manager.settings
                            settings.speedThreshold = Int64(newValue)
                            manager.updateSettings(settings)
                        }
                    ), in: 10_000...10_000_000, step: 10_000)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - History
    
    private var historyView: some View {
        VStack(spacing: 0) {
            // Header with clear button
            HStack {
                Text("\(manager.history.count) notifications")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Clear History") {
                    manager.clearHistory()
                }
                .buttonStyle(.borderless)
                .disabled(manager.history.isEmpty)
            }
            .padding()
            
            if manager.history.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("No Notification History")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Notifications will appear here once sent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.history) { item in
                        NotificationHistoryRow(item: item)
                    }
                }
            }
        }
    }
    
    // MARK: - Statistics
    
    private var statisticsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overview cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    NotificationStatCard(
                        title: "Total Sent",
                        value: "\(manager.statistics.totalSent)",
                        icon: "bell.fill",
                        color: .blue
                    )
                    
                    NotificationStatCard(
                        title: "Interactions",
                        value: "\(manager.statistics.totalInteracted)",
                        icon: "hand.tap.fill",
                        color: .green
                    )
                    
                    NotificationStatCard(
                        title: "Rate",
                        value: String(format: "%.1f%%", manager.statistics.interactionRate * 100),
                        icon: "chart.line.uptrend.xyaxis",
                        color: .orange
                    )
                }
                .padding(.horizontal)
                
                // By type
                if !manager.statistics.byType.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("By Type")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(Array(manager.statistics.byType.sorted(by: { $0.value > $1.value })), id: \.key) { type, count in
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                Text(type.rawValue)
                                    .font(.body)
                                
                                Spacer()
                                
                                Text("\(count)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                
                // Actions
                VStack(spacing: 12) {
                    Button("Clear Statistics") {
                        manager.clearStatistics()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let lastSent = manager.statistics.lastSentDate {
                        Text("Last notification: \(lastSent, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        let kb = Double(bytesPerSecond) / 1024
        let mb = kb / 1024
        
        if mb >= 1 {
            return String(format: "%.1f MB/s", mb)
        } else {
            return String(format: "%.0f KB/s", kb)
        }
    }
}

// MARK: - Supporting Views

struct NotificationHistoryRow: View {
    let item: NotificationHistory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.content.type.icon)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.content.title)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(item.content.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.sentDate, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if item.interacted {
                        Label("Clicked", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct NotificationStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

// MARK: - Preview

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView()
            .frame(width: 800, height: 600)
    }
}
