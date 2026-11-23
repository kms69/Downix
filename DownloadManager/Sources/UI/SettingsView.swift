import SwiftUI

/// Main settings window with tabbed interface
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case downloads = "Downloads"
        case scheduler = "Scheduler"
        case browser = "Browser"
        case network = "Network"
        case notifications = "Notifications"
        case appearance = "Appearance"
        case advanced = "Advanced"
        case about = "About"
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .downloads: return "arrow.down.circle"
            case .scheduler: return "clock"
            case .browser: return "safari"
            case .network: return "network"
            case .notifications: return "bell"
            case .appearance: return "paintbrush"
            case .advanced: return "terminal"
            case .about: return "info.circle"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            settingsTabStrip
            Divider()
            Group {
                switch selectedTab {
            case .general:
                GeneralSettingsView()
            case .downloads:
                DownloadsSettingsView()
            case .scheduler:
                SchedulerSettingsView()
            case .browser:
                BrowserSettingsView()
            case .network:
                NetworkSettingsView()
            case .notifications:
                NotificationsSettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .advanced:
                AdvancedSettingsView()
            case .about:
                AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 520)
    }

    /// Own tab strip: the system TabView mis-highlighted tabs and ignored clicks here.
    private var settingsTabStrip: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 17))
                        Text(tab.rawValue).font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundColor(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.14) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @AppStorage("defaultDownloadLocation") private var defaultLocation = ""
    @AppStorage("quitWhenLastWindowClosed") private var quitWhenClosed = false
    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("showStatusBarWidget") private var showStatusBar = true
    @AppStorage("confirmBeforeQuitting") private var confirmQuit = true
    
    var body: some View {
        Form {
            Section {
                LabeledContent("Default Download Location:") {
                    HStack {
                        Text(defaultLocation.isEmpty ? "~/Downloads" : defaultLocation)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("Choose...") {
                            selectDownloadLocation()
                        }
                    }
                }
            }
            
            Section {
                Toggle("Start at login", isOn: $startAtLogin)
                Toggle("Show status bar widget", isOn: $showStatusBar)
                Toggle("Quit when last window is closed", isOn: $quitWhenClosed)
                Toggle("Confirm before quitting", isOn: $confirmQuit)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func selectDownloadLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                defaultLocation = url.path
            }
        }
    }
}

// MARK: - Downloads Settings
struct DownloadsSettingsView: View {
    @AppStorage("maxSegments") private var maxSegments = 8
    @AppStorage("retryAttempts") private var retryAttempts = 3
    @AppStorage("timeout") private var timeout = 30
    @AppStorage("autoStartDownloads") private var autoStart = true
    @AppStorage("autoRetryFailed") private var autoRetry = true
    
    var body: some View {
        Form {
            Section("Download Behavior") {
                Text("Files downloaded at the same time are set per queue, in the Scheduler.")
                    .font(.caption).foregroundStyle(.secondary)
                
                LabeledContent("Segments per download:") {
                    Stepper("\(maxSegments)", value: $maxSegments, in: 1...32, step: 1)
                }
                
                Toggle("Auto-start new downloads", isOn: $autoStart)
                Toggle("Auto-retry failed downloads", isOn: $autoRetry)
            }
            
            Section("Video Downloads") {
                VideoCodecSettingRow()
            }

            Section("Connection Settings") {
                LabeledContent("Retry attempts:") {
                    Stepper("\(retryAttempts)", value: $retryAttempts, in: 0...10)
                }
                
                LabeledContent("Timeout (seconds):") {
                    Stepper("\(timeout)", value: $timeout, in: 10...120, step: 10)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Scheduler Settings
struct SchedulerSettingsView: View {
    var body: some View {
        SchedulerView()
            .padding()
    }
}

// MARK: - Browser Settings
struct BrowserSettingsView: View {
    var body: some View {
        BrowserIntegrationView()
            .padding()
    }
}

// MARK: - Network Settings (using global NetworkSettingsView from NetworkSettingsView.swift)

// MARK: - Security Settings
struct SecuritySettingsView: View {
    var body: some View {
        SecurityPrivacyView()
            .padding()
    }
}

// MARK: - Notifications Settings
struct NotificationsSettingsView: View {
    var body: some View {
        NotificationSettingsView()
            .padding()
    }
}

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    var body: some View {
        ThemeCustomizationView()
            .padding()
    }
}

// MARK: - Advanced Settings
struct AdvancedSettingsView: View {
    @State private var cacheBytes: Int64 = 0
    @State private var keptBytes: Int64 = 0
    @State private var cacheBusy = false
    
    var body: some View {
        Form {
            Section("Maintenance") {
                Button("Open Logs Folder") {
                    openLogsFolder()
                }
                
                LabeledContent("Cache size") {
                    Text(cacheBusy ? "Calculating…" : CacheUtil.format(cacheBytes))
                        .foregroundColor(.secondary)
                }
                if keptBytes > 0 {
                    LabeledContent("Kept so downloads can resume") {
                        Text(CacheUtil.format(keptBytes)).foregroundColor(.secondary)
                    }
                }
                Button("Clear Cache") {
                    clearCache()
                }
                .disabled(cacheBusy || cacheBytes == 0)
            }
            
            Section("Data") {
                Button("Reset to Defaults", role: .destructive) {
                    resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCacheSize() }
    }
    
    private func openLogsFolder() {
        guard let logsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs")
            .appendingPathComponent("DownloadManager") else { return }
        
        NSWorkspace.shared.open(logsURL)
    }
    
    // MARK: Cache

    /// The app's own cache folder, and the folder holding yt-dlp partial downloads.
    private func cacheFolders() -> (app: URL, partial: URL)? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let id = Bundle.main.bundleIdentifier else { return nil }
        return (base.appendingPathComponent(id),
                base.appendingPathComponent("DownloadManager/ytdlp-partial", isDirectory: true))
    }

    /// Partial-download folders of unfinished downloads (paused / cancelled / failed / running):
    /// they are what lets a download resume, so Clear Cache keeps them.
    @MainActor private func protectedPartialIDs() -> Set<String> {
        Set(VideoDownloadManager.shared.videoTasks.filter { $0.state != .completed }.map { $0.id.uuidString })
    }

    private func refreshCacheSize() {
        guard let f = cacheFolders() else { return }
        cacheBusy = true
        Task { @MainActor in
            let keep = protectedPartialIDs()
            let sizes = await Task.detached(priority: .utility) { () -> (Int64, Int64) in
                var reclaimable = CacheUtil.folderSize(f.app)
                var kept: Int64 = 0
                let subs = (try? FileManager.default.contentsOfDirectory(at: f.partial, includingPropertiesForKeys: nil)) ?? []
                for d in subs {
                    if keep.contains(d.lastPathComponent) { kept += CacheUtil.folderSize(d) }
                    else { reclaimable += CacheUtil.folderSize(d) }
                }
                return (reclaimable, kept)
            }.value
            cacheBytes = sizes.0
            keptBytes = sizes.1
            cacheBusy = false
        }
    }

    private func clearCache() {
        guard let f = cacheFolders() else { return }
        cacheBusy = true
        Task { @MainActor in
            let keep = protectedPartialIDs()
            await Task.detached(priority: .utility) {
                let fm = FileManager.default
                try? fm.removeItem(at: f.app)
                let subs = (try? fm.contentsOfDirectory(at: f.partial, includingPropertiesForKeys: nil)) ?? []
                for d in subs where !keep.contains(d.lastPathComponent) {
                    try? fm.removeItem(at: d)
                }
            }.value
            cacheBusy = false
            refreshCacheSize()
        }
    }
    
    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DownloadManager-Settings.json"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Export settings to JSON
                print("Exporting settings to \(url)")
            }
        }
    }
    
    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Import settings from JSON
                print("Importing settings from \(url)")
            }
        }
    }
    
    private func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset to Defaults?"
        alert.informativeText = "This will reset all settings to their default values. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Reset all UserDefaults
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

/// Disk-size helpers for the cache display.
private enum CacheUtil {
    static func folderSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: Set(keys))
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        bytes <= 0 ? "Empty" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
