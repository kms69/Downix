//
//  ClipboardMonitoringView.swift
//  Download Manager for Mac - Feature #17: URL Monitoring & Clipboard
//
//  Created on February 17, 2026
//

import SwiftUI

/// Main view for clipboard monitoring and URL detection
public struct ClipboardMonitoringView: View {
    @StateObject private var monitor = ClipboardMonitor.shared
    @State private var selectedTab: Tab = .detected
    @State private var showingAddRule = false
    @State private var showingAddDomain = false
    @State private var showingSettings = false
    @State private var selectedDetectedURL: DetectedURL?
    @State private var selectedRule: URLPatternRule?
    @State private var selectedDomain: DomainEntry?
    
    enum Tab: String, CaseIterable {
        case detected = "Detected URLs"
        case rules = "Rules"
        case domains = "Domains"
        case stats = "Statistics"
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("Clipboard Monitoring")
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingAddRule) {
            AddRuleView(monitor: monitor)
        }
        .sheet(isPresented: $showingAddDomain) {
            AddDomainView(monitor: monitor)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(monitor: monitor)
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
            Group {
                if let badge = tabBadge(tab) {
                    Label(tab.rawValue, systemImage: tabIcon(tab))
                        .badge(badge)
                } else {
                    Label(tab.rawValue, systemImage: tabIcon(tab))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    }
    
    private func tabIcon(_ tab: Tab) -> String {
        switch tab {
        case .detected: return "link.circle"
        case .rules: return "list.bullet.rectangle"
        case .domains: return "network"
        case .stats: return "chart.bar"
        }
    }
    
    private func tabBadge(_ tab: Tab) -> Int? {
        switch tab {
        case .detected:
            let pending = monitor.detectedURLs.filter { $0.status == .pending || $0.status == .valid }.count
            return pending > 0 ? pending : nil
        case .rules:
            return monitor.rules.filter { $0.isEnabled }.count
        case .domains:
            return monitor.domainList.filter { $0.isEnabled }.count
        case .stats:
            return nil
        }
    }
    
    // MARK: - Detail View
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .detected:
            detectedURLsView
        case .rules:
            rulesView
        case .domains:
            domainsView
        case .stats:
            statisticsView
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        SwiftUI.ToolbarItem(placement: .primaryAction) {
            HStack {
                // Monitoring toggle
                Toggle(isOn: Binding(
                    get: { monitor.isMonitoring },
                    set: { isOn in
                        if isOn {
                            monitor.startMonitoring()
                        } else {
                            monitor.stopMonitoring()
                        }
                    }
                )) {
                    Label("Monitor", systemImage: monitor.isMonitoring ? "eye.fill" : "eye.slash")
                }
                .toggleStyle(.button)
                .tint(monitor.isMonitoring ? .green : .gray)
                
                // Add button
                if selectedTab == .rules {
                    Button(action: { showingAddRule = true }) {
                        Label("Add Rule", systemImage: "plus")
                    }
                } else if selectedTab == .domains {
                    Button(action: { showingAddDomain = true }) {
                        Label("Add Domain", systemImage: "plus")
                    }
                }
                
                // Settings
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
    }
    
    // MARK: - Detected URLs View
    
    private var detectedURLsView: some View {
        Group {
            if monitor.detectedURLs.isEmpty {
                emptyDetectedState
            } else {
                detectedURLsList
            }
        }
    }
    
    private var emptyDetectedState: some View {
        VStack(spacing: 20) {
            Image(systemName: monitor.isMonitoring ? "link.circle" : "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(monitor.isMonitoring ? "No URLs Detected Yet" : "Monitoring Disabled")
                .font(.title2)
                .fontWeight(.medium)
            
            Text(monitor.isMonitoring ?
                 "Copy a download URL to your clipboard and it will appear here" :
                 "Enable monitoring to detect URLs from clipboard")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if !monitor.isMonitoring {
                Button("Start Monitoring") {
                    monitor.startMonitoring()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var detectedURLsList: some View {
        List {
            ForEach(monitor.detectedURLs) { detected in
                DetectedURLRow(detected: detected, monitor: monitor)
                    .contextMenu {
                        detectedURLContextMenu(detected)
                    }
            }
        }
        .listStyle(.inset)
    }
    
    @ViewBuilder
    private func detectedURLContextMenu(_ detected: DetectedURL) -> some View {
        if detected.isValid {
            Button("Download Now") {
                monitor.startDownload(for: detected)
            }
            
            Button("Add to Queue") {
                monitor.addToQueue(detected)
            }
        }
        
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(detected.url.absoluteString, forType: .string)
        }
        
        Button("Open in Browser") {
            NSWorkspace.shared.open(detected.url)
        }
        
        Divider()
        
        Button("Remove", role: .destructive) {
            monitor.deleteDetectedURL(detected)
        }
    }
    
    // MARK: - Rules View
    
    private var rulesView: some View {
        Group {
            if monitor.rules.isEmpty {
                emptyRulesState
            } else {
                rulesList
            }
        }
    }
    
    private var emptyRulesState: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Rules Configured")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Create rules to automatically handle detected URLs")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Add Rule") {
                showingAddRule = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var rulesList: some View {
        List {
            ForEach(monitor.rules.sorted { $0.priority > $1.priority }) { rule in
                ClipboardRuleRow(rule: rule, monitor: monitor)
                    .contextMenu {
                        ruleContextMenu(rule)
                    }
            }
            .onDelete { offsets in
                monitor.deleteRules(at: offsets)
            }
        }
        .listStyle(.inset)
    }
    
    @ViewBuilder
    private func ruleContextMenu(_ rule: URLPatternRule) -> some View {
        Button(rule.isEnabled ? "Disable" : "Enable") {
            var updated = rule
            updated.isEnabled.toggle()
            monitor.updateRule(updated)
        }
        
        Divider()
        
        Button("Delete", role: .destructive) {
            monitor.deleteRule(rule)
        }
    }
    
    // MARK: - Domains View
    
    private var domainsView: some View {
        Group {
            if monitor.domainList.isEmpty {
                emptyDomainsState
            } else {
                domainsList
            }
        }
    }
    
    private var emptyDomainsState: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Domains Configured")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Add domains to whitelist or blacklist")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button("Add Domain") {
                showingAddDomain = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var domainsList: some View {
        List {
            Section("Whitelist") {
                ForEach(monitor.domainList.filter { $0.type == .whitelist }) { domain in
                    DomainRow(domain: domain, monitor: monitor)
                        .contextMenu {
                            domainContextMenu(domain)
                        }
                }
            }
            
            Section("Blacklist") {
                ForEach(monitor.domainList.filter { $0.type == .blacklist }) { domain in
                    DomainRow(domain: domain, monitor: monitor)
                        .contextMenu {
                            domainContextMenu(domain)
                        }
                }
            }
        }
        .listStyle(.inset)
    }
    
    @ViewBuilder
    private func domainContextMenu(_ domain: DomainEntry) -> some View {
        Button(domain.isEnabled ? "Disable" : "Enable") {
            var updated = domain
            updated.isEnabled.toggle()
            monitor.updateDomain(updated)
        }
        
        Divider()
        
        Button("Delete", role: .destructive) {
            monitor.deleteDomain(domain)
        }
    }
    
    // MARK: - Statistics View
    
    private var statisticsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overview Cards
                HStack(spacing: 15) {
                    ClipboardStatCard(
                        title: "Total Detected",
                        value: "\(monitor.stats.totalURLsDetected)",
                        icon: "link.circle",
                        color: .blue
                    )
                    
                    ClipboardStatCard(
                        title: "Valid URLs",
                        value: "\(monitor.stats.validURLsCount)",
                        icon: "checkmark.circle",
                        color: .green
                    )
                    
                    ClipboardStatCard(
                        title: "Auto Downloaded",
                        value: "\(monitor.stats.autoDownloadedCount)",
                        icon: "arrow.down.circle",
                        color: .orange
                    )
                    
                    ClipboardStatCard(
                        title: "Ignored",
                        value: "\(monitor.stats.ignoredCount)",
                        icon: "eye.slash",
                        color: .gray
                    )
                }
                
                // Rates
                HStack(spacing: 15) {
                    RateCard(
                        title: "Detection Rate",
                        value: monitor.stats.detectionRate,
                        icon: "percent"
                    )
                    
                    RateCard(
                        title: "Auto-Download Rate",
                        value: monitor.stats.autoDownloadRate,
                        icon: "bolt.fill"
                    )
                }
                
                // Top Domains
                if !monitor.stats.detectionsByDomain.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Domains")
                            .font(.headline)
                        
                        ForEach(topDomains(), id: \.0) { domain, count in
                            HStack {
                                Image(systemName: "network")
                                    .foregroundColor(.blue)
                                Text(domain)
                                    .font(.body)
                                Spacer()
                                Text("\(count)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.1))
                    )
                }
                
                // Clear button
                Button(role: .destructive) {
                    monitor.clearStats()
                } label: {
                    Label("Clear Statistics", systemImage: "trash")
                }
                .padding(.top)
            }
            .padding()
        }
    }
    
    private func topDomains() -> [(String, Int)] {
        monitor.stats.detectionsByDomain
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }
    }
}

// MARK: - Detected URL Row

private struct DetectedURLRow: View {
    let detected: DetectedURL
    let monitor: ClipboardMonitor
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: detected.status.icon)
                .foregroundColor(statusColor)
                .frame(width: 20)
            
            // URL info
            VStack(alignment: .leading, spacing: 4) {
                Text(detected.fileName ?? detected.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(detected.url.host ?? detected.url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let size = detected.fileSize, size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action buttons
            if detected.isValid && detected.status == .valid {
                HStack(spacing: 8) {
                    Button(action: { monitor.addToQueue(detected) }) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: { monitor.startDownload(for: detected) }) {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                }
            }
            
            // Time
            Text(detected.detectedDate, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch detected.status {
        case .pending: return .orange
        case .validating: return .blue
        case .valid: return .green
        case .invalid: return .red
        case .downloading: return .blue
        case .completed: return .green
        case .ignored: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Rule Row

private struct ClipboardRuleRow: View {
    let rule: URLPatternRule
    let monitor: ClipboardMonitor
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.action.icon)
                .foregroundColor(actionColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.headline)
                
                Text(rule.pattern.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Priority badge
            Text("P\(rule.priority)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(4)
            
            // Match count
            if rule.matchCount > 0 {
                Text("\(rule.matchCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Enabled toggle
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { isOn in
                    var updated = rule
                    updated.isEnabled = isOn
                    monitor.updateRule(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }
    
    private var actionColor: Color {
        switch rule.action {
        case .download: return .green
        case .ask: return .blue
        case .ignore: return .gray
        case .addToQueue: return .orange
        case .copyToClipboard: return .purple
        }
    }
}

// MARK: - Domain Row

private struct DomainRow: View {
    let domain: DomainEntry
    let monitor: ClipboardMonitor
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: domain.type.icon)
                .foregroundColor(domain.type == .whitelist ? .green : .red)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(domain.domain)
                    .font(.headline)
                
                if !domain.notes.isEmpty {
                    Text(domain.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if domain.matchCount > 0 {
                Text("\(domain.matchCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Toggle("", isOn: Binding(
                get: { domain.isEnabled },
                set: { isOn in
                    var updated = domain
                    updated.isEnabled = isOn
                    monitor.updateDomain(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .opacity(domain.isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Stat Card

private struct ClipboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
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
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Rate Card

private struct RateCard: View {
    let title: String
    let value: Double
    let icon: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(Int(value * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Add Rule View

private struct AddRuleView: View {
    @Environment(\.dismiss) private var dismiss
    let monitor: ClipboardMonitor
    
    @State private var name = ""
    @State private var patternType: PatternType = .fileExtension
    @State private var patternValue = ""
    @State private var extensions: [String] = []
    @State private var action: URLAction = .download
    @State private var priority = 5
    
    enum PatternType: String, CaseIterable {
        case domain = "Domain"
        case subdomain = "Subdomain"
        case path = "Path"
        case fileExtension = "File Extension"
        case regex = "Regex"
        case contains = "Contains"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Rule Details") {
                    TextField("Rule Name", text: $name)
                    
                    Picker("Pattern Type", selection: $patternType) {
                        ForEach(PatternType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    
                    if patternType == .fileExtension {
                        TextField("Extensions (comma separated)", text: $patternValue)
                            .help("e.g., mp4,mkv,avi")
                    } else {
                        TextField("Pattern", text: $patternValue)
                    }
                }
                
                Section("Action") {
                    Picker("Action", selection: $action) {
                        ForEach(URLAction.allCases, id: \.self) { action in
                            Label(action.rawValue, systemImage: action.icon).tag(action)
                        }
                    }
                    
                    Stepper("Priority: \(priority)", value: $priority, in: 0...10)
                }
            }
            .navigationTitle("Add Rule")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                SwiftUI.ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRule()
                        dismiss()
                    }
                    .disabled(name.isEmpty || patternValue.isEmpty)
                }
            })
        }
        .frame(width: 500, height: 400)
    }
    
    private func addRule() {
        let pattern: ClipboardURLPattern
        
        switch patternType {
        case .domain:
            pattern = .domain(patternValue)
        case .subdomain:
            pattern = .subdomain(patternValue)
        case .path:
            pattern = .path(patternValue)
        case .fileExtension:
            let exts = patternValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            pattern = .fileExtension(exts)
        case .regex:
            pattern = .regex(patternValue)
        case .contains:
            pattern = .contains(patternValue)
        }
        
        let rule = URLPatternRule(
            name: name,
            pattern: pattern,
            action: action,
            priority: priority
        )
        
        monitor.addRule(rule)
    }
}

// MARK: - Add Domain View

private struct AddDomainView: View {
    @Environment(\.dismiss) private var dismiss
    let monitor: ClipboardMonitor
    
    @State private var domain = ""
    @State private var type: DomainListType = .whitelist
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Domain Details") {
                    TextField("Domain", text: $domain)
                        .help("e.g., example.com")
                    
                    Picker("Type", selection: $type) {
                        ForEach(DomainListType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Domain")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let entry = DomainEntry(
                            domain: domain,
                            type: type,
                            notes: notes
                        )
                        monitor.addDomain(entry)
                        dismiss()
                    }
                    .disabled(domain.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let monitor: ClipboardMonitor
    
    @State private var settings: ClipboardMonitoringSettings
    
    init(monitor: ClipboardMonitor) {
        self.monitor = monitor
        _settings = State(initialValue: monitor.settings)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Monitoring") {
                    Toggle("Enable Clipboard Monitoring", isOn: $settings.isEnabled)
                    
                    HStack {
                        Text("Polling Interval")
                        Spacer()
                        TextField("", value: $settings.pollingInterval, format: .number)
                            .frame(width: 60)
                        Text("seconds")
                    }
                    
                    Toggle("Detect Partial URLs", isOn: $settings.detectPartialURLs)
                    
                    HStack {
                        Text("Minimum URL Length")
                        Spacer()
                        TextField("", value: $settings.minimumURLLength, format: .number)
                            .frame(width: 60)
                    }
                }
                
                Section("Behavior") {
                    Toggle("Auto-Download", isOn: $settings.autoDownload)
                    Toggle("Show Confirmation", isOn: $settings.showConfirmation)
                }
                
                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: $settings.notificationEnabled)
                    Toggle("Play Sound", isOn: $settings.soundEnabled)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        monitor.updateSettings(settings)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 500)
    }
}
