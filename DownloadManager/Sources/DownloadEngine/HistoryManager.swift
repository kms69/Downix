import Foundation
import Combine

/// Manages download history and analytics
@MainActor
public class HistoryManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = HistoryManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var history: [DownloadHistoryEntry] = []
    @Published public private(set) var statistics: DownloadHistoryStatistics = DownloadHistoryStatistics()
    @Published public var filter: HistoryFilter = HistoryFilter()
    @Published public var sortOption: HistorySortOption = .dateNewest
    
    // MARK: - Private Properties
    
    private let historyKey = "download_history"
    private let maxHistoryEntries = 10000
    
    // MARK: - Computed Properties
    
    /// Filtered and sorted history
    public var filteredHistory: [DownloadHistoryEntry] {
        var filtered = history
        
        // Apply search query
        if !filter.searchQuery.isEmpty {
            let query = filter.searchQuery.lowercased()
            filtered = filtered.filter {
                $0.fileName.lowercased().contains(query) ||
                $0.url.absoluteString.lowercased().contains(query) ||
                $0.sourceWebsite?.lowercased().contains(query) == true
            }
        }
        
        // Apply status filter
        if let status = filter.status {
            filtered = filtered.filter { $0.status == status }
        }
        
        // Apply file type filter
        if let fileType = filter.fileType {
            filtered = filtered.filter { $0.fileType == fileType }
        }
        
        // Apply category filter
        if let category = filter.category {
            filtered = filtered.filter { $0.category == category }
        }
        
        // Apply source website filter
        if let website = filter.sourceWebsite {
            filtered = filtered.filter { $0.sourceWebsite == website }
        }
        
        // Apply date range filter
        if let dateRange = filter.dateRange, let interval = dateRange.dateInterval() {
            filtered = filtered.filter { interval.contains($0.startDate) }
        }
        
        // Apply file size filters
        if let minSize = filter.minFileSize {
            filtered = filtered.filter { $0.fileSize >= minSize }
        }
        if let maxSize = filter.maxFileSize {
            filtered = filtered.filter { $0.fileSize <= maxSize }
        }
        
        // Apply tags filter
        if !filter.tags.isEmpty {
            filtered = filtered.filter { entry in
                !Set(entry.tags).isDisjoint(with: Set(filter.tags))
            }
        }
        
        // Apply sorting
        return filtered.sorted { sortOption.compare($0, $1) }
    }
    
    /// All unique file types in history
    public var allFileTypes: [String] {
        Array(Set(history.map { $0.fileType })).sorted()
    }
    
    /// All unique categories in history
    public var allCategories: [String] {
        Array(Set(history.compactMap { $0.category })).sorted()
    }
    
    /// All unique source websites in history
    public var allSourceWebsites: [String] {
        Array(Set(history.compactMap { $0.sourceWebsite })).sorted()
    }
    
    /// All unique tags in history
    public var allTags: [String] {
        Array(Set(history.flatMap { $0.tags })).sorted()
    }
    
    // MARK: - Initialization
    
    private init() {
        loadHistory()
        calculateStatistics()
    }
    
    // MARK: - History Management
    
    /// Add a new entry to history
    public func addEntry(_ entry: DownloadHistoryEntry) {
        history.insert(entry, at: 0)
        
        // Limit history size
        if history.count > maxHistoryEntries {
            history = Array(history.prefix(maxHistoryEntries))
        }
        
        saveHistory()
        calculateStatistics()
    }
    
    /// Update an existing entry
    public func updateEntry(_ entry: DownloadHistoryEntry) {
        if let index = history.firstIndex(where: { $0.id == entry.id }) {
            history[index] = entry
            saveHistory()
            calculateStatistics()
        }
    }
    
    /// Delete an entry
    public func deleteEntry(_ entry: DownloadHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
        calculateStatistics()
    }
    
    /// Delete multiple entries
    public func deleteEntries(_ entries: [DownloadHistoryEntry]) {
        let ids = Set(entries.map { $0.id })
        history.removeAll { ids.contains($0.id) }
        saveHistory()
        calculateStatistics()
    }
    
    /// Clear all history
    public func clearHistory() {
        history.removeAll()
        statistics = DownloadHistoryStatistics()
        saveHistory()
    }
    
    /// Clear history older than specified date
    public func clearHistoryOlderThan(_ date: Date) {
        history.removeAll { $0.startDate < date }
        saveHistory()
        calculateStatistics()
    }
    
    /// Delete history for failed downloads
    public func clearFailedDownloads() {
        history.removeAll { $0.status == .failed }
        saveHistory()
        calculateStatistics()
    }
    
    // MARK: - Statistics
    
    /// Calculate statistics from history
    public func calculateStatistics() {
        guard !history.isEmpty else {
            statistics = DownloadHistoryStatistics()
            return
        }
        
        // Basic counts
        let totalDownloads = history.count
        let completedDownloads = history.filter { $0.status == .completed }.count
        let failedDownloads = history.filter { $0.status == .failed }.count
        let cancelledDownloads = history.filter { $0.status == .cancelled }.count
        
        // Total bytes and duration
        let totalBytes = history.reduce(Int64(0)) { $0 + $1.fileSize }
        let totalDuration = history.compactMap { $0.duration }.reduce(0, +)
        
        // Average and peak speed
        let speeds = history.map { $0.averageSpeed }
        let averageSpeed = speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count)
        let peakSpeed = speeds.max() ?? 0
        
        // Top file types
        let fileTypeCounts = Dictionary(grouping: history, by: { $0.fileType })
            .map { fileType, entries in
                FileTypeCount(
                    fileType: fileType,
                    count: entries.count,
                    totalBytes: entries.reduce(0) { $0 + $1.fileSize }
                )
            }
            .sorted { $0.count > $1.count }
            .prefix(10)
        
        // Top websites
        let websiteCounts = Dictionary(grouping: history.compactMap { entry -> (String, DownloadHistoryEntry)? in
            guard let website = entry.sourceWebsite else { return nil }
            return (website, entry)
        }, by: { $0.0 })
            .map { website, entries in
                WebsiteCount(
                    website: website,
                    count: entries.count,
                    totalBytes: entries.reduce(0) { $0 + $1.1.fileSize }
                )
            }
            .sorted { $0.count > $1.count }
            .prefix(10)
        
        // Top categories
        let categoryCounts = Dictionary(grouping: history.compactMap { entry -> (String, DownloadHistoryEntry)? in
            guard let category = entry.category else { return nil }
            return (category, entry)
        }, by: { $0.0 })
            .map { category, entries in
                CategoryCount(
                    category: category,
                    count: entries.count,
                    totalBytes: entries.reduce(0) { $0 + $1.1.fileSize }
                )
            }
            .sorted { $0.count > $1.count }
            .prefix(10)
        
        // Downloads by day (last 30 days)
        let byDay = calculateDownloadsByPeriod(days: 30)
        
        // Downloads by week (last 12 weeks)
        let byWeek = calculateDownloadsByPeriod(weeks: 12)
        
        // Downloads by month (last 12 months)
        let byMonth = calculateDownloadsByPeriod(months: 12)
        
        // Bytes downloaded by day (last 30 days)
        let bytesByDay = calculateBytesByPeriod(days: 30)
        
        // Update statistics
        statistics = DownloadHistoryStatistics(
            totalDownloads: totalDownloads,
            totalBytesDownloaded: totalBytes,
            totalDuration: totalDuration,
            averageSpeed: averageSpeed,
            peakSpeed: peakSpeed,
            completedDownloads: completedDownloads,
            failedDownloads: failedDownloads,
            cancelledDownloads: cancelledDownloads,
            topFileTypes: Array(fileTypeCounts),
            topWebsites: Array(websiteCounts),
            topCategories: Array(categoryCounts),
            downloadsByDay: byDay,
            downloadsByWeek: byWeek,
            downloadsByMonth: byMonth,
            bytesDownloadedByDay: bytesByDay
        )
    }
    
    /// Calculate downloads by period
    private func calculateDownloadsByPeriod(days: Int? = nil, weeks: Int? = nil, months: Int? = nil) -> [DateCount] {
        let calendar = Calendar.current
        let now = Date()
        
        var result: [DateCount] = []
        
        if let days = days {
            for i in 0..<days {
                if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                    let startOfDay = calendar.startOfDay(for: date)
                    let count = history.filter { calendar.isDate($0.startDate, inSameDayAs: startOfDay) }.count
                    result.append(DateCount(date: startOfDay, count: count))
                }
            }
        } else if let weeks = weeks {
            for i in 0..<weeks {
                if let date = calendar.date(byAdding: .weekOfYear, value: -i, to: now) {
                    let weekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                    let startOfWeek = calendar.date(from: weekComponents)!
                    let count = history.filter {
                        let entryWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0.startDate)
                        return entryWeek == weekComponents
                    }.count
                    result.append(DateCount(date: startOfWeek, count: count))
                }
            }
        } else if let months = months {
            for i in 0..<months {
                if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                    let monthComponents = calendar.dateComponents([.year, .month], from: date)
                    let startOfMonth = calendar.date(from: monthComponents)!
                    let count = history.filter {
                        let entryMonth = calendar.dateComponents([.year, .month], from: $0.startDate)
                        return entryMonth == monthComponents
                    }.count
                    result.append(DateCount(date: startOfMonth, count: count))
                }
            }
        }
        
        return result.reversed()
    }
    
    /// Calculate bytes downloaded by period
    private func calculateBytesByPeriod(days: Int) -> [DateBytes] {
        let calendar = Calendar.current
        let now = Date()
        
        var result: [DateBytes] = []
        
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let startOfDay = calendar.startOfDay(for: date)
                let bytes = history
                    .filter { calendar.isDate($0.startDate, inSameDayAs: startOfDay) }
                    .reduce(Int64(0)) { $0 + $1.fileSize }
                result.append(DateBytes(date: startOfDay, bytes: bytes))
            }
        }
        
        return result.reversed()
    }
    
    /// Get statistics for a specific time period
    public func statisticsForPeriod(_ period: AnalyticsTimePeriod) -> DownloadHistoryStatistics {
        let calendar = Calendar.current
        let now = Date()
        
        var filteredHistory: [DownloadHistoryEntry]
        
        switch period {
        case .day:
            filteredHistory = history.filter { calendar.isDateInToday($0.startDate) }
        case .week:
            filteredHistory = history.filter {
                guard let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) else { return false }
                return $0.startDate >= weekAgo
            }
        case .month:
            filteredHistory = history.filter {
                guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
                return $0.startDate >= monthAgo
            }
        case .year:
            filteredHistory = history.filter {
                guard let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return false }
                return $0.startDate >= yearAgo
            }
        case .all:
            filteredHistory = history
        }
        
        // Calculate statistics for filtered history
        let originalHistory = history
        history = filteredHistory
        calculateStatistics()
        let periodStats = statistics
        history = originalHistory
        calculateStatistics()
        
        return periodStats
    }
    
    // MARK: - Search
    
    /// Search history with query
    public func search(_ query: String) {
        filter.searchQuery = query
    }
    
    /// Clear search and filters
    public func clearFilters() {
        filter.reset()
    }
    
    // MARK: - Export
    
    /// Export history to file
    public func exportHistory(format: HistoryExportFormat, entries: [DownloadHistoryEntry]? = nil) -> String {
        let entriesToExport = entries ?? history
        
        switch format {
        case .csv:
            return exportToCSV(entriesToExport)
        case .json:
            return exportToJSON(entriesToExport)
        case .txt:
            return exportToText(entriesToExport)
        case .html:
            return exportToHTML(entriesToExport)
        }
    }
    
    private func exportToCSV(_ entries: [DownloadHistoryEntry]) -> String {
        var csv = "ID,URL,File Name,File Path,File Size,File Type,Start Date,Completion Date,Duration,Status,Average Speed,Peak Speed,Segments,Source Website,Category,Tags\n"
        
        for entry in entries {
            let id = entry.id.uuidString
            let url = entry.url.absoluteString
            let fileName = entry.fileName
            let filePath = entry.filePath
            let fileSize = String(entry.fileSize)
            let fileType = entry.fileType
            let startDate = ISO8601DateFormatter().string(from: entry.startDate)
            let completionDate = entry.completionDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            let duration = entry.duration.map { String($0) } ?? ""
            let status = entry.status.rawValue
            let avgSpeed = String(entry.averageSpeed)
            let peakSpeed = String(entry.peakSpeed)
            let segments = String(entry.segmentsUsed)
            let website = entry.sourceWebsite ?? ""
            let category = entry.category ?? ""
            let tags = entry.tags.joined(separator: ";")
            
            let row = [id, url, fileName, filePath, fileSize, fileType, startDate, completionDate, duration, status, avgSpeed, peakSpeed, segments, website, category, tags]
                .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
                .map { "\"\($0)\"" }
                .joined(separator: ",")
            
            csv += row + "\n"
        }
        
        return csv
    }
    
    private func exportToJSON(_ entries: [DownloadHistoryEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(entries),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        
        return json
    }
    
    private func exportToText(_ entries: [DownloadHistoryEntry]) -> String {
        var text = "Download History Export\n"
        text += "Exported: \(Date())\n"
        text += "Total Entries: \(entries.count)\n\n"
        text += String(repeating: "=", count: 80) + "\n\n"
        
        for entry in entries {
            text += "File: \(entry.fileName)\n"
            text += "URL: \(entry.url.absoluteString)\n"
            text += "Size: \(entry.fileSizeFormatted)\n"
            text += "Type: \(entry.fileType)\n"
            text += "Status: \(entry.status.rawValue)\n"
            text += "Started: \(entry.startDate)\n"
            if entry.completionDate != nil {
                text += "Completed: \(entry.completionDate!)\n"
            }
            if entry.duration != nil {
                text += "Duration: \(entry.durationFormatted)\n"
            }
            text += "Average Speed: \(entry.averageSpeedFormatted)\n"
            text += "Peak Speed: \(entry.peakSpeedFormatted)\n"
            if let website = entry.sourceWebsite {
                text += "Source: \(website)\n"
            }
            if let category = entry.category {
                text += "Category: \(category)\n"
            }
            if !entry.tags.isEmpty {
                text += "Tags: \(entry.tags.joined(separator: ", "))\n"
            }
            text += "\n" + String(repeating: "-", count: 80) + "\n\n"
        }
        
        return text
    }
    
    private func exportToHTML(_ entries: [DownloadHistoryEntry]) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Download History</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 20px; }
                h1 { color: #333; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
                th { background-color: #f5f5f5; font-weight: 600; }
                tr:hover { background-color: #f9f9f9; }
                .status { padding: 3px 8px; border-radius: 3px; font-size: 12px; }
                .completed { background-color: #d4edda; color: #155724; }
                .failed { background-color: #f8d7da; color: #721c24; }
                .cancelled { background-color: #fff3cd; color: #856404; }
            </style>
        </head>
        <body>
            <h1>Download History</h1>
            <p>Exported: \(Date())</p>
            <p>Total Entries: \(entries.count)</p>
            <table>
                <thead>
                    <tr>
                        <th>File Name</th>
                        <th>Size</th>
                        <th>Type</th>
                        <th>Status</th>
                        <th>Date</th>
                        <th>Speed</th>
                    </tr>
                </thead>
                <tbody>
        """
        
        for entry in entries {
            let statusClass: String
            switch entry.status {
            case .completed: statusClass = "completed"
            case .failed: statusClass = "failed"
            case .cancelled: statusClass = "cancelled"
            default: statusClass = ""
            }
            
            html += """
                    <tr>
                        <td>\(entry.fileName)</td>
                        <td>\(entry.fileSizeFormatted)</td>
                        <td>\(entry.fileType)</td>
                        <td><span class="status \(statusClass)">\(entry.status.rawValue)</span></td>
                        <td>\(entry.startDate)</td>
                        <td>\(entry.averageSpeedFormatted)</td>
                    </tr>
            """
        }
        
        html += """
                </tbody>
            </table>
        </body>
        </html>
        """
        
        return html
    }
    
    // MARK: - Persistence
    
    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let encoded = try? encoder.encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let decoded = try? decoder.decode([DownloadHistoryEntry].self, from: data) {
            history = decoded
        }
    }
}
