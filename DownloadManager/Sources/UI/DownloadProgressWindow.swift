//
//  DownloadProgressWindow.swift
//  Download Manager for Mac
//
//  Floating per-download progress window
//

import SwiftUI
import AppKit

// MARK: - Window Controller

class DownloadProgressWindowController: NSWindowController, NSWindowDelegate {

    static var openWindows: [UUID: NSWindowController] = [:]

    /// Open (or bring to front) a progress window for the given task.
    @MainActor
    static func open(for task: DownloadTask) {
        if let existing = openWindows[task.id] {
            centerOnScreen(existing.window)
            existing.window?.deminiaturize(nil)
            existing.window?.orderFrontRegardless()
            return
        }
        let controller = DownloadProgressWindowController(task: task)
        openWindows[task.id] = controller
        showCentered(controller)
    }

    @MainActor
    static func open(for task: VideoDownloadTask) {
        if let existing = openWindows[task.id] {
            centerOnScreen(existing.window)
            existing.window?.deminiaturize(nil)
            existing.window?.orderFrontRegardless()
            return
        }
        let controller = VideoProgressWindowController(task: task)
        openWindows[task.id] = controller
        showCentered(controller)
    }

    /// Show a new window and centre it again once SwiftUI has laid the content
    /// out (the hosting view can resize the window during the first display).
    @MainActor
    private static func showCentered(_ controller: NSWindowController) {
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        centerOnScreen(controller.window)
        DispatchQueue.main.async {
            centerOnScreen(controller.window)
        }
    }

    /// Floating windows always appear centred on the active screen.
    @MainActor
    static func centerOnScreen(_ window: NSWindow?) {
        guard let window else { return }
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                      y: visible.midY - size.height / 2))
    }

    private let task: DownloadTask

    @MainActor
    init(task: DownloadTask) {
        self.task = task

        let contentView = DownloadProgressView(task: task) {
            // Close via the registry so the window really disappears (Remove /
            // Close used to only drop the dictionary entry, leaving it on screen).
            DownloadProgressWindowController.close(for: task.id)
        }

        let hostingView = FirstMouseHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 300)

        let window = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = task.filename
        window.isReleasedWhenClosed = false
        DownloadProgressWindowController.centerOnScreen(window)
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        FloatingWindowTheme.apply(to: window)

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        DownloadProgressWindowController.openWindows.removeValue(forKey: task.id)
        return true
    }

    /// Dock-icon click: bring back any floating progress window that was
    /// minimized or hidden. Returns true when at least one was restored.
    /// True when at least one floating download window is open (it may be
    /// minimized, hidden, or just covered by other apps' windows).
    @MainActor
    static var hasHiddenWindows: Bool {
        DownloadCompleteWindowController.shared.hasPanels
            || openWindows.values.contains { $0.window != nil }
            || NSApp.windows.contains { $0 is NSPanel && $0.isMiniaturized }
    }

    /// Dock-icon click: bring every open floating download window to the
    /// front, un-minimizing it if needed. Returns true when there was one.
    @MainActor
    @discardableResult
    static func restoreHiddenWindows() -> Bool {
        var restored = false
        for controller in openWindows.values {
            guard let window = controller.window else { continue }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.orderFrontRegardless()
            restored = true
        }
        // Any other minimized window that is not the main manager window.
        for window in NSApp.windows where window.isMiniaturized && (window is NSPanel || window.level != .normal) {
            window.deminiaturize(nil)
            window.orderFrontRegardless()
            restored = true
        }
        if DownloadCompleteWindowController.shared.restorePanels() { restored = true }
        return restored
    }

    @MainActor
    static func hasOpenWindow(for taskId: UUID) -> Bool {
        openWindows[taskId] != nil
    }

    /// Close the compact progress window for one task and forget it.
    @MainActor
    static func close(for taskId: UUID) {
        guard let controller = openWindows.removeValue(forKey: taskId) else { return }
        controller.window?.close()
    }

    /// Adopt an existing panel (the unified capture window) as this task's
    /// progress window so completion dialogs and Close actions can find it.
    @MainActor
    static func register(_ window: NSWindow, for taskId: UUID) {
        openWindows[taskId] = NSWindowController(window: window)
    }

    @MainActor
    static func unregister(_ taskId: UUID) {
        openWindows.removeValue(forKey: taskId)
    }
}

// MARK: - Shared model

enum CompactDownloadStatus {
    case waiting
    case downloading
    case paused
    case converting
    case completed
    case failed
    case cancelled
}

protocol CompactDownloadTaskModel: ObservableObject {
    var compactID: UUID { get }
    var compactTitle: String { get }
    var compactSubtitle: String { get }
    var compactFileExtension: String { get }
    var compactStatus: CompactDownloadStatus { get }
    var compactStatusText: String { get }
    var compactProgress: Double { get }
    var compactSpeed: Int64 { get }
    var compactDownloadedBytes: Int64 { get }
    var compactTotalBytes: Int64 { get }
    var compactTimeRemaining: TimeInterval { get }
    var compactError: String? { get }
    var compactPostDownloadAction: PostDownloadAction { get set }
}

struct CompactDownloadActions {
    var pause: (() -> Void)?
    var stop: (() -> Void)?
    var resume: (() -> Void)?
    var cancel: (() -> Void)?
    var retry: (() -> Void)?
    var remove: (() -> Void)?
    var openFile: (() -> Void)?
    var showInFinder: (() -> Void)?
    var close: () -> Void
}

// MARK: - Shared progress view

struct CompactDownloadProgressView<Model: CompactDownloadTaskModel>: View {
    @ObservedObject var task: Model
    let actions: CompactDownloadActions

    @StateObject private var bandwidthManager = BandwidthManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    @State private var perLimitEnabled: Bool = false
    @State private var perLimitMBps: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            progressSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            speedLimitSection
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            postActionSection
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            actionSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 420)
        .background(theme.windowBackground)
        .onAppear(perform: loadPerDownloadLimit)
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(iconColor.opacity(0.22), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(task.compactTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(task.compactSubtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            statusBadge
        }
    }

    // MARK: Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.borderStrong)
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressBarColor)
                        .frame(width: max(0, geo.size.width * task.compactProgress), height: 10)
                        .animation(.linear(duration: 0.3), value: task.compactProgress)
                }
            }
            .frame(height: 10)

            HStack {
                Text(String(format: "%.1f%%", task.compactProgress * 100))
                    .font(.system(.callout, design: .monospaced))
                    .bold()
                    .foregroundColor(progressBarColor)

                Spacer()

                Text(bytesLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if task.compactStatus == .downloading {
                    Label(formatSpeed(task.compactSpeed), systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if task.compactStatus == .downloading && task.compactTimeRemaining > 0 {
                    Text("· \(formatETA(task.compactTimeRemaining))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = task.compactError, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(theme.danger)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Speed Limit

    private var speedLimitSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Speed limit:")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("", isOn: $perLimitEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.75)
                .onChange(of: perLimitEnabled) { _ in applyPerLimit() }

            if perLimitEnabled {
                HStack(spacing: 4) {
                    Slider(value: $perLimitMBps, in: 0.1...50.0, step: 0.1)
                        .frame(width: 120)
                        .onChange(of: perLimitMBps) { _ in applyPerLimit() }

                    Text(String(format: "%.1f MB/s", perLimitMBps))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70, alignment: .leading)
                }
            } else {
                Text("Unlimited")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: After Completion

    private var postActionSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "power")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("After all downloads:")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: postActionBinding) {
                ForEach(PostDownloadAction.compactCases, id: \.self) { action in
                    Label(action.rawValue, systemImage: action.icon).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 190)

            Spacer()
        }
    }

    private var postActionBinding: Binding<PostDownloadAction> {
        Binding(
            get: { task.compactPostDownloadAction },
            set: { task.compactPostDownloadAction = $0 }
        )
    }

    // MARK: Actions

    private var actionSection: some View {
        HStack(spacing: 8) {
            switch task.compactStatus {
            case .downloading:
                if let pause = actions.pause {
                    actionButton("Pause", icon: "pause.fill", color: .orange, action: pause)
                }
                if let stop = actions.stop {
                    actionButton("Stop", icon: "stop.fill", color: .red, action: stop)
                }

            case .paused:
                if let resume = actions.resume {
                    actionButton("Resume", icon: "play.fill", color: .green, action: resume)
                }
                if let cancel = actions.cancel {
                    actionButton("Cancel", icon: "xmark.circle.fill", color: .red, action: cancel)
                }

            case .waiting:
                if let cancel = actions.cancel {
                    actionButton("Cancel", icon: "xmark.circle.fill", color: .red, action: cancel)
                }

            case .converting:
                if let stop = actions.stop {
                    actionButton("Stop", icon: "stop.fill", color: .red, action: stop)
                }

            case .completed:
                if let openFile = actions.openFile {
                    actionButton("Open File", icon: "arrow.up.right.square.fill", color: .accentColor, action: openFile)
                }
                if let showInFinder = actions.showInFinder {
                    actionButton("Show in Finder", icon: "folder.fill", color: .secondary, action: showInFinder)
                }

            case .failed, .cancelled:
                if let retry = actions.retry {
                    actionButton("Retry", icon: "arrow.clockwise", color: .orange, action: retry)
                }
                if let remove = actions.remove {
                    actionButton("Remove", icon: "trash", color: .red, action: remove)
                }
            }

            Spacer()

            Button(action: actions.close) {
                Label("Close", systemImage: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Status Badge

    private var statusBadge: some View {
        Text(task.compactStatusText)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusBadgeColor.opacity(0.15))
            .foregroundColor(statusBadgeColor)
            .clipShape(Capsule())
    }

    // MARK: Helpers

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var progressBarColor: Color {
        switch task.compactStatus {
        case .completed: return .green
        case .failed, .cancelled: return .red
        case .paused: return .orange
        default: return .accentColor
        }
    }

    private var statusBadgeColor: Color {
        switch task.compactStatus {
        case .downloading: return .blue
        case .converting: return .purple
        case .completed: return .green
        case .failed, .cancelled: return .red
        case .paused: return .orange
        case .waiting: return .secondary
        }
    }

    private var fileIcon: String {
        switch task.compactFileExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": return "film.fill"
        case "mp3", "aac", "flac", "wav", "m4a", "ogg": return "music.note"
        case "zip", "rar", "7z", "gz", "tar": return "archivebox.fill"
        case "pdf": return "doc.richtext.fill"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo.fill"
        case "dmg", "pkg": return "opticaldisc.fill"
        default: return "arrow.down.circle.fill"
        }
    }

    private var iconColor: Color {
        switch task.compactFileExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": return .purple
        case "mp3", "aac", "flac", "wav", "m4a", "ogg": return .pink
        case "zip", "rar", "7z", "gz", "tar": return .orange
        case "pdf": return .red
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return .blue
        case "dmg", "pkg": return .gray
        default: return .accentColor
        }
    }

    private var bytesLabel: String {
        let down = ByteCountFormatter.string(fromByteCount: task.compactDownloadedBytes, countStyle: .file)
        if task.compactTotalBytes > 0 {
            let total = ByteCountFormatter.string(fromByteCount: task.compactTotalBytes, countStyle: .file)
            return "\(down) / \(total)"
        }
        return down
    }

    private func formatSpeed(_ bps: Int64) -> String {
        if bps <= 0 { return "—" }
        return ByteCountFormatter.string(fromByteCount: bps, countStyle: .file) + "/s"
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "" }
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }

    // MARK: Per-download limit persistence

    private func loadPerDownloadLimit() {
        if let limit = bandwidthManager.getDownloadLimit(task.compactID) {
            perLimitEnabled = limit.isEnabled
            perLimitMBps = limit.downloadSpeed > 0 ? Double(limit.downloadSpeed) / 1_000_000.0 : 1.0
        }
    }

    private func applyPerLimit() {
        let speedBytes = Int64(perLimitMBps * 1_000_000)
        let limit = BandwidthLimit(isEnabled: perLimitEnabled, downloadSpeed: speedBytes)
        bandwidthManager.setDownloadLimit(task.compactID, limit: limit)
    }
}

// MARK: - Regular download wrapper

struct DownloadProgressView: View {
    @ObservedObject var task: DownloadTask
    let onClose: () -> Void

    private var fileURL: URL {
        task.destinationPath.appendingPathComponent(task.filename)
    }

    var body: some View {
        IdmDownloadProgressView(
            task: task,
            actions: CompactDownloadActions(
                pause: {
                    Task { @MainActor in await DownloadManager.shared.pauseDownload(task) }
                },
                stop: {
                    Task { @MainActor in await DownloadManager.shared.stopDownload(task) }
                },
                resume: {
                    Task { @MainActor in await DownloadManager.shared.resumeDownload(task) }
                },
                cancel: {
                    Task { @MainActor in
                        await DownloadManager.shared.cancelDownload(task)
                        onClose()
                    }
                },
                retry: {
                    DownloadManager.shared.requeueDownload(task)
                },
                remove: {
                    Task { @MainActor in
                        await DownloadManager.shared.removeDownload(task)
                        onClose()
                    }
                },
                openFile: {
                    NSWorkspace.shared.open(fileURL)
                },
                showInFinder: {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                },
                close: onClose
            )
        )
    }
}

// MARK: - Model adapters

extension DownloadTask: CompactDownloadTaskModel {
    var compactID: UUID { id }
    var compactTitle: String { filename }
    var compactSubtitle: String { url.host ?? url.absoluteString }
    var compactFileExtension: String { (filename as NSString).pathExtension }
    var compactStatus: CompactDownloadStatus {
        switch state {
        case .waiting: return .waiting
        case .downloading: return .downloading
        case .paused: return .paused
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }
    var compactStatusText: String {
        switch state {
        case .waiting: return "Waiting"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    var compactProgress: Double { progress }
    var compactSpeed: Int64 { speed }
    var compactDownloadedBytes: Int64 { downloadedBytes }
    var compactTotalBytes: Int64 { totalBytes }
    var compactTimeRemaining: TimeInterval { timeRemaining }
    var compactError: String? { error?.localizedDescription }
    var compactPostDownloadAction: PostDownloadAction {
        get { postDownloadAction ?? .none }
        set {
            objectWillChange.send()   // postDownloadAction is not @Published; refresh the Picker
            postDownloadAction = newValue == .none ? nil : newValue
            PowerActionLog.log("On-completion set to \(newValue.rawValue) for \(filename)")
        }
    }
}
