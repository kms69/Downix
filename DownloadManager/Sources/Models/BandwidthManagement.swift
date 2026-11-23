//
//  BandwidthManagement.swift
//  Download Manager for Mac - Feature #10: Advanced Bandwidth Management
//
//  Created on February 16, 2026
//

import Foundation
import SystemConfiguration

// MARK: - Network Type

/// Network connection type
enum NetworkType: String, Codable, CaseIterable {
    case wifi = "WiFi"
    case ethernet = "Ethernet"
    case cellular = "Cellular"
    case thunderbolt = "Thunderbolt"
    case usb = "USB"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .thunderbolt: return "bolt"
        case .usb: return "cable.connector.horizontal"
        case .unknown: return "network"
        }
    }
    
    var defaultSpeedLimit: Int64 {
        switch self {
        case .wifi: return 0 // Unlimited
        case .ethernet: return 0 // Unlimited
        case .cellular: return 5_000_000 // 5 MB/s
        case .thunderbolt: return 0 // Unlimited
        case .usb: return 10_000_000 // 10 MB/s
        case .unknown: return 1_000_000 // 1 MB/s
        }
    }
    
    var isMetered: Bool {
        return self == .cellular
    }
}

// MARK: - Bandwidth Limit

/// Speed limit configuration
struct BandwidthLimit: Codable, Equatable {
    var isEnabled: Bool
    var downloadSpeed: Int64 // bytes per second (0 = unlimited)
    var uploadSpeed: Int64 // bytes per second (0 = unlimited)
    
    init(isEnabled: Bool = false, downloadSpeed: Int64 = 0, uploadSpeed: Int64 = 0) {
        self.isEnabled = isEnabled
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
    }
    
    var downloadSpeedMBps: Double {
        return Double(downloadSpeed) / 1_000_000.0
    }
    
    var uploadSpeedMBps: Double {
        return Double(uploadSpeed) / 1_000_000.0
    }
    
    var isUnlimited: Bool {
        return downloadSpeed == 0 && uploadSpeed == 0
    }
    
    func formattedDownloadSpeed() -> String {
        if downloadSpeed == 0 {
            return "Unlimited"
        }
        return ByteCountFormatter.string(fromByteCount: downloadSpeed, countStyle: .binary) + "/s"
    }
    
    func formattedUploadSpeed() -> String {
        if uploadSpeed == 0 {
            return "Unlimited"
        }
        return ByteCountFormatter.string(fromByteCount: uploadSpeed, countStyle: .binary) + "/s"
    }
}

// MARK: - Bandwidth Schedule

/// Time-based bandwidth allocation
struct BandwidthTimeSchedule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var startTime: Date
    var endTime: Date
    var daysOfWeek: Set<Int> // 1 = Sunday, 2 = Monday, etc.
    var limit: BandwidthLimit
    var priority: Int // Higher priority schedules take precedence
    
    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        startTime: Date,
        endTime: Date,
        daysOfWeek: Set<Int> = [1, 2, 3, 4, 5, 6, 7],
        limit: BandwidthLimit,
        priority: Int = 5
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.startTime = startTime
        self.endTime = endTime
        self.daysOfWeek = daysOfWeek
        self.limit = limit
        self.priority = priority
    }
    
    /// Check if schedule is active at given time
    func isActive(at date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        
        // Check day of week
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        guard daysOfWeek.contains(weekday) else { return false }
        
        // Check time range
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        let currentComponents = calendar.dateComponents([.hour, .minute], from: date)
        
        let currentMinutes = (currentComponents.hour ?? 0) * 60 + (currentComponents.minute ?? 0)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
        
        // Handle overnight schedules
        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes <= endMinutes
        } else {
            return currentMinutes >= startMinutes || currentMinutes <= endMinutes
        }
    }
    
    func formattedTimeRange() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    func formattedDays() -> String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if daysOfWeek.count == 7 {
            return "Every day"
        } else if daysOfWeek.count == 5 && !daysOfWeek.contains(1) && !daysOfWeek.contains(7) {
            return "Weekdays"
        } else if daysOfWeek.count == 2 && daysOfWeek.contains(1) && daysOfWeek.contains(7) {
            return "Weekends"
        } else {
            return daysOfWeek.sorted().map { dayNames[$0 - 1] }.joined(separator: ", ")
        }
    }
}

// MARK: - Network Configuration

/// Per-network bandwidth configuration
struct BandwidthNetworkConfiguration: Identifiable, Codable, Equatable {
    let id: UUID
    var networkType: NetworkType
    var limit: BandwidthLimit
    var autoApply: Bool // Apply automatically when this network is detected
    var allowMeteredDownloads: Bool // Allow downloads on metered connections
    
    init(
        id: UUID = UUID(),
        networkType: NetworkType,
        limit: BandwidthLimit = BandwidthLimit(),
        autoApply: Bool = true,
        allowMeteredDownloads: Bool = false
    ) {
        self.id = id
        self.networkType = networkType
        self.limit = limit
        self.autoApply = autoApply
        self.allowMeteredDownloads = allowMeteredDownloads
    }
}

// MARK: - Bandwidth Statistics

/// Bandwidth usage statistics
struct BandwidthStatistics: Codable {
    var totalBytesDownloaded: Int64
    var totalBytesUploaded: Int64
    var peakDownloadSpeed: Int64
    var peakUploadSpeed: Int64
    var averageDownloadSpeed: Int64
    var averageUploadSpeed: Int64
    var sessionStartTime: Date
    var lastResetDate: Date
    
    // Historical data for graphs (last 60 data points)
    var downloadSpeedHistory: [SpeedDataPoint]
    var uploadSpeedHistory: [SpeedDataPoint]
    
    init() {
        self.totalBytesDownloaded = 0
        self.totalBytesUploaded = 0
        self.peakDownloadSpeed = 0
        self.peakUploadSpeed = 0
        self.averageDownloadSpeed = 0
        self.averageUploadSpeed = 0
        self.sessionStartTime = Date()
        self.lastResetDate = Date()
        self.downloadSpeedHistory = []
        self.uploadSpeedHistory = []
    }
    
    mutating func recordDownload(bytes: Int64, speed: Int64) {
        totalBytesDownloaded += bytes
        
        if speed > peakDownloadSpeed {
            peakDownloadSpeed = speed
        }
        
        // Update average (simple moving average)
        let totalSamples = downloadSpeedHistory.count + 1
        averageDownloadSpeed = (averageDownloadSpeed * Int64(downloadSpeedHistory.count) + speed) / Int64(totalSamples)
        
        // Add to history
        let dataPoint = SpeedDataPoint(timestamp: Date(), speed: speed)
        downloadSpeedHistory.append(dataPoint)
        
        // Keep only last 60 points
        if downloadSpeedHistory.count > 60 {
            downloadSpeedHistory.removeFirst()
        }
    }
    
    mutating func recordUpload(bytes: Int64, speed: Int64) {
        totalBytesUploaded += bytes
        
        if speed > peakUploadSpeed {
            peakUploadSpeed = speed
        }
        
        // Update average
        let totalSamples = uploadSpeedHistory.count + 1
        averageUploadSpeed = (averageUploadSpeed * Int64(uploadSpeedHistory.count) + speed) / Int64(totalSamples)
        
        // Add to history
        let dataPoint = SpeedDataPoint(timestamp: Date(), speed: speed)
        uploadSpeedHistory.append(dataPoint)
        
        // Keep only last 60 points
        if uploadSpeedHistory.count > 60 {
            uploadSpeedHistory.removeFirst()
        }
    }
    
    mutating func reset() {
        totalBytesDownloaded = 0
        totalBytesUploaded = 0
        peakDownloadSpeed = 0
        peakUploadSpeed = 0
        averageDownloadSpeed = 0
        averageUploadSpeed = 0
        lastResetDate = Date()
        downloadSpeedHistory.removeAll()
        uploadSpeedHistory.removeAll()
    }
    
    var sessionDuration: TimeInterval {
        return Date().timeIntervalSince(sessionStartTime)
    }
    
    var formattedTotalDownloaded: String {
        return ByteCountFormatter.string(fromByteCount: totalBytesDownloaded, countStyle: .file)
    }
    
    var formattedTotalUploaded: String {
        return ByteCountFormatter.string(fromByteCount: totalBytesUploaded, countStyle: .file)
    }
    
    var formattedPeakDownloadSpeed: String {
        return ByteCountFormatter.string(fromByteCount: peakDownloadSpeed, countStyle: .binary) + "/s"
    }
    
    var formattedPeakUploadSpeed: String {
        return ByteCountFormatter.string(fromByteCount: peakUploadSpeed, countStyle: .binary) + "/s"
    }
    
    var formattedAverageDownloadSpeed: String {
        return ByteCountFormatter.string(fromByteCount: averageDownloadSpeed, countStyle: .binary) + "/s"
    }
    
    var formattedAverageUploadSpeed: String {
        return ByteCountFormatter.string(fromByteCount: averageUploadSpeed, countStyle: .binary) + "/s"
    }
}

// MARK: - Speed Data Point

/// Single speed measurement for graphing
struct SpeedDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let speed: Int64 // bytes per second
    
    init(id: UUID = UUID(), timestamp: Date, speed: Int64) {
        self.id = id
        self.timestamp = timestamp
        self.speed = speed
    }
    
    var speedMBps: Double {
        return Double(speed) / 1_000_000.0
    }
}

// MARK: - Bandwidth Rule

/// Custom bandwidth allocation rule
struct BandwidthRule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var condition: BandwidthCondition
    var limit: BandwidthLimit
    var priority: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        condition: BandwidthCondition,
        limit: BandwidthLimit,
        priority: Int = 5
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.condition = condition
        self.limit = limit
        self.priority = priority
    }
    
    func matches(task: DownloadTask, networkType: NetworkType) -> Bool {
        guard isEnabled else { return false }
        
        switch condition {
        case .fileSize(let min, let max):
            return task.totalBytes >= min && (max == nil || task.totalBytes <= max!)
            
        case .fileType(let extensions):
            let fileExtension = (task.destinationPath.lastPathComponent as NSString).pathExtension.lowercased()
            return extensions.contains(fileExtension)
            
        case .sourceURL(let pattern):
            return task.url.absoluteString.contains(pattern)
            
        case .networkType(let type):
            return networkType == type
            
        case .priority(let taskPriority):
            return task.priority == taskPriority
            
        case .category(let cat):
            return task.category == cat
            
        case .combined(let conditions):
            return conditions.allSatisfy { subCondition in
                // Recursively check sub-conditions
                let tempRule = BandwidthRule(name: "", condition: subCondition, limit: limit)
                return tempRule.matches(task: task, networkType: networkType)
            }
        }
    }
}

// MARK: - Bandwidth Condition

/// Condition for bandwidth rule matching
enum BandwidthCondition: Codable, Equatable {
    case fileSize(min: Int64, max: Int64?)
    case fileType(extensions: [String])
    case sourceURL(pattern: String)
    case networkType(NetworkType)
    case priority(DownloadPriority)
    case category(DownloadCategory)
    case combined([BandwidthCondition])
    
    var description: String {
        switch self {
        case .fileSize(let min, let max):
            let minStr = ByteCountFormatter.string(fromByteCount: min, countStyle: .file)
            if let max = max {
                let maxStr = ByteCountFormatter.string(fromByteCount: max, countStyle: .file)
                return "File size: \(minStr) - \(maxStr)"
            }
            return "File size: ≥ \(minStr)"
            
        case .fileType(let extensions):
            return "File type: \(extensions.joined(separator: ", "))"
            
        case .sourceURL(let pattern):
            return "Source URL contains: \(pattern)"
            
        case .networkType(let type):
            return "Network type: \(type.rawValue)"
            
        case .priority(let priority):
            return "Priority: \(priority.rawValue)"
            
        case .category(let category):
            return "Category: \(category.rawValue)"
            
        case .combined(let conditions):
            return "\(conditions.count) conditions"
        }
    }
}

// MARK: - Bandwidth Profile

/// Predefined bandwidth profile
struct BandwidthProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var icon: String
    var downloadSpeed: Int64
    var uploadSpeed: Int64
    var isPredefined: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "gauge",
        downloadSpeed: Int64,
        uploadSpeed: Int64,
        isPredefined: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.isPredefined = isPredefined
    }
    
    static let unlimited = BandwidthProfile(
        name: "Unlimited",
        icon: "infinity",
        downloadSpeed: 0,
        uploadSpeed: 0,
        isPredefined: true
    )
    
    static let highSpeed = BandwidthProfile(
        name: "High Speed",
        icon: "hare",
        downloadSpeed: 0,
        uploadSpeed: 5_000_000, // 5 MB/s
        isPredefined: true
    )
    
    static let balanced = BandwidthProfile(
        name: "Balanced",
        icon: "scale.3d",
        downloadSpeed: 10_000_000, // 10 MB/s
        uploadSpeed: 2_000_000, // 2 MB/s
        isPredefined: true
    )
    
    static let conservative = BandwidthProfile(
        name: "Conservative",
        icon: "tortoise",
        downloadSpeed: 1_000_000, // 1 MB/s
        uploadSpeed: 500_000, // 500 KB/s
        isPredefined: true
    )
    
    static let predefinedProfiles: [BandwidthProfile] = [
        .unlimited, .highSpeed, .balanced, .conservative
    ]
}
