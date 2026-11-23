//
//  QueueView.swift
//  Download Manager for Mac - Feature #2: Smart Queue UI
//
//  Created on February 15, 2026
//

import SwiftUI

/// Main queue view showing all downloads
struct QueueView: View {
    @ObservedObject var manager = DownloadManager.shared
    @State private var selectedFilter: QueueFilter = QueueFilter()
    @State private var selectedSort: QueueSortOption = .priority
    @State private var sortAscending: Bool = false
    @State private var searchText: String = ""
    @State private var selectedCategory: DownloadCategory = .all
    
    var filteredTasks: [DownloadTask] {
        var filter = QueueFilter(
            category: selectedCategory == .all ? nil : selectedCategory,
            searchText: searchText.isEmpty ? nil : searchText
        )
        return manager.filteredDownloads(filter: filter)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            QueueToolbarView(
                searchText: $searchText,
                selectedCategory: $selectedCategory,
                selectedSort: $selectedSort,
                sortAscending: $sortAscending,
                onAddDownload: addDownload,
                onPauseAll: { Task { @MainActor in await manager.pauseAll() } },
                onResumeAll: { Task { @MainActor in await manager.resumeAll() } }
            )
            
            Divider()
            
            // Main content
            HSplitView {
                // Sidebar
                QueueSidebarView(
                    selectedCategory: $selectedCategory,
                    statistics: manager.getQueueStatistics()
                )
                .frame(minWidth: 200, maxWidth: 250)
                
                // Download list
                if filteredTasks.isEmpty {
                    EmptyQueueView()
                } else {
                    QueueListView(
                        tasks: filteredTasks,
                        onMove: moveTask,
                        onPriority: setPriority,
                        onPause: { task in Task { @MainActor in await manager.pauseDownload(task) } },
                        onResume: { task in Task { @MainActor in await manager.resumeDownload(task) } },
                        onCancel: { task in Task { @MainActor in await manager.cancelDownload(task) } },
                        onRemove: { task in Task { @MainActor in await manager.removeDownload(task) } }
                    )
                }
            }
            
            Divider()
            
            // Status bar
            QueueStatusBar(
                activeDownloads: manager.activeDownloads,
                totalSpeed: manager.formattedTotalSpeed,
                statistics: manager.getQueueStatistics()
            )
        }
    }
    
    private func addDownload() {
        // This would show an add download dialog
        // For now, placeholder
    }
    
    private func moveTask(from source: IndexSet, to destination: Int) {
        var tasks = filteredTasks
        tasks.move(fromOffsets: source, toOffset: destination)
        
        // Update queue positions
        for (index, task) in tasks.enumerated() {
            manager.moveTask(task, to: index)
        }
    }
    
    private func setPriority(_ priority: DownloadPriority, for task: DownloadTask) {
        manager.setPriority(priority, for: task)
    }
}

// MARK: - Toolbar

struct QueueToolbarView: View {
    @Binding var searchText: String
    @Binding var selectedCategory: DownloadCategory
    @Binding var selectedSort: QueueSortOption
    @Binding var sortAscending: Bool
    
    let onAddDownload: () -> Void
    let onPauseAll: () -> Void
    let onResumeAll: () -> Void
    
    var body: some View {
        HStack {
            // Add button
            Button(action: onAddDownload) {
                Label("Add URL", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search downloads...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            Spacer()
            
            // Sort menu
            Menu {
                ForEach(QueueSortOption.allCases, id: \.self) { option in
                    Button {
                        selectedSort = option
                    } label: {
                        Label(option.rawValue, systemImage: option.icon)
                    }
                }
                
                Divider()
                
                Button {
                    sortAscending.toggle()
                } label: {
                    Label(sortAscending ? "Ascending" : "Descending",
                          systemImage: sortAscending ? "arrow.up" : "arrow.down")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            
            // Pause/Resume all
            Button(action: onPauseAll) {
                Label("Pause All", systemImage: "pause.circle")
            }
            
            Button(action: onResumeAll) {
                Label("Resume All", systemImage: "play.circle")
            }
        }
        .padding()
    }
}

// MARK: - Sidebar

struct QueueSidebarView: View {
    @Binding var selectedCategory: DownloadCategory
    let statistics: QueueStatistics
    
    var body: some View {
        List(selection: $selectedCategory) {
            Section("Queues") {
                NavigationLink(value: DownloadCategory.all) {
                    Label {
                        HStack {
                            Text("All Downloads")
                            Spacer()
                            Text("\(statistics.total)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "tray.full")
                    }
                }
                
                Label {
                    HStack {
                        Text("Downloading")
                        Spacer()
                        Text("\(statistics.downloading)")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                }
                
                Label {
                    HStack {
                        Text("Completed")
                        Spacer()
                        Text("\(statistics.completed)")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                Label {
                    HStack {
                        Text("Failed")
                        Spacer()
                        Text("\(statistics.failed)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            
            Section("Categories") {
                ForEach(DownloadCategory.allCases, id: \.self) { category in
                    if category != .all {
                        NavigationLink(value: category) {
                            Label {
                                HStack {
                                    Text(category.rawValue)
                                    Spacer()
                                    Text("\(statistics.categoryCounts[category] ?? 0)")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            } icon: {
                                Image(systemName: category.icon)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Download List

struct QueueListView: View {
    let tasks: [DownloadTask]
    let onMove: (IndexSet, Int) -> Void
    let onPriority: (DownloadPriority, DownloadTask) -> Void
    let onPause: (DownloadTask) -> Void
    let onResume: (DownloadTask) -> Void
    let onCancel: (DownloadTask) -> Void
    let onRemove: (DownloadTask) -> Void
    
    var body: some View {
        List {
            ForEach(tasks) { task in
                DownloadRowView(
                    task: task,
                    onPriority: { priority in onPriority(priority, task) },
                    onPause: { onPause(task) },
                    onResume: { onResume(task) },
                    onCancel: { onCancel(task) },
                    onRemove: { onRemove(task) }
                )
            }
            .onMove(perform: onMove)
        }
        .listStyle(.inset)
    }
}

// MARK: - Download Row

struct DownloadRowView: View {
    @ObservedObject var task: DownloadTask
    let onPriority: (DownloadPriority) -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                // File icon
                Image(systemName: task.category.icon)
                    .foregroundColor(.accentColor)
                
                // Filename
                Text(task.filename)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Priority badge
                PriorityBadge(priority: task.priority, onSelect: onPriority)
                
                // Actions
                QueueDownloadActionsView(
                    state: task.state,
                    onPause: onPause,
                    onResume: onResume,
                    onCancel: onCancel,
                    onRemove: onRemove
                )
            }
            
            // Progress bar
            if task.state == .downloading || task.state == .paused {
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
            }
            
            // Details
            HStack {
                // State
                StateIndicator(state: task.state)
                
                Spacer()
                
                // Stats
                if task.state == .downloading {
                    HStack(spacing: 12) {
                        Label("\(Int(task.progress * 100))%", systemImage: "chart.bar")
                        Label(task.formattedSpeed, systemImage: "speedometer")
                        Label(task.formattedTimeRemaining, systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                // Size
                if task.totalBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            ContextMenuView(
                task: task,
                onPriority: onPriority,
                onPause: onPause,
                onResume: onResume,
                onCancel: onCancel,
                onRemove: onRemove
            )
        }
    }
}

// MARK: - Supporting Views

struct PriorityBadge: View {
    let priority: DownloadPriority
    let onSelect: (DownloadPriority) -> Void
    
    var body: some View {
        Menu {
            ForEach(DownloadPriority.allCases, id: \.self) { p in
                Button {
                    onSelect(p)
                } label: {
                    Label(p.displayName, systemImage: p.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: priority.icon)
                Text(priority.displayName)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priorityColor.opacity(0.2))
            .foregroundColor(priorityColor)
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
    }
    
    var priorityColor: Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .normal: return .blue
        case .low: return .gray
        }
    }
}

struct StateIndicator: View {
    let state: DownloadState
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(state.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    var stateColor: Color {
        switch state {
        case .waiting: return .yellow
        case .downloading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

struct QueueDownloadActionsView: View {
    let state: DownloadState
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            if state == .downloading {
                Button(action: onPause) {
                    Image(systemName: "pause.circle")
                }
                .buttonStyle(.borderless)
            }
            
            if state == .paused || state == .failed {
                Button(action: onResume) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
            }
            
            if state == .downloading || state == .paused || state == .waiting {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
            
            if state == .completed || state == .failed || state == .cancelled {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct ContextMenuView: View {
    let task: DownloadTask
    let onPriority: (DownloadPriority) -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        if task.state == .downloading {
            Button("Pause", action: onPause)
        }
        
        if task.state == .paused {
            Button("Resume", action: onResume)
        }
        
        Divider()
        
        Menu("Set Priority") {
            ForEach(DownloadPriority.allCases, id: \.self) { priority in
                Button {
                    onPriority(priority)
                } label: {
                    Label(priority.displayName, systemImage: priority.icon)
                }
            }
        }
        
        Divider()
        
        Button("Cancel", action: onCancel)
        Button("Remove", action: onRemove)
    }
}

struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Downloads")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add a URL to start downloading")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QueueStatusBar: View {
    let activeDownloads: Int
    let totalSpeed: String
    let statistics: QueueStatistics
    
    var body: some View {
        HStack {
            Label("\(activeDownloads) active", systemImage: "arrow.down.circle")
            
            Spacer()
            
            Label(totalSpeed, systemImage: "speedometer")
            
            Spacer()
            
            Label("\(statistics.completed) completed", systemImage: "checkmark.circle")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Preview
// Note: Previews only work in Xcode projects, not SPM
// To use: Open in Xcode and add to SwiftUI preview canvas
