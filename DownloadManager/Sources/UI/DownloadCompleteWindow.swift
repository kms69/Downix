//
//  DownloadCompleteWindow.swift
//  Download Manager for Mac
//
//  IDM-style "Download Complete" dialog shown when a user-initiated download
//  finishes. Offers Open File / Open Folder, then closes the per-download
//  progress window so it does not linger on screen.
//

import SwiftUI
import AppKit

struct CompletedDownloadInfo: Identifiable {
    let id: UUID
    let filename: String
    let fileURL: URL
    let byteCount: Int64

    var folderURL: URL { fileURL.deletingLastPathComponent() }
}

@MainActor
final class DownloadCompleteWindowController: NSObject, NSWindowDelegate {
    static let shared = DownloadCompleteWindowController()

    /// One popup per finished download, all visible at the same time.
    private var panels: [UUID: NSPanel] = [:]
    private var infos: [UUID: CompletedDownloadInfo] = [:]

    var hasPanels: Bool { !panels.isEmpty }

    /// Dock-icon click: bring every open "Download Complete" popup to the front.
    @discardableResult
    func restorePanels() -> Bool {
        guard !panels.isEmpty else { return false }
        for panel in panels.values {
            if panel.isMiniaturized { panel.deminiaturize(nil) }
            panel.orderFrontRegardless()
        }
        return true
    }

    func present(for task: DownloadTask) {
        present(info: CompletedDownloadInfo(
            id: task.id,
            filename: task.filename,
            fileURL: task.destinationPath.appendingPathComponent(task.filename),
            byteCount: task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes
        ))
    }

    func present(info: CompletedDownloadInfo) {
        guard panels[info.id] == nil else { return }
        // The compact progress window has done its job; the dialog replaces it.
        DownloadProgressWindowController.close(for: info.id)

        let panel = makePanel(slot: panels.count)
        panel.appearance = ThemeManager.appearance(for: ThemeManager.shared.currentColorScheme)
        panels[info.id] = panel
        infos[info.id] = info
        panel.contentView = NSHostingView(rootView: DownloadCompleteView(
            info: info,
            onOpenFile: { [weak self] in self?.finish(info.id, open: .file) },
            onOpenFolder: { [weak self] in self?.finish(info.id, open: .folder) },
            onClose: { [weak self] in self?.finish(info.id, open: nil) }
        ).preferredColorScheme(ThemeManager.shared.currentColorScheme))
        panel.title = "Download Complete"
        panel.orderFrontRegardless()      // newest popup is always on top
    }

    private enum OpenTarget { case file, folder }

    private func finish(_ id: UUID, open target: OpenTarget?) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        let info = infos.removeValue(forKey: id)
        switch target {
        case .file:
            if let info { NSWorkspace.shared.open(info.fileURL) }
        case .folder:
            if let info { NSWorkspace.shared.activateFileViewerSelecting([info.fileURL]) }
        case nil:
            break
        }
        panel.delegate = nil
        panel.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let id = panels.first(where: { $0.value === sender })?.key {
            finish(id, open: nil)
        }
        return false
    }

    private func makePanel(slot: Int) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.title = "Download Complete"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.center()
        // Cascade so a new popup never hides the earlier ones.
        let step = CGFloat(slot % 8) * 30
        var origin = panel.frame.origin
        origin.x += step
        origin.y -= step
        panel.setFrameOrigin(origin)
        return panel
    }
}

private struct DownloadCompleteView: View {
    let info: CompletedDownloadInfo
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var st: IdmStyle { IdmStyle(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer().frame(width: 52)
                IdmLogoBadge(size: 20)
                Text("Download Complete")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(st.text)
                Spacer(minLength: 4)
                Text("100%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(st.emeraldBase.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(st.emeraldBase.opacity(0.3), lineWidth: 1))
                    .foregroundStyle(st.emerald)
            }
            .padding(.trailing, 12)
            .frame(height: 34)
            .background(st.header)
            .overlay(Rectangle().fill(st.line).frame(height: 1), alignment: .bottom)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(st.emerald)
                        .frame(width: 46, height: 46)
                        .background(st.emeraldBase.opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(st.emeraldBase.opacity(0.3), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.filename)
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(st.text)
                            .lineLimit(2).truncationMode(.middle)
                        Text(ByteCountFormatter.string(fromByteCount: info.byteCount, countStyle: .file))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(st.emerald)
                        Text(info.folderURL.path)
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(st.muted)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(st.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(st.line, lineWidth: 1))

                IdmProgressBar(fraction: 1, colors: st.barColors, height: 10, animated: false, track: st.track)
            }
            .padding(14)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Spacer()
                chip("Close", action: onClose).keyboardShortcut(.cancelAction)
                chip("Open Folder", action: onOpenFolder)
                Button(action: onOpenFile) {
                    Label("Open File", systemImage: "arrow.up.right.square.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(LinearGradient(colors: [Color(hexString: "#10b981"), Color(hexString: "#0d9488")],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color(hexString: "#10b981").opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(st.footer)
            .overlay(Rectangle().fill(st.line).frame(height: 1), alignment: .top)
        }
        .frame(width: 440, height: 220)
        .background(st.window)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(st.text)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(st.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
