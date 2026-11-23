import SwiftUI

/// Download History and Analytics UI
public struct DownloadHistoryView: View {
    
    @ObservedObject private var manager = HistoryManager.shared
    @State private var selectedTab: Tab = .history
    @State private var selectedEntries: Set<UUID> = []
    @State private var showingFilterSheet = false
    @State private var showingExportSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingClearHistoryAlert = false
    @State private var exportFormat: HistoryExportFormat = .csv
    @State private var selectedPeriod: AnalyticsTimePeriod = .month
   
    
    private enum Tab: String, CaseIterable {
        case history = "History"
        case statistics = "Statistics"
        case analytics = "Analytics"
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch selectedTab {
                case .history:
                    historyView
                case .statistics:
                    statisticsView
                case .analytics:
                    analyticsView
                }
            }
        }
        .alert("Delete Entries", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedEntries()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedEntries.count) selected entries?")
        }
        .alert("Clear History", isPresented: $showingClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                manager.clearHistory()
            }
        } message: {
            Text("Are you sure you want to clear all download history? This action cannot be undone.")
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
            Group {
                if let badge = tabBadge(tab) {
                    Label(tab.rawValue, systemImage: tabIcon(tab))
                        .badge(badge)
                } else {
                    Label(tab.rawValue, systemImage: tabIcon(tab))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    }
    
    private func tabIcon(_ tab: Tab) -> String {
        switch tab {
        case .history: return "clock.arrow.circlepath"
        case .statistics: return "chart.bar"
        case .analytics: return "chart.line.uptrend.xyaxis"
        }
    }
    
    private func tabBadge(_ tab: Tab) -> Int? {
        switch tab {
        case .history:
            return manager.filteredHistory.isEmpty ? nil : manager.filteredHistory.count
        case .statistics, .analytics:
            return nil
        }
    }
    
    // MARK: - History View
    
    private var historyView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search downloads...", text: $manager.filter.searchQuery)
                        .textFieldStyle(.plain)
                    if !manager.filter.searchQuery.isEmpty {
                        Button {
                            manager.filter.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
                Spacer()
                
                // Filter button
                Button {
                    showingFilterSheet = true
                } label: {
                    Label("Filter", systemImage: manager.filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .help("Filter downloads")
                
                // Sort menu
                Menu {
                    ForEach(HistorySortOption.allCases, id: \.self) { option in
                        Button {
                            manager.sortOption = option
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if manager.sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort downloads")
                
                // Export button
                Button {
                    showingExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export history")
                .disabled(manager.history.isEmpty)
                
                // Delete selected
                Button {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete selected entries")
                .disabled(selectedEntries.isEmpty)
                
                // Clear all
                Button {
                    showingClearHistoryAlert = true
                } label: {
                    Label("Clear", systemImage: "trash.fill")
                }
                .help("Clear all history")
                .disabled(manager.history.isEmpty)
            }
            .padding()
            
            Divider()
            
            // History List
            if manager.filteredHistory.isEmpty {
                emptyStateView
            } else {
                List(selection: $selectedEntries) {
                    ForEach(manager.filteredHistory) { entry in
                        HistoryEntryRow(entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                contextMenu(for: entry)
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Download History")
        .sheet(isPresented: $showingFilterSheet) {
            filterSheet
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Download History")
                .font(.title2)
                .fontWeight(.semibold)
            Text(manager.filter.isEmpty ? "Your download history will appear here" : "No downloads match your filters")
                .foregroundColor(.secondary)
            if !manager.filter.isEmpty {
                Button("Clear Filters") {
                    manager.clearFilters()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func contextMenu(for entry: DownloadHistoryEntry) -> some View {
        Group {
            if entry.fileExists {
                Button("Open File") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: entry.filePath))
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(entry.filePath, inFileViewerRootedAtPath: "")
                }
                Divider()
            }
            
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
            }
            
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.filePath, forType: .string)
            }
            
            Divider()
            
            Button("Delete Entry") {
                manager.deleteEntry(entry)
            }
        }
    }
    
    // MARK: - Statistics View
    
    private var statisticsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    HistoryStatCard(
                        title: "Total Downloads",
                        value: "\(manager.statistics.totalDownloads)",
                        icon: "arrow.down.circle.fill",
                        color: .blue
                    )
                    
                    HistoryStatCard(
                        title: "Total Downloaded",
                        value: manager.statistics.totalBytesFormatted,
                        icon: "internaldrive.fill",
                        color: .purple
                    )
                    
                    HistoryStatCard(
                        title: "Average Speed",
                        value: manager.statistics.averageSpeedFormatted,
                        icon: "speedometer",
                        color: .green
                    )
                    
                    HistoryStatCard(
                        title: "Success Rate",
                        value: String(format: "%.1f%%", manager.statistics.successRate),
                        icon: "checkmark.circle.fill",
                        color: .mint
                    )
                    
                    HistoryStatCard(
                        title: "Failed Downloads",
                        value: "\(manager.statistics.failedDownloads)",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                    
                    HistoryStatCard(
                        title: "Peak Speed",
                        value: manager.statistics.peakSpeedFormatted,
                        icon: "bolt.fill",
                        color: .orange
                    )
                }
                .padding()
                
                Divider()
                
                // Top File Types
                if !manager.statistics.topFileTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top File Types")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(manager.statistics.topFileTypes) { item in
                            HStack {
                                Text(item.fileType)
                                    .fontWeight(.medium)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(item.count) downloads")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(item.totalBytesFormatted)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                    
                    Divider()
                }
                
                // Top Websites
                if !manager.statistics.topWebsites.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Websites")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(manager.statistics.topWebsites) { item in
                            HStack {
                                Text(item.website)
                                    .fontWeight(.medium)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(item.count) downloads")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(item.totalBytesFormatted)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                    
                    Divider()
                }
                
                // Top Categories
                if !manager.statistics.topCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Categories")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(manager.statistics.topCategories) { item in
                            HStack {
                                Text(item.category)
                                    .fontWeight(.medium)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(item.count) downloads")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(item.totalBytesFormatted)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Statistics")
    }
    
    // MARK: - Analytics View
    
    private var analyticsView: some View {
        VStack {
            // Period Picker
            Picker("Time Period", selection: $selectedPeriod) {
                ForEach(AnalyticsTimePeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period as AnalyticsTimePeriod)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Downloads per day chart
                    if !manager.statistics.downloadsByDay.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Downloads per Day (Last 30 Days)")
                                .font(.headline)
                            
                            SimpleBarChart(
                                data: manager.statistics.downloadsByDay.map { ($0.dateFormatted, Double($0.count)) },
                                color: .blue
                            )
                            .frame(height: 200)
                        }
                        .padding()
                        
                        Divider()
                    }
                    
                    // Bytes downloaded per day chart
                    if !manager.statistics.bytesDownloadedByDay.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Data Downloaded per Day (Last 30 Days)")
                                .font(.headline)
                            
                            SimpleBarChart(
                                data: manager.statistics.bytesDownloadedByDay.map { ($0.dateFormatted, Double($0.bytes) / 1_000_000) }, // Convert to MB
                                color: .purple
                            )
                            .frame(height: 200)
                            
                            Text("Values in MB")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        
                        Divider()
                    }
                    
                    // Status distribution
                    VStack(alignment: .leading) {
                        Text("Download Status Distribution")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            StatusPieSegment(
                                title: "Completed",
                                count: manager.statistics.completedDownloads,
                                total: manager.statistics.totalDownloads,
                                color: .green
                            )
                            StatusPieSegment(
                                title: "Failed",
                                count: manager.statistics.failedDownloads,
                                total: manager.statistics.totalDownloads,
                                color: .red
                            )
                            StatusPieSegment(
                                title: "Cancelled",
                                count: manager.statistics.cancelledDownloads,
                                total: manager.statistics.totalDownloads,
                                color: .orange
                            )
                        }
                        .padding(.vertical)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Analytics")
    }
    
    // MARK: - Filter Sheet
    
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Status", selection: $manager.filter.status) {
                        Text("All").tag(nil as DownloadHistoryStatus?)
                        ForEach(DownloadHistoryStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status as DownloadHistoryStatus?)
                        }
                    }
                }
                
                Section("File Type") {
                    Picker("File Type", selection: $manager.filter.fileType) {
                        Text("All").tag(nil as String?)
                        ForEach(manager.allFileTypes, id: \.self) { type in
                            Text(type).tag(type as String?)
                        }
                    }
                }
                
                Section("Category") {
                    Picker("Category", selection: $manager.filter.category) {
                        Text("All").tag(nil as String?)
                        ForEach(manager.allCategories, id: \.self) { category in
                            Text(category).tag(category as String?)
                        }
                    }
                }
                
                Section("Source Website") {
                    Picker("Website", selection: $manager.filter.sourceWebsite) {
                        Text("All").tag(nil as String?)
                        ForEach(manager.allSourceWebsites, id: \.self) { website in
                            Text(website).tag(website as String?)
                        }
                    }
                }
                
                Section("Date Range") {
                    Picker("Date Range", selection: $manager.filter.dateRange) {
                        Text("All Time").tag(nil as DateRange?)
                        ForEach(DateRange.allCases.filter { $0 != .custom }, id: \.self) { range in
                            Text(range.rawValue).tag(range as DateRange?)
                        }
                    }
                }
            }
            .navigationTitle("Filter History")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        manager.clearFilters()
                        showingFilterSheet = false
                    }
                }
                SwiftUI.ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingFilterSheet = false
                    }
                }
            })
        }
        .frame(width: 400, height: 500)
    }
    
    // MARK: - Export Sheet
    
    private var exportSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Format")
                        .font(.headline)
                    
                    Picker("Format", selection: $exportFormat) {
                        ForEach(HistoryExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Options")
                        .font(.headline)
                    
                    Text("Entries to export: \(selectedEntries.isEmpty ? manager.filteredHistory.count : selectedEntries.count)")
                        .foregroundColor(.secondary)
                }
                .padding()
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        showingExportSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("Export") {
                        exportHistory()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .navigationTitle("Export History")
        }
        .frame(width: 400, height: 300)
    }
    
    // MARK: - Helper Methods
    
    private func deleteSelectedEntries() {
        let entries = manager.history.filter { selectedEntries.contains($0.id) }
        manager.deleteEntries(entries)
        selectedEntries.removeAll()
    }
    
    private func exportHistory() {
        let entries = selectedEntries.isEmpty ? manager.filteredHistory : manager.history.filter { selectedEntries.contains($0.id) }
        let content = manager.exportHistory(format: exportFormat, entries: entries)
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: exportFormat.fileExtension)!]
        savePanel.nameFieldStringValue = "download_history.\(exportFormat.fileExtension)"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        
        showingExportSheet = false
    }
}

// MARK: - Supporting Views

struct HistoryEntryRow: View {
    let entry: DownloadHistoryEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(systemName: fileIcon(for: entry.fileType))
                .font(.title2)
                .foregroundColor(fileColor(for: entry.fileType))
                .frame(width: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.fileName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(entry.fileSizeFormatted)
                    Text("•")
                    Text(entry.averageSpeedFormatted)
                    if let website = entry.sourceWebsite {
                        Text("•")
                        Text(website)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status and date
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: entry.status.icon)
                        .font(.caption)
                    Text(entry.status.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(statusColor(entry.status))
                
                Text(entry.startDate, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func fileIcon(for type: String) -> String {
        let lower = type.lowercased()
        if ["mp4", "mov", "avi", "mkv"].contains(lower) { return "film" }
        if ["mp3", "m4a", "wav", "flac"].contains(lower) { return "music.note" }
        if ["jpg", "jpeg", "png", "gif", "heic"].contains(lower) { return "photo" }
        if ["pdf", "doc", "docx", "txt"].contains(lower) { return "doc.text" }
        if ["zip", "rar", "7z", "tar", "gz"].contains(lower) { return "archivebox" }
        if ["dmg", "pkg", "app"].contains(lower) { return "app" }
        return "doc"
    }
    
    private func fileColor(for type: String) -> Color {
        let lower = type.lowercased()
        if ["mp4", "mov", "avi", "mkv"].contains(lower) { return .blue }
        if ["mp3", "m4a", "wav", "flac"].contains(lower) { return .purple }
        if ["jpg", "jpeg", "png", "gif", "heic"].contains(lower) { return .orange }
        if ["pdf", "doc", "docx", "txt"].contains(lower) { return .red }
        if ["zip", "rar", "7z", "tar", "gz"].contains(lower) { return .green }
        if ["dmg", "pkg", "app"].contains(lower) { return .indigo }
        return .gray
    }
    
    private func statusColor(_ status: DownloadHistoryStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .partial: return .yellow
        case .removed: return .gray
        }
    }
}

struct HistoryStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct StatusPieSegment: View {
    let title: String
    let count: Int
    let total: Int
    let color: Color
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total) * 100
    }
    
    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: percentage / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                VStack {
                    Text("\(Int(percentage))%")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct SimpleBarChart: View {
    let data: [(String, Double)]
    let color: Color
    
    private var maxValue: Double {
        data.map { $0.1 }.max() ?? 1
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                    VStack {
                        Rectangle()
                            .fill(color.opacity(0.7))
                            .frame(height: CGFloat(item.1 / maxValue) * geometry.size.height * 0.9)
                        
                        Text(item.0)
                            .font(.system(size: 8))
                            .rotationEffect(.degrees(-45))
                            .frame(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Preview

struct DownloadHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        DownloadHistoryView()
    }
}
