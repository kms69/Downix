//
//  QueueSchedulerWindow.swift
//  Download Manager for Mac
//
//  IDM-style "Scheduler" window: pick a queue, set "Start download at" /
//  "Stop download at", choose what happens when the queue finishes, and
//  Start Now / Stop the queue by hand.
//

import SwiftUI
import AppKit

// MARK: - Window controller

@MainActor
final class QueueSchedulerWindowController: NSWindowController {
    private static var shared: QueueSchedulerWindowController?

    static func show() {
        if let existing = shared, let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scheduler"          // keeps it out of AppDelegate's main-window hiding
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: QueueSchedulerView())
        window.minSize = NSSize(width: 680, height: 460)
        window.center()
        let controller = QueueSchedulerWindowController(window: window)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - View

struct QueueSchedulerView: View {
    @ObservedObject private var queueManager = SchedulerQueueManager.shared
    @ObservedObject private var controller = QueueRunController.shared
    @ObservedObject private var downloads = DownloadManager.shared

    @State private var selectedID: UUID?
    @State private var startEnabled = false
    @State private var startAt = Date().addingTimeInterval(3600)
    @State private var stopEnabled = false
    @State private var stopAt = Date().addingTimeInterval(3600 * 8)
    @State private var turnOff = false
    @State private var sleepWhenDone = false
    @State private var showingNewQueue = false
    @State private var newQueueName = ""
    @State private var now = Date()
    @State private var showingAddFiles = false
    @State private var selectedFiles = Set<UUID>()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var selected: SchedulerQueue? {
        guard let id = selectedID else { return nil }
        return queueManager.queues.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 190, idealWidth: 210, maxWidth: 260)
            detail.frame(minWidth: 460)
        }
        .onAppear {
            if selectedID == nil { selectedID = controller.defaultQueue?.id }
            loadDraft()
        }
        .onChange(of: selectedID) { _ in loadDraft() }
        .onReceive(clock) { now = $0 }
        .sheet(isPresented: $showingAddFiles) {
            if let q = selected { AddFilesToQueueSheet(queueID: q.id, queueName: q.name) }
        }
        .alert("New Queue", isPresented: $showingNewQueue) {
            TextField("Queue name", text: $newQueueName)
            Button("Create") {
                let name = newQueueName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let q = queueManager.addQueue(SchedulerQueue(name: name, colorHex: "#34C759"))
                    selectedID = q.id
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(queueManager.queues) { q in
                    HStack(spacing: 6) {
                        Image(systemName: q.name == QueueRunController.mainQueueName ? "tray.full.fill" : "tray.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(q.name).lineLimit(1)
                            Text(statusText(for: q))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(q.id)
                }
            }
            Divider()
            HStack {
                Button { newQueueName = ""; showingNewQueue = true } label: { Image(systemName: "plus") }
                Button {
                    if let q = selected, q.name != QueueRunController.mainQueueName {
                        queueManager.deleteQueue(q)
                        selectedID = controller.defaultQueue?.id
                    }
                } label: { Image(systemName: "minus") }
                .disabled(selected == nil || selected?.name == QueueRunController.mainQueueName)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let q = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(q.name).font(.title2.weight(.semibold))
                        Spacer()
                        Text(statusText(for: q))
                            .font(.callout).foregroundStyle(.secondary)
                    }

                    GroupBox("Schedule") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Toggle("Start download at", isOn: $startEnabled)
                                    .frame(width: 150, alignment: .leading)
                                DatePicker("", selection: $startAt, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden().disabled(!startEnabled)
                            }
                            HStack {
                                Toggle("Stop download at", isOn: $stopEnabled)
                                    .frame(width: 150, alignment: .leading)
                                DatePicker("", selection: $stopAt, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden().disabled(!stopEnabled)
                            }
                            Text("The queue processes its files once; finished files leave the queue.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let problem = validationMessage {
                                Label(problem, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .padding(6)
                    }

                    GroupBox("Downloading") {
                        VStack(alignment: .leading, spacing: 6) {
                            let limit = limitBinding(q)
                            HStack(spacing: 12) {
                                Text("Simultaneous downloads:")
                                HStack(spacing: 0) {
                                    Button { limit.wrappedValue -= 1 } label: {
                                        Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                                            .frame(width: 30, height: 26).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(limit.wrappedValue <= 1)
                                    .help("One file less at a time")
                                    Divider().frame(height: 16)
                                    Text("\(limit.wrappedValue)")
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .frame(width: 44)
                                    Divider().frame(height: 16)
                                    Button { limit.wrappedValue += 1 } label: {
                                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                                            .frame(width: 30, height: 26).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(limit.wrappedValue >= 16)
                                    .help("One more file at a time")
                                }
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.secondary.opacity(0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.secondary.opacity(0.35)))
                                Spacer()
                            }
                            Text("Applies to this queue only. The other files wait their turn, in the order shown below.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(6)
                    }

                    GroupBox("When the queue finishes") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Turn off computer when done", isOn: Binding(
                                get: { turnOff },
                                set: { turnOff = $0; if $0 { sleepWhenDone = false } }))
                            Toggle("Sleep when done", isOn: Binding(
                                get: { sleepWhenDone },
                                set: { sleepWhenDone = $0; if $0 { turnOff = false } }))
                            Text("Runs only after the last file finishes. If you stop the queue yourself, nothing is turned off. Keep the Mac plugged in and the lid open for overnight runs.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(6)
                    }

                    HStack(spacing: 10) {
                        Button("Apply") { apply(q) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(validationMessage != nil)
                        Button("Start Now") { applyThenStartNow(q) }
                        Button("Stop") { controller.stopManually(queueID: q.id) }
                            .disabled(!(controller.isRunning(q) || controller.isWaitingForStart(q) || hasActiveFiles(q)))
                        Spacer()
                    }

                    filesSection(q)
                }
                .padding(20)
            }
        } else {
            Text("Select a queue").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func filesSection(_ q: SchedulerQueue) -> some View {
        let files = controller.members(of: q)
        return GroupBox {
            HStack {
                Text("Files in this queue (\(files.count))").font(.headline)
                Spacer()
                HStack(spacing: 2) {
                    arrowButton("arrow.up.to.line", "Move to top", q, .top)
                    arrowButton("arrow.up", "Move up", q, .up)
                    arrowButton("arrow.down", "Move down", q, .down)
                    arrowButton("arrow.down.to.line", "Move to bottom", q, .bottom)
                }
                Button { showingAddFiles = true } label: { Label("Add Downloads…", systemImage: "plus") }
            }
            .padding(.bottom, 4)
            if files.isEmpty {
                Text("No files. Downloads you add go to the Main Download Queue, or pick this queue in Add URL.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            } else {
                VStack(spacing: 0) {
                    ForEach(files) { task in
                        QueueFileRow(task: task) { controller.remove(task.id, from: q.id) }
                            .background(selectedFiles.contains(task.id) ? Color.accentColor.opacity(0.18) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedFiles.contains(task.id) { selectedFiles.remove(task.id) }
                                else { selectedFiles.insert(task.id) }
                            }
                        Divider()
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }

    // MARK: Logic

    /// Saves the limit as soon as the stepper changes and lets waiting files start.
    private func limitBinding(_ q: SchedulerQueue) -> Binding<Int> {
        Binding(
            get: { queueManager.queues.first { $0.id == q.id }?.maxSimultaneousDownloads ?? 3 },
            set: { value in
                guard var fresh = queueManager.queues.first(where: { $0.id == q.id }) else { return }
                fresh.maxSimultaneousDownloads = max(1, min(16, value))
                queueManager.updateQueue(fresh)
                DownloadManager.shared.processQueue()
            })
    }

    /// One of the Top / Up / Down / Bottom buttons for the files ticked in the list.
    private func arrowButton(_ icon: String, _ help: String, _ q: SchedulerQueue,
                             _ direction: SchedulerQueueManager.MoveDirection) -> some View {
        Button {
            queueManager.move(selectedFiles, in: q.id, direction)
            downloads.objectWillChange.send()
            downloads.processQueue()
        } label: { Image(systemName: icon).frame(width: 22, height: 20) }
        .buttonStyle(.borderless)
        .disabled(selectedFiles.isEmpty)
        .help(help + " (click files to select them)")
    }

    private func hasActiveFiles(_ q: SchedulerQueue) -> Bool {
        controller.members(of: q).contains { $0.state == .downloading || $0.state == .waiting }
    }

    private var validationMessage: String? {
        if startEnabled && startAt <= now.addingTimeInterval(-60) {
            return "Choose a start time in the future (or use Start Now)."
        }
        if stopEnabled {
            let reference = startEnabled ? startAt : now
            if stopAt <= reference { return "The stop time must be after the start time." }
        }
        return nil
    }

    private func loadDraft() {
        guard let q = selected else { return }
        startEnabled = (q.startAtEnabled == true)
        startAt = q.startAt ?? Date().addingTimeInterval(3600)
        stopEnabled = (q.stopAtEnabled == true)
        stopAt = q.stopAt ?? Date().addingTimeInterval(3600 * 8)
        turnOff = q.postQueueAction == .shutdown
        sleepWhenDone = q.postQueueAction == .sleep
    }

    private var chosenAction: PostDownloadAction {
        turnOff ? .shutdown : (sleepWhenDone ? .sleep : .none)
    }

    private func apply(_ q: SchedulerQueue) {
        controller.apply(queueID: q.id, startEnabled: startEnabled, startAt: startAt,
                         stopEnabled: stopEnabled, stopAt: stopAt, action: chosenAction)
    }

    private func applyThenStartNow(_ q: SchedulerQueue) {
        // Start Now ignores the start time, so the "start at" box is cleared.
        startEnabled = false
        apply(q)
        controller.startNow(queueID: q.id)
        loadDraft()
    }

    private func statusText(for q: SchedulerQueue) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        if controller.isWaitingForStart(q), let s = q.startAt { return "Starts \(f.string(from: s))" }
        if controller.isRunning(q) {
            if q.stopAtEnabled == true, let e = q.stopAt { return "Running · stops \(f.string(from: e))" }
            return "Running"
        }
        return "Idle"
    }
}

private struct QueueFileRow: View {
    @ObservedObject var task: DownloadTask
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(task.filename).lineLimit(1).truncationMode(.middle)
            Spacer()
            if task.state == .downloading {
                ProgressView(value: task.progress).frame(width: 90)
            }
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 78, alignment: .trailing)
            Button(action: onRemove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove from this queue")
        }
        .padding(.vertical, 5)
    }

    private var label: String {
        switch task.state {
        case .waiting: return "Queued"
        case .downloading: return "\(Int(task.progress * 100))%"
        case .paused: return "Paused"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Add downloads to a queue

private struct AddFilesToQueueSheet: View {
    let queueID: UUID
    let queueName: String
    @ObservedObject private var controller = QueueRunController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var picked = Set<UUID>()

    var body: some View {
        let candidates = controller.addableDownloads(for: queueID)
        VStack(alignment: .leading, spacing: 12) {
            Text("Add downloads to \(queueName)").font(.headline)
            if candidates.isEmpty {
                Text("No other unfinished downloads. Add a new one with Add URL; it goes to the Main Download Queue.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(candidates) { task in
                    Toggle(isOn: Binding(
                        get: { picked.contains(task.id) },
                        set: { if $0 { picked.insert(task.id) } else { picked.remove(task.id) } })) {
                        Text(task.filename).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(minHeight: 200)
            }
            HStack {
                if !candidates.isEmpty {
                    Button("Select All") { picked = Set(candidates.map(\.id)) }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    controller.move(Array(picked), to: queueID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

// MARK: - "Move to Queue" context-menu item (main download list)

struct MoveToQueueMenu: View {
    let ids: [UUID]
    @ObservedObject private var queueManager = SchedulerQueueManager.shared

    var body: some View {
        Menu {
            ForEach(queueManager.queues) { q in
                Button(q.name) { QueueRunController.shared.move(ids, to: q.id) }
            }
        } label: {
            Label("Move to Queue", systemImage: "tray.and.arrow.down")
        }
    }
}
