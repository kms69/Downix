//
//  BrowserIntegrationTests.swift
//  Download Manager for Mac - Feature #5: Browser Integration Tests
//
//  Created on February 15, 2026
//

import XCTest
@testable import DownloadManager

class BrowserIntegrationTests: XCTestCase {
    
    var manager: BrowserIntegrationManager!
    var downloadManager: DownloadManager!
    
    override func setUp() {
        super.setUp()
        manager = BrowserIntegrationManager.shared
        downloadManager = DownloadManager.shared
        
        // Clear existing state
        manager.updateSettings(BrowserIntegrationSettings())
        manager.totalIntercepted = 0
        manager.totalCaptured = 0
        manager.totalIgnored = 0
        
        // Clear downloads
        for task in downloadManager.downloadTasks {
            downloadManager.removeDownload(task)
        }
    }
    
    override func tearDown() {
        // Clean up
        for task in downloadManager.downloadTasks {
            downloadManager.removeDownload(task)
        }
        super.tearDown()
    }
    
    // MARK: - Model Tests
    
    func testBrowserTypeEnum() {
        XCTAssertEqual(BrowserType.allCases.count, 5)
        XCTAssertTrue(BrowserType.allCases.contains(.safari))
        XCTAssertTrue(BrowserType.allCases.contains(.chrome))
        XCTAssertTrue(BrowserType.allCases.contains(.brave))
        XCTAssertTrue(BrowserType.allCases.contains(.firefox))
        XCTAssertTrue(BrowserType.allCases.contains(.edge))
    }
    
    func testBrowserTypeProperties() {
        XCTAssertEqual(BrowserType.safari.rawValue, "Safari")
        XCTAssertEqual(BrowserType.chrome.icon, "globe")
        XCTAssertEqual(BrowserType.firefox.icon, "flame.fill")
        
        // Test extension IDs
        XCTAssertTrue(BrowserType.safari.extensionID.contains("safari"))
        XCTAssertTrue(BrowserType.chrome.extensionID.contains("chrome"))
        
        // Test native host name
        for browser in BrowserType.allCases {
            XCTAssertEqual(browser.nativeMessagingHostName, "com.rapiddownload.native")
        }
    }
    
    func testCaptureRuleCreation() {
        let rule = CaptureRule(
            name: "Test Rule",
            pattern: .fileExtension(["zip", "rar"]),
            action: .capture,
            priority: 50
        )
        
        XCTAssertNotNil(rule.id)
        XCTAssertEqual(rule.name, "Test Rule")
        XCTAssertTrue(rule.isEnabled)
        XCTAssertEqual(rule.action, .capture)
        XCTAssertEqual(rule.priority, 50)
    }
    
    func testCaptureRuleEquality() {
        let id = UUID()
        let rule1 = CaptureRule(
            id: id,
            name: "Rule 1",
            pattern: .fileExtension(["zip"]),
            action: .capture,
            priority: 50
        )
        let rule2 = CaptureRule(
            id: id,
            name: "Rule 1",
            pattern: .fileExtension(["zip"]),
            action: .capture,
            priority: 50
        )
        
        XCTAssertEqual(rule1, rule2)
    }
    
    // MARK: - Capture Pattern Tests
    
    func testFileExtensionPattern() {
        let pattern = CaptureRule.CapturePattern.fileExtension(["zip", "rar", "7z"])
        
        XCTAssertTrue(pattern.matches(url: "https://example.com/file.zip", mimeType: nil, contentLength: nil))
        XCTAssertTrue(pattern.matches(url: "https://example.com/archive.RAR", mimeType: nil, contentLength: nil))
        XCTAssertTrue(pattern.matches(url: "https://example.com/data.7z", mimeType: nil, contentLength: nil))
        XCTAssertFalse(pattern.matches(url: "https://example.com/video.mp4", mimeType: nil, contentLength: nil))
    }
    
    func testURLPatternRegex() {
        let pattern = CaptureRule.CapturePattern.urlPattern(".*\\.example\\.com/downloads/.*")
        
        XCTAssertTrue(pattern.matches(url: "https://cdn.example.com/downloads/file.zip", mimeType: nil, contentLength: nil))
        XCTAssertFalse(pattern.matches(url: "https://other.com/downloads/file.zip", mimeType: nil, contentLength: nil))
    }
    
    func testMimeTypePattern() {
        let pattern = CaptureRule.CapturePattern.mimeType(["video/", "application/zip"])
        
        XCTAssertTrue(pattern.matches(url: "https://example.com/file", mimeType: "video/mp4", contentLength: nil))
        XCTAssertTrue(pattern.matches(url: "https://example.com/file", mimeType: "application/zip", contentLength: nil))
        XCTAssertFalse(pattern.matches(url: "https://example.com/file", mimeType: "text/html", contentLength: nil))
        XCTAssertFalse(pattern.matches(url: "https://example.com/file", mimeType: nil, contentLength: nil))
    }
    
    func testMinFileSizePattern() {
        let pattern = CaptureRule.CapturePattern.minFileSize(10_485_760) // 10 MB
        
        XCTAssertTrue(pattern.matches(url: "https://example.com/file", mimeType: nil, contentLength: 20_000_000))
        XCTAssertTrue(pattern.matches(url: "https://example.com/file", mimeType: nil, contentLength: 10_485_760))
        XCTAssertFalse(pattern.matches(url: "https://example.com/file", mimeType: nil, contentLength: 5_000_000))
        XCTAssertFalse(pattern.matches(url: "https://example.com/file", mimeType: nil, contentLength: nil))
    }
    
    func testDomainPattern() {
        let pattern = CaptureRule.CapturePattern.domain(["example.com", "cdn.site.org"])
        
        XCTAssertTrue(pattern.matches(url: "https://example.com/file.zip", mimeType: nil, contentLength: nil))
        XCTAssertTrue(pattern.matches(url: "https://cdn.site.org/data.zip", mimeType: nil, contentLength: nil))
        XCTAssertFalse(pattern.matches(url: "https://other.com/file.zip", mimeType: nil, contentLength: nil))
    }
    
    func testAllPattern() {
        let pattern = CaptureRule.CapturePattern.all
        
        XCTAssertTrue(pattern.matches(url: "https://example.com/anything", mimeType: nil, contentLength: nil))
        XCTAssertTrue(pattern.matches(url: "https://other.com/file.xyz", mimeType: "text/html", contentLength: 100))
    }
    
    // MARK: - Native Message Tests
    
    func testDownloadRequestEncoding() throws {
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/file.zip",
            filename: "file.zip",
            referrer: "https://example.com",
            cookies: "session=abc123",
            userAgent: "Mozilla/5.0",
            mimeType: "application/zip",
            contentLength: 1024000
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        
        XCTAssertFalse(data.isEmpty)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NativeMessage.DownloadRequest.self, from: data)
        
        XCTAssertEqual(decoded.url, request.url)
        XCTAssertEqual(decoded.filename, request.filename)
        XCTAssertEqual(decoded.contentLength, request.contentLength)
    }
    
    func testDownloadResponseEncoding() throws {
        let response = NativeMessage.DownloadResponse(
            success: true,
            taskId: "123-456-789",
            error: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        
        XCTAssertFalse(data.isEmpty)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NativeMessage.DownloadResponse.self, from: data)
        
        XCTAssertEqual(decoded.success, response.success)
        XCTAssertEqual(decoded.taskId, response.taskId)
        XCTAssertNil(decoded.error)
    }
    
    // MARK: - Browser Extension Status Tests
    
    func testExtensionStatusCreation() {
        let status = BrowserExtensionStatus(
            browser: .chrome,
            isInstalled: true,
            isEnabled: true,
            version: "1.0.0"
        )
        
        XCTAssertNotNil(status.id)
        XCTAssertEqual(status.browser, .chrome)
        XCTAssertTrue(status.isInstalled)
        XCTAssertTrue(status.isEnabled)
        XCTAssertEqual(status.version, "1.0.0")
        XCTAssertEqual(status.downloadsIntercepted, 0)
    }
    
    // MARK: - Browser Integration Settings Tests
    
    func testDefaultSettings() {
        let settings = BrowserIntegrationSettings()
        
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.autoCapture)
        XCTAssertTrue(settings.showNotifications)
        XCTAssertTrue(settings.closeOriginalDownload)
        XCTAssertEqual(settings.minFileSizeForCapture, 1_048_576) // 1 MB
        XCTAssertTrue(settings.captureRules.isEmpty)
        XCTAssertTrue(settings.blacklistedDomains.isEmpty)
        XCTAssertTrue(settings.whitelistedDomains.isEmpty)
    }
    
    func testDefaultRules() {
        let rules = BrowserIntegrationSettings.defaultRules
        
        XCTAssertEqual(rules.count, 5)
        
        // Check priorities are descending
        for i in 0..<(rules.count - 1) {
            XCTAssertGreaterThanOrEqual(rules[i].priority, rules[i + 1].priority)
        }
        
        // Check specific rules exist
        XCTAssertTrue(rules.contains { $0.name.contains("Large Files") })
        XCTAssertTrue(rules.contains { $0.name.contains("Videos") })
        XCTAssertTrue(rules.contains { $0.name.contains("Archives") })
        XCTAssertTrue(rules.contains { $0.name.contains("Software") })
        XCTAssertTrue(rules.contains { $0.name.contains("Documents") })
    }
    
    func testAggressiveCapturePreset() {
        let settings = BrowserIntegrationSettings.aggressiveCapture
        
        XCTAssertTrue(settings.autoCapture)
        XCTAssertEqual(settings.minFileSizeForCapture, 0)
        XCTAssertTrue(settings.closeOriginalDownload)
        XCTAssertFalse(settings.captureRules.isEmpty)
    }
    
    func testConservativeCapturePreset() {
        let settings = BrowserIntegrationSettings.conservativeCapture
        
        XCTAssertTrue(settings.autoCapture)
        XCTAssertEqual(settings.minFileSizeForCapture, 10_485_760) // 10 MB
        XCTAssertFalse(settings.closeOriginalDownload)
        XCTAssertEqual(settings.captureRules.count, 1)
    }
    
    func testManualCapturePreset() {
        let settings = BrowserIntegrationSettings.manualCapture
        
        XCTAssertFalse(settings.autoCapture)
        XCTAssertTrue(settings.captureRules.isEmpty)
    }
    
    // MARK: - Manager Settings Tests
    
    func testUpdateSettings() {
        var settings = BrowserIntegrationSettings()
        settings.isEnabled = false
        settings.autoCapture = false
        
        manager.updateSettings(settings)
        
        XCTAssertFalse(manager.settings.isEnabled)
        XCTAssertFalse(manager.settings.autoCapture)
    }
    
    func testAddCaptureRule() {
        let rule = CaptureRule(
            name: "Custom Rule",
            pattern: .fileExtension(["custom"]),
            priority: 95
        )
        
        manager.addCaptureRule(rule)
        
        XCTAssertTrue(manager.settings.captureRules.contains { $0.id == rule.id })
    }
    
    func testRemoveCaptureRule() {
        let rule = CaptureRule(
            name: "Temp Rule",
            pattern: .all,
            priority: 10
        )
        
        manager.addCaptureRule(rule)
        XCTAssertTrue(manager.settings.captureRules.contains { $0.id == rule.id })
        
        manager.removeCaptureRule(rule)
        XCTAssertFalse(manager.settings.captureRules.contains { $0.id == rule.id })
    }
    
    func testUpdateCaptureRule() {
        var rule = CaptureRule(
            name: "Original",
            pattern: .all,
            priority: 10
        )
        
        manager.addCaptureRule(rule)
        
        rule.name = "Updated"
        rule.priority = 20
        manager.updateCaptureRule(rule)
        
        let updated = manager.settings.captureRules.first { $0.id == rule.id }
        XCTAssertEqual(updated?.name, "Updated")
        XCTAssertEqual(updated?.priority, 20)
    }
    
    func testRulesSortedByPriority() {
        let rule1 = CaptureRule(name: "Low", pattern: .all, priority: 10)
        let rule2 = CaptureRule(name: "High", pattern: .all, priority: 100)
        let rule3 = CaptureRule(name: "Medium", pattern: .all, priority: 50)
        
        manager.addCaptureRule(rule1)
        manager.addCaptureRule(rule2)
        manager.addCaptureRule(rule3)
        
        // Rules should be sorted by priority descending
        XCTAssertEqual(manager.settings.captureRules[0].priority, 100)
        XCTAssertEqual(manager.settings.captureRules[1].priority, 50)
        XCTAssertEqual(manager.settings.captureRules[2].priority, 10)
    }
    
    // MARK: - Download Capture Tests
    
    func testCaptureDownload_Disabled() {
        var settings = manager.settings
        settings.isEnabled = false
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/file.zip",
            filename: "file.zip",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/zip",
            contentLength: 10_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertFalse(response.success)
        XCTAssertNil(response.taskId)
        XCTAssertNotNil(response.error)
        XCTAssertEqual(manager.totalIntercepted, 1)
        XCTAssertEqual(manager.totalCaptured, 0)
        XCTAssertEqual(manager.totalIgnored, 1)
    }
    
    func testCaptureDownload_AutoCaptureDisabled() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = false
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/file.zip",
            filename: "file.zip",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/zip",
            contentLength: 10_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertFalse(response.success)
        XCTAssertEqual(manager.totalIgnored, 1)
    }
    
    func testCaptureDownload_Blacklisted() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.blacklistedDomains = ["blocked.com"]
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://blocked.com/file.zip",
            filename: "file.zip",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/zip",
            contentLength: 10_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertFalse(response.success)
        XCTAssertEqual(manager.totalIgnored, 1)
    }
    
    func testCaptureDownload_NotInWhitelist() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.whitelistedDomains = ["allowed.com"]
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://notallowed.com/file.zip",
            filename: "file.zip",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/zip",
            contentLength: 10_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertFalse(response.success)
        XCTAssertEqual(manager.totalIgnored, 1)
    }
    
    func testCaptureDownload_InWhitelist() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.whitelistedDomains = ["allowed.com"]
        settings.minFileSizeForCapture = 0
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://allowed.com/file.zip",
            filename: "file.zip",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/zip",
            contentLength: 10_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.taskId)
        XCTAssertEqual(manager.totalCaptured, 1)
    }
    
    func testCaptureDownload_FileTooSmall() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.minFileSizeForCapture = 10_000_000 // 10 MB
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/small.txt",
            filename: "small.txt",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "text/plain",
            contentLength: 1024 // 1 KB
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertFalse(response.success)
        XCTAssertEqual(manager.totalIgnored, 1)
    }
    
    func testCaptureDownload_MatchesCaptureRule() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.captureRules = [
            CaptureRule(
                name: "Videos",
                pattern: .fileExtension(["mp4"]),
                action: .capture,
                priority: 100
            )
        ]
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/video.mp4",
            filename: "video.mp4",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "video/mp4",
            contentLength: 50_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.taskId)
        XCTAssertEqual(manager.totalCaptured, 1)
    }
    
    func testCaptureDownload_MatchesIgnoreRule() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.captureRules = [
            CaptureRule(
                name: "Ignore HTML",
                pattern: .mimeType(["text/html"]),
                action: .ignore,
                priority: 100
            )
        ]
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/page.html",
            filename: "page.html",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "text/html",
            contentLength: 50_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertFalse(response.success)
        XCTAssertEqual(manager.totalIgnored, 1)
    }
    
    func testCaptureDownload_HigherPriorityRuleWins() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.captureRules = [
            CaptureRule(
                name: "Capture All",
                pattern: .all,
                action: .capture,
                priority: 10
            ),
            CaptureRule(
                name: "Ignore Specific",
                pattern: .fileExtension(["exe"]),
                action: .ignore,
                priority: 100
            )
        ]
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/app.exe",
            filename: "app.exe",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/exe",
            contentLength: 5_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        // Higher priority ignore rule should win
        XCTAssertFalse(response.success)
        XCTAssertEqual(manager.totalIgnored, 1)
    }
    
    func testCaptureDownload_CreatesTask() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.minFileSizeForCapture = 0
        manager.updateSettings(settings)
        
        let initialTaskCount = downloadManager.downloadTasks.count
        
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/file.zip",
            filename: "file.zip",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/zip",
            contentLength: 10_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.taskId)
        XCTAssertEqual(downloadManager.downloadTasks.count, initialTaskCount + 1)
        
        // Verify task details
        if let taskId = response.taskId,
           let uuid = UUID(uuidString: taskId),
           let task = downloadManager.downloadTasks.first(where: { $0.id == uuid }) {
            XCTAssertEqual(task.url.absoluteString, request.url)
            XCTAssertTrue(task.filename.contains("file.zip"))
        } else {
            XCTFail("Task not created properly")
        }
    }
    
    func testCaptureDownload_InvalidURL() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        manager.updateSettings(settings)
        
        let request = NativeMessage.DownloadRequest(
            url: "not-a-valid-url",
            filename: "file.zip",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: nil,
            contentLength: nil
        )
        
        let response = manager.handleDownloadRequest(request)
        
        XCTAssertFalse(response.success)
        XCTAssertNil(response.taskId)
        XCTAssertNotNil(response.error)
    }
    
    // MARK: - Extension Status Tests
    
    func testInitialExtensionStatuses() {
        // Manager should initialize with all browser types
        XCTAssertEqual(manager.extensionStatuses.count, BrowserType.allCases.count)
        
        for browser in BrowserType.allCases {
            let status = manager.extensionStatuses.first { $0.browser == browser }
            XCTAssertNotNil(status)
            XCTAssertFalse(status!.isInstalled)
            XCTAssertFalse(status!.isEnabled)
        }
    }
    
    func testUpdateExtensionStatus() {
        manager.updateExtensionStatus(.chrome, isInstalled: true, isEnabled: true)
        
        let status = manager.getExtensionStatus(.chrome)
        XCTAssertNotNil(status)
        XCTAssertTrue(status!.isInstalled)
        XCTAssertTrue(status!.isEnabled)
        XCTAssertNotNil(status!.lastCommunication)
    }
    
    func testRecordExtensionCommunication() {
        let initialStatus = manager.getExtensionStatus(.firefox)
        let initialCount = initialStatus?.downloadsIntercepted ?? 0
        
        manager.recordExtensionCommunication(.firefox)
        
        let updatedStatus = manager.getExtensionStatus(.firefox)
        XCTAssertNotNil(updatedStatus?.lastCommunication)
        XCTAssertEqual(updatedStatus?.downloadsIntercepted, initialCount + 1)
    }
    
    func testGetExtensionStatus() {
        let status = manager.getExtensionStatus(.safari)
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.browser, .safari)
    }
    
    // MARK: - Statistics Tests
    
    func testInitialStatistics() {
        let stats = manager.getStatistics()
        
        XCTAssertEqual(stats.totalIntercepted, 0)
        XCTAssertEqual(stats.totalCaptured, 0)
        XCTAssertEqual(stats.totalIgnored, 0)
        XCTAssertEqual(stats.captureRate, 0)
        XCTAssertEqual(stats.installedExtensions, 0)
        XCTAssertEqual(stats.enabledExtensions, 0)
    }
    
    func testStatisticsAfterCaptures() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.minFileSizeForCapture = 0
        manager.updateSettings(settings)
        
        // Capture 3 downloads
        for i in 1...3 {
            let request = NativeMessage.DownloadRequest(
                url: "https://example.com/file\(i).zip",
                filename: "file\(i).zip",
                referrer: nil,
                cookies: nil,
                userAgent: nil,
                mimeType: "application/zip",
                contentLength: 1_000_000
            )
            _ = manager.handleDownloadRequest(request)
        }
        
        // Ignore 2 downloads
        settings.autoCapture = false
        manager.updateSettings(settings)
        for i in 1...2 {
            let request = NativeMessage.DownloadRequest(
                url: "https://example.com/ignored\(i).txt",
                filename: "ignored\(i).txt",
                referrer: nil,
                cookies: nil,
                userAgent: nil,
                mimeType: "text/plain",
                contentLength: 100
            )
            _ = manager.handleDownloadRequest(request)
        }
        
        let stats = manager.getStatistics()
        
        XCTAssertEqual(stats.totalIntercepted, 5)
        XCTAssertEqual(stats.totalCaptured, 3)
        XCTAssertEqual(stats.totalIgnored, 2)
        XCTAssertEqual(stats.captureRate, 0.6, accuracy: 0.01)
    }
    
    func testStatisticsWithExtensions() {
        manager.updateExtensionStatus(.chrome, isInstalled: true, isEnabled: true)
        manager.updateExtensionStatus(.firefox, isInstalled: true, isEnabled: false)
        manager.updateExtensionStatus(.safari, isInstalled: false, isEnabled: false)
        
        let stats = manager.getStatistics()
        
        XCTAssertEqual(stats.installedExtensions, 2)
        XCTAssertEqual(stats.enabledExtensions, 1)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteWorkflow() {
        // Setup
        var settings = BrowserIntegrationSettings.aggressiveCapture
        settings.captureRules = [
            CaptureRule(
                name: "Large Videos",
                pattern: .fileExtension(["mp4", "mkv"]),
                action: .capture,
                priority: 100
            )
        ]
        manager.updateSettings(settings)
        manager.updateExtensionStatus(.chrome, isInstalled: true, isEnabled: true)
        
        // Simulate download from browser
        let request = NativeMessage.DownloadRequest(
            url: "https://videos.example.com/movie.mp4",
            filename: "movie.mp4",
            referrer: "https://example.com",
            cookies: "session=xyz",
            userAgent: "Chrome/120.0",
            mimeType: "video/mp4",
            contentLength: 500_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        // Verify success
        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.taskId)
        
        // Verify statistics
        XCTAssertEqual(manager.totalIntercepted, 1)
        XCTAssertEqual(manager.totalCaptured, 1)
        XCTAssertEqual(manager.totalIgnored, 0)
        
        // Verify download task created
        XCTAssertEqual(downloadManager.downloadTasks.count, 1)
        let task = downloadManager.downloadTasks.first!
        XCTAssertEqual(task.url.absoluteString, request.url)
    }
    
    func testMultipleBrowsersScenario() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.minFileSizeForCapture = 0
        manager.updateSettings(settings)
        
        // Simulate multiple browsers
        manager.updateExtensionStatus(.chrome, isInstalled: true, isEnabled: true)
        manager.updateExtensionStatus(.firefox, isInstalled: true, isEnabled: true)
        manager.updateExtensionStatus(.safari, isInstalled: true, isEnabled: false)
        
        // Record communications
        manager.recordExtensionCommunication(.chrome)
        manager.recordExtensionCommunication(.chrome)
        manager.recordExtensionCommunication(.firefox)
        
        // Verify tracking
        let chromeStatus = manager.getExtensionStatus(.chrome)
        let firefoxStatus = manager.getExtensionStatus(.firefox)
        let safariStatus = manager.getExtensionStatus(.safari)
        
        XCTAssertEqual(chromeStatus?.downloadsIntercepted, 2)
        XCTAssertEqual(firefoxStatus?.downloadsIntercepted, 1)
        XCTAssertEqual(safariStatus?.downloadsIntercepted, 0)
        
        let stats = manager.getStatistics()
        XCTAssertEqual(stats.installedExtensions, 3)
        XCTAssertEqual(stats.enabledExtensions, 2)
    }
    
    func testRuleBasedFiltering() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.captureRules = [
            CaptureRule(
                name: "Only PDFs from docs domain",
                pattern: .domain(["docs.example.com"]),
                action: .capture,
                priority: 100
            ),
            CaptureRule(
                name: "Ignore everything else",
                pattern: .all,
                action: .ignore,
                priority: 10
            )
        ]
        manager.updateSettings(settings)
        
        // Should capture
        let request1 = NativeMessage.DownloadRequest(
            url: "https://docs.example.com/manual.pdf",
            filename: "manual.pdf",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/pdf",
            contentLength: 2_000_000
        )
        let response1 = manager.handleDownloadRequest(request1)
        XCTAssertTrue(response1.success)
        
        // Should ignore
        let request2 = NativeMessage.DownloadRequest(
            url: "https://other.com/file.pdf",
            filename: "file.pdf",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: "application/pdf",
            contentLength: 2_000_000
        )
        let response2 = manager.handleDownloadRequest(request2)
        XCTAssertFalse(response2.success)
        
        XCTAssertEqual(manager.totalCaptured, 1)
        XCTAssertEqual(manager.totalIgnored, 1)
    }
    
    // MARK: - Performance Tests
    
    func testLargeNumberOfRules() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        
        // Add 100 rules
        var rules: [CaptureRule] = []
        for i in 0..<100 {
            rules.append(CaptureRule(
                name: "Rule \(i)",
                pattern: .fileExtension(["ext\(i)"]),
                action: .capture,
                priority: i
            ))
        }
        settings.captureRules = rules
        manager.updateSettings(settings)
        
        // Measure performance
        let start = Date()
        
        let request = NativeMessage.DownloadRequest(
            url: "https://example.com/file.ext50",
            filename: "file.ext50",
            referrer: nil,
            cookies: nil,
            userAgent: nil,
            mimeType: nil,
            contentLength: 1_000_000
        )
        
        let response = manager.handleDownloadRequest(request)
        
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertTrue(response.success)
        XCTAssertLessThan(duration, 0.1) // Should be fast even with 100 rules
    }
    
    func testConcurrentRequests() {
        var settings = manager.settings
        settings.isEnabled = true
        settings.autoCapture = true
        settings.minFileSizeForCapture = 0
        manager.updateSettings(settings)
        
        let expectation = self.expectation(description: "Concurrent requests")
        expectation.expectedFulfillmentCount = 10
        
        DispatchQueue.concurrentPerform(iterations: 10) { i in
            let request = NativeMessage.DownloadRequest(
                url: "https://example.com/file\(i).zip",
                filename: "file\(i).zip",
                referrer: nil,
                cookies: nil,
                userAgent: nil,
                mimeType: "application/zip",
                contentLength: 1_000_000
            )
            
            _ = manager.handleDownloadRequest(request)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        XCTAssertEqual(manager.totalIntercepted, 10)
        XCTAssertEqual(manager.totalCaptured, 10)
    }
}
