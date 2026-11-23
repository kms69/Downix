import SwiftUI
import AppKit

/// Main application entry point for Download Manager
@main
struct DownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var themeManager = ThemeManager.shared
    
    init() {
        // Configure app-wide settings
        setupAppearance()
    }
    
    var body: some Scene {
        // Main window (single: browser grabs must not spawn extra windows)
        Window("Downix Download Manager", id: "main") {
            MainWindowView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .tint(DownixAccent.primary)
                .id(themeManager.effectiveTheme.id)      // redraw with the new theme colours
                .frame(minWidth: 1080, minHeight: 620)
        }
        .commands {
            // File menu commands
            CommandGroup(replacing: .newItem) {
                Button("Add Download...") {
                    NotificationCenter.default.post(name: .showAddDownload, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                
                Button("Add URLs from Clipboard") {
                    NotificationCenter.default.post(name: .addFromClipboard, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Import URLs...") {
                    NotificationCenter.default.post(name: .importURLs, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }
            
            // Downloads menu
            CommandMenu("Downloads") {
                Button("Pause All") {
                    Task { @MainActor in
                        await DownloadManager.shared.pauseAll()
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                
                Button("Resume All") {
                    Task { @MainActor in
                        await DownloadManager.shared.resumeAll()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Clear Completed") {
                    Task { @MainActor in
                        await DownloadManager.shared.clearCompleted()
                    }
                }
                
                Button("Retry Failed") {
                    Task { @MainActor in
                        await DownloadManager.shared.retryFailed()
                    }
                }
            }
            
            // View menu enhancements
            CommandGroup(after: .sidebar) {
                Button("Toggle Day / Night Theme") {
                    let isDark: Bool
                    if let scheme = themeManager.currentColorScheme {
                        isDark = scheme == .dark
                    } else {
                        isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    }
                    themeManager.setAppearanceMode(isDark ? .light : .dark)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Show Statistics") {
                    NotificationCenter.default.post(name: .showStatistics, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                
                Button("Show Scheduler") {
                    QueueSchedulerWindowController.show()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }
        
        // Settings window
        Settings {
            SettingsView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .tint(DownixAccent.primary)
        }
        
        // Menu bar extra
        MenuBarExtra {
            MenuBarExtraView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentColorScheme)
        } label: {
            MenuBarIconLabel()      // always alive: gives the Dock-click handler an openWindow
        }
        .menuBarExtraStyle(.window)
    }
    
    private func setupAppearance() {
        // Apply initial theme - ThemeManager handles its own theme application
        // No need to manually apply here as it uses environment objects
    }
}

/// Lets AppKit code (Dock click) open the SwiftUI main window by id.
enum MainWindowOpener {
    static var open: (() -> Void)?
}

/// Menu-bar icon. Besides drawing the icon it registers `openWindow` for MainWindowOpener.
struct MenuBarIconLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = { MainWindowOpener.open = { openWindow(id: "main") } }()
        DownixMenuBarContent()
    }
}

/// App delegate for handling app lifecycle and system events
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarWidget: StatusBarWidget?

    private var suppressMainWindowUntil = Date.distantPast
    /// Addresses captured in the last 30 s, so one browser download cannot open two windows.
    private var recentCaptures: [String: Date] = [:]
    /// While in the future, any manager main window is kept fully transparent
    /// (checked on every window update, before the frame is drawn).
    private var keepMainInvisibleUntil = Date.distantPast
    private var bypassReopenDeferral = false
    private let launchedAt = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Download Manager launching...")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowDidBecomeVisible(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(allowMainWindow),
            name: .showMainWindow,
            object: nil
        )
        
        // Initialize all managers
        ManagerCoordinator.shared.initialize()
        DispatchQueue.global(qos: .utility).async { ExternalToolRunner.ensureManagedYtDlpRuns() }
        ThemeManager.applyAppAppearance(ThemeManager.shared.currentColorScheme)
        QueueRunController.shared.start()      // scheduled queue start/stop times
        
        // Setup notification permissions
        setupNotifications()
        
        // Setup status bar widget (optional)
        if UserDefaults.standard.bool(forKey: "showStatusBarWidget") {
            statusBarWidget = StatusBarWidget()
        }
        
        // Check for updates (if implemented)
        #if !DEBUG
        checkForUpdates()
        #endif
        
        print("✅ Download Manager ready")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 Download Manager shutting down...")
        
        // Cleanup and save state
        Task { @MainActor in
            await ManagerCoordinator.shared.shutdown()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running if downloads are active
        if DownloadManager.shared.hasActiveDownloads {
            // Just hide the window instead of quitting
            NSApp.windows.first?.orderOut(nil)
            return false
        }
        return UserDefaults.standard.bool(forKey: "quitWhenLastWindowClosed")
    }

    /// Reopening the app (Dock click / `open -a`) must not spawn a second main
    /// window: bring the existing one forward, or let SwiftUI make one if none exists.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        suppressMainWindowUntil = .distantPast
        YtDlpLog.log("dock: reopen flag=\(flag) floating=\(DownloadProgressWindowController.openWindows.count) windows: " + NSApp.windows.map {
            "\(type(of: $0)) main=\(Self.isManagerMainWindow($0)) mini=\($0.isMiniaturized) vis=\($0.isVisible) title='\($0.title)'"
        }.joined(separator: " | "))
        // A minimized / hidden floating download window comes back first;
        // the main window only opens when there was nothing to restore.
        let mainWasVisible = NSApp.windows.contains { Self.isManagerMainWindow($0) && $0.isVisible }
        if DownloadProgressWindowController.restoreHiddenWindows() {
            // Do not activate the app: that makes SwiftUI re-present the main
            // window. Keep it hidden for a moment unless it was already open.
            // Only the floating window(s) come back. The main window is never raised here:
            // if it was open it stays where it is, if it was hidden it stays hidden.
            if !mainWasVisible {
                keepMainInvisibleUntil = Date().addingTimeInterval(4)
                suppressMainWindowUntil = Date().addingTimeInterval(4)
                keepMainWindowHidden(until: Date().addingTimeInterval(3.5))
            }
            return false
        }
        // A browser capture sends its URL event a split second AFTER this reopen.
        // Showing the main window right now made it flash on the first capture, so
        // wait briefly; if a capture arrives meanwhile the window is never shown.
        if !mainWasVisible && !bypassReopenDeferral {
            for window in NSApp.windows where Self.isManagerMainWindow(window) { window.alphaValue = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                if self.suppressMainWindowUntil == .distantFuture {
                    YtDlpLog.log("dock: reopen came from a browser capture; main window stays hidden")
                    return
                }
                self.bypassReopenDeferral = true
                _ = self.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
                self.bypassReopenDeferral = false
            }
            return false
        }
        keepMainInvisibleUntil = .distantPast
        YtDlpLog.log("dock: no hidden floating window; windows: " + NSApp.windows.map {
            "\(type(of: $0)) mini=\($0.isMiniaturized) vis=\($0.isVisible)"
        }.joined(separator: ", "))
        for window in NSApp.windows where Self.isManagerMainWindow(window) {
            window.alphaValue = 1
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return false
        }
        // No manager window (it was destroyed): ask SwiftUI to create a new one.
        NSApp.activate(ignoringOtherApps: true)
        if let open = MainWindowOpener.open {
            open()
            return false
        }
        return true
    }

    /// The red close button hides the main window instead of destroying it, so a
    /// Dock click can always bring it straight back. (SwiftUI discards a closed
    /// `Window` scene, which is why only the menu-bar "Show main window" worked.)
    @objc private func hideMainWindowInsteadOfClosing(_ sender: Any?) {
        for window in NSApp.windows where Self.isManagerMainWindow(window) {
            window.orderOut(nil)
        }
    }

    private func interceptClose(of window: NSWindow) {
        guard Self.isManagerMainWindow(window),
              let button = window.standardWindowButton(.closeButton) else { return }
        button.target = self
        button.action = #selector(hideMainWindowInsteadOfClosing(_:))
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        // Handle URL scheme (downloadmanager://)
        for url in urls {
            if url.scheme == "downloadmanager" {
                handleCustomURL(url)
            }
        }
    }
    
    /// Hide the SwiftUI main window whenever the app is activated by a browser
    /// grab, cold or warm. The URL event activates the app, which would otherwise
    /// bring the manager forward; only the floating capture panel may show.
    private func suppressMainWindowForBrowserCapture() {
        suppressMainWindowUntil = .distantFuture
        keepMainWindowHidden(until: Date().addingTimeInterval(3.0))
    }

    private func keepMainWindowHidden(until deadline: Date) {
        orderOutMainWindows()
        guard Date() < suppressMainWindowUntil else { return }
        if Date() >= deadline {
            // Keep guarding for as long as one of our capture panels is on screen;
            // SwiftUI can re-present the scene when the app is activated.
            let hasCapturePanel = NSApp.windows.contains { $0 is NSPanel && $0.isVisible }
            guard hasCapturePanel else { return }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.keepMainWindowHidden(until: deadline)
        }
    }

    /// True only for the real SwiftUI manager window. NSApp.windows also holds
    /// popup-menu windows (the "On completion" Picker), tooltips and status-bar
    /// windows; those have no title and are not NSPanels, so the old check
    /// ordered them out and the dropdown / floating window vanished on click.
    static func isManagerMainWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel),
              window.styleMask.contains(.titled),
              window.level == .normal,
              window.canBecomeMain,
              window.parent == nil, window.sheetParent == nil else { return false }
        let title = window.title
        return title.isEmpty || title == "Downix Download Manager"
    }

    private func orderOutMainWindows() {
        for window in NSApp.windows where Self.isManagerMainWindow(window) {
            window.alphaValue = 0          // invisible even for the frame before orderOut
            window.orderOut(nil)
        }
    }

    private func revealMainWindows() {
        for window in NSApp.windows where Self.isManagerMainWindow(window) {
            window.alphaValue = 1
        }
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        guard Date() < keepMainInvisibleUntil,
              let w = notification.object as? NSWindow,
              Self.isManagerMainWindow(w), w.alphaValue != 0 else { return }
        w.alphaValue = 0
    }

    /// Runs BEFORE the app activates, i.e. before SwiftUI can draw the main
    /// window. With a capture / floating window on screen the main window must
    /// not flash up.
    func applicationWillBecomeActive(_ notification: Notification) {
        YtDlpLog.log("dock: willBecomeActive floating=\(DownloadProgressWindowController.openWindows.count)")
        ThemeManager.applyAppAppearance(ThemeManager.shared.currentColorScheme)
        // holdMainBriefly: the browser's URL event arrives ~100 ms AFTER activation, and
        // activating the app raises a main window that is open but covered by the
        // browser, which flashed on the first capture. Keep it invisible for a moment;
        // if no capture follows it is revealed again.
        if Date().timeIntervalSince(launchedAt) > 3, Date() >= suppressMainWindowUntil,
           NSApp.windows.contains(where: { Self.isManagerMainWindow($0) }) {
            keepMainInvisibleUntil = Date().addingTimeInterval(0.5)
            for window in NSApp.windows where Self.isManagerMainWindow(window) { window.alphaValue = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, self.suppressMainWindowUntil != .distantFuture,
                      Date() >= self.suppressMainWindowUntil else { return }
                self.keepMainInvisibleUntil = .distantPast
                self.revealMainWindows()
            }
        }
        let mainVisible = NSApp.windows.contains { Self.isManagerMainWindow($0) && $0.isVisible }
        // The browser's URL event arrives AFTER the app activates, so the very first
        // capture used to flash the main window before it could be suppressed.
        // When the main window is hidden and the app is activated in the background
        // (not at launch), keep it hidden for a moment; a Dock click still shows it
        // through applicationShouldHandleReopen.
        let backgroundActivation = !mainVisible && Date().timeIntervalSince(launchedAt) > 3
        if backgroundActivation && Date() >= suppressMainWindowUntil {
            suppressMainWindowUntil = Date().addingTimeInterval(1.2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self, self.suppressMainWindowUntil != .distantFuture else { return }
                self.keepMainInvisibleUntil = .distantPast
                self.revealMainWindows()      // window stays ordered out; only restores its alpha
            }
        }
        if Date() < suppressMainWindowUntil
            || (!mainVisible && DownloadProgressWindowController.hasHiddenWindows) {
            keepMainInvisibleUntil = Date().addingTimeInterval(1.5)
            for window in NSApp.windows where Self.isManagerMainWindow(window) {
                window.alphaValue = 0
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if Date() < suppressMainWindowUntil { orderOutMainWindows() }
    }

    @objc private func allowMainWindow() {
        suppressMainWindowUntil = .distantPast
        keepMainInvisibleUntil = .distantPast
        revealMainWindows()
    }

    @objc private func mainWindowDidBecomeVisible(_ notification: Notification) {
        if let window = notification.object as? NSWindow { interceptClose(of: window) }
        if let w = notification.object as? NSWindow, Self.isManagerMainWindow(w) {
            YtDlpLog.log("dock: main window became key; suppressed=\(Date() < suppressMainWindowUntil)")
        }
        if Date() >= suppressMainWindowUntil, let w = notification.object as? NSWindow,
           Self.isManagerMainWindow(w), w.alphaValue < 1 { w.alphaValue = 1 }
        guard Date() < suppressMainWindowUntil,
              let window = notification.object as? NSWindow,
              Self.isManagerMainWindow(window) else { return }
        window.orderOut(nil)
    }

    // MARK: - Starting a confirmed browser capture

    /// Every browser grab asks first (IDM behaviour): the floating panel shows
    /// the file info with Save / Cancel, and only Save starts the transfer.
    private func present(_ prompt: DownloadPrompt) {
        DownloadConfirmationController.shared.enqueue(prompt)
    }

    private func startBrowserVideoDownload(url: URL, options: VideoDownloadOptions,
                                           cookieFile: URL?, title: String?,
                                           headers: [String: String], folder: URL) -> StartedCapture {
        let task = VideoDownloadManager.shared.addAndStartDownload(
            url: url, options: options, cookieFile: cookieFile,
            preferredTitle: title, httpHeaders: headers, destinationFolder: folder)
        // The confirmation panel becomes the progress window for this task.
        NotificationCenter.default.post(name: .videoDownloadStarted, object: nil)
        return .video(task)
    }

    private func startBrowserFileDownload(url: URL, filename: String?, headers: [String: String], folder: URL) -> StartedCapture {
        let task = DownloadManager.shared.addDownload(
            url: url,
            destinationPath: folder,
            filename: (filename?.isEmpty == false) ? filename : nil,
            headers: headers
        )
        task.showsCompletionDialog = true
        return .file(task)
    }

    private func setupNotifications() {
        Task { @MainActor in
            try? await NotificationManager.shared.requestAuthorization()
        }
    }
    
    private func handleCustomURL(_ url: URL) {
        // Handle downloadmanager:// URL scheme
        guard url.scheme == "downloadmanager" else { return }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        switch url.host {
        case "add":
            // downloadmanager://add?url=…&filename=…&referer=…&cookie=…&ua=…&kind=file|video
            guard let downloadURL = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let url = URL(string: downloadURL) else { return }
            let filename = components?.queryItems?.first(where: { $0.name == "filename" })?.value
            let kind = components?.queryItems?.first(where: { $0.name == "kind" })?.value

            // Forward browser context so protected links still work.
            var headers: [String: String] = [:]
            if let referer = components?.queryItems?.first(where: { $0.name == "referer" })?.value,
               !referer.isEmpty { headers["Referer"] = referer }
            if let cookie = components?.queryItems?.first(where: { $0.name == "cookie" })?.value,
               !cookie.isEmpty { headers["Cookie"] = cookie }
            if let ua = components?.queryItems?.first(where: { $0.name == "ua" })?.value,
               !ua.isEmpty { headers["User-Agent"] = ua }

            // Handle here (not in MainWindowView) so captures also work when the
            // window is closed or the app was just launched by the browser.
            // The browser can report one download twice (original + redirect/retry).
            let captureKey = url.absoluteString
            recentCaptures = recentCaptures.filter { Date().timeIntervalSince($0.value) < 30 }
            YtDlpLog.log("capture: \(captureKey.prefix(120)) kind=\(kind ?? "-") duplicate=\(recentCaptures[captureKey] != nil)")
            if recentCaptures[captureKey] != nil { return }
            recentCaptures[captureKey] = Date()
            if let existing = DownloadManager.shared.downloadTasks.first(where: {
                $0.url == url && ($0.state == .downloading || $0.state == .waiting || $0.state == .paused)
            }) {
                YtDlpLog.log("capture: already downloading, showing its window")
                recentCaptures[captureKey] = nil
                DownloadProgressWindowController.open(for: existing)
                return
            }

            let isVideo = kind == "video" || VideoPlatform.detect(from: url) != .generic
            suppressMainWindowForBrowserCapture()

            if isVideo {
                var options = VideoDownloadOptions.default
                let qualityRaw = components?.queryItems?.first(where: { $0.name == "quality" })?.value
                if let height = Int(qualityRaw ?? "") {
                    options.quality = VideoQuality.from(height: height)
                } else if qualityRaw == "best" {
                    options.quality = .best
                }
                if components?.queryItems?.first(where: { $0.name == "audio" })?.value == "1" {
                    options.extractAudioOnly = true
                    options.format = .m4a
                    options.embedThumbnail = false
                }
                let cookieFilePath = components?.queryItems?.first(where: { $0.name == "cookiefile" })?.value
                let cookieFile = (cookieFilePath?.isEmpty == false) ? URL(fileURLWithPath: cookieFilePath!) : nil

                let displayName = (filename?.isEmpty == false) ? filename!
                    : (url.host ?? url.lastPathComponent)
                var subtitleParts = [url.host ?? ""]
                if options.extractAudioOnly {
                    subtitleParts.append("Audio (M4A)")
                } else {
                    subtitleParts.append(options.quality.rawValue)
                }
                let subtitle = subtitleParts.filter { !$0.isEmpty }.joined(separator: " • ")

                let prompt = DownloadPrompt(
                    title: "Download this video?",
                    name: displayName,
                    subtitle: subtitle,
                    icon: "play.rectangle.fill",
                    tint: .purple,
                    onSave: { [weak self] folder in
                        self?.startBrowserVideoDownload(url: url, options: options,
                                                        cookieFile: cookieFile, title: filename,
                                                        headers: headers, folder: folder)
                    },
                    onCancel: {
                        if let cookieFile { try? FileManager.default.removeItem(at: cookieFile) }
                    }
                )
                present(prompt)
            } else {
                let displayName = (filename?.isEmpty == false) ? filename!
                    : (url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent)
                let prompt = DownloadPrompt(
                    title: "Download this file?",
                    name: displayName,
                    subtitle: url.host ?? url.absoluteString,
                    icon: "arrow.down.doc.fill",
                    tint: .blue,
                    onSave: { [weak self] folder in
                        self?.startBrowserFileDownload(url: url, filename: filename, headers: headers,
                                                       folder: folder)
                    },
                    onCancel: { [weak self] in self?.recentCaptures[captureKey] = nil }
                )
                present(prompt)
            }

        case "addbatch":
            // downloadmanager://addbatch?file=<json written by the browser helper>
            guard let path = components?.queryItems?.first(where: { $0.name == "file" })?.value,
                  let batch = LinkBatch.load(from: URL(fileURLWithPath: path)) else { return }
            suppressMainWindowForBrowserCapture()
            BatchLinksController.shared.present(batch)

        case "snapshot":
            for (index, window) in NSApp.windows.enumerated() {
                guard let view = window.contentView, view.bounds.width > 100,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                guard let data = rep.representation(using: .png, properties: [:]) else { continue }
                let suffix = window.title == "Downix Download Manager" ? "main" : "window-\(index)"
                try? data.write(to: URL(fileURLWithPath: "/tmp/rdm-\(suffix).png"))
            }

        case "queue":
            // downloadmanager://queue?action=pause
            if let action = components?.queryItems?.first(where: { $0.name == "action" })?.value {
                NotificationCenter.default.post(
                    name: .queueAction,
                    object: nil,
                    userInfo: ["action": action]
                )
            }
            
        default:
            break
        }
    }
    
    private func checkForUpdates() {
        // Placeholder for update checking logic
        // Could integrate with Sparkle or custom update mechanism
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let showMainWindow = Notification.Name("showMainWindow")
    static let showAddDownload = Notification.Name("showAddDownload")
    static let addFromClipboard = Notification.Name("addFromClipboard")
    static let importURLs = Notification.Name("importURLs")
    static let showStatistics = Notification.Name("showStatistics")
    static let showScheduler = Notification.Name("showScheduler")
    static let addDownloadFromURL = Notification.Name("addDownloadFromURL")
    static let videoDownloadStarted = Notification.Name("videoDownloadStarted")
    static let queueAction = Notification.Name("queueAction")
}
