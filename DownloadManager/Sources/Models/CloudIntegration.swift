//
//  CloudIntegration.swift
//  Download Manager for Mac - Feature #9: Cloud Integration
//
//  Created on February 16, 2026
//

import Foundation

// MARK: - Cloud Provider

/// Cloud storage provider types
enum CloudProvider: String, Codable, CaseIterable, Identifiable {
    case iCloudDrive = "iCloud Drive"
    case dropbox = "Dropbox"
    case googleDrive = "Google Drive"
    case oneDrive = "OneDrive"
    case box = "Box"
    case awsS3 = "AWS S3"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .iCloudDrive: return "icloud.fill"
        case .dropbox: return "cloud.fill"
        case .googleDrive: return "cloud.circle.fill"
        case .oneDrive: return "cloud.square.fill"
        case .box: return "shippingbox.fill"
        case .awsS3: return "server.rack"
        case .custom: return "cloud"
        }
    }
    
    var color: String {
        switch self {
        case .iCloudDrive: return "blue"
        case .dropbox: return "blue"
        case .googleDrive: return "green"
        case .oneDrive: return "blue"
        case .box: return "blue"
        case .awsS3: return "orange"
        case .custom: return "gray"
        }
    }
    
    var requiresAuthentication: Bool {
        switch self {
        case .iCloudDrive: return false
        case .custom: return true
        default: return true
        }
    }
}

// MARK: - Cloud Account

/// Cloud storage account configuration
struct CloudAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var provider: CloudProvider
    var accountName: String
    var email: String?
    var isEnabled: Bool
    var isAuthenticated: Bool
    var lastSyncDate: Date?
    var totalSpace: Int64
    var usedSpace: Int64
    var createdAt: Date
    var settings: CloudAccountSettings
    
    // Credentials stored in Keychain (this is just the reference ID)
    var hasCredentials: Bool {
        // Check if credentials exist in Keychain
        return (try? KeychainManager.shared.fetchCredentials(forAccount: id.uuidString)) != nil
    }
    
    init(
        id: UUID = UUID(),
        provider: CloudProvider,
        accountName: String,
        email: String? = nil,
        isEnabled: Bool = true,
        isAuthenticated: Bool = false,
        totalSpace: Int64 = 0,
        usedSpace: Int64 = 0,
        settings: CloudAccountSettings = CloudAccountSettings()
    ) {
        self.id = id
        self.provider = provider
        self.accountName = accountName
        self.email = email
        self.isEnabled = isEnabled
        self.isAuthenticated = isAuthenticated
        self.totalSpace = totalSpace
        self.usedSpace = usedSpace
        self.createdAt = Date()
        self.settings = settings
    }
    
    var availableSpace: Int64 {
        return totalSpace - usedSpace
    }
    
    var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100
    }
    
    var isSpaceAvailable: Bool {
        return availableSpace > 1_000_000 // At least 1MB available
    }
    
    mutating func updateSpace(used: Int64, total: Int64) {
        self.usedSpace = used
        self.totalSpace = total
        self.lastSyncDate = Date()
    }
}

// MARK: - Cloud Account Settings

/// Settings for cloud account behavior
struct CloudAccountSettings: Codable, Equatable {
    var autoUpload: Bool
    var uploadPath: String
    var deleteAfterUpload: Bool
    var fileTypeFilter: [String]
    var maxFileSize: Int64?
    var compressionEnabled: Bool
    var notifyOnUpload: Bool
    var syncDownloadHistory: Bool
    
    init(
        autoUpload: Bool = false,
        uploadPath: String = "/Downloads",
        deleteAfterUpload: Bool = false,
        fileTypeFilter: [String] = [],
        maxFileSize: Int64? = nil,
        compressionEnabled: Bool = false,
        notifyOnUpload: Bool = true,
        syncDownloadHistory: Bool = false
    ) {
        self.autoUpload = autoUpload
        self.uploadPath = uploadPath
        self.deleteAfterUpload = deleteAfterUpload
        self.fileTypeFilter = fileTypeFilter
        self.maxFileSize = maxFileSize
        self.compressionEnabled = compressionEnabled
        self.notifyOnUpload = notifyOnUpload
        self.syncDownloadHistory = syncDownloadHistory
    }
    
    func shouldUpload(_ task: DownloadTask) -> Bool {
        // Check if file type is in filter (if filter is not empty)
        if !fileTypeFilter.isEmpty {
            let fileExtension = URL(fileURLWithPath: task.filename).pathExtension.lowercased()
            if !fileTypeFilter.contains(fileExtension) {
                return false
            }
        }
        
        // Check file size limit
        if let maxSize = maxFileSize, task.totalBytes > maxSize {
            return false
        }
        
        return true
    }
}

// MARK: - Cloud Upload Task

/// Upload task for cloud storage
class CloudUploadTask: Identifiable, ObservableObject {
    let id: UUID
    let downloadTask: DownloadTask
    let account: CloudAccount
    let sourceURL: URL
    let destinationPath: String
    
    @Published var state: CloudUploadState
    @Published var progress: Double
    @Published var uploadedBytes: Int64
    @Published var totalBytes: Int64
    @Published var uploadSpeed: Double
    @Published var error: CloudUploadError?
    @Published var startedAt: Date?
    @Published var completedAt: Date?
    
    var remainingTime: TimeInterval? {
        guard uploadSpeed > 0, state == .uploading else { return nil }
        let remaining = Double(totalBytes - uploadedBytes)
        return remaining / uploadSpeed
    }
    
    init(
        id: UUID = UUID(),
        downloadTask: DownloadTask,
        account: CloudAccount,
        sourceURL: URL,
        destinationPath: String
    ) {
        self.id = id
        self.downloadTask = downloadTask
        self.account = account
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.state = .pending
        self.progress = 0
        self.uploadedBytes = 0
        self.totalBytes = downloadTask.totalBytes
        self.uploadSpeed = 0
    }
    
    func start() {
        state = .uploading
        startedAt = Date()
        error = nil
    }
    
    func updateProgress(uploaded: Int64, speed: Double) {
        uploadedBytes = uploaded
        uploadSpeed = speed
        progress = totalBytes > 0 ? Double(uploaded) / Double(totalBytes) : 0
    }
    
    func complete() {
        state = .completed
        progress = 1.0
        completedAt = Date()
    }
    
    func fail(error: CloudUploadError) {
        state = .failed
        self.error = error
        completedAt = Date()
    }
    
    func retry() {
        state = .pending
        error = nil
        uploadedBytes = 0
        progress = 0
    }
}

// MARK: - Cloud Upload State

/// Upload task state
enum CloudUploadState: String, Codable {
    case pending = "Pending"
    case uploading = "Uploading"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .uploading: return "arrow.up.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .pending: return "gray"
        case .uploading: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        }
    }
}

// MARK: - Cloud Upload Error

/// Errors that can occur during cloud upload
enum CloudUploadError: Error, Codable, Equatable {
    case notAuthenticated
    case insufficientSpace
    case networkError(String)
    case fileNotFound
    case invalidPath
    case uploadFailed(String)
    case authenticationExpired
    case quotaExceeded
    case providerError(String)
    
    var localizedDescription: String {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with cloud provider"
        case .insufficientSpace:
            return "Insufficient cloud storage space"
        case .networkError(let message):
            return "Network error: \(message)"
        case .fileNotFound:
            return "Source file not found"
        case .invalidPath:
            return "Invalid destination path"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .authenticationExpired:
            return "Authentication expired, please re-authenticate"
        case .quotaExceeded:
            return "Cloud storage quota exceeded"
        case .providerError(let message):
            return "Provider error: \(message)"
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .networkError, .uploadFailed, .providerError:
            return true
        case .notAuthenticated, .authenticationExpired:
            return true
        default:
            return false
        }
    }
}

// MARK: - Cloud Sync History

/// Download history sync record
struct CloudSyncHistory: Identifiable, Codable {
    let id: UUID
    let downloadTaskId: UUID
    let filename: String
    let url: String
    let fileSize: Int64
    let downloadedAt: Date
    let syncedAt: Date
    var cloudAccounts: [UUID] // Account IDs where this is synced
    
    init(
        id: UUID = UUID(),
        downloadTaskId: UUID,
        filename: String,
        url: String,
        fileSize: Int64,
        downloadedAt: Date,
        cloudAccounts: [UUID] = []
    ) {
        self.id = id
        self.downloadTaskId = downloadTaskId
        self.filename = filename
        self.url = url
        self.fileSize = fileSize
        self.downloadedAt = downloadedAt
        self.syncedAt = Date()
        self.cloudAccounts = cloudAccounts
    }
}

// MARK: - Cloud Statistics

/// Statistics for cloud uploads and storage
struct CloudStatistics: Codable {
    var totalUploads: Int
    var successfulUploads: Int
    var failedUploads: Int
    var totalBytesUploaded: Int64
    var totalUploadTime: TimeInterval
    var averageUploadSpeed: Double
    var lastUploadDate: Date?
    
    init() {
        self.totalUploads = 0
        self.successfulUploads = 0
        self.failedUploads = 0
        self.totalBytesUploaded = 0
        self.totalUploadTime = 0
        self.averageUploadSpeed = 0
    }
    
    var successRate: Double {
        guard totalUploads > 0 else { return 0 }
        return Double(successfulUploads) / Double(totalUploads) * 100
    }
    
    mutating func recordUpload(bytes: Int64, duration: TimeInterval, success: Bool) {
        totalUploads += 1
        if success {
            successfulUploads += 1
            totalBytesUploaded += bytes
            totalUploadTime += duration
            
            // Update average speed
            if totalUploadTime > 0 {
                averageUploadSpeed = Double(totalBytesUploaded) / totalUploadTime
            }
        } else {
            failedUploads += 1
        }
        lastUploadDate = Date()
    }
}

// MARK: - Cloud Upload Rule

/// Rule for automatic cloud uploads
struct CloudUploadRule: Identifiable, Codable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var accountId: UUID
    var conditions: [UploadCondition]
    var destinationPath: String
    var priority: Int
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        accountId: UUID,
        conditions: [UploadCondition] = [],
        destinationPath: String = "/Downloads",
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.accountId = accountId
        self.conditions = conditions
        self.destinationPath = destinationPath
        self.priority = priority
        self.createdAt = Date()
    }
    
    func matches(_ task: DownloadTask) -> Bool {
        guard isEnabled else { return false }
        return conditions.isEmpty || conditions.allSatisfy { $0.matches(task) }
    }
}

// MARK: - Upload Condition

/// Condition for upload rules
enum UploadCondition: Codable, Equatable {
    case fileType([String])
    case fileSize(min: Int64?, max: Int64?)
    case sourceURL(pattern: String)
    case category(DownloadCategory)
    
    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .fileType(let extensions):
            let ext = URL(fileURLWithPath: task.filename).pathExtension.lowercased()
            return extensions.contains(ext)
            
        case .fileSize(let min, let max):
            if let min = min, task.totalBytes < min { return false }
            if let max = max, task.totalBytes > max { return false }
            return true
            
        case .sourceURL(let pattern):
            return task.url.absoluteString.localizedCaseInsensitiveContains(pattern)
            
        case .category(_):
            // Would need to check task category
            return true
        }
    }
}

// MARK: - Cloud Space Monitor

/// Monitor for cloud storage space
struct CloudSpaceMonitor: Codable {
    var accountId: UUID
    var warningThreshold: Double // Percentage (e.g., 80.0 for 80%)
    var criticalThreshold: Double // Percentage (e.g., 95.0 for 95%)
    var enableNotifications: Bool
    var lastCheckDate: Date?
    
    init(
        accountId: UUID,
        warningThreshold: Double = 80.0,
        criticalThreshold: Double = 95.0,
        enableNotifications: Bool = true
    ) {
        self.accountId = accountId
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.enableNotifications = enableNotifications
    }
    
    func shouldWarn(account: CloudAccount) -> Bool {
        return account.usagePercentage >= warningThreshold
    }
    
    func isCritical(account: CloudAccount) -> Bool {
        return account.usagePercentage >= criticalThreshold
    }
    
    func getStatus(account: CloudAccount) -> SpaceStatus {
        if isCritical(account: account) {
            return .critical
        } else if shouldWarn(account: account) {
            return .warning
        } else {
            return .normal
        }
    }
    
    enum SpaceStatus: String {
        case normal = "Normal"
        case warning = "Warning"
        case critical = "Critical"
        
        var color: String {
            switch self {
            case .normal: return "green"
            case .warning: return "orange"
            case .critical: return "red"
            }
        }
        
        var icon: String {
            switch self {
            case .normal: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }
}

// MARK: - Cloud Credentials

/// Secure credentials storage for cloud providers (stored in Keychain)
struct CloudCredentials: Codable {
    let accountId: String
    let provider: CloudProvider
    
    // OAuth tokens
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?
    var tokenType: String?
    var scope: String?
    
    // API keys (for S3, custom providers)
    var apiKey: String?
    var apiSecret: String?
    
    // Custom authentication
    var customAuth: [String: String]?
    
    init(accountId: String, provider: CloudProvider,
         accessToken: String? = nil, refreshToken: String? = nil,
         expiresAt: Date? = nil, tokenType: String? = nil, scope: String? = nil,
         apiKey: String? = nil, apiSecret: String? = nil,
         customAuth: [String: String]? = nil) {
        self.accountId = accountId
        self.provider = provider
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.scope = scope
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.customAuth = customAuth    }
}