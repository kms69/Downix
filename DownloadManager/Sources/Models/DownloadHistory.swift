import Foundation

// MARK: - Download History Entry

/// Represents a single download history entry
public struct DownloadHistoryEntry: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let url: URL
    public let fileName: String
    public let filePath: String
    public let fileSize: Int64
    public let fileType: String
    public let mimeType: String?
    
    public let startDate: Date
    public let completionDate: Date?
    public let duration: TimeInterval?
    
    public let status: DownloadHistoryStatus
    public let errorMessage: String?
    public let errorCode: Int?
    
    public let averageSpeed: Double // bytes per second
    public let peakSpeed: Double
    public let segmentsUsed: Int
    
    public let sourceWebsite: String?
    public let category: String?
    public let tags: [String]
    
    public var metadata: DownloadHistoryMetadata
    
    public init(
        id: UUID = UUID(),
        url: URL,
        fileName: String,
        filePath: String,
        fileSize: Int64,
        fileType: String,
        mimeType: String? = nil,
        startDate: Date = Date(),
        completionDate: Date? = nil,
        duration: TimeInterval? = nil,
        status: DownloadHistoryStatus = .completed,
        errorMessage: String? = nil,
        errorCode: Int? = nil,
        averageSpeed: Double = 0,
        peakSpeed: Double = 0,
        segmentsUsed: Int = 1,
        sourceWebsite: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        metadata: DownloadHistoryMetadata = DownloadHistoryMetadata()
    ) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.filePath = filePath
        self.fileSize = fileSize
        self.fileType = fileType
        self.mimeType = mimeType
        self.startDate = startDate
        self.completionDate = completionDate
        self.duration = duration
        self.status = status
        self.errorMessage = errorMessage
        self.errorCode = errorCode
        self.averageSpeed = averageSpeed
        self.peakSpeed = peakSpeed
        self.segmentsUsed = segmentsUsed
        self.sourceWebsite = sourceWebsite
        self.category = category
        self.tags = tags
        self.metadata = metadata
    }
    
    /// Formatted file size
    public var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// Formatted average speed
    public var averageSpeedFormatted: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(averageSpeed), countStyle: .file))/s"
    }
    
    /// Formatted peak speed
    public var peakSpeedFormatted: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(peakSpeed), countStyle: .file))/s"
    }
    
    /// Formatted duration
    public var durationFormatted: String {
        guard let duration = duration else { return "N/A" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    /// File exists on disk
    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
}

// MARK: - Download History Status

public enum DownloadHistoryStatus: String, Codable, CaseIterable {
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case partial = "Partial"
    case removed = "Removed"
    
    public var icon: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .removed: return "trash.circle.fill"
        }
    }
    
    public var color: String {
        switch self {
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        case .partial: return "yellow"
        case .removed: return "gray"
        }
    }
}

// MARK: - Download History Metadata

public struct DownloadHistoryMetadata: Codable, Equatable, Hashable {
    public var browserName: String?
    public var browserVersion: String?
    public var userAgent: String?
    public var referrer: String?
    public var ipAddress: String?
    public var vpnUsed: Bool
    public var networkType: String? // WiFi, Ethernet, etc.
    public var retryCount: Int
    public var segmentErrors: Int
    public var checksumVerified: Bool
    public var compressionUsed: Bool
    public var encryptionUsed: Bool
    
    public init(
        browserName: String? = nil,
        browserVersion: String? = nil,
        userAgent: String? = nil,
        referrer: String? = nil,
        ipAddress: String? = nil,
        vpnUsed: Bool = false,
        networkType: String? = nil,
        retryCount: Int = 0,
        segmentErrors: Int = 0,
        checksumVerified: Bool = false,
        compressionUsed: Bool = false,
        encryptionUsed: Bool = false
    ) {
        self.browserName = browserName
        self.browserVersion = browserVersion
        self.userAgent = userAgent
        self.referrer = referrer
        self.ipAddress = ipAddress
        self.vpnUsed = vpnUsed
        self.networkType = networkType
        self.retryCount = retryCount
        self.segmentErrors = segmentErrors
        self.checksumVerified = checksumVerified
        self.compressionUsed = compressionUsed
        self.encryptionUsed = encryptionUsed
    }
}

// MARK: - Download History Statistics

public struct DownloadHistoryStatistics: Codable, Equatable {
    public var totalDownloads: Int
    public var totalBytesDownloaded: Int64
    public var totalDuration: TimeInterval
    public var averageSpeed: Double
    public var peakSpeed: Double
    
    public var completedDownloads: Int
    public var failedDownloads: Int
    public var cancelledDownloads: Int
    
    public var topFileTypes: [FileTypeCount]
    public var topWebsites: [WebsiteCount]
    public var topCategories: [CategoryCount]
    
    public var downloadsByDay: [DateCount]
    public var downloadsByWeek: [DateCount]
    public var downloadsByMonth: [DateCount]
    
    public var bytesDownloadedByDay: [DateBytes]
    
    public init(
        totalDownloads: Int = 0,
        totalBytesDownloaded: Int64 = 0,
        totalDuration: TimeInterval = 0,
        averageSpeed: Double = 0,
        peakSpeed: Double = 0,
        completedDownloads: Int = 0,
        failedDownloads: Int = 0,
        cancelledDownloads: Int = 0,
        topFileTypes: [FileTypeCount] = [],
        topWebsites: [WebsiteCount] = [],
        topCategories: [CategoryCount] = [],
        downloadsByDay: [DateCount] = [],
        downloadsByWeek: [DateCount] = [],
        downloadsByMonth: [DateCount] = [],
        bytesDownloadedByDay: [DateBytes] = []
    ) {
        self.totalDownloads = totalDownloads
        self.totalBytesDownloaded = totalBytesDownloaded
        self.totalDuration = totalDuration
        self.averageSpeed = averageSpeed
        self.peakSpeed = peakSpeed
        self.completedDownloads = completedDownloads
        self.failedDownloads = failedDownloads
        self.cancelledDownloads = cancelledDownloads
        self.topFileTypes = topFileTypes
        self.topWebsites = topWebsites
        self.topCategories = topCategories
        self.downloadsByDay = downloadsByDay
        self.downloadsByWeek = downloadsByWeek
        self.downloadsByMonth = downloadsByMonth
        self.bytesDownloadedByDay = bytesDownloadedByDay
    }
    
    /// Formatted total bytes downloaded
    public var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytesDownloaded, countStyle: .file)
    }
    
    /// Formatted average speed
    public var averageSpeedFormatted: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(averageSpeed), countStyle: .file))/s"
    }
    
    /// Formatted peak speed
    public var peakSpeedFormatted: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(peakSpeed), countStyle: .file))/s"
    }
    
    /// Success rate percentage
    public var successRate: Double {
        guard totalDownloads > 0 else { return 0 }
        return Double(completedDownloads) / Double(totalDownloads) * 100
    }
}

// MARK: - Supporting Count Types

public struct FileTypeCount: Codable, Equatable, Identifiable {
    public let id: UUID
    public let fileType: String
    public var count: Int
    public var totalBytes: Int64
    
    public init(id: UUID = UUID(), fileType: String, count: Int, totalBytes: Int64 = 0) {
        self.id = id
        self.fileType = fileType
        self.count = count
        self.totalBytes = totalBytes
    }
    
    public var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

public struct WebsiteCount: Codable, Equatable, Identifiable {
    public let id: UUID
    public let website: String
    public var count: Int
    public var totalBytes: Int64
    
    public init(id: UUID = UUID(), website: String, count: Int, totalBytes: Int64 = 0) {
        self.id = id
        self.website = website
        self.count = count
        self.totalBytes = totalBytes
    }
    
    public var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

public struct CategoryCount: Codable, Equatable, Identifiable {
    public let id: UUID
    public let category: String
    public var count: Int
    public var totalBytes: Int64
    
    public init(id: UUID = UUID(), category: String, count: Int, totalBytes: Int64 = 0) {
        self.id = id
        self.category = category
        self.count = count
        self.totalBytes = totalBytes
    }
    
    public var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

public struct DateCount: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public var count: Int
    
    public init(id: UUID = UUID(), date: Date, count: Int) {
        self.id = id
        self.date = date
        self.count = count
    }
    
    public var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

public struct DateBytes: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public var bytes: Int64
    
    public init(id: UUID = UUID(), date: Date, bytes: Int64) {
        self.id = id
        self.date = date
        self.bytes = bytes
    }
    
    public var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    public var bytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - History Filter

public struct HistoryFilter: Equatable {
    public var searchQuery: String
    public var status: DownloadHistoryStatus?
    public var fileType: String?
    public var category: String?
    public var sourceWebsite: String?
    public var dateRange: DateRange?
    public var minFileSize: Int64?
    public var maxFileSize: Int64?
    public var tags: [String]
    
    public init(
        searchQuery: String = "",
        status: DownloadHistoryStatus? = nil,
        fileType: String? = nil,
        category: String? = nil,
        sourceWebsite: String? = nil,
        dateRange: DateRange? = nil,
        minFileSize: Int64? = nil,
        maxFileSize: Int64? = nil,
        tags: [String] = []
    ) {
        self.searchQuery = searchQuery
        self.status = status
        self.fileType = fileType
        self.category = category
        self.sourceWebsite = sourceWebsite
        self.dateRange = dateRange
        self.minFileSize = minFileSize
        self.maxFileSize = maxFileSize
        self.tags = tags
    }
    
    /// Check if filter is empty
    public var isEmpty: Bool {
        searchQuery.isEmpty && status == nil && fileType == nil &&
        category == nil && sourceWebsite == nil && dateRange == nil &&
        minFileSize == nil && maxFileSize == nil && tags.isEmpty
    }
    
    /// Reset all filters
    public mutating func reset() {
        searchQuery = ""
        status = nil
        fileType = nil
        category = nil
        sourceWebsite = nil
        dateRange = nil
        minFileSize = nil
        maxFileSize = nil
        tags = []
    }
}

// MARK: - Date Range

public enum DateRange: String, CaseIterable, Equatable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisYear = "This Year"
    case custom = "Custom"
    
    public func dateInterval() -> DateInterval? {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return DateInterval(start: start, end: end)
            
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
            let end = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: end)
            
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: now)!
            return DateInterval(start: start, end: now)
            
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return DateInterval(start: start, end: now)
            
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
            return DateInterval(start: start, end: end)
            
        case .lastMonth:
            let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
            let end = thisMonthStart
            return DateInterval(start: start, end: end)
            
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))!
            return DateInterval(start: start, end: now)
            
        case .custom:
            return nil
        }
    }
}

// MARK: - History Sort Option

public enum HistorySortOption: String, CaseIterable {
    case dateNewest = "Date (Newest)"
    case dateOldest = "Date (Oldest)"
    case nameAZ = "Name (A-Z)"
    case nameZA = "Name (Z-A)"
    case sizeSmallest = "Size (Smallest)"
    case sizeLargest = "Size (Largest)"
    case speedSlowest = "Speed (Slowest)"
    case speedFastest = "Speed (Fastest)"
    
    public func compare(_ a: DownloadHistoryEntry, _ b: DownloadHistoryEntry) -> Bool {
        switch self {
        case .dateNewest:
            return a.startDate > b.startDate
        case .dateOldest:
            return a.startDate < b.startDate
        case .nameAZ:
            return a.fileName < b.fileName
        case .nameZA:
            return a.fileName > b.fileName
        case .sizeSmallest:
            return a.fileSize < b.fileSize
        case .sizeLargest:
            return a.fileSize > b.fileSize
        case .speedSlowest:
            return a.averageSpeed < b.averageSpeed
        case .speedFastest:
            return a.averageSpeed > b.averageSpeed
        }
    }
}

// MARK: - Export Format

public enum HistoryExportFormat: String, CaseIterable {
    case csv = "CSV"
    case json = "JSON"
    case txt = "Text"
    case html = "HTML"
    
    public var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .txt: return "txt"
        case .html: return "html"
        }
    }
    
    public var mimeType: String {
        switch self {
        case .csv: return "text/csv"
        case .json: return "application/json"
        case .txt: return "text/plain"
        case .html: return "text/html"
        }
    }
}

// MARK: - Analytics Time Period

public enum AnalyticsTimePeriod: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All Time"
}
