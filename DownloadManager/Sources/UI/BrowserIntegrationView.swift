//
//  BrowserIntegrationView.swift
//  Download Manager for Mac - Feature #5: Browser Integration UI
//
//  Created on February 15, 2026
//

import SwiftUI

struct BrowserIntegrationView: View {
    @StateObject private var manager = BrowserIntegrationManager.shared
    @State private var showingAddRule = false
    @State private var editingRule: CaptureRule?
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tabs
            Picker("", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Extensions").tag(1)
                Text("Capture Rules").tag(2)
                Text("Settings").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                overviewTab.tag(0)
                extensionsTab.tag(1)
                captureRulesTab.tag(2)
                settingsTab.tag(3)
            }
            .tabViewStyle(.automatic)
        }
        .sheet(isPresented: $showingAddRule) {
            AddCaptureRuleSheet { rule in
                manager.addCaptureRule(rule)
            }
        }
        .sheet(item: $editingRule) { rule in
            EditCaptureRuleSheet(rule: rule) { updated in
                manager.updateCaptureRule(updated)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Browser Integration")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Capture downloads from web browsers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            statusIndicator
        }
        .padding()
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.isNativeHostInstalled ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(manager.isNativeHostInstalled ? "Connected" : "Not Installed")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Statistics
                statisticsSection
                
                // Quick Actions
                quickActionsSection
                
                // Recent Activity
                recentActivitySection
            }
            .padding()
        }
    }
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
            
            let stats = manager.getStatistics()
            
            HStack(spacing: 16) {
                BrowserStatCard(
                    title: "Intercepted",
                    value: "\(stats.totalIntercepted)",
                    color: .blue
                )
                
                BrowserStatCard(
                    title: "Captured",
                    value: "\(stats.totalCaptured)",
                    color: .green
                )
                
                BrowserStatCard(
                    title: "Ignored",
                    value: "\(stats.totalIgnored)",
                    color: .orange
                )
                
                BrowserStatCard(
                    title: "Capture Rate",
                    value: String(format: "%.0f%%", stats.captureRate * 100),
                    color: .purple
                )
            }
        }
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            VStack(spacing: 8) {
                if !manager.isNativeHostInstalled {
                    Button(action: installNativeHost) {
                        Label("Install Browser Integration", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive, action: {
                        try? manager.uninstallNativeHost()
                    }) {
                        Label("Uninstall Browser Integration", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: { showingAddRule = true }) {
                    Label("Add Capture Rule", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browser Extensions")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(manager.extensionStatuses) { status in
                    BrowserStatusRow(status: status)
                }
            }
        }
    }
    
    // MARK: - Extensions Tab
    
    private var extensionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Installed Browser Extensions")
                    .font(.headline)
                
                ForEach(manager.extensionStatuses) { status in
                    ExtensionDetailCard(status: status)
                }
                
                Divider()
                    .padding(.vertical)
                
                installationInstructions
            }
            .padding()
        }
    }
    
    private var installationInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to Add the Extension to Your Browser")
                .font(.headline)

            // Step 1: install native host
            GroupBox(label: Label("Step 1: Install Native Messaging Host", systemImage: "1.circle.fill")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Click the **Install Browser Integration** button above. This writes the native host script and JSON manifests that let the browser extension communicate with the app.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    if manager.isNativeHostInstalled {
                        Label("Native host installed ✓", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    }
                }
                .padding(.top, 4)
            }

            // Step 2: load the extension
            GroupBox(label: Label("Step 2: Load the Extension (Chrome & Brave)", systemImage: "2.circle.fill")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Follow these steps in **Chrome** or **Brave** (each browser needs its own load):")
                    Text("1. Open **chrome://extensions** in Chrome  —  or  **brave://extensions** in Brave")
                    Text("2. Enable **Developer mode** (top-right toggle)")
                    Text("3. Click **Load unpacked** and select the matching folder:")

                    // Chrome row
                    let chromePath = chromeFolderPath()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chrome:").font(.caption).bold()
                        HStack(spacing: 6) {
                            Text(chromePath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [URL(fileURLWithPath: chromePath)]
                                )
                            } label: { Image(systemName: "folder") }
                            .buttonStyle(.plain)
                            .help("Show in Finder")
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }

                    // Brave row
                    let bravePath = braveFolderPath()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Brave:").font(.caption).bold()
                        HStack(spacing: 6) {
                            Text(bravePath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [URL(fileURLWithPath: bravePath)]
                                )
                            } label: { Image(systemName: "folder") }
                            .buttonStyle(.plain)
                            .help("Show in Finder")
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }

                    Label("After loading, the extension ID will be eeikofcgbbeahbphkdbgonopangmdcga (pinned by the manifest key).", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(.callout)
                .padding(.top, 4)
            }

            GroupBox(label: Label("Step 2 (Firefox)", systemImage: "flame.fill")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open **about:debugging#/runtime/this-firefox**")
                    Text("2. Click **Load Temporary Add-on…**")
                    Text("3. Select **manifest.json** inside:")

                    let ffPath = firefoxFolderPath()
                    HStack(spacing: 6) {
                        Text(ffPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: ffPath)]
                            )
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)

                    Label("Note: Firefox temporary add-ons are removed when the browser closes. For permanent installation, the extension must be signed by Mozilla.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(.callout)
                .padding(.top, 4)
            }

            GroupBox(label: Label("Step 3: Allow Native Messaging", systemImage: "3.circle.fill")) {
                Text("After loading the extension, click its toolbar icon. If it asks for permissions, allow them. The extension will automatically route new downloads to Download Manager based on your capture rules.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private func extensionFolderPath(subfolder: String) -> String {
        let fm = FileManager.default
        let candidates: [String] = [
            Bundle.main.bundlePath + "/../BrowserExtensions/" + subfolder,
            fm.homeDirectoryForCurrentUser.path + "/Documents/development/Download_Manager_Mac/BrowserExtensions/" + subfolder
        ]
        for c in candidates where fm.fileExists(atPath: c) {
            return (try? URL(fileURLWithPath: c).resolvingSymlinksInPath().path) ?? c
        }
        // Installed app: the extensions ship inside it. Copy them to a normal folder in the
        // home directory, which the browser's "Load unpacked" dialog can reach.
        let target = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downix Extensions/\(subfolder)")
        if let res = Bundle.main.resourcePath {
            let source = URL(fileURLWithPath: res).appendingPathComponent("BrowserExtensions/\(subfolder)")
            let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
            let marker = target.appendingPathComponent(".downix-version")
            let current = try? String(contentsOf: marker, encoding: .utf8)
            if fm.fileExists(atPath: source.path), current != version {
                try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: target)
                try? fm.copyItem(at: source, to: target)
                try? version.write(to: marker, atomically: true, encoding: .utf8)
            }
        }
        return target.path
    }

    private func chromeFolderPath() -> String { extensionFolderPath(subfolder: "Chrome") }
    private func braveFolderPath()  -> String { extensionFolderPath(subfolder: "Brave") }
    private func firefoxFolderPath() -> String { extensionFolderPath(subfolder: "Firefox") }
    
    // MARK: - Capture Rules Tab
    
    private var captureRulesTab: some View {
        VStack {
            List {
                ForEach(manager.settings.captureRules) { rule in
                    CaptureRuleRow(rule: rule)
                        .onTapGesture {
                            editingRule = rule
                        }
                        .contextMenu {
                            Button("Edit") {
                                editingRule = rule
                            }
                            
                            Button("Delete", role: .destructive) {
                                manager.removeCaptureRule(rule)
                            }
                        }
                }
            }
            .listStyle(.inset)
            
            HStack {
                Button(action: { showingAddRule = true }) {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button("Reset to Defaults") {
                    manager.updateSettings(BrowserIntegrationSettings(
                        captureRules: BrowserIntegrationSettings.defaultRules
                    ))
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }
    
    // MARK: - Settings Tab
    
    private var settingsTab: some View {
        Form {
            Section("General") {
                Toggle("Enable Browser Integration", isOn: Binding(
                    get: { manager.settings.isEnabled },
                    set: { newValue in
                        var settings = manager.settings
                        settings.isEnabled = newValue
                        manager.updateSettings(settings)
                    }
                ))
                
                Toggle("Auto-Capture Downloads", isOn: Binding(
                    get: { manager.settings.autoCapture },
                    set: { newValue in
                        var settings = manager.settings
                        settings.autoCapture = newValue
                        manager.updateSettings(settings)
                    }
                ))
            }
            
            Section("Capture Settings") {
                VStack(alignment: .leading) {
                    Text("Minimum File Size: \(formatBytes(manager.settings.minFileSizeForCapture))")
                    
                    Slider(
                        value: Binding(
                            get: { Double(manager.settings.minFileSizeForCapture) },
                            set: { newValue in
                                var settings = manager.settings
                                settings.minFileSizeForCapture = Int64(newValue)
                                manager.updateSettings(settings)
                            }
                        ),
                        in: 0...104_857_600, // 0 to 100 MB
                        step: 1_048_576 // 1 MB steps
                    )
                }
                
                Toggle("Show Notifications", isOn: Binding(
                    get: { manager.settings.showNotifications },
                    set: { newValue in
                        var settings = manager.settings
                        settings.showNotifications = newValue
                        manager.updateSettings(settings)
                    }
                ))
                
                Toggle("Close Original Download", isOn: Binding(
                    get: { manager.settings.closeOriginalDownload },
                    set: { newValue in
                        var settings = manager.settings
                        settings.closeOriginalDownload = newValue
                        manager.updateSettings(settings)
                    }
                ))
            }
            
            Section("Presets") {
                Button("Aggressive Capture") {
                    manager.updateSettings(.aggressiveCapture)
                }
                
                Button("Conservative Capture") {
                    manager.updateSettings(.conservativeCapture)
                }
                
                Button("Manual Only") {
                    manager.updateSettings(.manualCapture)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Actions
    
    private func installNativeHost() {
        do {
            try manager.installNativeHost()
        } catch {
            print("Failed to install native host: \(error)")
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 {
            return "No minimum"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Helper Views

struct BrowserStatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct BrowserStatusRow: View {
    let status: BrowserExtensionStatus
    
    var body: some View {
        HStack {
            Image(systemName: status.browser.icon)
                .font(.title2)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(status.browser.rawValue)
                    .font(.headline)
                
                Text(status.isInstalled ? "Installed" : "Not Installed")
                    .font(.caption)
                    .foregroundColor(status.isInstalled ? .green : .secondary)
            }
            
            Spacer()
            
            if status.isInstalled {
                Text("\(status.downloadsIntercepted)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ExtensionDetailCard: View {
    let status: BrowserExtensionStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: status.browser.icon)
                    .font(.title)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.browser.rawValue)
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        BrowserStatusBadge(
                            label: status.isInstalled ? "Installed" : "Not Installed",
                            color: status.isInstalled ? .green : .gray
                        )
                        
                        if status.isEnabled {
                            BrowserStatusBadge(label: "Enabled", color: .blue)
                        }
                    }
                }
                
                Spacer()
            }
            
            if let lastComm = status.lastCommunication {
                Text("Last communication: \(formatDate(lastComm))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if status.downloadsIntercepted > 0 {
                Text("Downloads intercepted: \(status.downloadsIntercepted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct BrowserStatusBadge: View {
    let label: String
    let color: Color
    
    var body: some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

struct InstructionCard: View {
    let browser: String
    let steps: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(browser)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(step)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct CaptureRuleRow: View {
    let rule: CaptureRule
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.headline)
                
                Text(patternDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(rule.action.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(actionColor.opacity(0.2))
                .foregroundColor(actionColor)
                .cornerRadius(4)
        }
        .opacity(rule.isEnabled ? 1.0 : 0.5)
    }
    
    private var patternDescription: String {
        switch rule.pattern {
        case .fileExtension(let exts):
            return "Extensions: \(exts.joined(separator: ", "))"
        case .urlPattern(let pattern):
            return "URL Pattern: \(pattern)"
        case .mimeType(let types):
            return "MIME Types: \(types.joined(separator: ", "))"
        case .minFileSize(let size):
            return "Min Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        case .domain(let domains):
            return "Domains: \(domains.joined(separator: ", "))"
        case .all:
            return "All downloads"
        }
    }
    
    private var actionColor: Color {
        switch rule.action {
        case .capture: return .green
        case .ignore: return .red
        case .ask: return .orange
        }
    }
}

struct AddCaptureRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (CaptureRule) -> Void
    
    @State private var name = ""
    @State private var isEnabled = true
    @State private var patternType = 0
    @State private var extensions = ""
    @State private var action: CaptureRule.CaptureAction = .capture
    @State private var priority = 50
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Rule Name", text: $name)
                
                Toggle("Enabled", isOn: $isEnabled)
                
                Picker("Pattern Type", selection: $patternType) {
                    Text("File Extensions").tag(0)
                    Text("Minimum File Size").tag(1)
                }
                
                if patternType == 0 {
                    TextField("Extensions (comma-separated)", text: $extensions)
                }
                
                Picker("Action", selection: $action) {
                    Text("Capture").tag(CaptureRule.CaptureAction.capture)
                    Text("Ignore").tag(CaptureRule.CaptureAction.ignore)
                    Text("Ask").tag(CaptureRule.CaptureAction.ask)
                }
                
                Stepper("Priority: \(priority)", value: $priority, in: 0...100)
            }
            .navigationTitle("Add Capture Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRule()
                    }
                }
            }
        }
    }
    
    private func saveRule() {
        let pattern: CaptureRule.CapturePattern
        if patternType == 0 {
            let exts = extensions.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            pattern = .fileExtension(exts)
        } else {
            pattern = .minFileSize(10_485_760) // 10 MB default
        }
        
        let rule = CaptureRule(
            name: name,
            isEnabled: isEnabled,
            pattern: pattern,
            action: action,
            priority: priority
        )
        
        onSave(rule)
        dismiss()
    }
}

struct EditCaptureRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rule: CaptureRule
    let onSave: (CaptureRule) -> Void
    
    var body: some View {
        // Similar to AddCaptureRuleSheet but pre-filled with rule data
        Text("Edit Rule: \(rule.name)")
    }
}

// MARK: - Preview

struct BrowserIntegrationView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserIntegrationView()
            .frame(width: 900, height: 600)
    }
}
