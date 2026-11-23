//
//  CloudIntegrationManager.swift
//  Download Manager for Mac - Feature #9: Cloud Integration
//
//  Created on February 16, 2026
//

import Foundation
import Combine

/// Manages cloud storage integration and uploads
class CloudIntegrationManager: ObservableObject {
    
    static let shared = CloudIntegrationManager()
    
    @Published var accounts: [CloudAccount] = []
    @Published var uploadTasks: [CloudUploadTask] = []
    @Published var uploadRules: [CloudUploadRule] = []
    @Published var statistics: CloudStatistics = CloudStatistics()
    @Published var syncHistory: [CloudSyncHistory] = []
    @Published var spaceMonitors: [CloudSpaceMonitor] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let downloadManager = DownloadManager.shared
    
    private init() {
        loadAccounts()
        loadUploadRules()
        loadStatistics()
        loadSyncHistory()
        loadSpaceMonitors()
        setupObservers()
    }
    
    // MARK: - Account Management
    
    /// Add a new cloud account
    func addAccount(_ account: CloudAccount) {
        accounts.append(account)
        saveAccounts()
        
        // Create space monitor for the account
        let monitor = CloudSpaceMonitor(accountId: account.id)
        spaceMonitors.append(monitor)
        saveSpaceMonitors()
    }
    
    /// Update an existing account
    func updateAccount(_ account: CloudAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
            saveAccounts()
        }
    }
    
    /// Delete an account
    func deleteAccount(_ account: CloudAccount) {
        // Cancel any active uploads for this account
        let accountUploads = uploadTasks.filter { $0.account.id == account.id }
        for upload in accountUploads {
            cancelUpload(upload)
        }
        
        // Remove account
        accounts.removeAll { $0.id == account.id }
        
        // Remove space monitor
        spaceMonitors.removeAll { $0.accountId == account.id }
        
        saveAccounts()
        saveSpaceMonitors()
    }
    
    /// Authenticate an account using real OAuth or API keys
    func authenticateAccount(_ accountId: UUID) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == accountId }) else {
            throw CloudUploadError.notAuthenticated
        }
        
        let account = accounts[index]
        
        // Use real OAuth for supported providers
        switch account.provider {
        case .iCloudDrive:
            // iCloud Drive doesn't need OAuth - use CloudKit
            await MainActor.run {
                accounts[index].isAuthenticated = true
                saveAccounts()
            }
            
        case .dropbox, .googleDrive, .oneDrive, .box:
            // Use real OAuth
            _ = try await OAuthManager.shared.authenticate(
                provider: account.provider,
                accountId: account.id.uuidString
            )
            
            await MainActor.run {
                accounts[index].isAuthenticated = true
                saveAccounts()
            }
            
            // Fetch real space info after authentication
            try await refreshAccountSpaceAsync(account.id)
            
        case .awsS3, .custom:
            // API key authentication - credentials should be set separately via setAPICredentials
            await MainActor.run {
                // Check if credentials exist in Keychain
                if (try? KeychainManager.shared.fetchCredentials(forAccount: account.id.uuidString)) != nil {
                    accounts[index].isAuthenticated = true
                    saveAccounts()
                }
            }
        }
    }
    
    /// Set API credentials for S3 or custom providers
    func setAPICredentials(accountId: UUID, apiKey: String, apiSecret: String) throws {
        guard let index = accounts.firstIndex(where: { $0.id == accountId }) else {
            throw CloudUploadError.notAuthenticated
        }
        
        let credentials = CloudCredentials(
            accountId: accounts[index].id.uuidString,
            provider: accounts[index].provider,
            apiKey: apiKey,
            apiSecret: apiSecret
        )
        
        // Save to Keychain
        try KeychainManager.shared.saveCredentials(credentials)
        
        accounts[index].isAuthenticated = true
        saveAccounts()
    }
    
    /// Legacy authentication method (for backward compatibility / testing)
    func authenticateAccount(_ account: CloudAccount, completion: @escaping (Result<Void, CloudUploadError>) -> Void) {
        Task {
            do {
                try await authenticateAccount(account.id)
                completion(.success(()))
            } catch let error as CloudUploadError {
                completion(.failure(error))
            } catch {
                completion(.failure(.authenticationExpired))
            }
        }
    }
    
    /// Refresh account space using real provider APIs
    private func refreshAccountSpaceAsync(_ accountId: UUID) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == accountId }) else {
            return
        }
        
        let account = accounts[index]
        guard account.isAuthenticated else { return }
        
        // Get credentials with valid token
        guard let credentials = try? await OAuthManager.shared.ensureValidToken(for: account.id.uuidString) else {
            return
        }
        
        // Fetch space info from provider
        let (usedSpace, totalSpace) = try await fetchSpaceInfo(for: account.provider, credentials: credentials)
        
        await MainActor.run {
            if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
                accounts[idx].updateSpace(used: usedSpace, total: totalSpace)
                saveAccounts()
                
                // Check space status
                if let monitor = spaceMonitors.first(where: { $0.accountId == accountId }) {
                    let status = monitor.getStatus(account: accounts[idx])
                    if monitor.enableNotifications && status != .normal {
                        notifySpaceWarning(account: accounts[idx], status: status)
                    }
                }
            }
        }
    }
    
    /// Fetch space info from cloud provider
    private func fetchSpaceInfo(for provider: CloudProvider, credentials: CloudCredentials) async throws -> (used: Int64, total: Int64) {
        guard let accessToken = credentials.accessToken else {
            throw CloudUploadError.notAuthenticated
        }
        
        var request: URLRequest
        
        switch provider {
        case .dropbox:
            // Dropbox API
            request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/users/get_space_usage")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
        case .googleDrive:
            // Google Drive API
            request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=storageQuota")!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
        case .oneDrive:
            // OneDrive API
            request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive")!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
        case .box:
            // Box API
            request = URLRequest(url: URL(string: "https://api.box.com/2.0/users/me")!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
        default:
            // For iCloud, AWS S3, and custom, space checking varies
            // Return simulated values for now
            return (Int64.random(in: 1_000_000_000...10_000_000_000), 15_000_000_000)
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse response based on provider
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        switch provider {
        case .dropbox:
            let used = (json?["used"] as? Int64) ?? 0
            let allocated = (json?["allocation"] as? [String: Any])?["allocated"] as? Int64 ?? 0
            return (used, allocated)
            
        case .googleDrive:
            let quota = json?["storageQuota"] as? [String: Any]
            let used = Int64((quota?["usage"] as? String) ?? "0") ?? 0
            let total = Int64((quota?["limit"] as? String) ?? "0") ?? 0
            return (used, total)
            
        case .oneDrive:
            let quota = json?["quota"] as? [String: Any]
            let used = (quota?["used"] as? Int64) ?? 0
            let total = (quota?["total"] as? Int64) ?? 0
            return (used, total)
            
        case .box:
            let used = (json?["space_used"] as? Int64) ?? 0
            let total = (json?["space_amount"] as? Int64) ?? 0
            return (used, total)
            
        default:
            return (0, 0)
        }
    }
    
    /// Refresh account space information (legacy sync method)
    func refreshAccountSpace(_ account: CloudAccount) {
        Task {
            try? await refreshAccountSpaceAsync(account.id)
        }
    }
    
    // MARK: - Upload Management
    
    /// Create upload task for a download
    func createUploadTask(for downloadTask: DownloadTask, to account: CloudAccount, destinationPath: String? = nil) -> CloudUploadTask? {
        guard account.isEnabled && account.isAuthenticated else {
            print("Account not enabled or authenticated")
            return nil
        }
        
        guard account.isSpaceAvailable else {
            print("Insufficient space in cloud account")
            return nil
        }
        
        // Check if file exists
        let sourceURL = downloadTask.destinationPath
        
        let path = destinationPath ?? account.settings.uploadPath
        let uploadTask = CloudUploadTask(
            downloadTask: downloadTask,
            account: account,
            sourceURL: sourceURL,
            destinationPath: path
        )
        
        uploadTasks.append(uploadTask)
        return uploadTask
    }
    
    /// Start an upload
    func startUpload(_ uploadTask: CloudUploadTask) {
        guard uploadTask.state == .pending else { return }
        
        uploadTask.start()
        
        // Simulate upload progress
        simulateUpload(uploadTask)
    }
    
    /// Cancel an upload
    func cancelUpload(_ uploadTask: CloudUploadTask) {
        uploadTask.state = .cancelled
        uploadTasks.removeAll { $0.id == uploadTask.id }
    }
    
    /// Retry a failed upload
    func retryUpload(_ uploadTask: CloudUploadTask) {
        uploadTask.retry()
        startUpload(uploadTask)
    }
    
    /// Process auto-uploads for completed download
    func processAutoUploads(for downloadTask: DownloadTask) {
        // Find accounts with auto-upload enabled
        let autoUploadAccounts = accounts.filter { account in
            account.isEnabled &&
            account.isAuthenticated &&
            account.settings.autoUpload &&
            account.settings.shouldUpload(downloadTask)
        }
        
        // Check upload rules
        let matchingRules = uploadRules.filter { $0.matches(downloadTask) }
            .sorted { $0.priority > $1.priority }
        
        var accountsToUpload = Set<UUID>()
        
        // Add accounts from auto-upload settings
        autoUploadAccounts.forEach { accountsToUpload.insert($0.id) }
        
        // Add accounts from rules
        matchingRules.forEach { accountsToUpload.insert($0.accountId) }
        
        // Create upload tasks
        for accountId in accountsToUpload {
            if let account = accounts.first(where: { $0.id == accountId }) {
                if let uploadTask = createUploadTask(for: downloadTask, to: account) {
                    startUpload(uploadTask)
                }
            }
        }
    }
    
    // MARK: - Upload Rules
    
    /// Add upload rule
    func addUploadRule(_ rule: CloudUploadRule) {
        uploadRules.append(rule)
        saveUploadRules()
    }
    
    /// Update upload rule
    func updateUploadRule(_ rule: CloudUploadRule) {
        if let index = uploadRules.firstIndex(where: { $0.id == rule.id }) {
            uploadRules[index] = rule
            saveUploadRules()
        }
    }
    
    /// Delete upload rule
    func deleteUploadRule(_ rule: CloudUploadRule) {
        uploadRules.removeAll { $0.id == rule.id }
        saveUploadRules()
    }
    
    // MARK: - History Sync
    
    /// Sync download history to cloud
    func syncHistoryToCloud(tasks: [DownloadTask], to account: CloudAccount) {
        guard account.isAuthenticated && account.settings.syncDownloadHistory else { return }
        
        for task in tasks {
            let historyRecord = CloudSyncHistory(
                downloadTaskId: task.id,
                filename: task.filename,
                url: task.url.absoluteString,
                fileSize: task.totalBytes,
                downloadedAt: task.createdAt,
                cloudAccounts: [account.id]
            )
            
            // Check if already synced
            if let index = syncHistory.firstIndex(where: { $0.downloadTaskId == task.id }) {
                if !syncHistory[index].cloudAccounts.contains(account.id) {
                    syncHistory[index].cloudAccounts.append(account.id)
                }
            } else {
                syncHistory.append(historyRecord)
            }
        }
        
        saveSyncHistory()
    }
    
    /// Get synced history from cloud
    func getSyncedHistory(from account: CloudAccount) -> [CloudSyncHistory] {
        return syncHistory.filter { $0.cloudAccounts.contains(account.id) }
    }
    
    // MARK: - Space Monitoring
    
    /// Update space monitor settings
    func updateSpaceMonitor(_ monitor: CloudSpaceMonitor) {
        if let index = spaceMonitors.firstIndex(where: { $0.accountId == monitor.accountId }) {
            spaceMonitors[index] = monitor
            saveSpaceMonitors()
        }
    }
    
    /// Check all accounts for space warnings
    func checkAllAccountSpaces() {
        for account in accounts where account.isAuthenticated {
            refreshAccountSpace(account)
        }
    }
    
    // MARK: - Statistics
    
    /// Get statistics for specific account
    func getStatistics(for account: CloudAccount) -> CloudStatistics {
        // In a real app, would track per-account statistics
        return statistics
    }
    
    // MARK: - Private Helpers
    
    private func setupObservers() {
        // Observe download completions for auto-upload
        NotificationCenter.default.publisher(for: .init("DownloadCompleted"))
            .compactMap { $0.object as? DownloadTask }
            .sink { [weak self] task in
                self?.processAutoUploads(for: task)
            }
            .store(in: &cancellables)
    }
    
    private func simulateUpload(_ uploadTask: CloudUploadTask) {
        let totalBytes = uploadTask.totalBytes
        let chunkSize: Int64 = 1_000_000 // 1MB chunks
        var uploaded: Int64 = 0
        
        // Simulate upload in background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while uploaded < totalBytes && uploadTask.state == .uploading {
                Thread.sleep(forTimeInterval: 0.1)
                
                uploaded = min(uploaded + chunkSize, totalBytes)
                let speed = Double.random(in: 1_000_000...5_000_000) // 1-5 MB/s
                
                DispatchQueue.main.async {
                    uploadTask.updateProgress(uploaded: uploaded, speed: speed)
                }
            }
            
            // Complete upload
            if uploadTask.state == .uploading {
                DispatchQueue.main.async { [weak self] in
                    uploadTask.complete()
                    
                    // Update statistics
                    let duration = Date().timeIntervalSince(uploadTask.startedAt ?? Date())
                    self?.statistics.recordUpload(bytes: totalBytes, duration: duration, success: true)
                    self?.saveStatistics()
                    
                    // Handle post-upload actions
                    if uploadTask.account.settings.deleteAfterUpload {
                        self?.deleteLocalFile(uploadTask.sourceURL)
                    }
                    
                    // Notify
                    if uploadTask.account.settings.notifyOnUpload {
                        self?.notifyUploadComplete(uploadTask)
                    }
                }
            }
        }
    }
    
    private func deleteLocalFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("Failed to delete local file: \(error)")
        }
    }
    
    private func notifyUploadComplete(_ uploadTask: CloudUploadTask) {
        // In a real app, would send macOS notification
        print("Upload complete: \(uploadTask.downloadTask.filename) to \(uploadTask.account.provider.rawValue)")
    }
    
    private func notifySpaceWarning(account: CloudAccount, status: CloudSpaceMonitor.SpaceStatus) {
        // In a real app, would send macOS notification
        print("Space \(status.rawValue): \(account.accountName) - \(account.usagePercentage)% used")
    }
    
    // MARK: - Persistence
    
    private func loadAccounts() {
        if let data = UserDefaults.standard.data(forKey: "CloudAccounts"),
           let loaded = try? JSONDecoder().decode([CloudAccount].self, from: data) {
            accounts = loaded
        }
    }
    
    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: "CloudAccounts")
        }
    }
    
    private func loadUploadRules() {
        if let data = UserDefaults.standard.data(forKey: "CloudUploadRules"),
           let loaded = try? JSONDecoder().decode([CloudUploadRule].self, from: data) {
            uploadRules = loaded
        }
    }
    
    private func saveUploadRules() {
        if let data = try? JSONEncoder().encode(uploadRules) {
            UserDefaults.standard.set(data, forKey: "CloudUploadRules")
        }
    }
    
    private func loadStatistics() {
        if let data = UserDefaults.standard.data(forKey: "CloudStatistics"),
           let loaded = try? JSONDecoder().decode(CloudStatistics.self, from: data) {
            statistics = loaded
        }
    }
    
    private func saveStatistics() {
        if let data = try? JSONEncoder().encode(statistics) {
            UserDefaults.standard.set(data, forKey: "CloudStatistics")
        }
    }
    
    private func loadSyncHistory() {
        if let data = UserDefaults.standard.data(forKey: "CloudSyncHistory"),
           let loaded = try? JSONDecoder().decode([CloudSyncHistory].self, from: data) {
            syncHistory = loaded
        }
    }
    
    private func saveSyncHistory() {
        if let data = try? JSONEncoder().encode(syncHistory) {
            UserDefaults.standard.set(data, forKey: "CloudSyncHistory")
        }
    }
    
    private func loadSpaceMonitors() {
        if let data = UserDefaults.standard.data(forKey: "CloudSpaceMonitors"),
           let loaded = try? JSONDecoder().decode([CloudSpaceMonitor].self, from: data) {
            spaceMonitors = loaded
        }
    }
    
    private func saveSpaceMonitors() {
        if let data = try? JSONEncoder().encode(spaceMonitors) {
            UserDefaults.standard.set(data, forKey: "CloudSpaceMonitors")
        }
    }
}
