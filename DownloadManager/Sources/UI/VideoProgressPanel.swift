//
//  VideoProgressPanel.swift
//  Download Manager for Mac
//

import SwiftUI
import AppKit

@MainActor
final class VideoProgressWindowController: NSWindowController, NSWindowDelegate {

    private let task: VideoDownloadTask

    @MainActor
    init(task: VideoDownloadTask) {
        self.task = task

        let contentView = VideoProgressView(task: task) {
            DownloadProgressWindowController.close(for: task.id)
        }

        let hostingView = FirstMouseHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 300)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.title = task.compactTitle
        panel.titlebarAppearsTransparent = false
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        FloatingWindowTheme.apply(to: panel)

        DownloadProgressWindowController.centerOnScreen(panel)

        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        DownloadProgressWindowController.openWindows.removeValue(forKey: task.id)
        return true
    }
}

struct VideoProgressView: View {
    @ObservedObject var task: VideoDownloadTask
    let onClose: () -> Void

    private var manager: VideoDownloadManager { .shared }

    var body: some View {
        IdmDownloadProgressView(
            task: task,
            actions: CompactDownloadActions(
                pause: {
                    manager.pauseDownload(task)
                },
                stop: {
                    manager.cancelDownload(task)
                },
                resume: {
                    manager.resumeDownload(task)
                },
                cancel: {
                    manager.cancelDownload(task)
                    manager.removeTask(task)
                    onClose()
                },
                retry: {
                    manager.retryDownload(task)
                },
                remove: {
                    manager.removeTask(task)
                    onClose()
                },
                openFile: {
                    let url = manager.outputURL(for: task)
                    if FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.open(url)
                    }
                },
                showInFinder: {
                    let url = manager.outputURL(for: task)
                    if FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                },
                close: onClose
            )
        )
    }
}

extension VideoDownloadTask: CompactDownloadTaskModel {
    var compactID: UUID { id }
    var compactTitle: String {
        if let t = metadata?.title, !t.isEmpty { return t }
        if let t = preferredTitle, !t.isEmpty { return t }
        return url.absoluteString
    }
    var compactSubtitle: String { url.host ?? url.absoluteString }
    var compactFileExtension: String {
        outputURL?.pathExtension ?? options.format.fileExtension
    }
    var compactStatus: CompactDownloadStatus {
        switch state {
        case .pending, .fetchingMetadata, .ready: return .waiting
        case .downloading: return .downloading
        case .paused: return .paused
        case .converting: return .converting
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }
    var compactStatusText: String { state.rawValue }
    var compactProgress: Double { progress }
    var compactSpeed: Int64 { speed }
    var compactDownloadedBytes: Int64 {
        downloadTask?.downloadedBytes ?? downloadedBytes
    }
    var compactTotalBytes: Int64 {
        downloadTask?.totalBytes ?? totalBytes
    }
    var compactTimeRemaining: TimeInterval { estimatedTimeRemaining ?? 0 }
    var compactError: String? { error }
    var compactPostDownloadAction: PostDownloadAction {
        get { postDownloadAction }
        set {
            postDownloadAction = newValue
            PowerActionLog.log("On-completion set to \(newValue.rawValue) for video \(compactTitle)")
        }
    }
}
