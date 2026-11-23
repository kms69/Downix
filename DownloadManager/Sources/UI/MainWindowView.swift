import SwiftUI

/// Main window view with toolbar, sidebar, and download list
struct MainWindowView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var videoManager = VideoDownloadManager.shared
    @State private var selectedSidebarItem: SidebarItem = .all
    @State private var selectedQueueID: UUID? = nil
    @State private var showingAddDownload = false
    @State private var showingSettings = false
    @State private var columnSortOrder = DownloadSortStore.load()
    @State private var downloadSelection = Set<UUID>()
    @State private var searchText = ""
    @State private var removalRequest: RemovalRequest?

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedItem: $selectedSidebarItem, selectedQueueID: $selectedQueueID)
                .frame(width: 236)

            Rectangle()
                .fill(theme.border)
                .frame(width: 1)

            VStack(spacing: 0) {
                HyperHeaderView()

                ToolbarView(
                    showingAddDownload: $showingAddDownload,
                    selection: downloadSelection,
                    searchText: $searchText,
                    onStart: resumeSelection,
                    onStop: stopSelection,
                    onDelete: deleteSelection
                )

                // Download list
                if selectedSidebarItem == .videos {
                    VideoDownloadView()
                } else {
                    DownloadListView(
                        sidebarItem: selectedSidebarItem,
                        selection: $downloadSelection,
                        sortOrder: Binding(get: { columnSortOrder },
                                          set: { columnSortOrder = $0; DownloadSortStore.save($0) }),
                        searchText: searchText,
                        onRequestRemove: requestRemoval
                    )
                }

                // Bottom status bar
                StatusBarView()
            }
            .background { theme.windowBackground }
        }
        .frame(minWidth: 1080, minHeight: 620)
        .tint(theme.accent)
        .preferredColorScheme(themeManager.currentColorScheme)
        .navigationTitle("Downix Download Manager")
        .sheet(isPresented: $showingAddDownload) {
            AddDownloadView()
        }
        .sheet(item: $removalRequest) { request in
            RemoveDownloadsSheet(
                count: request.taskIDs.count,
                onCancel: { removalRequest = nil },
                onRemove: { deleteFile in
                    removalRequest = nil
                    performRemoval(ids: request.taskIDs, deleteFile: deleteFile)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddDownload)) { _ in
            showingAddDownload = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .addFromClipboard)) { _ in
            addFromClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importURLs)) { _ in
            importURLs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addDownloadFromURL)) { notification in
            if let urlString = notification.userInfo?["url"] as? String {
                let filename = notification.userInfo?["filename"] as? String
                var headers: [String: String] = [:]
                if let referer = notification.userInfo?["referer"] as? String { headers["Referer"] = referer }
                if let cookie = notification.userInfo?["cookie"] as? String { headers["Cookie"] = cookie }
                if let ua = notification.userInfo?["ua"] as? String { headers["User-Agent"] = ua }
                addDownload(from: urlString, filename: filename,
                            headers: headers, kind: notification.userInfo?["kind"] as? String)
            }
        }
        .onChange(of: selectedSidebarItem) { _ in
            downloadSelection.removeAll()
        }
        .onChange(of: selectedQueueID) { id in
            downloadSelection.removeAll()
            QueueSelection.shared.queueID = id
        }
    }

    /// Toolbar actions only ever touch the selected rows. With no selection
    /// they are disabled and these methods are intentionally no-ops.
    private func resumeSelection() {
        guard !downloadSelection.isEmpty else { return }
        Task { @MainActor in
            for id in downloadSelection {
                if let dl = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                    await downloadManager.resumeDownload(dl)
                }
            }
        }
    }

    private func stopSelection() {
        guard !downloadSelection.isEmpty else { return }
        Task { @MainActor in
            for id in downloadSelection {
                if let dl = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                    await downloadManager.stopDownload(dl)
                }
            }
        }
    }

    private func deleteSelection() {
        guard !downloadSelection.isEmpty else { return }
        requestRemoval(downloadSelection)
    }

    private func requestRemoval(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        removalRequest = RemovalRequest(taskIDs: ids)
    }

    private func performRemoval(ids: Set<UUID>, deleteFile: Bool) {
        downloadSelection.subtract(ids)
        Task { @MainActor in
            for id in ids {
                guard let task = downloadManager.downloadTasks.first(where: { $0.id == id }) else { continue }
                if let videoTaskID = task.videoTaskID,
                   let videoTask = videoManager.videoTasks.first(where: { $0.id == videoTaskID }) {
                    // Always remove the row exactly like plain "Remove", then delete files.
                    let url = videoManager.outputURL(for: videoTask)
                    videoManager.removeTask(videoTask)
                    if deleteFile { DownloadManager.deleteLeftovers(of: url) }
                } else if deleteFile {
                    await downloadManager.deleteFileAndRemove(task)
                } else {
                    await downloadManager.removeDownload(task)
                }
            }
        }
    }

    private func addFromClipboard() {
        // Check clipboard and start monitoring
        if let string = NSPasteboard.general.string(forType: .string),
           let url = URL(string: string), url.scheme != nil {
            addDownload(from: string)
        }
    }
    
    private func importURLs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a text file with URLs (one per line)"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    let result = BatchOperationManager.shared.importFromFile(at: url.path)
                    switch result {
                    case .success(let urls):
                        for urlString in urls {
                            if let downloadURL = URL(string: urlString) {
                                DownloadManager.shared.addDownload(url: downloadURL)
                            }
                        }
                    case .failure(let error):
                        print("Failed to import URLs: \(error)")
                    }
                }
            }
        }
    }
    
    private func addDownload(from urlString: String, filename: String? = nil,
                             headers: [String: String] = [:], kind: String? = nil) {
        guard let url = URL(string: urlString) else { return }

        // Route video pages / stream manifests to the video pipeline (yt-dlp),
        // direct files to the segment engine (with the browser's Referer / Cookie).
        let isVideoRequest = kind == "video" || VideoPlatform.detect(from: urlString) != .generic
        if isVideoRequest {
            Task { @MainActor in
                // Starts by itself as soon as the video info is fetched (no polling timeout).
                let task = VideoDownloadManager.shared.addAndStartDownload(
                    url: url, preferredTitle: filename, httpHeaders: headers)
                DownloadProgressWindowController.open(for: task)
            }
            return
        }

        Task { @MainActor in
            downloadManager.addDownload(url: url, destinationPath: nil, filename: filename, headers: headers)
        }
    }
}

// MARK: - HyperFetch-style header

private struct HyperHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var downloadManager = DownloadManager.shared

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    private var activeCount: Int {
        downloadManager.downloadTasks.filter { $0.status == .downloading }.count
    }

    private var totalSpeed: Double {
        downloadManager.downloadTasks
            .filter { $0.status == .downloading }
            .reduce(0) { $0 + Double($1.speed) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: DownixLogo.mark)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 52, height: 46)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text("Downix Download Manager")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                }
                Text("MULTI-THREAD DOWNLOAD ENGINE")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer(minLength: 10)

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(activeCount > 0 ? theme.success : theme.textTertiary)
                        .frame(width: 7, height: 7)
                        .shadow(color: (activeCount > 0 ? theme.success : .clear).opacity(0.7), radius: 4)
                    Text(activeCount > 0 ? "Engine Active" : "Engine Idle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(activeCount > 0 ? theme.success : theme.textSecondary)
                }

                Rectangle().fill(theme.borderStrong).frame(width: 1, height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.accent)
                    Text(activeCount > 0 ? formatSpeed(totalSpeed) : "0 MB/s")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                }

                Rectangle().fill(theme.borderStrong).frame(width: 1, height: 12)

                Text("\(activeCount) active")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.surfaceMuted.opacity(colorScheme == .dark ? 0.9 : 0.7),
                        in: Capsule())
            .overlay(Capsule().stroke(theme.border, lineWidth: 1))

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    themeManager.setAppearanceMode(colorScheme == .dark ? .light : .dark)
                }
            } label: {
                Image(systemName: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? theme.amber : theme.indigo)
                    .frame(width: 28, height: 28)
                    .background(theme.surfaceMuted.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(colorScheme == .dark ? "Switch to Day theme" : "Switch to Night theme")
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(theme.header)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }
}

// MARK: - Sidebar Item
enum SidebarItem: String, CaseIterable, Identifiable {
    case all = "All Downloads"
    case downloading = "Downloading"
    case completed = "Completed"
    case failed = "Failed"
    case scheduled = "Scheduled"
    case videos = "Video"
    case audio = "Music"
    case documents = "Documents"
    case archives = "Archives"
    case applications = "Programs"
    case others = "Other"
    case history = "History"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "tray.2"
        case .downloading: return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .scheduled: return "clock"
        case .videos: return "film"
        case .audio: return "music.note"
        case .documents: return "doc"
        case .archives: return "archivebox"
        case .applications: return "app"
        case .others: return "folder"
        case .history: return "clock.arrow.circlepath"
        }
    }
    
    var isQueue: Bool {
        switch self {
        case .all, .downloading, .completed, .failed, .scheduled:
            return true
        default:
            return false
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedItem: SidebarItem
    @Binding var selectedQueueID: UUID?
    @ObservedObject private var queueManager = SchedulerQueueManager.shared
    @ObservedObject private var queueRun = QueueRunController.shared
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var videoManager = VideoDownloadManager.shared
    @State private var diskFree: Int64 = 0
    @State private var diskTotal: Int64 = 0

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("LIBRARY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(theme.textTertiary)
                        Spacer()
                        Text("\(downloadManager.downloadTasks.count)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                    categoryRow(.all)
                    ForEach(categoryItems) { row($0) }

                    sectionHeader("TRANSFER STATUS")
                    ForEach(statusItems) { row($0) }

                    queuesSection

                    sectionHeader("SYNCHRONIZATION")
                    row(.history)

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            SidebarStatusCard(
                free: diskFree,
                total: diskTotal,
                speed: totalSpeed,
                active: activeCount
            )
            .padding(10)
        }
        .background(theme.sidebar)
        .onAppear(perform: loadDiskStats)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 5)
    }

    private func categoryRow(_ item: SidebarItem) -> some View {
        row(item)
    }

    private func row(_ item: SidebarItem) -> some View {
        let isSelected = selectedItem == item && selectedQueueID == nil
        let tint = accentColor(for: item)
        return Button {
            selectedQueueID = nil
            selectedItem = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? theme.accent : tint)
                    .frame(width: 18)

                Text(item.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let count = itemCount(for: item), count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? theme.accent : theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            (isSelected ? theme.accent.opacity(0.15) : theme.surfaceMuted.opacity(0.75)),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.selectedRow)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.accent)
                                .frame(width: 2.5, height: 16)
                                .padding(.leading, 1)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Queues (IDM-style: every queue is listed and opens its files)

    @ViewBuilder
    private var queuesSection: some View {
        HStack {
            Text("QUEUES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(theme.textTertiary)
            Spacer()
            Button {
                QueueSchedulerWindowController.show()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Create or schedule queues")
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 5)

        ForEach(queueManager.queues) { queue in
            queueRow(queue)
        }
    }

    private func queueRow(_ queue: SchedulerQueue) -> some View {
        let isSelected = selectedQueueID == queue.id
        let count = queue.taskIDs.count
        let running = queueRun.isRunning(queue)
        let waiting = queueRun.isWaitingForStart(queue)
        return Button {
            selectedItem = .all
            selectedQueueID = queue.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: queue.name == QueueRunController.mainQueueName ? "tray.full.fill" : "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? theme.accent : theme.amber)
                    .frame(width: 18)

                Text(queue.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if running {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.success)
                        .help("Queue is running")
                } else if waiting {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .help("Waiting for its start time")
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? theme.accent : theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            (isSelected ? theme.accent.opacity(0.15) : theme.surfaceMuted.opacity(0.75)),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.selectedRow)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Start Queue") { QueueRunController.shared.startNow(queueID: queue.id) }
            Button("Stop Queue") { QueueRunController.shared.stopManually(queueID: queue.id) }
            Divider()
            Button("Scheduler…") { QueueSchedulerWindowController.show() }
        }
    }

    private var categoryItems: [SidebarItem] {
        [.videos, .audio, .documents, .applications, .archives, .others]
    }

    private var statusItems: [SidebarItem] {
        [.downloading, .completed, .failed]
    }

    private var activeCount: Int {
        downloadManager.downloadTasks.filter { $0.status == .downloading }.count
    }

    private var totalSpeed: Double {
        downloadManager.downloadTasks
            .filter { $0.status == .downloading }
            .reduce(0) { $0 + Double($1.speed) }
    }

    private func accentColor(for item: SidebarItem) -> Color {
        switch item {
        case .all: return theme.accent
        case .downloading: return theme.accent
        case .completed: return theme.success
        case .failed: return theme.danger
        case .scheduled: return theme.purple
        case .videos: return theme.pink
        case .audio: return theme.purple
        case .documents: return theme.success
        case .archives: return theme.amber
        case .applications: return theme.accent
        case .others: return theme.indigo
        case .history: return theme.indigo
        }
    }

    private func itemCount(for item: SidebarItem) -> Int? {
        switch item {
        case .all:
            return downloadManager.downloadTasks.count
        case .downloading:
            return downloadManager.downloadTasks.filter { $0.status == .downloading || $0.status == .paused }.count
        case .completed:
            return downloadManager.downloadTasks.filter { $0.status == .completed }.count
        case .failed:
            return downloadManager.downloadTasks.filter { $0.status == .failed }.count
        case .scheduled:
            return QueueRunController.shared.scheduledTasks().count
        case .videos:
            return downloadManager.downloadTasks.filter { $0.fileCategory == .video }.count
                + videoManager.videoTasks.count
        case .audio:
            return downloadManager.downloadTasks.filter { $0.fileCategory == .audio }.count
        case .documents:
            return downloadManager.downloadTasks.filter { $0.fileCategory == .document }.count
        case .archives:
            return downloadManager.downloadTasks.filter { $0.fileCategory == .archive }.count
        case .applications:
            return downloadManager.downloadTasks.filter { $0.fileCategory == .application }.count
        case .others:
            return downloadManager.downloadTasks.filter { $0.fileCategory == .other }.count
        case .history:
            return nil
        }
    }

    private func loadDiskStats() {
        let url = downloadManager.defaultSaveLocation
        if let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]) {
            diskFree = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        }
    }
}

// MARK: - Sidebar storage / bandwidth widget

private struct SidebarStatusCard: View {
    let free: Int64
    let total: Int64
    let speed: Double
    let active: Int

    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    private var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - free) / Double(total)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.accent)
                Text("Macintosh HD · Downloads")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(free > 0 ? "\(formatBytes(free)) free" : "—")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.borderStrong)
                    Capsule()
                        .fill(theme.accentGradient)
                        .frame(width: max(0, geo.size.width * usedFraction))
                }
            }
            .frame(height: 6)

            HStack {
                Text("Used: \(total > 0 ? formatBytes(total - free) : "—")")
                Spacer()
                Text("Total: \(total > 0 ? formatBytes(total) : "—")")
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(theme.textTertiary)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.success)
                Text("BANDWIDTH LOAD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Text(active > 0 ? formatSpeed(speed) : "Idle")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(active > 0 ? theme.success : theme.textTertiary)
            }

            TimelineView(.periodic(from: .now, by: 0.65)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<14, id: \.self) { index in
                        let wave = (sin(t * 1.55 + Double(index) * 0.58) + 1) / 2
                        let level = active > 0 ? 0.22 + wave * 0.78 : 0.10
                        Capsule()
                            .fill(index % 3 == 0 ? theme.indigo.opacity(0.8) : theme.accent.opacity(0.65))
                            .frame(height: 3 + level * 22)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 26)
        }
        .padding(10)
        .background(theme.surface.opacity(colorScheme == .dark ? 0.82 : 0.72),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Toolbar View
struct ToolbarView: View {
    @Binding var showingAddDownload: Bool
    let selection: Set<UUID>
    @Binding var searchText: String
    let onStart: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var downloadManager = DownloadManager.shared

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    private var selectedTasks: [DownloadTask] {
        guard !selection.isEmpty else { return [] }
        return downloadManager.downloadTasks.filter { selection.contains($0.id) }
    }

    private var canResume: Bool {
        selectedTasks.contains { $0.status == .paused || $0.status == .failed }
    }

    private var canStop: Bool {
        selectedTasks.contains { $0.status == .downloading || $0.status == .paused }
    }

    private var canDelete: Bool {
        !selection.isEmpty
    }

    private var canStopAll: Bool {
        downloadManager.downloadTasks.contains { $0.status == .downloading || $0.status == .paused }
    }

    @ObservedObject private var toolbarQueueSelection = QueueSelection.shared
    @ObservedObject private var toolbarQueueManager = SchedulerQueueManager.shared

    /// The queue chosen in the sidebar, if any.
    private var activeQueue: SchedulerQueue? {
        guard let id = toolbarQueueSelection.queueID else { return nil }
        return toolbarQueueManager.queues.first { $0.id == id }
    }

    private var canClear: Bool {
        downloadManager.downloadTasks.contains { $0.status == .completed }
    }

    var body: some View {
        HStack(spacing: 5) {
            IdmToolbarButton(title: "Add URL", icon: "plus.circle.fill",
                             tint: .white, style: .primary) {
                showingAddDownload = true
            }

            IdmToolbarDivider()

            if let queue = activeQueue {
                IdmToolbarButton(title: "Start Queue", icon: "play.fill", tint: theme.success) {
                    QueueRunController.shared.startNow(queueID: queue.id)
                }
                .help("Start \"\(queue.name)\": every file in it is started or resumed")

                IdmToolbarButton(title: "Stop Queue", icon: "stop.fill", tint: theme.danger) {
                    QueueRunController.shared.stopManually(queueID: queue.id)
                }
                .help("Stop \"\(queue.name)\": files keep their progress and Start Queue continues them")
            } else {
                IdmToolbarButton(title: "Resume", icon: "play.fill", tint: theme.success,
                                 disabled: !canResume, action: onStart)

                IdmToolbarButton(title: "Stop", icon: "stop.fill", tint: theme.warning,
                                 disabled: !canStop, action: onStop)

                IdmToolbarButton(title: "Stop All", icon: "stop.circle.fill", tint: theme.danger,
                                 disabled: !canStopAll, action: stopAll)
            }

            IdmToolbarButton(title: "Delete", icon: "trash", tint: theme.danger,
                             disabled: !canDelete, compact: true, action: onDelete)

            IdmToolbarButton(title: "Delete Completed", icon: "trash.slash", tint: theme.purple,
                             disabled: !canClear, action: clearCompleted)
            .help("Remove finished downloads from the list (files stay on disk)")

            IdmToolbarDivider()

            IdmToolbarButton(title: "Scheduler", icon: "alarm.fill", tint: .orange) {
                QueueSchedulerWindowController.show()
            }
            .help("Scheduler: start and stop queues at a set time, then sleep or shut down")

            IdmToolbarButton(title: "Options", icon: "gearshape.fill", tint: theme.accent,
                             compact: true) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Spacer(minLength: 8)

            DownloadSearchField(text: $searchText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.toolbar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    private func stopAll() {
        let active = downloadManager.downloadTasks.filter {
            $0.status == .downloading || $0.status == .paused
        }
        Task { @MainActor in
            for task in active {
                await downloadManager.stopDownload(task)
            }
        }
    }

    private func clearCompleted() {
        Task { @MainActor in
            await downloadManager.clearCompleted()
        }
    }
}

private struct DownloadSearchField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            TextField("Search downloads", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 220, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.surface.opacity(colorScheme == .dark ? 0.82 : 0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(focused ? theme.accent.opacity(0.8) : theme.border, lineWidth: 1)
        )
        .help("Search downloads by file name or URL")
    }
}

private struct IdmToolbarButton: View {
    enum Style { case normal, primary }

    let title: String
    let icon: String
    var tint: Color = .primary
    var disabled: Bool = false
    var compact: Bool = false
    var style: Style = .normal
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(disabled ? theme.textTertiary : tint)
                if !compact {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(disabled ? theme.textTertiary : (style == .primary ? .white : theme.textPrimary))
                }
            }
            .padding(.horizontal, compact ? 7 : 9)
            .frame(height: 28)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(style == .primary ? Color.clear : theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(title)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var background: some View {
        if style == .primary {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.accentGradient)
                .shadow(color: theme.accentDeep.opacity(0.25), radius: 5, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? theme.surfaceMuted : theme.surface.opacity(colorScheme == .dark ? 0.82 : 0.62))
        }
    }
}

private struct IdmToolbarDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(HyperTheme(scheme: colorScheme).borderStrong)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }
}

// MARK: - Download List View
struct DownloadListView: View {
    let sidebarItem: SidebarItem
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<DownloadTask>]
    let searchText: String
    let onRequestRemove: (Set<UUID>) -> Void

    @StateObject private var downloadManager = DownloadManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var propertiesTask: DownloadTask? = nil
    @ObservedObject private var queueSelection = QueueSelection.shared
    @ObservedObject private var queueOrderWatcher = SchedulerQueueManager.shared   // refresh when the order changes

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        if sidebarItem == .history {
            DownloadHistoryView()
        } else {
            VStack(spacing: 0) {
                if filteredDownloads.isEmpty {
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(theme.surfaceMuted.opacity(0.75))
                                .frame(width: 58, height: 58)
                            Image(systemName: "cloud.arrow.down")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(theme.textTertiary)
                        }
                        Text("No downloads match this view")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                        Text(hasSearchQuery
                             ? "Try a different search or clear the search field."
                             : "Click Add URL or grab a link from your browser.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Group {
                        if #available(macOS 14.0, *) {
                            DownloadTable(downloads: sortedDownloads,
                                          selection: $selection,
                                          sortOrder: $sortOrder)
                        } else {
                            LegacyDownloadTable(downloads: sortedDownloads,
                                                selection: $selection,
                                                sortOrder: $sortOrder)
                        }
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 42)
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if ids.count == 1, let id = ids.first,
                           let download = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                            downloadContextMenu(for: download)
                            Divider()
                            MoveToQueueMenu(ids: Array(ids))
                        } else if !ids.isEmpty {
                            Button { resumeSelected(ids) } label: {
                                Label("Resume Selected", systemImage: "play.fill")
                            }
                            Button { stopSelected(ids) } label: {
                                Label("Stop Selected", systemImage: "stop.fill")
                            }
                            Button { showInFinder(ids) } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }
                            Button { copyURLs(ids) } label: {
                                Label("Copy URLs", systemImage: "doc.on.doc")
                            }
                            MoveToQueueMenu(ids: Array(ids))
                            Divider()
                            Button(role: .destructive) { onRequestRemove(ids) } label: {
                                Label("Remove…", systemImage: "minus.circle")
                            }
                        }
                    } primaryAction: { ids in
                        guard let id = ids.first,
                              let download = downloadManager.downloadTasks.first(where: { $0.id == id })
                        else { return }
                        if download.status == .completed {
                            NSWorkspace.shared.open(download.fileURL)
                        } else {
                            DownloadProgressWindowController.open(for: download)
                        }
                    }
                    .sheet(item: $propertiesTask) { task in
                        DownloadPropertiesView(download: task)
                    }
                }
            }
            .background(theme.surface.opacity(colorScheme == .dark ? 0.78 : 0.66))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: Per-row context menu
    @ViewBuilder
    private func downloadContextMenu(for download: DownloadTask) -> some View {
        // ── Playback ──────────────────────────────────────────────────
        if download.status == .paused || download.status == .failed {
            Button { Task { @MainActor in await downloadManager.resumeDownload(download) } }
            label: { Label("Resume", systemImage: "play.fill") }
        }
        if download.status == .downloading {
            Button { Task { @MainActor in await downloadManager.pauseDownload(download) } }
            label: { Label("Pause", systemImage: "pause.fill") }
            Button { Task { @MainActor in await downloadManager.stopDownload(download) } }
            label: { Label("Stop", systemImage: "stop.fill") }
        }
        if download.status == .cancelled {
            Button { downloadManager.requeueDownload(download) }
            label: { Label("Re-add to Queue", systemImage: "arrow.counterclockwise") }
        }

        Button { DownloadProgressWindowController.open(for: download) }
        label: { Label("Show Progress Window", systemImage: "macwindow") }

        Divider()

        // ── File ──────────────────────────────────────────────────────
        if download.status == .completed {
            Button { NSWorkspace.shared.open(download.fileURL) }
            label: { Label("Open File", systemImage: "arrow.up.forward.app") }
        }
        Button {
            if FileManager.default.fileExists(atPath: download.fileURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([download.fileURL])
            } else {
                NSWorkspace.shared.open(downloadManager.defaultSaveLocation)
            }
        } label: { Label("Open Folder", systemImage: "folder") }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(download.url.absoluteString, forType: .string)
        } label: { Label("Copy URL", systemImage: "doc.on.doc") }

        Divider()

        // ── Queue ─────────────────────────────────────────────────────
        // Only inside a queue: reordering means nothing in All Downloads / Completed / Failed.
        if queueSelection.queueID != nil {
            let moveIDs: Set<UUID> = selection.contains(download.id) ? selection : [download.id]
            Button { downloadManager.moveInQueue(moveIDs, .top) }
            label: { Label("Move to Top of Queue", systemImage: "arrow.up.to.line") }
            Button { downloadManager.moveInQueue(moveIDs, .up) }
            label: { Label("Move Up", systemImage: "arrow.up") }
            Button { downloadManager.moveInQueue(moveIDs, .down) }
            label: { Label("Move Down", systemImage: "arrow.down") }
            Button { downloadManager.moveInQueue(moveIDs, .bottom) }
            label: { Label("Move to Bottom of Queue", systemImage: "arrow.down.to.line") }
        }
        Button { downloadManager.startQueue() }
        label: { Label("Start Queue", systemImage: "play.circle") }
        Button { downloadManager.stopQueue() }
        label: { Label("Stop Queue", systemImage: "stop.circle") }

        Divider()

        // ── Properties ───────────────────────────────────────────────
        Button { propertiesTask = download }
        label: { Label("Properties…", systemImage: "info.circle") }

        Divider()

        // ── Destructive ───────────────────────────────────────────────
        Button(role: .destructive) {
            onRequestRemove([download.id])
        } label: { Label("Remove…", systemImage: "minus.circle") }
    }
    
    private var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredDownloads: [DownloadTask] {
        var downloads = downloadManager.downloadTasks
        switch sidebarItem {
        case .all: break
        case .downloading: downloads = downloads.filter { $0.status == .downloading || $0.status == .paused }
        case .completed: downloads = downloads.filter { $0.status == .completed }
        case .failed: downloads = downloads.filter { $0.status == .failed }
        case .scheduled: downloads = QueueRunController.shared.scheduledTasks()
        case .videos: downloads = downloads.filter { $0.fileCategory == .video }
        case .audio: downloads = downloads.filter { $0.fileCategory == .audio }
        case .documents: downloads = downloads.filter { $0.fileCategory == .document }
        case .archives: downloads = downloads.filter { $0.fileCategory == .archive }
        case .applications: downloads = downloads.filter { $0.fileCategory == .application }
        case .others: downloads = downloads.filter { $0.fileCategory == .other }
        case .history: break
        }
        if let qid = queueSelection.queueID {
            let ids = Set(SchedulerQueueManager.shared.queues.first(where: { $0.id == qid })?.taskIDs ?? [])
            downloads = downloads.filter { ids.contains($0.id) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return downloads }
        return downloads.filter {
            $0.filename.localizedCaseInsensitiveContains(query)
                || $0.url.absoluteString.localizedCaseInsensitiveContains(query)
        }
    }

    /// SwiftUI's Table only updates `sortOrder`; the rows must be sorted here.
    private var sortedDownloads: [DownloadTask] {
        // Inside a queue the list shows the queue's own order (that is what Move Up / Down change).
        if let qid = queueSelection.queueID,
           let order = SchedulerQueueManager.shared.queues.first(where: { $0.id == qid })?.taskIDs {
            var rank: [UUID: Int] = [:]
            for (index, id) in order.enumerated() where rank[id] == nil { rank[id] = index }
            return filteredDownloads.sorted { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
        }
        return filteredDownloads.sorted(using: sortOrder)
    }
    
    private func pauseSelected(_ ids: Set<UUID>) {
        Task { @MainActor in
            for id in ids {
                if let dl = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                    await downloadManager.pauseDownload(dl)
                }
            }
        }
    }
    private func resumeSelected(_ ids: Set<UUID>) {
        Task { @MainActor in
            for id in ids {
                if let dl = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                    await downloadManager.resumeDownload(dl)
                }
            }
        }
    }
    private func cancelSelected(_ ids: Set<UUID>) {
        Task { @MainActor in
            for id in ids {
                if let dl = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                    await downloadManager.cancelDownload(dl)
                }
            }
        }
    }
    private func showInFinder(_ ids: Set<UUID>) {
        for id in ids {
            if let dl = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                NSWorkspace.shared.activateFileViewerSelecting([dl.fileURL])
            }
        }
    }
    private func copyURLs(_ ids: Set<UUID>) {
        let urls = ids.compactMap { id in
            downloadManager.downloadTasks.first(where: { $0.id == id })?.url.absoluteString
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls, forType: .string)
    }
    private func removeSelected(_ ids: Set<UUID>) {
        onRequestRemove(ids)
    }
    private func stopSelected(_ ids: Set<UUID>) {
        Task { @MainActor in
            for id in ids {
                if let dl = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                    await downloadManager.stopDownload(dl)
                }
            }
        }
    }
    private func deleteFiles(_ ids: Set<UUID>) {
        Task { @MainActor in
            for id in ids {
                if let dl = downloadManager.downloadTasks.first(where: { $0.id == id }) {
                    await downloadManager.deleteFileAndRemove(dl)
                }
            }
        }
    }
}

// MARK: - Download Row Header
struct DownloadRowHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc").frame(width: 20).hidden()
            Text("Name")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: 80, alignment: .trailing)
            Text("Progress")
                .frame(width: 140, alignment: .leading)
            Text("Speed")
                .frame(width: 90, alignment: .trailing)
            Text("ETA")
                .frame(width: 80, alignment: .trailing)
            Text("Status")
                .frame(width: 90, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Download Row
struct DownloadRow: View {
    @ObservedObject var download: DownloadTask

    var body: some View {
        HStack(spacing: 8) {
            // File type icon
            Image(systemName: download.fileCategory.icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            // Filename + URL
            VStack(alignment: .leading, spacing: 2) {
                Text(download.name)
                    .lineLimit(1)
                    .font(.body)
                Text(download.url.host ?? download.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            // File size
            Text(download.totalBytes > 0 ? formatBytes(download.totalBytes) : "—")
                .frame(width: 80, alignment: .trailing)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)

            // Progress bar + percent
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: download.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 110)
                HStack(spacing: 4) {
                    Text(formatBytes(download.downloadedBytes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(Int(download.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, alignment: .leading)

            // Speed
            Group {
                if download.status == .downloading && download.speed > 0 {
                    Text(formatBytes(download.speed) + "/s")
                        .foregroundStyle(.primary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 90, alignment: .trailing)
            .font(.body.monospacedDigit())

            // ETA
            Group {
                if download.status == .downloading && download.speed > 0 && download.totalBytes > 0 {
                    Text(download.formattedTimeRemaining)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 80, alignment: .trailing)
            .font(.body.monospacedDigit())

            // Status badge
            StatusBadge(status: download.status)
                .frame(width: 90, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Table Cells
struct DownloadNameCell: View {
    @ObservedObject var download: DownloadTask
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(download.fileCategory.tint.opacity(colorScheme == .dark ? 0.16 : 0.13))
                    .frame(width: 27, height: 27)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(download.fileCategory.tint.opacity(0.22), lineWidth: 1)
                    )
                Image(systemName: download.fileCategory.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(download.fileCategory.tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(download.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .help(download.url.absoluteString)
                Text(download.url.host ?? download.fileCategory.rawValue.capitalized)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}

struct DownloadSizeCell: View {
    @ObservedObject var download: DownloadTask
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        Text(download.totalBytes > 0 ? formatBytes(download.totalBytes) : "—")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct DownloadStatusCell: View {
    @ObservedObject var download: DownloadTask
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(download.status.color)
                    .frame(width: 5, height: 5)
                Text(download.statusDetail ?? download.status.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(download.status.color)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(Int(download.progress * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
            ProgressView(value: download.progress)
                .progressViewStyle(.linear)
                .tint(download.status.color)
                .scaleEffect(x: 1, y: 0.65, anchor: .center)
        }
    }
}

struct DownloadSpeedCell: View {
    @ObservedObject var download: DownloadTask
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        Text(download.status == .downloading && download.speed > 0
             ? formatBytes(download.speed) + "/s" : "—")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(download.speed > 0 ? theme.accent : theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct DownloadTimeLeftCell: View {
    @ObservedObject var download: DownloadTask
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        Text(download.status == .downloading && download.timeRemaining > 0
             ? download.formattedTimeRemaining : "—")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(download.timeRemaining > 0 && download.status == .downloading
                             ? theme.textSecondary : theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct DownloadLastTryCell: View {
    @ObservedObject var download: DownloadTask
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        Text(download.lastAttemptAt.map(Self.compactString(for:)) ?? "—")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(download.lastAttemptAt == nil ? theme.textTertiary : theme.textSecondary)
            .help(download.lastAttemptAt?.formatted(date: .abbreviated, time: .standard) ?? "")
    }

    private static func compactString(for date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 { return "Now" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3_600))h" }
        if elapsed < 7 * 86_400 { return "\(Int(elapsed / 86_400))d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Download Properties Sheet
struct DownloadPropertiesView: View {
    @ObservedObject var download: DownloadTask
    @Environment(\.dismiss) private var dismiss

    /// The web page the download was captured from (the browser's Referer).
    private var pageURLString: String? {
        let h = download.requestHeaders
        guard let v = h["Referer"] ?? h["referer"], !v.isEmpty,
              v != download.url.absoluteString else { return nil }
        return v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: download.fileCategory.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("Download Properties")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    PropertyRow(label: "Filename",  value: download.filename)
                    PropertyRow(label: "URL",       value: download.url.absoluteString)
                    if let page = pageURLString {
                        PropertyRow(label: "Page", value: page)
                        HStack {
                            Spacer().frame(width: 122)
                            Button("Open Page in Browser") {
                                if let u = URL(string: page) { NSWorkspace.shared.open(u) }
                            }
                            .controlSize(.small)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 4)
                    }
                    PropertyRow(label: "Save To",   value: download.destinationPath.path)
                    PropertyRow(label: "Status",    value: download.status.displayName)
                    PropertyRow(label: "Size",      value: download.totalBytes > 0 ? formatBytes(download.totalBytes) : "Unknown")
                    PropertyRow(label: "Downloaded",value: formatBytes(download.downloadedBytes))
                    PropertyRow(label: "Progress",  value: "\(Int(download.progress * 100))%")
                    PropertyRow(label: "Speed",     value: download.status == .downloading ? formatBytes(download.speed) + "/s" : "—")
                    PropertyRow(label: "ETA",       value: download.status == .downloading ? download.formattedTimeRemaining : "—")
                    PropertyRow(label: "Segments",  value: "\(download.numberOfSegments)")
                    PropertyRow(label: "Added",     value: download.createdAt.formatted(date: .abbreviated, time: .standard))
                    if let lastTry = download.lastAttemptAt {
                        PropertyRow(label: "Last Try", value: lastTry.formatted(date: .abbreviated, time: .standard))
                    }
                    if let completed = download.completedAt {
                        PropertyRow(label: "Completed", value: completed.formatted(date: .abbreviated, time: .standard))
                    }
                    if let err = download.error {
                        PropertyRow(label: "Error", value: err.localizedDescription, valueColor: .red)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 480, height: 430)
    }
}

private struct PropertyRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
                .padding(.trailing, 12)
            Text(value)
                .font(.callout)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            Rectangle()
                .fill(Color(nsColor: .alternatingContentBackgroundColors[0]))
                .opacity(0.5)
        )
    }
}



// MARK: - Status Badge
struct StatusBadge: View {
    let status: DownloadStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .clipShape(Capsule())
    }
}

extension DownloadStatus {
    var displayName: String {
        switch self {
        case .waiting: return "Waiting"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: Color {
        switch self {
        case .waiting: return .gray
        case .downloading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Status Bar View
struct StatusBarView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var bandwidthManager = BandwidthManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 5) {
                Circle()
                    .fill(activeDownloadsCount > 0 ? theme.accent : theme.textTertiary)
                    .frame(width: 6, height: 6)
                Text("\(activeDownloadsCount) active")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }

            Divider().frame(height: 11)

            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(formatSpeed(totalSpeed))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
            }

            Divider().frame(height: 11)

            HStack(spacing: 4) {
                Circle()
                    .fill(networkManager.isNetworkAvailable ? theme.success : theme.textTertiary)
                    .frame(width: 5, height: 5)
                Text(networkManager.isNetworkAvailable ? "Online" : "Offline")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
            }

            if bandwidthManager.globalLimit.downloadSpeed > 0 {
                Divider().frame(height: 11)
                Label("Limited", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.warning)
            }

            Spacer()

            Text("MULTI-THREAD ENGINE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(theme.textTertiary)

            Menu {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }

                Divider()

                Toggle("Speed Limit", isOn: $bandwidthManager.globalLimit.isEnabled)
                Toggle("Clipboard Monitoring", isOn: .constant(ClipboardMonitor.shared.isMonitoring))

                Divider()

                Button("Clear Completed") {
                    Task { @MainActor in
                        await downloadManager.clearCompleted()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 18)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(theme.footer)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }
    
    private var activeDownloadsCount: Int {
        downloadManager.downloadTasks.filter { $0.status == .downloading }.count
    }
    
    private var totalSpeed: Double {
        downloadManager.downloadTasks
            .filter { $0.status == .downloading }
            .reduce(0.0) { $0 + Double($1.speed) }
    }
}

// MARK: - Helper Functions
private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

private func formatSpeed(_ bytesPerSecond: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
}

private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
    if seconds.isInfinite || seconds.isNaN {
        return "—"
    }
    
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    let secs = Int(seconds) % 60
    
    if hours > 0 {
        return String(format: "%dh %dm", hours, minutes)
    } else if minutes > 0 {
        return String(format: "%dm %ds", minutes, secs)
    } else {
        return String(format: "%ds", secs)
    }
}

extension FileType {
    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc"
        case .archive: return "archivebox"
        case .application: return "app"
        case .image: return "photo"
        case .other: return "doc.fill"
        }
    }
}
