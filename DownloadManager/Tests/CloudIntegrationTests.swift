//
//  CloudIntegrationTests.swift
//  Download Manager for Mac - Feature #9: Cloud Integration Tests
//
//  Created on February 16, 2026
//

import XCTest
@testable import DownloadManager

final class CloudIntegrationTests: XCTestCase {
    
    var manager: CloudIntegrationManager!
    var downloadManager: DownloadManager!
    
    override func setUp() {
        super.setUp()
        manager = CloudIntegrationManager.shared
        downloadManager = DownloadManager.shared
        
        // Clear existing data
        manager.accounts.removeAll()
        manager.uploadTasks.removeAll()
        manager.uploadRules.removeAll()
        manager.syncHistory.removeAll()
        manager.spaceMonitors.removeAll()
        manager.statistics = CloudStatistics()
    }
    
    override func tearDown() {
        manager.accounts.removeAll()
        manager.uploadTasks.removeAll()
        manager.uploadRules.removeAll()
        super.tearDown()
    }
    
    // MARK: - Account Management Tests
    
    func testAddAccount() {
        let account = createMockAccount(provider: .dropbox, name: "My Dropbox")
        
        manager.addAccount(account)
        
        XCTAssertEqual(manager.accounts.count, 1)
        XCTAssertEqual(manager.accounts.first?.accountName, "My Dropbox")
        XCTAssertEqual(manager.spaceMonitors.count, 1)
    }
    
    func testUpdateAccount() {
        var account = createMockAccount(provider: .googleDrive, name: "Original")
        manager.addAccount(account)
        
        account.accountName = "Updated"
        manager.updateAccount(account)
        
        XCTAssertEqual(manager.accounts.count, 1)
        XCTAssertEqual(manager.accounts.first?.accountName, "Updated")
    }
    
    func testDeleteAccount() {
        let account = createMockAccount(provider: .oneDrive, name: "Test")
        manager.addAccount(account)
        
        XCTAssertEqual(manager.accounts.count, 1)
        
        manager.deleteAccount(account)
        
        XCTAssertEqual(manager.accounts.count, 0)
        XCTAssertEqual(manager.spaceMonitors.count, 0)
    }
    
    func testAccountAuthentication() {
        let account = createMockAccount(provider: .dropbox, name: "Test")
        manager.addAccount(account)
        
        XCTAssertFalse(account.isAuthenticated)
        
        let expectation = expectation(description: "Authentication completes")
        
        manager.authenticateAccount(account) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure:
                XCTFail("Authentication should succeed")
            }
        }
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertTrue(manager.accounts.first?.isAuthenticated ?? false)
        XCTAssertGreaterThan(manager.accounts.first?.totalSpace ?? 0, 0)
    }
    
    func testAccountSpaceCalculations() {
        var account = createMockAccount(provider: .iCloudDrive, name: "iCloud")
        account.updateSpace(used: 5_000_000_000, total: 10_000_000_000)
        
        XCTAssertEqual(account.availableSpace, 5_000_000_000)
        XCTAssertEqual(account.usagePercentage, 50.0)
        XCTAssertTrue(account.isSpaceAvailable)
    }
    
    func testAccountSpaceWarning() {
        var account = createMockAccount(provider: .dropbox, name: "Dropbox")
        account.updateSpace(used: 9_000_000_000, total: 10_000_000_000) // 90% used
        
        XCTAssertEqual(account.usagePercentage, 90.0)
        XCTAssertFalse(account.isSpaceAvailable)
    }
    
    // MARK: - Provider Tests
    
    func testAllProviders() {
        let providers = CloudProvider.allCases
        
        XCTAssertEqual(providers.count, 7)
        XCTAssertTrue(providers.contains(.iCloudDrive))
        XCTAssertTrue(providers.contains(.dropbox))
        XCTAssertTrue(providers.contains(.googleDrive))
        XCTAssertTrue(providers.contains(.oneDrive))
        XCTAssertTrue(providers.contains(.box))
        XCTAssertTrue(providers.contains(.awsS3))
        XCTAssertTrue(providers.contains(.custom))
    }
    
    func testProviderAuthentication() {
        XCTAssertFalse(CloudProvider.iCloudDrive.requiresAuthentication)
        XCTAssertTrue(CloudProvider.dropbox.requiresAuthentication)
        XCTAssertTrue(CloudProvider.googleDrive.requiresAuthentication)
        XCTAssertTrue(CloudProvider.custom.requiresAuthentication)
    }
    
    // MARK: - Upload Task Tests
    
    func testCreateUploadTask() {
        let account = createAuthenticatedAccount(provider: .googleDrive, name: "Google")
        manager.addAccount(account)
        
        let downloadTask = createMockDownloadTask(filename: "file.zip", totalBytes: 1_000_000)
        
        let uploadTask = manager.createUploadTask(
            for: downloadTask,
            to: account,
            destinationPath: "/Uploads"
        )
        
        XCTAssertNotNil(uploadTask)
        XCTAssertEqual(uploadTask?.state, .pending)
        XCTAssertEqual(uploadTask?.totalBytes, 1_000_000)
        XCTAssertEqual(uploadTask?.destinationPath, "/Uploads")
    }
    
    func testCreateUploadTaskUnauthenticated() {
        let account = createMockAccount(provider: .dropbox, name: "Dropbox")
        manager.addAccount(account)
        
        let downloadTask = createMockDownloadTask(filename: "file.zip")
        
        let uploadTask = manager.createUploadTask(for: downloadTask, to: account)
        
        XCTAssertNil(uploadTask)
    }
    
    func testCreateUploadTaskInsufficientSpace() {
        var account = createAuthenticatedAccount(provider: .box, name: "Box")
        account.updateSpace(used: 10_000_000_000, total: 10_000_000_000) // Full
        manager.addAccount(account)
        
        let downloadTask = createMockDownloadTask(filename: "file.zip")
        
        let uploadTask = manager.createUploadTask(for: downloadTask, to: account)
        
        XCTAssertNil(uploadTask)
    }
    
    func testUploadTaskProgress() {
        let account = createAuthenticatedAccount(provider: .oneDrive, name: "OneDrive")
        manager.addAccount(account)
        
        let downloadTask = createMockDownloadTask(filename: "file.zip", totalBytes: 1_000_000)
        
        if let uploadTask = manager.createUploadTask(for: downloadTask, to: account) {
            uploadTask.updateProgress(uploaded: 500_000, speed: 100_000)
            
            XCTAssertEqual(uploadTask.progress, 0.5)
            XCTAssertEqual(uploadTask.uploadedBytes, 500_000)
            XCTAssertEqual(uploadTask.uploadSpeed, 100_000)
            XCTAssertNotNil(uploadTask.remainingTime)
        } else {
            XCTFail("Upload task should be created")
        }
    }
    
    func testUploadTaskCompletion() {
        let account = createAuthenticatedAccount(provider: .dropbox, name: "Dropbox")
        manager.addAccount(account)
        
        let downloadTask = createMockDownloadTask(filename: "file.zip")
        
        if let uploadTask = manager.createUploadTask(for: downloadTask, to: account) {
            uploadTask.complete()
            
            XCTAssertEqual(uploadTask.state, .completed)
            XCTAssertEqual(uploadTask.progress, 1.0)
            XCTAssertNotNil(uploadTask.completedAt)
        } else {
            XCTFail("Upload task should be created")
        }
    }
    
    func testUploadTaskFailure() {
        let account = createAuthenticatedAccount(provider: .googleDrive, name: "Google")
        manager.addAccount(account)
        
        let downloadTask = createMockDownloadTask(filename: "file.zip")
        
        if let uploadTask = manager.createUploadTask(for: downloadTask, to: account) {
            let error = CloudUploadError.networkError("Connection lost")
            uploadTask.fail(error: error)
            
            XCTAssertEqual(uploadTask.state, .failed)
            XCTAssertNotNil(uploadTask.error)
            XCTAssertTrue(uploadTask.error?.isRecoverable ?? false)
        } else {
            XCTFail("Upload task should be created")
        }
    }
    
    func testUploadTaskRetry() {
        let account = createAuthenticatedAccount(provider: .oneDrive, name: "OneDrive")
        manager.addAccount(account)
        
        let downloadTask = createMockDownloadTask(filename: "file.zip")
        
        if let uploadTask = manager.createUploadTask(for: downloadTask, to: account) {
            uploadTask.fail(error: .networkError("Test"))
            XCTAssertEqual(uploadTask.state, .failed)
            
            uploadTask.retry()
            
            XCTAssertEqual(uploadTask.state, .pending)
            XCTAssertNil(uploadTask.error)
            XCTAssertEqual(uploadTask.progress, 0)
        } else {
            XCTFail("Upload task should be created")
        }
    }
    
    // MARK: - Upload Rules Tests
    
    func testAddUploadRule() {
        let account = createAuthenticatedAccount(provider: .dropbox, name: "Dropbox")
        manager.addAccount(account)
        
        let rule = CloudUploadRule(
            name: "Upload Videos",
            accountId: account.id,
            conditions: [.fileType(["mp4", "mov"])],
            destinationPath: "/Videos"
        )
        
        manager.addUploadRule(rule)
        
        XCTAssertEqual(manager.uploadRules.count, 1)
        XCTAssertEqual(manager.uploadRules.first?.name, "Upload Videos")
    }
    
    func testUpdateUploadRule() {
        let account = createAuthenticatedAccount(provider: .googleDrive, name: "Google")
        manager.addAccount(account)
        
        var rule = CloudUploadRule(
            name: "Original",
            accountId: account.id
        )
        manager.addUploadRule(rule)
        
        rule.name = "Updated"
        manager.updateUploadRule(rule)
        
        XCTAssertEqual(manager.uploadRules.first?.name, "Updated")
    }
    
    func testDeleteUploadRule() {
        let account = createAuthenticatedAccount(provider: .box, name: "Box")
        manager.addAccount(account)
        
        let rule = CloudUploadRule(name: "Test", accountId: account.id)
        manager.addUploadRule(rule)
        
        XCTAssertEqual(manager.uploadRules.count, 1)
        
        manager.deleteUploadRule(rule)
        
        XCTAssertEqual(manager.uploadRules.count, 0)
    }
    
    func testUploadRuleMatching() {
        let account = createAuthenticatedAccount(provider: .dropbox, name: "Dropbox")
        manager.addAccount(account)
        
        let rule = CloudUploadRule(
            name: "Upload Large Files",
            accountId: account.id,
            conditions: [
                .fileSize(min: 10_000_000, max: nil)
            ]
        )
        
        let smallTask = createMockDownloadTask(filename: "small.txt", totalBytes: 1_000)
        let largeTask = createMockDownloadTask(filename: "large.zip", totalBytes: 50_000_000)
        
        XCTAssertFalse(rule.matches(smallTask))
        XCTAssertTrue(rule.matches(largeTask))
    }
    
    func testUploadRuleFileTypeCondition() {
        let account = createAuthenticatedAccount(provider: .googleDrive, name: "Google")
        
        let rule = CloudUploadRule(
            name: "Upload Images",
            accountId: account.id,
            conditions: [.fileType(["jpg", "png", "gif"])]
        )
        
        let imageTask = createMockDownloadTask(filename: "photo.jpg")
        let videoTask = createMockDownloadTask(filename: "video.mp4")
        
        XCTAssertTrue(rule.matches(imageTask))
        XCTAssertFalse(rule.matches(videoTask))
    }
    
    func testUploadRuleSourceURLCondition() {
        let account = createAuthenticatedAccount(provider: .oneDrive, name: "OneDrive")
        
        let rule = CloudUploadRule(
            name: "Upload from YouTube",
            accountId: account.id,
            conditions: [.sourceURL(pattern: "youtube.com")]
        )
        
        let youtubeTask = createMockDownloadTask(url: "https://youtube.com/watch?v=123")
        let vimeoTask = createMockDownloadTask(url: "https://vimeo.com/123")
        
        XCTAssertTrue(rule.matches(youtubeTask))
        XCTAssertFalse(rule.matches(vimeoTask))
    }
    
    // MARK: - Account Settings Tests
    
    func testAccountSettingsAutoUpload() {
        let settings = CloudAccountSettings(autoUpload: true, fileTypeFilter: ["pdf", "doc"])
        
        let pdfTask = createMockDownloadTask(filename: "document.pdf")
        let imageTask = createMockDownloadTask(filename: "photo.jpg")
        
        XCTAssertTrue(settings.shouldUpload(pdfTask))
        XCTAssertFalse(settings.shouldUpload(imageTask))
    }
    
    func testAccountSettingsFileSize() {
        let settings = CloudAccountSettings(maxFileSize: 10_000_000) // 10MB max
        
        let smallTask = createMockDownloadTask(filename: "small.txt", totalBytes: 1_000)
        let largeTask = createMockDownloadTask(filename: "large.zip", totalBytes: 50_000_000)
        
        XCTAssertTrue(settings.shouldUpload(smallTask))
        XCTAssertFalse(settings.shouldUpload(largeTask))
    }
    
    func testAccountSettingsNoFilter() {
        let settings = CloudAccountSettings(autoUpload: true)
        
        let task = createMockDownloadTask(filename: "any.file")
        
        XCTAssertTrue(settings.shouldUpload(task))
    }
    
    // MARK: - History Sync Tests
    
    func testSyncHistoryToCloud() {
        let account = createAuthenticatedAccount(provider: .iCloudDrive, name: "iCloud")
        var accountSettings = account.settings
        accountSettings.syncDownloadHistory = true
        var updatedAccount = account
        updatedAccount.settings = accountSettings
        
        manager.addAccount(updatedAccount)
        
        let tasks = [
            createMockDownloadTask(filename: "file1.zip"),
            createMockDownloadTask(filename: "file2.pdf")
        ]
        
        manager.syncHistoryToCloud(tasks: tasks, to: updatedAccount)
        
        XCTAssertEqual(manager.syncHistory.count, 2)
        XCTAssertTrue(manager.syncHistory.allSatisfy { $0.cloudAccounts.contains(updatedAccount.id) })
    }
    
    func testGetSyncedHistory() {
        let account = createAuthenticatedAccount(provider: .dropbox, name: "Dropbox")
        manager.addAccount(account)
        
        let history1 = CloudSyncHistory(
            downloadTaskId: UUID(),
            filename: "file1.zip",
            url: "https://example.com/file1.zip",
            fileSize: 1000,
            downloadedAt: Date(),
            cloudAccounts: [account.id]
        )
        
        let history2 = CloudSyncHistory(
            downloadTaskId: UUID(),
            filename: "file2.zip",
            url: "https://example.com/file2.zip",
            fileSize: 2000,
            downloadedAt: Date(),
            cloudAccounts: [UUID()] // Different account
        )
        
        manager.syncHistory = [history1, history2]
        
        let syncedHistory = manager.getSyncedHistory(from: account)
        
        XCTAssertEqual(syncedHistory.count, 1)
        XCTAssertEqual(syncedHistory.first?.filename, "file1.zip")
    }
    
    // MARK: - Space Monitor Tests
    
    func testSpaceMonitorWarning() {
        var account = createAuthenticatedAccount(provider: .googleDrive, name: "Google")
        account.updateSpace(used: 8_500_000_000, total: 10_000_000_000) // 85%
        
        let monitor = CloudSpaceMonitor(accountId: account.id, warningThreshold: 80.0)
        
        XCTAssertTrue(monitor.shouldWarn(account: account))
        XCTAssertFalse(monitor.isCritical(account: account))
        XCTAssertEqual(monitor.getStatus(account: account), .warning)
    }
    
    func testSpaceMonitorCritical() {
        var account = createAuthenticatedAccount(provider: .oneDrive, name: "OneDrive")
        account.updateSpace(used: 9_600_000_000, total: 10_000_000_000) // 96%
        
        let monitor = CloudSpaceMonitor(accountId: account.id, criticalThreshold: 95.0)
        
        XCTAssertTrue(monitor.shouldWarn(account: account))
        XCTAssertTrue(monitor.isCritical(account: account))
        XCTAssertEqual(monitor.getStatus(account: account), .critical)
    }
    
    func testSpaceMonitorNormal() {
        var account = createAuthenticatedAccount(provider: .box, name: "Box")
        account.updateSpace(used: 5_000_000_000, total: 10_000_000_000) // 50%
        
        let monitor = CloudSpaceMonitor(accountId: account.id)
        
        XCTAssertFalse(monitor.shouldWarn(account: account))
        XCTAssertFalse(monitor.isCritical(account: account))
        XCTAssertEqual(monitor.getStatus(account: account), .normal)
    }
    
    // MARK: - Statistics Tests
    
    func testStatisticsRecordSuccess() {
        var statistics = CloudStatistics()
        
        statistics.recordUpload(bytes: 1_000_000, duration: 10.0, success: true)
        
        XCTAssertEqual(statistics.totalUploads, 1)
        XCTAssertEqual(statistics.successfulUploads, 1)
        XCTAssertEqual(statistics.failedUploads, 0)
        XCTAssertEqual(statistics.totalBytesUploaded, 1_000_000)
        XCTAssertEqual(statistics.successRate, 100.0)
    }
    
    func testStatisticsRecordFailure() {
        var statistics = CloudStatistics()
        
        statistics.recordUpload(bytes: 1_000_000, duration: 5.0, success: false)
        
        XCTAssertEqual(statistics.totalUploads, 1)
        XCTAssertEqual(statistics.successfulUploads, 0)
        XCTAssertEqual(statistics.failedUploads, 1)
        XCTAssertEqual(statistics.totalBytesUploaded, 0)
        XCTAssertEqual(statistics.successRate, 0.0)
    }
    
    func testStatisticsAverageSpeed() {
        var statistics = CloudStatistics()
        
        statistics.recordUpload(bytes: 1_000_000, duration: 1.0, success: true)
        statistics.recordUpload(bytes: 2_000_000, duration: 1.0, success: true)
        
        XCTAssertEqual(statistics.totalBytesUploaded, 3_000_000)
        XCTAssertEqual(statistics.totalUploadTime, 2.0)
        XCTAssertEqual(statistics.averageUploadSpeed, 1_500_000)
    }
    
    func testStatisticsMixedResults() {
        var statistics = CloudStatistics()
        
        statistics.recordUpload(bytes: 1_000_000, duration: 1.0, success: true)
        statistics.recordUpload(bytes: 2_000_000, duration: 1.0, success: false)
        statistics.recordUpload(bytes: 3_000_000, duration: 1.0, success: true)
        
        XCTAssertEqual(statistics.totalUploads, 3)
        XCTAssertEqual(statistics.successfulUploads, 2)
        XCTAssertEqual(statistics.failedUploads, 1)
        XCTAssertEqual(statistics.successRate, 66.66666666666667, accuracy: 0.01)
    }
    
    // MARK: - Error Handling Tests
    
    func testCloudUploadErrors() {
        let errors: [CloudUploadError] = [
            .notAuthenticated,
            .insufficientSpace,
            .networkError("Test"),
            .fileNotFound,
            .invalidPath,
            .uploadFailed("Test"),
            .authenticationExpired,
            .quotaExceeded,
            .providerError("Test")
        ]
        
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
    
    func testRecoverableErrors() {
        XCTAssertTrue(CloudUploadError.networkError("Test").isRecoverable)
        XCTAssertTrue(CloudUploadError.uploadFailed("Test").isRecoverable)
        XCTAssertTrue(CloudUploadError.notAuthenticated.isRecoverable)
        XCTAssertFalse(CloudUploadError.insufficientSpace.isRecoverable)
        XCTAssertFalse(CloudUploadError.fileNotFound.isRecoverable)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteUploadWorkflow() {
        // Setup account
        let account = createAuthenticatedAccount(provider: .dropbox, name: "Dropbox")
        var settings = account.settings
        settings.autoUpload = true
        var updatedAccount = account
        updatedAccount.settings = settings
        
        manager.addAccount(updatedAccount)
        
        // Create upload rule
        let rule = CloudUploadRule(
            name: "Auto-upload PDFs",
            accountId: updatedAccount.id,
            conditions: [.fileType(["pdf"])]
        )
        manager.addUploadRule(rule)
        
        // Create download task
        let downloadTask = createMockDownloadTask(filename: "document.pdf")
        
        // Process auto-uploads
        manager.processAutoUploads(for: downloadTask)
        
        // Verify upload task created
        XCTAssertGreaterThan(manager.uploadTasks.count, 0)
    }
    
    // MARK: - Helper Methods
    
    private func createMockAccount(provider: CloudProvider, name: String) -> CloudAccount {
        return CloudAccount(
            provider: provider,
            accountName: name,
            email: "\(name.lowercased())@example.com"
        )
    }
    
    private func createAuthenticatedAccount(provider: CloudProvider, name: String) -> CloudAccount {
        var account = createMockAccount(provider: provider, name: name)
        account.isAuthenticated = true
        account.updateSpace(used: 5_000_000_000, total: 15_000_000_000)
        return account
    }
    
    private func createMockDownloadTask(
        url: String = "https://example.com/file.zip",
        filename: String = "file.zip",
        totalBytes: Int64 = 1_000_000
    ) -> DownloadTask {
        let task = DownloadTask(url: URL(string: url)!)
        task.filename = filename
        task.totalBytes = totalBytes
        return task
    }
}
