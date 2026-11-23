//
//  FileVerification.swift
//  DownloadManager
//
//  Feature #21: File Verification & Integrity
//  Comprehensive checksum and hash verification system
//

import Foundation
import CryptoKit

// MARK: - Hash Algorithm

/// Supported hash algorithms for file verification
public enum HashAlgorithm: String, Codable, CaseIterable, Identifiable {
    case md5 = "MD5"
    case sha1 = "SHA-1"
    case sha256 = "SHA-256"
    case sha512 = "SHA-512"
    case crc32 = "CRC-32"
    
    public var id: String { rawValue }
    
    /// Display name for UI
    public var displayName: String { rawValue }
    
    /// Hash length in characters (hex)
    public var hashLength: Int {
        switch self {
        case .md5: return 32
        case .sha1: return 40
        case .sha256: return 64
        case .sha512: return 128
        case .crc32: return 8
        }
    }
    
    /// Relative strength for security (higher is better)
    public var securityStrength: Int {
        switch self {
        case .crc32: return 1
        case .md5: return 2
        case .sha1: return 3
        case .sha256: return 4
        case .sha512: return 5
        }
    }
    
    /// Whether this algorithm is considered secure for modern use
    public var isSecure: Bool {
        switch self {
        case .sha256, .sha512: return true
        case .sha1, .md5, .crc32: return false
        }
    }
    
    /// Icon name for UI display
    public var iconName: String {
        switch self {
        case .crc32: return "checkmark.shield"
        case .md5: return "lock.shield"
        case .sha1: return "lock.shield.fill"
        case .sha256: return "checkmark.shield.fill"
        case .sha512: return "shield.lefthalf.filled"
        }
    }
    
    /// Recommended use case description
    public var description: String {
        switch self {
        case .crc32: return "Fast integrity check, not cryptographic"
        case .md5: return "Legacy, use for compatibility only"
        case .sha1: return "Legacy, use for compatibility only"
        case .sha256: return "Recommended for security"
        case .sha512: return "Maximum security, larger hash"
        }
    }
}

// MARK: - Verification Status

/// Status of file verification process
public enum VerificationStatus: String, Codable, CaseIterable {
    case notVerified = "Not Verified"
    case pending = "Pending"
    case verifying = "Verifying"
    case verified = "Verified"
    case failed = "Failed"
    case skipped = "Skipped"
    case unavailable = "Unavailable"
    
    /// Icon for UI display
    public var icon: String {
        switch self {
        case .notVerified: return "questionmark.circle"
        case .pending: return "clock"
        case .verifying: return "arrow.triangle.2.circlepath"
        case .verified: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "forward.circle"
        case .unavailable: return "exclamationmark.triangle"
        }
    }
    
    /// Color for UI display
    public var color: String {
        switch self {
        case .notVerified: return "gray"
        case .pending: return "blue"
        case .verifying: return "blue"
        case .verified: return "green"
        case .failed: return "red"
        case .skipped: return "orange"
        case .unavailable: return "yellow"
        }
    }
    
    /// Whether this status indicates completion
    public var isComplete: Bool {
        switch self {
        case .verified, .failed, .skipped, .unavailable: return true
        case .notVerified, .pending, .verifying: return false
        }
    }
    
    /// Whether this status indicates success
    public var isSuccess: Bool {
        self == .verified
    }
}

// MARK: - Verification Failure Action

/// Action to take when verification fails
public enum VerificationFailureAction: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case notify = "Notify Only"
    case quarantine = "Move to Quarantine"
    case delete = "Delete File"
    case redownload = "Re-download"
    
    public var id: String { rawValue }
    
    /// Icon for UI display
    public var icon: String {
        switch self {
        case .none: return "circle"
        case .notify: return "bell.fill"
        case .quarantine: return "folder.badge.minus"
        case .delete: return "trash.fill"
        case .redownload: return "arrow.clockwise"
        }
    }
    
    /// Description for UI
    public var description: String {
        switch self {
        case .none: return "Take no action, just mark as failed"
        case .notify: return "Show notification about failure"
        case .quarantine: return "Move file to quarantine folder"
        case .delete: return "Delete the corrupted file"
        case .redownload: return "Automatically re-download the file"
        }
    }
    
    /// Whether this action is destructive
    public var isDestructive: Bool {
        switch self {
        case .delete, .quarantine: return true
        case .none, .notify, .redownload: return false
        }
    }
}

// MARK: - File Checksum

/// Represents a checksum for a file
public struct FileChecksum: Codable, Equatable, Identifiable {
    public let id: UUID
    public let algorithm: HashAlgorithm
    public var expectedHash: String?
    public var actualHash: String?
    public var verificationDate: Date?
    public var isVerified: Bool {
        guard let expected = expectedHash?.lowercased(),
              let actual = actualHash?.lowercased() else {
            return false
        }
        return expected == actual
    }
    
    public init(
        id: UUID = UUID(),
        algorithm: HashAlgorithm,
        expectedHash: String? = nil,
        actualHash: String? = nil,
        verificationDate: Date? = nil
    ) {
        self.id = id
        self.algorithm = algorithm
        self.expectedHash = expectedHash
        self.actualHash = actualHash
        self.verificationDate = verificationDate
    }
    
    /// Validate hash format for the algorithm
    public func isValidHashFormat(_ hash: String) -> Bool {
        let cleanHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check length
        guard cleanHash.count == algorithm.hashLength else {
            return false
        }
        // Check if hex string
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return cleanHash.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }
}

// MARK: - Verification Result

/// Result of file verification process
public struct VerificationResult: Codable, Equatable, Identifiable {
    public let id: UUID
    public let downloadTaskId: UUID
    public var status: VerificationStatus
    public var checksums: [FileChecksum]
    public var startTime: Date
    public var endTime: Date?
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    public var errorMessage: String?
    public var fileSize: Int64
    public var filePath: String
    
    public init(
        id: UUID = UUID(),
        downloadTaskId: UUID,
        status: VerificationStatus = .notVerified,
        checksums: [FileChecksum] = [],
        startTime: Date = Date(),
        endTime: Date? = nil,
        errorMessage: String? = nil,
        fileSize: Int64 = 0,
        filePath: String = ""
    ) {
        self.id = id
        self.downloadTaskId = downloadTaskId
        self.status = status
        self.checksums = checksums
        self.startTime = startTime
        self.endTime = endTime
        self.errorMessage = errorMessage
        self.fileSize = fileSize
        self.filePath = filePath
    }
    
    /// Whether all checksums are verified
    public var allChecksumsVerified: Bool {
        !checksums.isEmpty && checksums.allSatisfy { $0.isVerified }
    }
    
    /// Number of verified checksums
    public var verifiedCount: Int {
        checksums.filter { $0.isVerified }.count
    }
    
    /// Number of failed checksums
    public var failedCount: Int {
        checksums.filter { !$0.isVerified && $0.actualHash != nil }.count
    }
    
    /// Progress percentage (0-100)
    public var progress: Double {
        guard !checksums.isEmpty else { return 0 }
        let processed = checksums.filter { $0.actualHash != nil }.count
        return Double(processed) / Double(checksums.count) * 100.0
    }
}

// MARK: - Verification Configuration

/// Configuration for file verification
public struct VerificationConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var autoVerifyOnComplete: Bool
    public var defaultAlgorithms: [HashAlgorithm]
    public var failureAction: VerificationFailureAction
    public var maxRetries: Int
    public var quarantinePath: String?
    public var showNotifications: Bool
    public var verifyInBackground: Bool
    public var skipVerificationForSmallFiles: Bool
    public var smallFileThresholdMB: Int
    public var bufferSize: Int
    
    public init(
        isEnabled: Bool = true,
        autoVerifyOnComplete: Bool = true,
        defaultAlgorithms: [HashAlgorithm] = [.sha256],
        failureAction: VerificationFailureAction = .notify,
        maxRetries: Int = 3,
        quarantinePath: String? = nil,
        showNotifications: Bool = true,
        verifyInBackground: Bool = true,
        skipVerificationForSmallFiles: Bool = false,
        smallFileThresholdMB: Int = 1,
        bufferSize: Int = 8192
    ) {
        self.isEnabled = isEnabled
        self.autoVerifyOnComplete = autoVerifyOnComplete
        self.defaultAlgorithms = defaultAlgorithms
        self.failureAction = failureAction
        self.maxRetries = maxRetries
        self.quarantinePath = quarantinePath
        self.showNotifications = showNotifications
        self.verifyInBackground = verifyInBackground
        self.skipVerificationForSmallFiles = skipVerificationForSmallFiles
        self.smallFileThresholdMB = smallFileThresholdMB
        self.bufferSize = bufferSize
    }
    
    /// Default configuration
    public static let `default` = VerificationConfig()
    
    /// Secure configuration (SHA-256 + SHA-512)
    public static let secure = VerificationConfig(
        defaultAlgorithms: [.sha256, .sha512],
        failureAction: .quarantine
    )
    
    /// Fast configuration (CRC-32 only)
    public static let fast = VerificationConfig(
        defaultAlgorithms: [.crc32],
        failureAction: .notify
    )
    
    /// Paranoid configuration (all algorithms)
    public static let paranoid = VerificationConfig(
        defaultAlgorithms: [.md5, .sha1, .sha256, .sha512],
        failureAction: .redownload,
        maxRetries: 5
    )
}

// MARK: - Verification Statistics

/// Statistics for file verification operations
public struct VerificationStatistics: Codable, Equatable {
    public var totalVerifications: Int
    public var successfulVerifications: Int
    public var failedVerifications: Int
    public var skippedVerifications: Int
    public var totalBytesVerified: Int64
    public var totalVerificationTime: TimeInterval
    public var averageVerificationSpeed: Double {
        guard totalVerificationTime > 0 else { return 0 }
        return Double(totalBytesVerified) / totalVerificationTime
    }
    public var successRate: Double {
        guard totalVerifications > 0 else { return 0 }
        return Double(successfulVerifications) / Double(totalVerifications) * 100.0
    }
    public var verificationsByAlgorithm: [HashAlgorithm: Int]
    public var lastVerificationDate: Date?
    
    public init(
        totalVerifications: Int = 0,
        successfulVerifications: Int = 0,
        failedVerifications: Int = 0,
        skippedVerifications: Int = 0,
        totalBytesVerified: Int64 = 0,
        totalVerificationTime: TimeInterval = 0,
        verificationsByAlgorithm: [HashAlgorithm: Int] = [:],
        lastVerificationDate: Date? = nil
    ) {
        self.totalVerifications = totalVerifications
        self.successfulVerifications = successfulVerifications
        self.failedVerifications = failedVerifications
        self.skippedVerifications = skippedVerifications
        self.totalBytesVerified = totalBytesVerified
        self.totalVerificationTime = totalVerificationTime
        self.verificationsByAlgorithm = verificationsByAlgorithm
        self.lastVerificationDate = lastVerificationDate
    }
    
    /// Reset all statistics
    public mutating func reset() {
        totalVerifications = 0
        successfulVerifications = 0
        failedVerifications = 0
        skippedVerifications = 0
        totalBytesVerified = 0
        totalVerificationTime = 0
        verificationsByAlgorithm = [:]
        lastVerificationDate = nil
    }
}

// MARK: - Checksum Source

/// Source of checksum information
public enum ChecksumSource: String, Codable {
    case manual = "Manual Entry"
    case file = "Checksum File"
    case url = "URL Metadata"
    case metalink = "Metalink"
    case torrent = "Torrent"
    case http = "HTTP Header"
    
    public var icon: String {
        switch self {
        case .manual: return "keyboard"
        case .file: return "doc.text"
        case .url: return "link"
        case .metalink: return "doc.badge.gearshape"
        case .torrent: return "network"
        case .http: return "globe"
        }
    }
}

// MARK: - Checksum File Format

/// Supported checksum file formats
public enum ChecksumFileFormat: String, CaseIterable {
    case md5sum = ".md5"
    case sha1sum = ".sha1"
    case sha256sum = ".sha256"
    case sha512sum = ".sha512"
    case sfv = ".sfv"
    
    public var algorithm: HashAlgorithm? {
        switch self {
        case .md5sum: return .md5
        case .sha1sum: return .sha1
        case .sha256sum: return .sha256
        case .sha512sum: return .sha512
        case .sfv: return .crc32
        }
    }
    
    /// Parse checksum file content
    public func parseFile(_ content: String, filename: String) -> FileChecksum? {
        guard let algorithm = self.algorithm else { return nil }
        
        // Common format: "hash  filename" or "hash *filename"
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            
            // Parse line
            let components = trimmed.components(separatedBy: .whitespaces)
            if components.count >= 2 {
                let hash = components[0]
                let file = components[1...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                
                // Check if filename matches
                if file == filename || file == URL(fileURLWithPath: filename).lastPathComponent {
                    return FileChecksum(algorithm: algorithm, expectedHash: hash)
                }
            }
        }
        
        return nil
    }
}
