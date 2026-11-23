//
//  ResumeCapability.swift
//  Download Manager for Mac - Feature #6: Resume Capability
//
//  Created on February 15, 2026
//

import Foundation

/// Error types for download failures
enum DownloadError: Error, LocalizedError {
    case networkError(UnderlyingError)
    case serverError(Int)
    case fileSystemError(String)
    case resumeNotSupported
    case checksumMismatch
    case insufficientSpace
    case timeout
    case cancelled
    case unknown(String)
    
    struct UnderlyingError: Codable {
        let domain: String
        let code: Int
        let description: String
    }
    
    var errorDescription: String? {
        switch self {
        case .networkError(let underlying):
            return "Network error: \(underlying.description)"
        case .serverError(let code):
            return "Server error: HTTP \(code)"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        case .resumeNotSupported:
            return "Server does not support resume"
        case .checksumMismatch:
            return "File integrity check failed"
        case .insufficientSpace:
            return "Insufficient disk space"
        case .timeout:
            return "Connection timeout"
        case .cancelled:
            return "Download cancelled by user"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkError, .serverError, .timeout:
            return true
        case .cancelled, .insufficientSpace, .checksumMismatch:
            return false
        case .resumeNotSupported, .fileSystemError, .unknown:
            return true
        }
    }
}

/// Retry policy configuration
struct RetryPolicy: Codable, Equatable {
    var maxRetries: Int
    var initialDelay: TimeInterval
    var maxDelay: TimeInterval
    var backoffMultiplier: Double
    var retryableErrorCodes: [Int]
    
    init(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 2.0,
        maxDelay: TimeInterval = 60.0,
        backoffMultiplier: Double = 2.0,
        retryableErrorCodes: [Int] = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.retryableErrorCodes = retryableErrorCodes
    }
    
    /// Calculate delay for a given retry attempt
    func delayForAttempt(_ attempt: Int) -> TimeInterval {
        let delay = initialDelay * pow(backoffMultiplier, Double(attempt))
        return min(delay, maxDelay)
    }
    
    /// Check if an error is retryable
    func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < maxRetries else { return false }
        
        if let downloadError = error as? DownloadError {
            return downloadError.isRetryable
        }
        
        if let urlError = error as? URLError {
            return urlError.isRetryable
        }
        
        return true
    }
    
    // MARK: - Presets
    
    static var aggressive: RetryPolicy {
        RetryPolicy(
            maxRetries: 10,
            initialDelay: 1.0,
            maxDelay: 120.0,
            backoffMultiplier: 1.5
        )
    }
    
    static var conservative: RetryPolicy {
        RetryPolicy(
            maxRetries: 3,
            initialDelay: 5.0,
            maxDelay: 30.0,
            backoffMultiplier: 2.0
        )
    }
    
    static var noRetry: RetryPolicy {
        RetryPolicy(maxRetries: 0, initialDelay: 0, maxDelay: 0, backoffMultiplier: 1.0)
    }
}

/// Resume strategy for handling interrupted downloads
enum ResumeStrategy: String, Codable {
    case automatic      // Try to resume if supported, restart if not
    case resumeOnly     // Only resume, fail if not supported
    case restartOnly    // Always restart from beginning
    case askUser        // Prompt user to choose
    
    var description: String {
        switch self {
        case .automatic:
            return "Resume if possible, restart otherwise"
        case .resumeOnly:
            return "Resume only (fail if not supported)"
        case .restartOnly:
            return "Always restart from beginning"
        case .askUser:
            return "Ask user each time"
        }
    }
}

/// Resume data structure for tracking partial downloads
struct ResumeData: Codable {
    let url: URL
    let destinationPath: URL
    let partialFilePath: URL
    let downloadedBytes: Int64
    let totalBytes: Int64
    let etag: String?
    let lastModified: String?
    let supportsRangeRequests: Bool
    var segmentsProgress: [Int: Int64] // segment index -> bytes downloaded
    let createdAt: Date
    let lastUpdated: Date
    
    init(
        url: URL,
        destinationPath: URL,
        partialFilePath: URL,
        downloadedBytes: Int64,
        totalBytes: Int64,
        etag: String? = nil,
        lastModified: String? = nil,
        supportsRangeRequests: Bool = false,
        segmentsProgress: [Int: Int64] = [:],
        createdAt: Date = Date(),
        lastUpdated: Date = Date()
    ) {
        self.url = url
        self.destinationPath = destinationPath
        self.partialFilePath = partialFilePath
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.etag = etag
        self.lastModified = lastModified
        self.supportsRangeRequests = supportsRangeRequests
        self.segmentsProgress = segmentsProgress
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
    
    var progressPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes) * 100
    }
    
    var canResume: Bool {
        return supportsRangeRequests && (etag != nil || lastModified != nil)
    }
}

/// Retry attempt record
struct RetryAttempt: Identifiable, Codable {
    let id: UUID
    let attemptNumber: Int
    let timestamp: Date
    let error: String
    let delayBeforeRetry: TimeInterval
    
    init(
        id: UUID = UUID(),
        attemptNumber: Int,
        timestamp: Date = Date(),
        error: String,
        delayBeforeRetry: TimeInterval
    ) {
        self.id = id
        self.attemptNumber = attemptNumber
        self.timestamp = timestamp
        self.error = error
        self.delayBeforeRetry = delayBeforeRetry
    }
}

/// Resume capability settings
struct ResumeSettings: Codable {
    var retryPolicy: RetryPolicy
    var resumeStrategy: ResumeStrategy
    var saveResumeData: Bool
    var verifyFileIntegrity: Bool
    var connectionTimeout: TimeInterval
    var enableAutoResume: Bool // Auto-resume on app restart
    var cleanupFailedDownloads: Bool
    var cleanupAfterDays: Int
    
    init(
        retryPolicy: RetryPolicy = RetryPolicy(),
        resumeStrategy: ResumeStrategy = .automatic,
        saveResumeData: Bool = true,
        verifyFileIntegrity: Bool = true,
        connectionTimeout: TimeInterval = 60.0,
        enableAutoResume: Bool = true,
        cleanupFailedDownloads: Bool = false,
        cleanupAfterDays: Int = 7
    ) {
        self.retryPolicy = retryPolicy
        self.resumeStrategy = resumeStrategy
        self.saveResumeData = saveResumeData
        self.verifyFileIntegrity = verifyFileIntegrity
        self.connectionTimeout = connectionTimeout
        self.enableAutoResume = enableAutoResume
        self.cleanupFailedDownloads = cleanupFailedDownloads
        self.cleanupAfterDays = cleanupAfterDays
    }
    
    // MARK: - Presets
    
    static var reliable: ResumeSettings {
        ResumeSettings(
            retryPolicy: .aggressive,
            resumeStrategy: .automatic,
            saveResumeData: true,
            verifyFileIntegrity: true,
            enableAutoResume: true
        )
    }
    
    static var fast: ResumeSettings {
        ResumeSettings(
            retryPolicy: .conservative,
            resumeStrategy: .automatic,
            saveResumeData: false,
            verifyFileIntegrity: false,
            enableAutoResume: false
        )
    }
    
    static var manual: ResumeSettings {
        ResumeSettings(
            retryPolicy: .noRetry,
            resumeStrategy: .askUser,
            saveResumeData: true,
            verifyFileIntegrity: false,
            enableAutoResume: false
        )
    }
}

// MARK: - URLError Extension

extension URLError {
    var isRetryable: Bool {
        switch code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost,
             .networkConnectionLost, .dnsLookupFailed,
             .notConnectedToInternet, .badServerResponse:
            return true
        case .cancelled, .userCancelledAuthentication:
            return false
        default:
            return true
        }
    }
}

// MARK: - Download Statistics

struct DownloadStatistics: Codable {
    var totalAttempts: Int
    var successfulDownloads: Int
    var failedDownloads: Int
    var resumedDownloads: Int
    var restartedDownloads: Int
    var totalRetries: Int
    var averageRetries: Double
    var totalDataDownloaded: Int64
    var totalDataResumed: Int64
    
    init() {
        self.totalAttempts = 0
        self.successfulDownloads = 0
        self.failedDownloads = 0
        self.resumedDownloads = 0
        self.restartedDownloads = 0
        self.totalRetries = 0
        self.averageRetries = 0
        self.totalDataDownloaded = 0
        self.totalDataResumed = 0
    }
    
    mutating func recordSuccess(wasResumed: Bool, retries: Int, bytesDownloaded: Int64) {
        totalAttempts += 1
        successfulDownloads += 1
        totalRetries += retries
        totalDataDownloaded += bytesDownloaded
        
        if wasResumed {
            resumedDownloads += 1
        }
        
        updateAverageRetries()
    }
    
    mutating func recordFailure(retries: Int) {
        totalAttempts += 1
        failedDownloads += 1
        totalRetries += retries
        updateAverageRetries()
    }
    
    mutating func recordRestart(bytesReused: Int64) {
        restartedDownloads += 1
        totalDataResumed += bytesReused
    }
    
    private mutating func updateAverageRetries() {
        guard totalAttempts > 0 else {
            averageRetries = 0
            return
        }
        averageRetries = Double(totalRetries) / Double(totalAttempts)
    }
    
    var successRate: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(successfulDownloads) / Double(totalAttempts) * 100
    }
    
    var resumeRate: Double {
        guard successfulDownloads > 0 else { return 0 }
        return Double(resumedDownloads) / Double(successfulDownloads) * 100
    }
}
