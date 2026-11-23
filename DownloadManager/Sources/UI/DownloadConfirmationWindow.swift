//
//  DownloadConfirmationWindow.swift
//  Download Manager for Mac
//
//  IDM-style browser capture window. A grab never starts a transfer until the
//  user confirms here. The same centered panel then becomes the live progress
//  window (progress bar + Pause/Stop), so there is no second popup and the main
//  manager window is never involved.
//

import SwiftUI
import AppKit

/// Result of starting a confirmed capture, so the panel can adopt the new task.
enum StartedCapture {
    case file(DownloadTask)
    case video(VideoDownloadTask)
}

struct DownloadPrompt {
    let id = UUID()
    let title: String
    let name: String
    let subtitle: String
    let icon: String
    let tint: Color
    let onSave: (URL) -> StartedCapture?
    let onCancel: () -> Void
}

@MainActor
final class DownloadConfirmationController: NSObject {
    static let shared = DownloadConfirmationController()

    private final class Capture: NSObject, NSWindowDelegate {
        let prompt: DownloadPrompt
        let panel: NSPanel
        weak var owner: DownloadConfirmationController?
        var startedTaskID: UUID?

        init(prompt: DownloadPrompt, panel: NSPanel, owner: DownloadConfirmationController) {
            self.prompt = prompt
            self.panel = panel
            self.owner = owner
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool { true }

        func windowWillClose(_ notification: Notification) {
            owner?.captureDidClose(self)
        }
    }

    private var captures: [UUID: Capture] = [:]

    func enqueue(_ prompt: DownloadPrompt) {
        let panel = makePanel(cascade: captures.count)
        let capture = Capture(prompt: prompt, panel: panel, owner: self)
        captures[prompt.id] = capture
        panel.delegate = capture
        showConfirmation(capture)
        panel.orderFrontRegardless()
    }

    // MARK: Confirmation -> progress in the same window

    private func showConfirmation(_ capture: Capture) {
        let id = capture.prompt.id
        capture.panel.title = capture.prompt.title
        capture.panel.contentView = FirstMouseHostingView(rootView: DownloadConfirmationView(
            prompt: capture.prompt,
            onSave: { [weak self] folder in self?.save(id, folder: folder) },
            onCancel: { [weak self] in self?.cancel(id) }
        ))
    }

    private func save(_ id: UUID, folder: URL) {
        guard let capture = captures[id], capture.startedTaskID == nil else { return }
        guard let started = capture.prompt.onSave(folder) else {
            capture.panel.close()
            return
        }

        switch started {
        case .file(let task):
            capture.startedTaskID = task.id
            capture.panel.contentView = FirstMouseHostingView(rootView: DownloadProgressView(task: task) { [weak self] in
                self?.closePanel(id)
            })
            DownloadProgressWindowController.register(capture.panel, for: task.id)

        case .video(let task):
            capture.startedTaskID = task.id
            capture.panel.contentView = FirstMouseHostingView(rootView: VideoProgressView(task: task) { [weak self] in
                self?.closePanel(id)
            })
            DownloadProgressWindowController.register(capture.panel, for: task.id)
        }

        // The progress layout is shorter than the confirmation one; keep the
        // panel visually centred once SwiftUI has applied the new height.
        DownloadProgressWindowController.centerOnScreen(capture.panel)
        DispatchQueue.main.async {
            DownloadProgressWindowController.centerOnScreen(capture.panel)
        }
    }

    private func cancel(_ id: UUID) {
        guard let capture = captures[id], capture.startedTaskID == nil else { return }
        capture.panel.close()
    }

    private func closePanel(_ id: UUID) {
        captures[id]?.panel.close()
    }

    private func captureDidClose(_ capture: Capture) {
        captures.removeValue(forKey: capture.prompt.id)
        if let taskID = capture.startedTaskID {
            DownloadProgressWindowController.unregister(taskID)
        } else {
            // Closed before starting: nothing was created, so abort entirely.
            capture.prompt.onCancel()
        }
    }

    // MARK: Panel

    private func makePanel(cascade: Int) -> NSPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        FloatingWindowTheme.apply(to: panel)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Centered on screen. Extra captures cascade slightly instead of
        // covering each other exactly.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 - CGFloat(cascade) * 24
            ))
        } else {
            panel.center()
        }
        return panel
    }
}

private struct DownloadConfirmationView: View {
    let prompt: DownloadPrompt
    let onSave: (URL) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var folders = DownloadFolderStore.shared
    @State private var folder: URL = DownloadFolderStore.shared.resolvedDefault
    @State private var makeDefault = false

    private var st: IdmStyle { IdmStyle(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            // Title strip (the close button of the panel sits at the left)
            HStack(spacing: 8) {
                Spacer().frame(width: 52)
                IdmLogoBadge(size: 20)
                Text(prompt.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(st.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("Ready")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(st.sky.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(st.sky.opacity(0.3), lineWidth: 1))
                    .foregroundStyle(st.sky)
            }
            .padding(.trailing, 12)
            .frame(height: 34)
            .background(st.header)
            .overlay(Rectangle().fill(st.line).frame(height: 1), alignment: .bottom)

            VStack(spacing: 12) {
                // File card
                HStack(spacing: 11) {
                    Image(systemName: prompt.icon)
                        .font(.system(size: 22))
                        .foregroundColor(prompt.tint)
                        .frame(width: 42, height: 42)
                        .background(prompt.tint.opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(prompt.tint.opacity(0.28), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(prompt.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(st.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        HStack(spacing: 5) {
                            Text("GET")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(st.emeraldBase.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(st.emerald)
                            Text(prompt.subtitle)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(st.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(st.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(st.line, lineWidth: 1))

                // Destination row: pick any folder, or create a new one
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(st.amber)
                        Text("Save to").font(.system(size: 11.5)).foregroundStyle(st.muted)
                        Spacer(minLength: 6)
                        Menu {
                            ForEach(folders.choices, id: \.path) { url in
                                Button {
                                    folder = url
                                } label: {
                                    if url.path == folder.path {
                                        Label(DownloadFolderStore.display(url), systemImage: "checkmark")
                                    } else {
                                        Text(DownloadFolderStore.display(url))
                                    }
                                }
                            }
                            Divider()
                            Button("Choose Folder…") { chooseFolder() }
                            Button("New Folder…") { createFolder() }
                        } label: {
                            HStack(spacing: 5) {
                                Text(DownloadFolderStore.display(folder))
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .lineLimit(1).truncationMode(.head)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                            }
                            .foregroundStyle(st.text)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(st.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        Button { chooseFolder() } label: {
                            Text("Browse…").font(.system(size: 11, weight: .semibold)).foregroundStyle(st.text)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(st.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Toggle(isOn: $makeDefault) {
                        Text("Use this folder as the default for new downloads")
                            .font(.system(size: 10.5)).foregroundStyle(st.muted)
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(st.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(st.line, lineWidth: 1))

                Text("The transfer starts as soon as you click Start Download.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(st.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Spacer()
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(st.text)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(st.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button(action: save) {
                    Label("Start Download", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
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
        .frame(width: 420, height: 350)
        .background(st.window)
    }

    private func save() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if makeDefault { folders.setDefault(folder) } else { folders.remember(folder) }
        onSave(folder)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where to save"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true          // gives a "New Folder" button
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { folder = url }
    }

    private func createFolder() {
        let alert = NSAlert()
        alert.messageText = "New folder"
        alert.informativeText = "Created inside \(DownloadFolderStore.display(folder))"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = url
    }
}
