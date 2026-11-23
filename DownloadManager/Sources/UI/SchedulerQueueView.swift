//
//  SchedulerQueueView.swift
//  Download Manager for Mac
//
//  IDM-style scheduler queue manager.
//  Left sidebar: named queues with enable toggles.
//  Right panel: downloads assigned to the selected queue.
//  Per-queue: schedule window, speed limit, concurrency, post-completion action.
//

import SwiftUI

// MARK: - Root View

struct SchedulerQueueView: View {
    @ObservedObject private var queueManager = SchedulerQueueManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    @State private var selectedQueueID: UUID?
    @State private var showingAddQueue = false
    @State private var editingQueue: SchedulerQueue?
    @State private var queueToDelete: SchedulerQueue?
    @State private var showingDeleteConfirm = false

    var selectedQueue: SchedulerQueue? {
        queueManager.queues.first { $0.id == selectedQueueID }
    }

    var body: some View {
        HSplitView {
            SchedulerQueueSidebarView(
                queueManager: queueManager,
                selectedQueueID: $selectedQueueID,
                onAddQueue: { showingAddQueue = true },
                onEditQueue: { editingQueue = $0 },
                onDeleteQueue: { queueToDelete = $0; showingDeleteConfirm = true }
            )
            .frame(minWidth: 230, idealWidth: 250, maxWidth: 300)

            if let queue = selectedQueue {
                QueueDetailView(
                    queue: queue,
                    downloadManager: downloadManager,
                    queueManager: queueManager,
                    onEditQueue: { editingQueue = queue }
                )
            } else {
                NoQueueSelectedView(onAdd: { showingAddQueue = true })
            }
        }
        .sheet(isPresented: $showingAddQueue) {
            QueueEditSheet(queue: nil) { newQueue in
                let created = queueManager.addQueue(newQueue)
                selectedQueueID = created.id
            }
        }
        .sheet(item: $editingQueue) { queue in
            QueueEditSheet(queue: queue) { updated in
                queueManager.updateQueue(updated)
            }
        }
        .confirmationDialog(
            "Delete \"\(queueToDelete?.name ?? "Queue")\"?",
            isPresented: $showingDeleteConfirm,
            presenting: queueToDelete
        ) { q in
            Button("Delete Queue", role: .destructive) {
                queueManager.deleteQueue(q)
                if selectedQueueID == q.id {
                    selectedQueueID = queueManager.queues.first?.id
                }
            }
        } message: { q in
            Text("Downloads assigned to \"\(q.name)\" will not be deleted — only unassigned from this queue.")
        }
        .onAppear {
            if selectedQueueID == nil {
                selectedQueueID = queueManager.queues.first?.id
            }
        }
    }
}

// MARK: - Sidebar

struct SchedulerQueueSidebarView: View {
    @ObservedObject var queueManager: SchedulerQueueManager
    @Binding var selectedQueueID: UUID?

    let onAddQueue: () -> Void
    let onEditQueue: (SchedulerQueue) -> Void
    let onDeleteQueue: (SchedulerQueue) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Queues")
                    .font(.headline)
                    .padding(.leading, 4)
                Spacer()
                Button { onAddQueue() } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .help("New Queue")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Queue list
            List(selection: $selectedQueueID) {
                ForEach(queueManager.queues) { queue in
                    SchedulerSidebarQueueRow(queue: queue, queueManager: queueManager)
                        .tag(queue.id)
                        .contextMenu {
                            Button("Edit Queue…") { onEditQueue(queue) }
                            Button("Duplicate") { duplicateQueue(queue) }
                            Divider()
                            Button("Delete Queue", role: .destructive) {
                                onDeleteQueue(queue)
                            }
                        }
                }
                .onMove { src, dst in
                    queueManager.moveQueues(fromOffsets: src, toOffset: dst)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom toolbar
            HStack(spacing: 2) {
                ToolbarIconButton(systemImage: "plus", help: "New Queue", action: onAddQueue)
                ToolbarIconButton(systemImage: "minus", help: "Delete Queue") {
                    if let q = queueManager.queues.first(where: { $0.id == selectedQueueID }) {
                        onDeleteQueue(q)
                    }
                }
                .disabled(selectedQueueID == nil)

                Divider().frame(height: 16).padding(.horizontal, 4)

                ToolbarIconButton(systemImage: "pencil", help: "Edit Queue") {
                    if let q = queueManager.queues.first(where: { $0.id == selectedQueueID }) {
                        onEditQueue(q)
                    }
                }
                .disabled(selectedQueueID == nil)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func duplicateQueue(_ source: SchedulerQueue) {
        var copy = SchedulerQueue(name: "\(source.name) Copy", colorHex: source.colorHex)
        copy.isScheduleEnabled = source.isScheduleEnabled
        copy.startTime = source.startTime
        copy.stopTime = source.stopTime
        copy.weekdays = source.weekdays
        copy.maxSimultaneousDownloads = source.maxSimultaneousDownloads
        copy.bandwidthLimitBytesPerSec = source.bandwidthLimitBytesPerSec
        copy.postQueueAction = source.postQueueAction
        queueManager.addQueue(copy)
    }
}

struct SchedulerSidebarQueueRow: View {
    let queue: SchedulerQueue
    @ObservedObject var queueManager: SchedulerQueueManager

    var stats: SchedulerQueueManager.QueueStats {
        queueManager.stats(for: queue)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Color dot
            Circle()
                .fill(Color(hexString: queue.colorHex))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(queue.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(stats.totalDownloads) download\(stats.totalDownloads == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if stats.activeDownloads > 0 {
                        Text("• \(stats.activeDownloads) active")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            // Status indicator
            if !queue.isEnabled {
                Image(systemName: "pause.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if queue.isInScheduleWindow() {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
            } else if queue.isScheduleEnabled {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Detail View

struct QueueDetailView: View {
    let queue: SchedulerQueue
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var queueManager: SchedulerQueueManager
    let onEditQueue: () -> Void

    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var showingMoveSheet = false
    @State private var moveTargetQueueID: UUID?

    var queueTasks: [DownloadTask] {
        queue.taskIDs.compactMap { id in
            downloadManager.downloadTasks.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            scheduleInfoBanner
            Divider()

            if queueTasks.isEmpty {
                EmptyQueueDetailView()
            } else {
                downloadsTable
            }

            Divider()
            detailFooter
        }
    }

    // MARK: Header

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hexString: queue.colorHex))
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(queue.name)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 12) {
                    Label(
                        "\(queue.maxSimultaneousDownloads) concurrent",
                        systemImage: "arrow.down.to.line.alt"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Label(queue.formattedBandwidth, systemImage: "speedometer")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if queue.postQueueAction != .none {
                        Label(queue.postQueueAction.rawValue,
                              systemImage: queue.postQueueAction.icon)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Actions toolbar
            HStack(spacing: 8) {
                // Start/Pause queue
                Button {
                    var updated = queue
                    updated.isPaused = !queue.isPaused
                    queueManager.updateQueue(updated)
                } label: {
                    Label(
                        queue.isPaused ? "Resume Queue" : "Pause Queue",
                        systemImage: queue.isPaused ? "play.circle.fill" : "pause.circle.fill"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(queue.isPaused ? "Resume all downloads in this queue" : "Pause all downloads in this queue")

                Button { onEditQueue() } label: {
                    Label("Edit Queue", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Enable toggle
            Toggle(isOn: Binding(
                get: { queue.isEnabled },
                set: { enabled in
                    var updated = queue
                    updated.isEnabled = enabled
                    queueManager.updateQueue(updated)
                }
            )) {
                Text("Enabled")
                    .font(.caption)
            }
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Schedule info banner

    @ViewBuilder
    private var scheduleInfoBanner: some View {
        if queue.isScheduleEnabled {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(queue.isInScheduleWindow() ? .green : .orange)

                Text(queue.isInScheduleWindow()
                     ? "Schedule active — download window: \(queue.scheduleTimeRange)"
                     : "Outside schedule window (\(queue.scheduleTimeRange)) — downloads will be paused"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                // Weekday pills
                HStack(spacing: 3) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Text(day.shortName)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                queue.weekdays.contains(day)
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15)
                            )
                            .foregroundColor(
                                queue.weekdays.contains(day) ? .white : .secondary
                            )
                            .cornerRadius(3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                queue.isInScheduleWindow()
                    ? Color.green.opacity(0.07)
                    : Color.orange.opacity(0.07)
            )
        }
    }

    // MARK: Downloads table

    private var downloadsTable: some View {
        VStack(spacing: 0) {
            // Selection toolbar
            if !selectedTaskIDs.isEmpty {
                HStack(spacing: 12) {
                    Text("\(selectedTaskIDs.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Menu("Move to Queue…") {
                        ForEach(queueManager.queues.filter { $0.id != queue.id }) { other in
                            Button(other.name) {
                                for id in selectedTaskIDs {
                                    queueManager.moveTask(id, toQueue: other.id)
                                }
                                selectedTaskIDs = []
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Button {
                        for id in selectedTaskIDs {
                            queueManager.removeTask(id, fromQueue: queue.id)
                        }
                        selectedTaskIDs = []
                    } label: {
                        Label("Remove from Queue", systemImage: "minus.circle")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.07))

                Divider()
            }

            // Column headers
            HStack {
                Text("Filename").frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                Text("Status").frame(width: 90, alignment: .leading)
                Text("Progress").frame(width: 110, alignment: .leading)
                Text("Speed").frame(width: 78, alignment: .trailing)
                Text("Size").frame(width: 78, alignment: .trailing)
                Text("After").frame(width: 60, alignment: .center)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List(queueTasks, selection: $selectedTaskIDs) { task in
                QueueTaskRow(task: task, queue: queue, queueManager: queueManager)
                    .tag(task.id)
            }
            .listStyle(.inset)
        }
    }

    // MARK: Footer

    private var detailFooter: some View {
        let stats = queueManager.stats(for: queue)
        return HStack(spacing: 16) {
            Text("\(stats.totalDownloads) total")
                .font(.caption)
                .foregroundColor(.secondary)

            if stats.activeDownloads > 0 {
                Label("\(stats.activeDownloads) active", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            if stats.completedDownloads > 0 {
                Label("\(stats.completedDownloads) done", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            if stats.failedDownloads > 0 {
                Label("\(stats.failedDownloads) failed", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Task Row

struct QueueTaskRow: View {
    @ObservedObject var task: DownloadTask
    let queue: SchedulerQueue
    @ObservedObject var queueManager: SchedulerQueueManager

    var body: some View {
        HStack {
            // Filename + state icon
            HStack(spacing: 6) {
                Image(systemName: task.state.queueIcon)
                    .foregroundColor(task.state.queueColor)
                    .frame(width: 16)

                Text(task.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)

            // Status label
            Text(task.state.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(task.state.queueColor)
                .frame(width: 90, alignment: .leading)

            // Progress bar
            Group {
                if task.state == .downloading || task.state == .paused {
                    HStack(spacing: 4) {
                        ProgressView(value: task.progress)
                            .progressViewStyle(.linear)
                            .frame(width: 68)
                        Text(String(format: "%.0f%%", task.progress * 100))
                            .font(.caption2)
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                } else {
                    Text(task.state == .completed ? "100%" : "—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 110, alignment: .leading)

            // Speed
            Text(task.state == .downloading ? task.formattedSpeed : "—")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .trailing)

            // File size
            Text(task.totalBytes > 0
                    ? ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file)
                    : "—")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .trailing)

            // Per-download post-action
            Group {
                if let action = task.postDownloadAction, action != .none {
                    Image(systemName: action.icon)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .help("After completion: \(action.rawValue)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 60, alignment: .center)
        }
        .padding(.vertical, 2)
        .contextMenu {
            queueContextMenu
        }
    }

    @ViewBuilder
    private var queueContextMenu: some View {
        // Move to queue submenu
        Menu("Move to Queue") {
            ForEach(queueManager.queues.filter { $0.id != queue.id }) { other in
                Button(other.name) {
                    queueManager.moveTask(task.id, toQueue: other.id)
                }
            }
        }

        Button("Remove from Queue") {
            queueManager.removeTask(task.id, fromQueue: queue.id)
        }

        Divider()

        // After-completion action submenu
        Menu("After This Download…") {
            ForEach(PostDownloadAction.macCases, id: \.self) { action in
                Button {
                    task.postDownloadAction = action
                } label: {
                    Label(action.rawValue, systemImage: action.icon)
                }
            }
        }

        Divider()

        Button("Pause") {
            Task { await DownloadManager.shared.pauseDownload(task) }
        }
        .disabled(task.state != .downloading)

        Button("Resume") {
            Task { await DownloadManager.shared.resumeDownload(task) }
        }
        .disabled(task.state != .paused)

        Button("Cancel", role: .destructive) {
            Task { await DownloadManager.shared.cancelDownload(task) }
        }
        .disabled(task.state == .completed || task.state == .cancelled)
    }
}

// MARK: - Queue Edit Sheet

struct QueueEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    var queue: SchedulerQueue?
    let onSave: (SchedulerQueue) -> Void

    // General
    @State private var name: String = ""
    @State private var colorHex: String = "#007AFF"
    @State private var maxSimultaneous: Int = 3

    // Schedule
    @State private var isScheduleEnabled: Bool = false
    @State private var startTime: Date = Calendar.current.date(bySettingHour: 9,  minute: 0, second: 0, of: Date()) ?? Date()
    @State private var stopTime:  Date = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekdays: Set<Weekday> = Set(Weekday.allCases)

    // Speed
    @State private var limitSpeed: Bool = false
    @State private var speedKBps: Double = 1024

    // Completion
    @State private var postAction: PostDownloadAction = .none

    private var isEditing: Bool { queue != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private let accentColors: [(label: String, hex: String)] = [
        ("Blue",   "#007AFF"),
        ("Green",  "#34C759"),
        ("Orange", "#FF9500"),
        ("Red",    "#FF3B30"),
        ("Purple", "#AF52DE"),
        ("Pink",   "#FF2D55"),
        ("Teal",   "#5AC8FA"),
        ("Yellow", "#FFCC00"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(isEditing ? "Edit Queue" : "New Queue")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            Form {
                // ── General ──────────────────────────────────────────
                Section("General") {
                    LabeledContent("Name") {
                        TextField("Queue name", text: $name)
                    }

                    LabeledContent("Color") {
                        colorPicker
                    }

                    Stepper(
                        "Max simultaneous downloads: \(maxSimultaneous)",
                        value: $maxSimultaneous,
                        in: 1...16
                    )
                }

                // ── Schedule ─────────────────────────────────────────
                Section {
                    Toggle("Enable schedule window", isOn: $isScheduleEnabled)

                    if isScheduleEnabled {
                        DatePicker(
                            "Start time",
                            selection: $startTime,
                            displayedComponents: .hourAndMinute
                        )

                        DatePicker(
                            "Stop time",
                            selection: $stopTime,
                            displayedComponents: .hourAndMinute
                        )

                        LabeledContent("Active days") {
                            HStack(spacing: 4) {
                                ForEach(Weekday.allCases, id: \.self) { day in
                                    Toggle(day.shortName, isOn: Binding(
                                        get: { weekdays.contains(day) },
                                        set: { on in
                                            if on { weekdays.insert(day) }
                                            else  { weekdays.remove(day) }
                                        }
                                    ))
                                    .toggleStyle(.button)
                                    .controlSize(.small)
                                }
                            }
                        }

                        Label(
                            "Downloads will automatically pause outside the defined window.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Schedule")
                }

                // ── Speed limit ───────────────────────────────────────
                Section("Speed Limit") {
                    Toggle("Limit download speed for this queue", isOn: $limitSpeed)

                    if limitSpeed {
                        HStack {
                            Slider(value: $speedKBps, in: 64...102400, step: 64) {
                                Text("Speed")
                            }
                            Text("\(Int(speedKBps)) KB/s")
                                .frame(width: 100)
                                .monospacedDigit()
                        }

                        Label(
                            "Approximately \(ByteCountFormatter.string(fromByteCount: Int64(speedKBps * 1024), countStyle: .file))/s",
                            systemImage: "speedometer"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                // ── Post-queue completion ─────────────────────────────
                Section("When Queue Completes") {
                    Picker("Action", selection: $postAction) {
                        ForEach(PostDownloadAction.macCases, id: \.self) { action in
                            Label(action.rawValue, systemImage: action.icon).tag(action)
                        }
                    }
                    .pickerStyle(.menu)

                    if postAction != .none {
                        Label(
                            "\(postAction.rawValue) will be executed automatically when every download in this queue finishes.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save Changes" : "Create Queue") {
                    saveQueue()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 540, height: 660)
        .onAppear { loadFields() }
    }

    private var colorPicker: some View {
        HStack(spacing: 6) {
            ForEach(accentColors, id: \.hex) { item in
                Button {
                    colorHex = item.hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hexString: item.hex))
                            .frame(width: 22, height: 22)
                        if colorHex == item.hex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(item.label)
            }
        }
    }

    private func loadFields() {
        guard let q = queue else { return }
        name = q.name
        colorHex = q.colorHex
        maxSimultaneous = q.maxSimultaneousDownloads
        isScheduleEnabled = q.isScheduleEnabled
        startTime = q.startTime
        stopTime  = q.stopTime
        weekdays  = q.weekdays
        if let bw = q.bandwidthLimitBytesPerSec {
            limitSpeed = true
            speedKBps  = Double(bw / 1024)
        }
        postAction = q.postQueueAction
    }

    private func saveQueue() {
        var q = queue ?? SchedulerQueue(name: name, colorHex: colorHex)
        q.name                    = name.trimmingCharacters(in: .whitespaces)
        q.colorHex                = colorHex
        q.maxSimultaneousDownloads = maxSimultaneous
        q.isScheduleEnabled       = isScheduleEnabled
        q.startTime               = startTime
        q.stopTime                = stopTime
        q.weekdays                = weekdays
        q.bandwidthLimitBytesPerSec = limitSpeed ? Int64(speedKBps * 1024) : nil
        q.postQueueAction         = postAction
        onSave(q)
        dismiss()
    }
}

// MARK: - Empty / placeholder views

struct NoQueueSelectedView: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 56))
                .foregroundColor(.secondary)

            Text("No Queue Selected")
                .font(.title2.weight(.semibold))

            Text("Select a queue from the sidebar, or create a new one to organise your downloads.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Create New Queue", action: onAdd)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyQueueDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Queue is Empty")
                .font(.headline)

            Text("Assign downloads to this queue from the Add Download dialog or by right-clicking an existing download in the main list.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small helper views

struct ToolbarIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - DownloadState display helpers

extension DownloadState {
    var queueIcon: String {
        switch self {
        case .waiting:     return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused:      return "pause.circle.fill"
        case .completed:   return "checkmark.circle.fill"
        case .failed:      return "exclamationmark.circle.fill"
        case .cancelled:   return "xmark.circle.fill"
        }
    }

    var queueColor: Color {
        switch self {
        case .waiting:     return .secondary
        case .downloading: return .blue
        case .paused:      return .orange
        case .completed:   return .green
        case .failed:      return .red
        case .cancelled:   return .secondary
        }
    }
}

// MARK: - Color(hexString:) helper

extension Color {
    /// Initialise from a hex string like "#FF3B30" or "FF3B30".
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16,        int >> 8 & 0xFF,        int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 122, 255) // fallback: system blue
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
