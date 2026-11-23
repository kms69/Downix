//
//  ErrorRecovery.swift
//  Download Manager
//
//  Feature #22: Advanced Error Recovery
//  Created on February 17, 2026
//

import Foundation

// MARK: - Error Types

/// Types of download errors that can occur
public enum DownloadErrorType: String, Codable, Equatable, CaseIterable {
    case networkConnection = "network_connection"
    case serverTimeout = "server_timeout"
    case serverError = "server_error"
    case invalidResponse = "invalid_response"
    case diskSpace = "disk_space"
    case filePermission = "file_permission"
    case checksumMismatch = "checksum_mismatch"
    case partialContent = "partial_content"
    case rateLimited = "rate_limited"
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .networkConnection: return "Network Connection Error"
        case .serverTimeout: return "Server Timeout"
        case .serverError: return "Server Error"
        case .invalidResponse: return "Invalid Response"
        case .diskSpace: return "Insufficient Disk Space"
        case .filePermission: return "File Permission Denied"
        case .checksumMismatch: return "Checksum Mismatch"
        case .partialContent: return "Partial Content Error"
        case .rateLimited: return "Rate Limited"
        case .unknown: return "Unknown Error"
        }
    }
    
    public var icon: String {
        switch self {
        case .networkConnection: return "wifi.exclamationmark"
        case .serverTimeout: return "clock.badge.exclamationmark"
        case .serverError: return "server.rack"
        case .invalidResponse: return "exclamationmark.bubble"
        case .diskSpace: return "internaldrive.fill"
        case .filePermission: return "lock.fill"
        case .checksumMismatch: return "checkmark.seal.fill"
        case .partialContent: return "doc.badge.ellipsis"
        case .rateLimited: return "speedometer"
        case .unknown: return "questionmark.circle"
        }
    }
    
    /// Whether this error is recoverable
    public var isRecoverable: Bool {
        switch self {
        case .networkConnection, .serverTimeout, .serverError, .partialContent, .rateLimited:
            return true
        case .invalidResponse, .diskSpace, .filePermission, .checksumMismatch, .unknown:
            return false
        }
    }
    
    /// Recommended retry strategy for this error type
    public var recommendedStrategy: RetryStrategy {
        switch self {
        case .networkConnection: return .exponentialBackoff
        case .serverTimeout: return .exponentialBackoff
        case .serverError: return .linearDelay
        case .partialContent: return .immediate
        case .rateLimited: return .exponentialBackoff
        default: return .none
        }
    }
}

// MARK: - Retry Strategies

/// Retry strategy for failed downloads
public enum RetryStrategy: String, Codable, Equatable, CaseIterable {
    case none = "none"
    case immediate = "immediate"
    case linearDelay = "linear_delay"
    case exponentialBackoff = "exponential_backoff"
    case custom = "custom"
    
    public var displayName: String {
        switch self {
        case .none: return "No Retry"
        case .immediate: return "Immediate Retry"
        case .linearDelay: return "Linear Delay"
        case .exponentialBackoff: return "Exponential Backoff"
        case .custom: return "Custom Strategy"
        }
    }
    
    public var description: String {
        switch self {
        case .none: return "Do not retry failed downloads"
        case .immediate: return "Retry immediately without delay"
        case .linearDelay: return "Wait same amount before each retry (e.g., 5s, 5s, 5s)"
        case .exponentialBackoff: return "Wait increasingly longer (e.g., 1s, 2s, 4s, 8s)"
        case .custom: return "Use custom retry intervals"
        }
    }
    
    public var icon: String {
        switch self {
        case .none: return "xmark.circle"
        case .immediate: return "arrow.clockwise"
        case .linearDelay: return "chart.line.flattrend.xyaxis"
        case .exponentialBackoff: return "chart.line.uptrend.xyaxis"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    /// Calculate delay for given attempt number
    public func delay(forAttempt attempt: Int, baseDelay: TimeInterval) -> TimeInterval {
        switch self {
        case .none:
            return 0
        case .immediate:
            return 0
        case .linearDelay:
            return baseDelay
        case .exponentialBackoff:
            let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
            let maxDelay: TimeInterval = 300.0 // Cap at 5 minutes
            return min(exponentialDelay, maxDelay)
        case .custom:
            return baseDelay
        }
    }
}

// MARK: - Recovery Actions

/// Actions to take when download fails
public enum RecoveryAction: String, Codable, Equatable, CaseIterable {
    case retry = "retry"
    case tryMirror = "try_mirror"
    case reduceConnections = "reduce_connections"
    case changeNetwork = "change_network"
    case resumePartial = "resume_partial"
    case redownload = "redownload"
    case skipFile = "skip_file"
    case manualIntervention = "manual"
    
    public var displayName: String {
        switch self {
        case .retry: return "Retry Download"
        case .tryMirror: return "Try Mirror Server"
        case .reduceConnections: return "Reduce Connections"
        case .changeNetwork: return "Change Network"
        case .resumePartial: return "Resume Partial"
        case .redownload: return "Redownload File"
        case .skipFile: return "Skip File"
        case .manualIntervention: return "Manual Intervention"
        }
    }
    
    public var icon: String {
        switch self {
        case .retry: return "arrow.clockwise"
        case .tryMirror: return "server.rack"
        case .reduceConnections: return "arrow.down.right.circle"
        case .changeNetwork: return "network"
        case .resumePartial: return "play.circle"
        case .redownload: return "arrow.down.circle"
        case .skipFile: return "forward.circle"
        case .manualIntervention: return "person.circle"
        }
    }
    
    public var description: String {
        switch self {
        case .retry: return "Retry the failed download with same settings"
        case .tryMirror: return "Find and use an alternative download source"
        case .reduceConnections: return "Reduce number of parallel connections"
        case .changeNetwork: return "Detect and switch to better network"
        case .resumePartial: return "Resume from partially downloaded content"
        case .redownload: return "Start download from beginning"
        case .skipFile: return "Skip this file and continue with queue"
        case .manualIntervention: return "Wait for user to decide action"
        }
    }
}

// MARK: - Network Change Detection

/// Connection interface types
public enum ConnectionType: String, Codable, Equatable {
    case wifi = "wifi"
    case ethernet = "ethernet"
    case cellular = "cellular"
    case vpn = "vpn"
    case unknown = "unknown"
    
    public var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .vpn: return "VPN"
        case .unknown: return "Unknown"
        }
    }
    
    public var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .vpn: return "lock.shield"
        case .unknown: return "network"
        }
    }
    
    /// Reliability score (higher is better)
    public var reliabilityScore: Int {
        switch self {
        case .ethernet: return 100
        case .wifi: return 80
        case .vpn: return 60
        case .cellular: return 40
        case .unknown: return 0
        }
    }
}

/// Network change event
public struct NetworkChangeEvent: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let previousNetwork: ConnectionType
    public let currentNetwork: ConnectionType
    public let isImprovement: Bool
    public let affectedDownloads: [UUID] // Download task IDs
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        previousNetwork: ConnectionType,
        currentNetwork: ConnectionType,
        affectedDownloads: [UUID] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.previousNetwork = previousNetwork
        self.currentNetwork = currentNetwork
        self.isImprovement = currentNetwork.reliabilityScore > previousNetwork.reliabilityScore
        self.affectedDownloads = affectedDownloads
    }
}

// MARK: - Recovery Attempt

/// Record of a recovery attempt
public struct RecoveryAttempt: Identifiable, Codable, Equatable {
    public let id: UUID
    public let downloadTaskId: UUID
    public let attemptNumber: Int
    public let timestamp: Date
    public let errorType: DownloadErrorType
    public let strategy: RetryStrategy
    public let action: RecoveryAction
    public let delayUsed: TimeInterval
    public var wasSuccessful: Bool
    public var errorMessage: String?
    public var mirrorUrlUsed: String?
    public var connectionsReduced: Int?
    
    public init(
        id: UUID = UUID(),
        downloadTaskId: UUID,
        attemptNumber: Int,
        timestamp: Date = Date(),
        errorType: DownloadErrorType,
        strategy: RetryStrategy,
        action: RecoveryAction,
        delayUsed: TimeInterval,
        wasSuccessful: Bool = false,
        errorMessage: String? = nil,
        mirrorUrlUsed: String? = nil,
        connectionsReduced: Int? = nil
    ) {
        self.id = id
        self.downloadTaskId = downloadTaskId
        self.attemptNumber = attemptNumber
        self.timestamp = timestamp
        self.errorType = errorType
        self.strategy = strategy
        self.action = action
        self.delayUsed = delayUsed
        self.wasSuccessful = wasSuccessful
        self.errorMessage = errorMessage
        self.mirrorUrlUsed = mirrorUrlUsed
        self.connectionsReduced = connectionsReduced
    }
}

// MARK: - Recovery Configuration

/// Configuration for error recovery system
public struct RecoveryConfiguration: Codable, Equatable {
    public var isEnabled: Bool
    public var autoRetryOnFailure: Bool
    public var maxRetryAttempts: Int
    public var retryStrategy: RetryStrategy
    public var baseDelay: TimeInterval
    public var enableMirrorFallback: Bool
    public var enableNetworkChangeDetection: Bool
    public var enablePartialRecovery: Bool
    public var reduceConnectionsOnError: Bool
    public var minConnections: Int
    public var notifyOnRecovery: Bool
    public var notifyOnFailure: Bool
    public var trackRecoveryHistory: Bool
    public var maxHistoryEntries: Int
    
    public init(
        isEnabled: Bool = true,
        autoRetryOnFailure: Bool = true,
        maxRetryAttempts: Int = 5,
        retryStrategy: RetryStrategy = .exponentialBackoff,
        baseDelay: TimeInterval = 2.0,
        enableMirrorFallback: Bool = true,
        enableNetworkChangeDetection: Bool = true,
        enablePartialRecovery: Bool = true,
        reduceConnectionsOnError: Bool = true,
        minConnections: Int = 1,
        notifyOnRecovery: Bool = true,
        notifyOnFailure: Bool = true,
        trackRecoveryHistory: Bool = true,
        maxHistoryEntries: Int = 1000
    ) {
        self.isEnabled = isEnabled
        self.autoRetryOnFailure = autoRetryOnFailure
        self.maxRetryAttempts = maxRetryAttempts
        self.retryStrategy = retryStrategy
        self.baseDelay = baseDelay
        self.enableMirrorFallback = enableMirrorFallback
        self.enableNetworkChangeDetection = enableNetworkChangeDetection
        self.enablePartialRecovery = enablePartialRecovery
        self.reduceConnectionsOnError = reduceConnectionsOnError
        self.minConnections = minConnections
        self.notifyOnRecovery = notifyOnRecovery
        self.notifyOnFailure = notifyOnFailure
        self.trackRecoveryHistory = trackRecoveryHistory
        self.maxHistoryEntries = maxHistoryEntries
    }
    
    /// Conservative preset - fewer retries, longer delays
    public static let conservative = RecoveryConfiguration(
        maxRetryAttempts: 3,
        retryStrategy: .exponentialBackoff,
        baseDelay: 5.0,
        enableMirrorFallback: true,
        reduceConnectionsOnError: true
    )
    
    /// Aggressive preset - more retries, shorter delays
    public static let aggressive = RecoveryConfiguration(
        maxRetryAttempts: 10,
        retryStrategy: .exponentialBackoff,
        baseDelay: 1.0,
        enableMirrorFallback: true,
        reduceConnectionsOnError: false
    )
    
    /// Balanced preset - default settings
    public static let balanced = RecoveryConfiguration()
    
    /// Minimal preset - only basic retry
    public static let minimal = RecoveryConfiguration(
        maxRetryAttempts: 3,
        retryStrategy: .linearDelay,
        baseDelay: 3.0,
        enableMirrorFallback: false,
        enableNetworkChangeDetection: false,
        reduceConnectionsOnError: false
    )
}

// MARK: - Recovery Statistics

/// Statistics for error recovery system
public struct RecoveryStatistics: Codable, Equatable {
    public var totalErrors: Int
    public var totalRecoveryAttempts: Int
    public var successfulRecoveries: Int
    public var failedRecoveries: Int
    public var mirrorFallbacksUsed: Int
    public var networkChangesDetected: Int
    public var partialRecoveriesSuccessful: Int
    public var totalDelayTime: TimeInterval
    public var errorsByType: [DownloadErrorType: Int]
    public var actionsByType: [RecoveryAction: Int]
    public var lastRecoveryDate: Date?
    
    public init(
        totalErrors: Int = 0,
        totalRecoveryAttempts: Int = 0,
        successfulRecoveries: Int = 0,
        failedRecoveries: Int = 0,
        mirrorFallbacksUsed: Int = 0,
        networkChangesDetected: Int = 0,
        partialRecoveriesSuccessful: Int = 0,
        totalDelayTime: TimeInterval = 0,
        errorsByType: [DownloadErrorType: Int] = [:],
        actionsByType: [RecoveryAction: Int] = [:],
        lastRecoveryDate: Date? = nil
    ) {
        self.totalErrors = totalErrors
        self.totalRecoveryAttempts = totalRecoveryAttempts
        self.successfulRecoveries = successfulRecoveries
        self.failedRecoveries = failedRecoveries
        self.mirrorFallbacksUsed = mirrorFallbacksUsed
        self.networkChangesDetected = networkChangesDetected
        self.partialRecoveriesSuccessful = partialRecoveriesSuccessful
        self.totalDelayTime = totalDelayTime
        self.errorsByType = errorsByType
        self.actionsByType = actionsByType
        self.lastRecoveryDate = lastRecoveryDate
    }
    
    /// Recovery success rate (0-100)
    public var successRate: Double {
        guard totalRecoveryAttempts > 0 else { return 0.0 }
        return (Double(successfulRecoveries) / Double(totalRecoveryAttempts)) * 100.0
    }
    
    /// Average delay time per recovery attempt
    public var averageDelayTime: TimeInterval {
        guard totalRecoveryAttempts > 0 else { return 0.0 }
        return totalDelayTime / Double(totalRecoveryAttempts)
    }
    
    /// Most common error type
    public var mostCommonError: DownloadErrorType? {
        errorsByType.max(by: { $0.value < $1.value })?.key
    }
    
    /// Most common recovery action
    public var mostCommonAction: RecoveryAction? {
        actionsByType.max(by: { $0.value < $1.value })?.key
    }
    
    /// Reset all statistics
    public mutating func reset() {
        totalErrors = 0
        totalRecoveryAttempts = 0
        successfulRecoveries = 0
        failedRecoveries = 0
        mirrorFallbacksUsed = 0
        networkChangesDetected = 0
        partialRecoveriesSuccessful = 0
        totalDelayTime = 0
        errorsByType = [:]
        actionsByType = [:]
        lastRecoveryDate = nil
    }
}

// MARK: - Recovery Result

/// Result of a recovery attempt
public struct RecoveryResult: Identifiable, Codable, Equatable {
    public let id: UUID
    public let downloadTaskId: UUID
    public let timestamp: Date
    public let wasSuccessful: Bool
    public let totalAttempts: Int
    public let finalAction: RecoveryAction
    public let errorType: DownloadErrorType
    public let recoveryTime: TimeInterval
    public let attempts: [RecoveryAttempt]
    public var notes: String?
    
    public init(
        id: UUID = UUID(),
        downloadTaskId: UUID,
        timestamp: Date = Date(),
        wasSuccessful: Bool,
        totalAttempts: Int,
        finalAction: RecoveryAction,
        errorType: DownloadErrorType,
        recoveryTime: TimeInterval,
        attempts: [RecoveryAttempt] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.downloadTaskId = downloadTaskId
        self.timestamp = timestamp
        self.wasSuccessful = wasSuccessful
        self.totalAttempts = totalAttempts
        self.finalAction = finalAction
        self.errorType = errorType
        self.recoveryTime = recoveryTime
        self.attempts = attempts
        self.notes = notes
    }
}

// MARK: - Download Health Status

/// Health status of a download
public enum DownloadHealthStatus: String, Codable, Equatable {
    case healthy = "healthy"
    case warning = "warning"
    case unstable = "unstable"
    case failing = "failing"
    case recovered = "recovered"
    
    public var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .unstable: return "Unstable"
        case .failing: return "Failing"
        case .recovered: return "Recovered"
        }
    }
    
    public var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .unstable: return "exclamationmark.circle.fill"
        case .failing: return "xmark.circle.fill"
        case .recovered: return "arrow.uturn.backward.circle.fill"
        }
    }
    
    public var color: String {
        switch self {
        case .healthy: return "green"
        case .warning: return "yellow"
        case .unstable: return "orange"
        case .failing: return "red"
        case .recovered: return "blue"
        }
    }
}

/// Download health monitor data
public struct DownloadHealth: Identifiable, Codable, Equatable {
    public let id: UUID
    public let downloadTaskId: UUID
    public var status: DownloadHealthStatus
    public var errorCount: Int
    public var recoveryAttempts: Int
    public var currentConnections: Int
    public var recommendedConnections: Int
    public var lastErrorType: DownloadErrorType?
    public var lastErrorTime: Date?
    public var averageSpeed: Double // bytes per second
    public var speedVariability: Double // standard deviation
    public var lastHealthCheck: Date
    
    public init(
        id: UUID = UUID(),
        downloadTaskId: UUID,
        status: DownloadHealthStatus = .healthy,
        errorCount: Int = 0,
        recoveryAttempts: Int = 0,
        currentConnections: Int = 1,
        recommendedConnections: Int = 1,
        lastErrorType: DownloadErrorType? = nil,
        lastErrorTime: Date? = nil,
        averageSpeed: Double = 0,
        speedVariability: Double = 0,
        lastHealthCheck: Date = Date()
    ) {
        self.id = id
        self.downloadTaskId = downloadTaskId
        self.status = status
        self.errorCount = errorCount
        self.recoveryAttempts = recoveryAttempts
        self.currentConnections = currentConnections
        self.recommendedConnections = recommendedConnections
        self.lastErrorType = lastErrorType
        self.lastErrorTime = lastErrorTime
        self.averageSpeed = averageSpeed
        self.speedVariability = speedVariability
        self.lastHealthCheck = lastHealthCheck
    }
    
    /// Whether health is degraded
    public var isDegraded: Bool {
        status == .warning || status == .unstable || status == .failing
    }
    
    /// Whether recovery is recommended
    public var needsRecovery: Bool {
        status == .failing || (status == .unstable && errorCount > 2)
    }
}
