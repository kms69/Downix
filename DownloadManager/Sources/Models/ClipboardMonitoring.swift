//
//  ClipboardMonitoring.swift
//  Download Manager for Mac - Feature #17: URL Monitoring & Clipboard
//
//  Created on February 17, 2026
//

import Foundation

// MARK: - Clipboard Monitoring Settings

/// Configuration for clipboard monitoring behavior
public struct ClipboardMonitoringSettings: Codable, Equatable {
    public var isEnabled: Bool
    public var autoDownload: Bool
    public var showConfirmation: Bool
    public var soundEnabled: Bool
    public var notificationEnabled: Bool
    public var minimumURLLength: Int
    public var pollingInterval: TimeInterval
    public var detectPartialURLs: Bool
    
    public init(
        isEnabled: Bool = false,
        autoDownload: Bool = false,
        showConfirmation: Bool = true,
        soundEnabled: Bool = true,
        notificationEnabled: Bool = true,
        minimumURLLength: Int = 10,
        pollingInterval: TimeInterval = 0.5,
        detectPartialURLs: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.autoDownload = autoDownload
        self.showConfirmation = showConfirmation
        self.soundEnabled = soundEnabled
        self.notificationEnabled = notificationEnabled
        self.minimumURLLength = minimumURLLength
        self.pollingInterval = pollingInterval
        self.detectPartialURLs = detectPartialURLs
    }
}

// MARK: - URL Pattern Rule

/// Rule for matching and handling URLs
public struct URLPatternRule: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var pattern: ClipboardURLPattern
    public var action: URLAction
    public var priority: Int
    public var isEnabled: Bool
    public var createdDate: Date
    public var lastMatchDate: Date?
    public var matchCount: Int
    
    public init(
        id: UUID = UUID(),
        name: String,
        pattern: ClipboardURLPattern,
        action: URLAction = .ask,
        priority: Int = 0,
        isEnabled: Bool = true,
        createdDate: Date = Date(),
        lastMatchDate: Date? = nil,
        matchCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.action = action
        self.priority = priority
        self.isEnabled = isEnabled
        self.createdDate = createdDate
        self.lastMatchDate = lastMatchDate
        self.matchCount = matchCount
    }
    
    /// Check if URL matches this rule
    public func matches(_ url: URL) -> Bool {
        guard isEnabled else { return false }
        return pattern.matches(url)
    }
}

// MARK: - URL Pattern

/// Pattern types for URL matching
public enum ClipboardURLPattern: Codable, Equatable, Hashable {
    case domain(String)
    case subdomain(String)
    case path(String)
    case fileExtension([String])
    case regex(String)
    case contains(String)
    case custom((URL) -> Bool)
    
    enum CodingKeys: String, CodingKey {
        case type, value, extensions
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "domain":
            let value = try container.decode(String.self, forKey: .value)
            self = .domain(value)
        case "subdomain":
            let value = try container.decode(String.self, forKey: .value)
            self = .subdomain(value)
        case "path":
            let value = try container.decode(String.self, forKey: .value)
            self = .path(value)
        case "fileExtension":
            let extensions = try container.decode([String].self, forKey: .extensions)
            self = .fileExtension(extensions)
        case "regex":
            let value = try container.decode(String.self, forKey: .value)
            self = .regex(value)
        case "contains":
            let value = try container.decode(String.self, forKey: .value)
            self = .contains(value)
        default:
            self = .contains("")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .domain(let value):
            try container.encode("domain", forKey: .type)
            try container.encode(value, forKey: .value)
        case .subdomain(let value):
            try container.encode("subdomain", forKey: .type)
            try container.encode(value, forKey: .value)
        case .path(let value):
            try container.encode("path", forKey: .type)
            try container.encode(value, forKey: .value)
        case .fileExtension(let extensions):
            try container.encode("fileExtension", forKey: .type)
            try container.encode(extensions, forKey: .extensions)
        case .regex(let value):
            try container.encode("regex", forKey: .type)
            try container.encode(value, forKey: .value)
        case .contains(let value):
            try container.encode("contains", forKey: .type)
            try container.encode(value, forKey: .value)
        case .custom:
            try container.encode("custom", forKey: .type)
        }
    }
    
    public static func == (lhs: ClipboardURLPattern, rhs: ClipboardURLPattern) -> Bool {
        switch (lhs, rhs) {
        case (.domain(let a), .domain(let b)): return a == b
        case (.subdomain(let a), .subdomain(let b)): return a == b
        case (.path(let a), .path(let b)): return a == b
        case (.fileExtension(let a), .fileExtension(let b)): return a == b
        case (.regex(let a), .regex(let b)): return a == b
        case (.contains(let a), .contains(let b)): return a == b
        case (.custom, .custom): return true
        default: return false
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .domain(let value):
            hasher.combine("domain")
            hasher.combine(value)
        case .subdomain(let value):
            hasher.combine("subdomain")
            hasher.combine(value)
        case .path(let value):
            hasher.combine("path")
            hasher.combine(value)
        case .fileExtension(let extensions):
            hasher.combine("fileExtension")
            hasher.combine(extensions)
        case .regex(let value):
            hasher.combine("regex")
            hasher.combine(value)
        case .contains(let value):
            hasher.combine("contains")
            hasher.combine(value)
        case .custom:
            hasher.combine("custom")
        }
    }
    
    /// Check if URL matches this pattern
    public func matches(_ url: URL) -> Bool {
        let urlString = url.absoluteString
        
        switch self {
        case .domain(let domain):
            return url.host?.lowercased() == domain.lowercased()
            
        case .subdomain(let subdomain):
            guard let host = url.host?.lowercased() else { return false }
            return host == subdomain.lowercased() || host.hasSuffix(".\(subdomain.lowercased())")
            
        case .path(let path):
            return url.path.lowercased().contains(path.lowercased())
            
        case .fileExtension(let extensions):
            let pathExtension = url.pathExtension.lowercased()
            return extensions.contains { $0.lowercased() == pathExtension }
            
        case .regex(let pattern):
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(urlString.startIndex..., in: urlString)
            return regex.firstMatch(in: urlString, range: range) != nil
            
        case .contains(let substring):
            return urlString.lowercased().contains(substring.lowercased())
            
        case .custom(let matcher):
            return matcher(url)
        }
    }
    
    public var displayName: String {
        switch self {
        case .domain(let domain):
            return "Domain: \(domain)"
        case .subdomain(let subdomain):
            return "Subdomain: \(subdomain)"
        case .path(let path):
            return "Path: \(path)"
        case .fileExtension(let extensions):
            return "Extensions: \(extensions.joined(separator: ", "))"
        case .regex(let pattern):
            return "Regex: \(pattern)"
        case .contains(let substring):
            return "Contains: \(substring)"
        case .custom:
            return "Custom Rule"
        }
    }
}

// MARK: - URL Action

/// Action to take when URL is detected
public enum URLAction: String, Codable, CaseIterable, Equatable, Hashable {
    case download = "Download"
    case ask = "Ask"
    case ignore = "Ignore"
    case addToQueue = "Add to Queue"
    case copyToClipboard = "Copy to Clipboard"
    
    public var icon: String {
        switch self {
        case .download: return "arrow.down.circle.fill"
        case .ask: return "questionmark.circle"
        case .ignore: return "xmark.circle"
        case .addToQueue: return "list.bullet"
        case .copyToClipboard: return "doc.on.clipboard"
        }
    }
    
    public var color: String {
        switch self {
        case .download: return "green"
        case .ask: return "blue"
        case .ignore: return "gray"
        case .addToQueue: return "orange"
        case .copyToClipboard: return "purple"
        }
    }
}

// MARK: - Domain List

/// List type for domain filtering
public enum DomainListType: String, Codable, CaseIterable {
    case whitelist = "Whitelist"
    case blacklist = "Blacklist"
    
    public var icon: String {
        switch self {
        case .whitelist: return "checkmark.circle.fill"
        case .blacklist: return "xmark.circle.fill"
        }
    }
    
    public var color: String {
        switch self {
        case .whitelist: return "green"
        case .blacklist: return "red"
        }
    }
}

/// Domain entry for whitelist/blacklist
public struct DomainEntry: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var domain: String
    public var type: DomainListType
    public var isEnabled: Bool
    public var notes: String
    public var createdDate: Date
    public var lastMatchDate: Date?
    public var matchCount: Int
    
    public init(
        id: UUID = UUID(),
        domain: String,
        type: DomainListType,
        isEnabled: Bool = true,
        notes: String = "",
        createdDate: Date = Date(),
        lastMatchDate: Date? = nil,
        matchCount: Int = 0
    ) {
        self.id = id
        self.domain = domain
        self.type = type
        self.isEnabled = isEnabled
        self.notes = notes
        self.createdDate = createdDate
        self.lastMatchDate = lastMatchDate
        self.matchCount = matchCount
    }
    
    /// Check if domain matches this entry
    public func matches(_ url: URL) -> Bool {
        guard isEnabled, let host = url.host else { return false }
        let cleanDomain = domain.lowercased().replacingOccurrences(of: "www.", with: "")
        let cleanHost = host.lowercased().replacingOccurrences(of: "www.", with: "")
        
        return cleanHost == cleanDomain || cleanHost.hasSuffix(".\(cleanDomain)")
    }
}

// MARK: - Detected URL

/// URL detected from clipboard
public struct DetectedURL: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let url: URL
    public let detectedDate: Date
    public var isValid: Bool
    public var fileSize: Int64?
    public var fileName: String?
    public var mimeType: String?
    public var matchedRules: [URLPatternRule]
    public var suggestedAction: URLAction
    public var status: DetectionStatus
    
    public init(
        id: UUID = UUID(),
        url: URL,
        detectedDate: Date = Date(),
        isValid: Bool = true,
        fileSize: Int64? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        matchedRules: [URLPatternRule] = [],
        suggestedAction: URLAction = .ask,
        status: DetectionStatus = .pending
    ) {
        self.id = id
        self.url = url
        self.detectedDate = detectedDate
        self.isValid = isValid
        self.fileSize = fileSize
        self.fileName = fileName
        self.mimeType = mimeType
        self.matchedRules = matchedRules
        self.suggestedAction = suggestedAction
        self.status = status
    }
}

// MARK: - Detection Status

/// Status of detected URL
public enum DetectionStatus: String, CaseIterable, Equatable, Hashable {
    case pending = "Pending"
    case validating = "Validating"
    case valid = "Valid"
    case invalid = "Invalid"
    case downloading = "Downloading"
    case completed = "Completed"
    case ignored = "Ignored"
    case error = "Error"
    
    public var icon: String {
        switch self {
        case .pending: return "clock"
        case .validating: return "arrow.triangle.2.circlepath"
        case .valid: return "checkmark.circle"
        case .invalid: return "xmark.circle"
        case .downloading: return "arrow.down.circle"
        case .completed: return "checkmark.circle.fill"
        case .ignored: return "eye.slash"
        case .error: return "exclamationmark.triangle"
        }
    }
    
    public var color: String {
        switch self {
        case .pending: return "orange"
        case .validating: return "blue"
        case .valid: return "green"
        case .invalid: return "red"
        case .downloading: return "blue"
        case .completed: return "green"
        case .ignored: return "gray"
        case .error: return "red"
        }
    }
}

// MARK: - URL Validation Result

/// Result of URL validation
public struct ClipboardURLValidationResult: Equatable {
    public let url: URL
    public var isValid: Bool
    public var isReachable: Bool
    public var fileSize: Int64?
    public var fileName: String?
    public var mimeType: String?
    public var serverSupportsResume: Bool
    public var error: ClipboardURLValidationError?
    
    public init(
        url: URL,
        isValid: Bool = true,
        isReachable: Bool = true,
        fileSize: Int64? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        serverSupportsResume: Bool = false,
        error: ClipboardURLValidationError? = nil
    ) {
        self.url = url
        self.isValid = isValid
        self.isReachable = isReachable
        self.fileSize = fileSize
        self.fileName = fileName
        self.mimeType = mimeType
        self.serverSupportsResume = serverSupportsResume
        self.error = error
    }
}

// MARK: - URL Validation Error

/// Errors that can occur during URL validation
public enum ClipboardURLValidationError: Error, LocalizedError, Equatable {
    case invalidURL
    case unreachable
    case timeout
    case forbidden
    case notFound
    case serverError
    case networkError(String)
    case unsupportedProtocol
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL format"
        case .unreachable:
            return "URL is not reachable"
        case .timeout:
            return "Connection timeout"
        case .forbidden:
            return "Access forbidden (403)"
        case .notFound:
            return "Resource not found (404)"
        case .serverError:
            return "Server error occurred"
        case .networkError(let message):
            return "Network error: \(message)"
        case .unsupportedProtocol:
            return "Unsupported protocol"
        }
    }
}

// MARK: - Clipboard Monitoring Statistics

/// Statistics for clipboard monitoring
public struct ClipboardMonitoringStats: Codable, Equatable {
    public var totalURLsDetected: Int
    public var validURLsCount: Int
    public var invalidURLsCount: Int
    public var autoDownloadedCount: Int
    public var ignoredCount: Int
    public var lastDetectionDate: Date?
    public var monitoringStartDate: Date
    public var detectionsByDomain: [String: Int]
    
    public init(
        totalURLsDetected: Int = 0,
        validURLsCount: Int = 0,
        invalidURLsCount: Int = 0,
        autoDownloadedCount: Int = 0,
        ignoredCount: Int = 0,
        lastDetectionDate: Date? = nil,
        monitoringStartDate: Date = Date(),
        detectionsByDomain: [String: Int] = [:]
    ) {
        self.totalURLsDetected = totalURLsDetected
        self.validURLsCount = validURLsCount
        self.invalidURLsCount = invalidURLsCount
        self.autoDownloadedCount = autoDownloadedCount
        self.ignoredCount = ignoredCount
        self.lastDetectionDate = lastDetectionDate
        self.monitoringStartDate = monitoringStartDate
        self.detectionsByDomain = detectionsByDomain
    }
    
    public var detectionRate: Double {
        guard totalURLsDetected > 0 else { return 0 }
        return Double(validURLsCount) / Double(totalURLsDetected)
    }
    
    public var autoDownloadRate: Double {
        guard validURLsCount > 0 else { return 0 }
        return Double(autoDownloadedCount) / Double(validURLsCount)
    }
}
