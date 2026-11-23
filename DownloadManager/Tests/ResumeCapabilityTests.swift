//
//  ResumeCapabilityTests.swift
//  Download Manager for Mac - Feature #6: Resume Capability Tests
//
//  Created on February 15, 2026
//

import XCTest
@testable import DownloadManager

class ResumeCapabilityTests: XCTestCase {
    
    var resumeManager: ResumeManager!
    var downloadManager: DownloadManager!
    
    override func setUp() {
        super.setUp()
        resumeManager = ResumeManager.shared
        downloadManager = DownloadManager.shared
        
        // Reset to default settings
        resumeManager.updateSettings(ResumeSettings())
        
        // Clear downloads
        for task in downloadManager.downloadTasks {
            downloadManager.removeDownload(task)
        }
    }
    
    override func tearDown() {
        for task in downloadManager.downloadTasks {
            downloadManager.removeDownload(task)
        }
        super.tearDown()
    }
    
    // MARK: - Model Tests
    
    func testDownloadErrorTypes() {
        let networkError = DownloadError.networkError(
            DownloadError.UnderlyingError(domain: "test", code: 404, description: "Not found")
        )
        let serverError = DownloadError.serverError(500)
        let timeout = DownloadError.timeout
        let cancelled = DownloadError.cancelled
        
        // Test retryability
        XCTAssertTrue(networkError.isRetryable)
        XCTAssertTrue(serverError.isRetryable)
        XCTAssertTrue(timeout.isRetryable)
        XCTAssertFalse(cancelled.isRetryable)
        
        // Test descriptions
        XCTAssertNotNil(networkError.errorDescription)
        XCTAssertNotNil(serverError.errorDescription)
        XCTAssertNotNil(timeout.errorDescription)
    }
    
    func testRetryPolicyDefaults() {
        let policy = RetryPolicy()
        
        XCTAssertEqual(policy.maxRetries, 3)
        XCTAssertEqual(policy.initialDelay, 2.0)
        XCTAssertEqual(policy.maxDelay, 60.0)
        XCTAssertEqual(policy.backoffMultiplier, 2.0)
        XCTAssertFalse(policy.retryableErrorCodes.isEmpty)
    }
    
    func testRetryPolicyDelayCalculation() {
        let policy = RetryPolicy(initialDelay: 2.0, maxDelay: 60.0, backoffMultiplier: 2.0)
        
        // Attempt 0: 2s
        XCTAssertEqual(policy.delayForAttempt(0), 2.0)
        
        // Attempt 1: 4s
        XCTAssertEqual(policy.delayForAttempt(1), 4.0)
        
        // Attempt 2: 8s
        XCTAssertEqual(policy.delayForAttempt(2), 8.0)
        
        // Attempt 3: 16s
        XCTAssertEqual(policy.delayForAttempt(3), 16.0)
        
        // Attempt 10: Should cap at 60s
        XCTAssertEqual(policy.delayForAttempt(10), 60.0)
    }
    
    func testRetryPolicyShouldRetry() {
        let policy = RetryPolicy(maxRetries: 3)
        let error = DownloadError.timeout
        
        // Should retry attempts 0, 1, 2
        XCTAssertTrue(policy.shouldRetry(error: error, attempt: 0))
        XCTAssertTrue(policy.shouldRetry(error: error, attempt: 1))
        XCTAssertTrue(policy.shouldRetry(error: error, attempt: 2))
        
        // Should not retry attempt 3 (max reached)
        XCTAssertFalse(policy.shouldRetry(error: error, attempt: 3))
        
        // Non-retryable error
        let cancelledError = DownloadError.cancelled
        XCTAssertFalse(policy.shouldRetry(error: cancelledError, attempt: 0))
    }
    
    func testRetryPolicyPresets() {
        let aggressive = RetryPolicy.aggressive
        XCTAssertEqual(aggressive.maxRetries, 10)
        XCTAssertEqual(aggressive.initialDelay, 1.0)
        
        let conservative = RetryPolicy.conservative
        XCTAssertEqual(conservative.maxRetries, 3)
        XCTAssertEqual(conservative.initialDelay, 5.0)
        
        let noRetry = RetryPolicy.noRetry
        XCTAssertEqual(noRetry.maxRetries, 0)
    }
    
    func testResumeStrategy() {
        XCTAssertEqual(ResumeStrategy.automatic.description, "Resume if possible, restart otherwise")
        XCTAssertEqual(ResumeStrategy.resumeOnly.description, "Resume only (fail if not supported)")
        XCTAssertEqual(ResumeStrategy.restartOnly.description, "Always restart from beginning")
        XCTAssertEqual(ResumeStrategy.askUser.description, "Ask user each time")
    }
    
    func testResumeDataCreation() {
        let url = URL(string: "https://example.com/file.zip")!
        let dest = URL(fileURLWithPath: "/tmp/file.zip")
        let partial = URL(fileURLWithPath: "/tmp/file.zip.partial")
        
        let resumeData = ResumeData(
            url: url,
            destinationPath: dest,
            partialFilePath: partial,
            downloadedBytes: 5_000_000,
            totalBytes: 10_000_000,
            etag: "abc123",
            supportsRangeRequests: true
        )
        
        XCTAssertEqual(resumeData.url, url)
        XCTAssertEqual(resumeData.downloadedBytes, 5_000_000)
        XCTAssertEqual(resumeData.totalBytes, 10_000_000)
        XCTAssertEqual(resumeData.progressPercentage, 50.0)
        XCTAssertTrue(resumeData.canResume)
    }
    
    func testResumeDataCannotResumeWithoutETag() {
        let url = URL(string: "https://example.com/file.zip")!
        let dest = URL(fileURLWithPath: "/tmp/file.zip")
        let partial = URL(fileURLWithPath: "/tmp/file.zip.partial")
        
        let resumeData = ResumeData(
            url: url,
            destinationPath: dest,
            partialFilePath: partial,
            downloadedBytes: 5_000_000,
            totalBytes: 10_000_000,
            supportsRangeRequests: true
        )
        
        // Without etag or lastModified, cannot resume
        XCTAssertFalse(resumeData.canResume)
    }
    
    func testRetryAttemptCreation() {
        let attempt = RetryAttempt(
            attemptNumber: 1,
            error: "Network timeout",
            delayBeforeRetry: 2.0
        )
        
        XCTAssertNotNil(attempt.id)
        XCTAssertEqual(attempt.attemptNumber, 1)
        XCTAssertEqual(attempt.error, "Network timeout")
        XCTAssertEqual(attempt.delayBeforeRetry, 2.0)
    }
    
    func testResumeSettingsDefaults() {
        let settings = ResumeSettings()
        
        XCTAssertEqual(settings.retryPolicy.maxRetries, 3)
        XCTAssertEqual(settings.resumeStrategy, .automatic)
        XCTAssertTrue(settings.saveResumeData)
        XCTAssertTrue(settings.verifyFileIntegrity)
        XCTAssertEqual(settings.connectionTimeout, 60.0)
        XCTAssertTrue(settings.enableAutoResume)
        XCTAssertFalse(settings.cleanupFailedDownloads)
        XCTAssertEqual(settings.cleanupAfterDays, 7)
    }
    
    func testResumeSettingsPresets() {
        let reliable = ResumeSettings.reliable
        XCTAssertEqual(reliable.retryPolicy.maxRetries, 10)
        XCTAssertTrue(reliable.enableAutoResume)
        
        let fast = ResumeSettings.fast
        XCTAssertFalse(fast.saveResumeData)
        XCTAssertFalse(fast.verifyFileIntegrity)
        
        let manual = ResumeSettings.manual
        XCTAssertEqual(manual.retryPolicy.maxRetries, 0)
        XCTAssertEqual(manual.resumeStrategy, .askUser)
    }
    
    // MARK: - Statistics Tests
    
    func testDownloadStatisticsInitialization() {
        let stats = DownloadStatistics()
        
        XCTAssertEqual(stats.totalAttempts, 0)
        XCTAssertEqual(stats.successfulDownloads, 0)
        XCTAssertEqual(stats.failedDownloads, 0)
        XCTAssertEqual(stats.resumedDownloads, 0)
        XCTAssertEqual(stats.totalRetries, 0)
        XCTAssertEqual(stats.averageRetries, 0)
        XCTAssertEqual(stats.successRate, 0)
        XCTAssertEqual(stats.resumeRate, 0)
    }
    
    func testStatisticsRecordSuccess() {
        var stats = DownloadStatistics()
        
        stats.recordSuccess(wasResumed: false, retries: 0, bytesDownloaded: 1_000_000)
        
        XCTAssertEqual(stats.totalAttempts, 1)
        XCTAssertEqual(stats.successfulDownloads, 1)
        XCTAssertEqual(stats.resumedDownloads, 0)
        XCTAssertEqual(stats.totalRetries, 0)
        XCTAssertEqual(stats.successRate, 100.0)
    }
    
    func testStatisticsRecordSuccessWithResume() {
        var stats = DownloadStatistics()
        
        stats.recordSuccess(wasResumed: true, retries: 2, bytesDownloaded: 5_000_000)
        
        XCTAssertEqual(stats.totalAttempts, 1)
        XCTAssertEqual(stats.successfulDownloads, 1)
        XCTAssertEqual(stats.resumedDownloads, 1)
        XCTAssertEqual(stats.totalRetries, 2)
        XCTAssertEqual(stats.resumeRate, 100.0)
        XCTAssertEqual(stats.averageRetries, 2.0)
    }
    
    func testStatisticsRecordFailure() {
        var stats = DownloadStatistics()
        
        stats.recordFailure(retries: 3)
        
        XCTAssertEqual(stats.totalAttempts, 1)
        XCTAssertEqual(stats.failedDownloads, 1)
        XCTAssertEqual(stats.totalRetries, 3)
        XCTAssertEqual(stats.successRate, 0.0)
    }
    
    func testStatisticsMixedResults() {
        var stats = DownloadStatistics()
        
        // 3 successes, 1 failure
        stats.recordSuccess(wasResumed: false, retries: 0, bytesDownloaded: 1_000_000)
        stats.recordSuccess(wasResumed: true, retries: 1, bytesDownloaded: 2_000_000)
        stats.recordSuccess(wasResumed: false, retries: 0, bytesDownloaded: 3_000_000)
        stats.recordFailure(retries: 3)
        
        XCTAssertEqual(stats.totalAttempts, 4)
        XCTAssertEqual(stats.successfulDownloads, 3)
        XCTAssertEqual(stats.failedDownloads, 1)
        XCTAssertEqual(stats.resumedDownloads, 1)
        XCTAssertEqual(stats.totalRetries, 4)
        XCTAssertEqual(stats.successRate, 75.0)
        XCTAssertEqual(stats.resumeRate, 100.0 / 3.0, accuracy: 0.1)
        XCTAssertEqual(stats.averageRetries, 1.0)
        XCTAssertEqual(stats.totalDataDownloaded, 6_000_000)
    }
    
    // MARK: - Manager Tests
    
    func testManagerInitialization() {
        XCTAssertNotNil(resumeManager.settings)
        XCTAssertNotNil(resumeManager.statistics)
        XCTAssertTrue(resumeManager.activeRetries.isEmpty)
    }
    
    func testUpdateSettings() {
        let newSettings = ResumeSettings.fast
        resumeManager.updateSettings(newSettings)
        
        XCTAssertEqual(resumeManager.settings.saveResumeData, false)
        XCTAssertEqual(resumeManager.settings.verifyFileIntegrity, false)
    }
    
    func testSaveAndGetResumeData() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/file.zip")!
        let dest = URL(fileURLWithPath: "/tmp/file.zip")
        let partial = URL(fileURLWithPath: "/tmp/file.zip.partial")
        
        let resumeData = ResumeData(
            url: url,
            destinationPath: dest,
            partialFilePath: partial,
            downloadedBytes: 5_000_000,
            totalBytes: 10_000_000,
            etag: "abc123",
            supportsRangeRequests: true
        )
        
        resumeManager.saveResumeData(resumeData, for: taskId)
        
        let retrieved = resumeManager.getResumeData(for: taskId)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.downloadedBytes, 5_000_000)
        XCTAssertEqual(retrieved?.etag, "abc123")
    }
    
    func testDeleteResumeData() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/file.zip")!
        let dest = URL(fileURLWithPath: "/tmp/file.zip")
        let partial = URL(fileURLWithPath: "/tmp/file.zip.partial")
        
        let resumeData = ResumeData(
            url: url,
            destinationPath: dest,
            partialFilePath: partial,
            downloadedBytes: 5_000_000,
            totalBytes: 10_000_000,
            etag: "abc123",
            supportsRangeRequests: true
        )
        
        resumeManager.saveResumeData(resumeData, for: taskId)
        XCTAssertTrue(resumeManager.hasResumeData(for: taskId))
        
        resumeManager.deleteResumeData(for: taskId)
        XCTAssertFalse(resumeManager.hasResumeData(for: taskId))
    }
    
    func testShouldRetry() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            destinationPath: URL(fileURLWithPath: "/tmp/file.zip")
        )
        
        let retryableError = DownloadError.timeout
        let nonRetryableError = DownloadError.cancelled
        
        // Should retry retryable errors
        XCTAssertTrue(resumeManager.shouldRetry(task: task, error: retryableError))
        
        // Should not retry non-retryable errors
        XCTAssertFalse(resumeManager.shouldRetry(task: task, error: nonRetryableError))
        
        // Should not retry after max attempts
        task.retryCount = resumeManager.settings.retryPolicy.maxRetries
        XCTAssertFalse(resumeManager.shouldRetry(task: task, error: retryableError))
    }
    
    func testDetermineResumeAction_NoResumeData() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            destinationPath: URL(fileURLWithPath: "/tmp/file.zip")
        )
        
        let action = resumeManager.determineResumeAction(for: task, error: nil)
        
        switch action {
        case .restart:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected restart action when no resume data")
        }
    }
    
    func testDetermineResumeAction_AutomaticStrategy() {
        let taskId = UUID()
        let url = URL(string: "https://example.com/file.zip")!
        let dest = URL(fileURLWithPath: "/tmp/file.zip")
        let partial = URL(fileURLWithPath: "/tmp/file.zip.partial")
        
        let task = DownloadTask(url: url, destinationPath: dest)
        // Manually set the task ID to match
        
        let resumeData = ResumeData(
            url: url,
            destinationPath: dest,
            partialFilePath: partial,
            downloadedBytes: 5_000_000,
            totalBytes: 10_000_000,
            etag: "abc123",
            supportsRangeRequests: true
        )
        
        resumeManager.saveResumeData(resumeData, for: task.id)
        resumeManager.updateSettings(ResumeSettings(resumeStrategy: .automatic))
        
        let action = resumeManager.determineResumeAction(for: task, error: nil)
        
        switch action {
        case .resume(let data):
            XCTAssertEqual(data.downloadedBytes, 5_000_000)
        default:
            XCTFail("Expected resume action with automatic strategy")
        }
    }
    
    func testDetermineResumeAction_RestartOnlyStrategy() {
        let url = URL(string: "https://example.com/file.zip")!
        let dest = URL(fileURLWithPath: "/tmp/file.zip")
        let partial = URL(fileURLWithPath: "/tmp/file.zip.partial")
        
        let task = DownloadTask(url: url, destinationPath: dest)
        
        let resumeData = ResumeData(
            url: url,
            destinationPath: dest,
            partialFilePath: partial,
            downloadedBytes: 5_000_000,
            totalBytes: 10_000_000,
            etag: "abc123",
            supportsRangeRequests: true
        )
        
        resumeManager.saveResumeData(resumeData, for: task.id)
        resumeManager.updateSettings(ResumeSettings(resumeStrategy: .restartOnly))
        
        let action = resumeManager.determineResumeAction(for: task, error: nil)
        
        switch action {
        case .restart:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected restart action with restartOnly strategy")
        }
    }
    
    func testRecordSuccess() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            destinationPath: URL(fileURLWithPath: "/tmp/file.zip")
        )
        task.totalBytes = 10_000_000
        task.retryCount = 2
        
        let initialSuccesses = resumeManager.statistics.successfulDownloads
        
        resumeManager.recordSuccess(task: task, wasResumed: true)
        
        XCTAssertEqual(resumeManager.statistics.successfulDownloads, initialSuccesses + 1)
        XCTAssertEqual(resumeManager.statistics.resumedDownloads, 1)
        XCTAssertFalse(resumeManager.hasResumeData(for: task.id))
    }
    
    func testRecordFailure() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            destinationPath: URL(fileURLWithPath: "/tmp/file.zip")
        )
        task.retryCount = 3
        
        let initialFailures = resumeManager.statistics.failedDownloads
        
        resumeManager.recordFailure(task: task)
        
        XCTAssertEqual(resumeManager.statistics.failedDownloads, initialFailures + 1)
    }
    
    // MARK: - Integration Tests
    
    func testRetryWorkflow() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            destinationPath: URL(fileURLWithPath: "/tmp/file.zip")
        )
        
        let error = DownloadError.timeout
        
        // First retry should be scheduled
        XCTAssertTrue(resumeManager.shouldRetry(task: task, error: error))
        
        let expectation = self.expectation(description: "Retry scheduled")
        var retryCallbackCalled = false
        
        resumeManager.scheduleRetry(task: task, error: error) {
            retryCallbackCalled = true
            expectation.fulfill()
        }
        
        // Verify retry is active
        XCTAssertNotNil(resumeManager.activeRetries[task.id])
        
        // Wait for retry
        waitForExpectations(timeout: 5.0)
        
        XCTAssertTrue(retryCallbackCalled)
        XCTAssertEqual(task.retryCount, 1)
        XCTAssertNil(resumeManager.activeRetries[task.id])
    }
    
    func testCancelRetry() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            destinationPath: URL(fileURLWithPath: "/tmp/file.zip")
        )
        
        let error = DownloadError.timeout
        
        resumeManager.scheduleRetry(task: task, error: error) {
            XCTFail("Retry callback should not be called after cancellation")
        }
        
        XCTAssertNotNil(resumeManager.activeRetries[task.id])
        
        resumeManager.cancelRetry(for: task.id)
        
        XCTAssertNil(resumeManager.activeRetries[task.id])
    }
    
    func testRetryHistoryTracking() {
        let task = DownloadTask(
            url: URL(string: "https://example.com/file.zip")!,
            destinationPath: URL(fileURLWithPath: "/tmp/file.zip")
        )
        
        let error = DownloadError.timeout
        
        // Schedule multiple retries
        for _ in 1...3 {
            let expectation = self.expectation(description: "Retry \(task.retryCount)")
            
            resumeManager.scheduleRetry(task: task, error: error) {
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5.0)
        }
        
        let history = resumeManager.getRetryHistory(for: task.id)
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].attemptNumber, 1)
        XCTAssertEqual(history[1].attemptNumber, 2)
        XCTAssertEqual(history[2].attemptNumber, 3)
    }
    
    // MARK: - Performance Tests
    
    func testResumeDataPerformance() {
        measure {
            for _ in 0..<100 {
                let taskId = UUID()
                let url = URL(string: "https://example.com/file\(taskId).zip")!
                let dest = URL(fileURLWithPath: "/tmp/file\(taskId).zip")
                let partial = URL(fileURLWithPath: "/tmp/file\(taskId).zip.partial")
                
                let resumeData = ResumeData(
                    url: url,
                    destinationPath: dest,
                    partialFilePath: partial,
                    downloadedBytes: Int64.random(in: 1_000_000...10_000_000),
                    totalBytes: 10_000_000,
                    etag: UUID().uuidString,
                    supportsRangeRequests: true
                )
                
                resumeManager.saveResumeData(resumeData, for: taskId)
            }
        }
    }
    
    func testRetryPolicyPerformance() {
        let policy = RetryPolicy()
        
        measure {
            for attempt in 0..<1000 {
                _ = policy.delayForAttempt(attempt)
            }
        }
    }
}
