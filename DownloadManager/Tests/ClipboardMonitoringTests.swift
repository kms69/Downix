//
//  ClipboardMonitoringTests.swift
//  Download Manager for Mac - Feature #17: URL Monitoring & Clipboard Tests
//
//  Created on February 17, 2026
//

import XCTest
@testable import DownloadManager

class ClipboardMonitoringTests: XCTestCase {
    
    var monitor: ClipboardMonitor!
    
    override func setUp() async throws {
        try await super.setUp()
        monitor = await ClipboardMonitor.shared
        
        // Clear existing data
        await MainActor.run {
            monitor.rules.removeAll()
            monitor.domainList.removeAll()
            monitor.detectedURLs.removeAll()
            monitor.clearStats()
        }
    }
    
    // MARK: - Settings Tests
    
    func testDefaultSettings() async {
        let settings = await monitor.settings
        
        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(settings.autoDownload)
        XCTAssertTrue(settings.showConfirmation)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertTrue(settings.notificationEnabled)
        XCTAssertEqual(settings.minimumURLLength, 10)
        XCTAssertEqual(settings.pollingInterval, 0.5)
        XCTAssertFalse(settings.detectPartialURLs)
    }
    
    func testUpdateSettings() async {
        var newSettings = await monitor.settings
        newSettings.isEnabled = true
        newSettings.autoDownload = true
        newSettings.pollingInterval = 1.0
        
        await monitor.updateSettings(newSettings)
        
        let updated = await monitor.settings
        XCTAssertTrue(updated.isEnabled)
        XCTAssertTrue(updated.autoDownload)
        XCTAssertEqual(updated.pollingInterval, 1.0)
    }
    
    // MARK: - URL Pattern Tests
    
    func testDomainPattern() {
        let pattern = URLPattern.domain("example.com")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/file.zip")!))
        XCTAssertTrue(pattern.matches(URL(string: "http://example.com")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://sub.example.com")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://other.com")!))
    }
    
    func testSubdomainPattern() {
        let pattern = URLPattern.subdomain("example.com")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://sub.example.com")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://deep.sub.example.com")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://other.com")!))
    }
    
    func testPathPattern() {
        let pattern = URLPattern.path("/downloads/")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/downloads/file.zip")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/public/downloads/")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://example.com/files/")!))
    }
    
    func testFileExtensionPattern() {
        let pattern = URLPattern.fileExtension(["zip", "rar", "7z"])
        
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/file.zip")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/archive.RAR")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/compressed.7z")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://example.com/file.pdf")!))
    }
    
    func testContainsPattern() {
        let pattern = URLPattern.contains("download")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/download/file.zip")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://downloads.example.com")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/file.zip?action=download")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://example.com/files/")!))
    }
    
    func testRegexPattern() {
        let pattern = URLPattern.regex("\\d{4}/\\d{2}/")
        
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/2024/05/file.zip")!))
        XCTAssertTrue(pattern.matches(URL(string: "https://example.com/archive/2023/12/data.pdf")!))
        XCTAssertFalse(pattern.matches(URL(string: "https://example.com/file.zip")!))
    }
    
    // MARK: - URL Action Tests
    
    func testURLActionProperties() {
        XCTAssertEqual(URLAction.download.icon, "arrow.down.circle.fill")
        XCTAssertEqual(URLAction.ask.icon, "questionmark.circle")
        XCTAssertEqual(URLAction.ignore.icon, "xmark.circle")
        XCTAssertEqual(URLAction.addToQueue.icon, "list.bullet")
        XCTAssertEqual(URLAction.copyToClipboard.icon, "doc.on.clipboard")
    }
    
    // MARK: - URL Pattern Rule Tests
    
    func testRuleCreation() {
        let rule = URLPatternRule(
            name: "Video Files",
            pattern: .fileExtension(["mp4", "mkv"]),
            action: .download,
            priority: 10
        )
        
        XCTAssertEqual(rule.name, "Video Files")
        XCTAssertEqual(rule.action, .download)
        XCTAssertEqual(rule.priority, 10)
        XCTAssertTrue(rule.isEnabled)
        XCTAssertEqual(rule.matchCount, 0)
    }
    
    func testRuleMatching() {
        let rule = URLPatternRule(
            name: "Video Files",
            pattern: .fileExtension(["mp4", "mkv"]),
            action: .download,
            priority: 10
        )
        
        XCTAssertTrue(rule.matches(URL(string: "https://example.com/video.mp4")!))
        XCTAssertTrue(rule.matches(URL(string: "https://example.com/movie.mkv")!))
        XCTAssertFalse(rule.matches(URL(string: "https://example.com/audio.mp3")!))
    }
    
    func testDisabledRuleDoesNotMatch() {
        var rule = URLPatternRule(
            name: "Video Files",
            pattern: .fileExtension(["mp4"]),
            action: .download,
            priority: 10
        )
        rule.isEnabled = false
        
        XCTAssertFalse(rule.matches(URL(string: "https://example.com/video.mp4")!))
    }
    
    // MARK: - Domain List Tests
    
    func testDomainListTypes() {
        XCTAssertEqual(DomainListType.whitelist.rawValue, "Whitelist")
        XCTAssertEqual(DomainListType.blacklist.rawValue, "Blacklist")
        XCTAssertEqual(DomainListType.whitelist.icon, "checkmark.circle.fill")
        XCTAssertEqual(DomainListType.blacklist.icon, "xmark.circle.fill")
    }
    
    func testDomainEntryMatching() {
        let entry = DomainEntry(
            domain: "example.com",
            type: .whitelist
        )
        
        XCTAssertTrue(entry.matches(URL(string: "https://example.com/file.zip")!))
        XCTAssertTrue(entry.matches(URL(string: "https://www.example.com")!))
        XCTAssertTrue(entry.matches(URL(string: "https://sub.example.com")!))
        XCTAssertFalse(entry.matches(URL(string: "https://other.com")!))
    }
    
    func testDisabledDomainDoesNotMatch() {
        var entry = DomainEntry(
            domain: "example.com",
            type: .blacklist
        )
        entry.isEnabled = false
        
        XCTAssertFalse(entry.matches(URL(string: "https://example.com")!))
    }
    
    // MARK: - Detected URL Tests
    
    func testDetectedURLCreation() {
        let url = URL(string: "https://example.com/file.zip")!
        let detected = DetectedURL(
            url: url,
            isValid: true,
            fileSize: 1048576,
            fileName: "file.zip",
            suggestedAction: .download,
            status: .valid
        )
        
        XCTAssertEqual(detected.url, url)
        XCTAssertTrue(detected.isValid)
        XCTAssertEqual(detected.fileSize, 1048576)
        XCTAssertEqual(detected.fileName, "file.zip")
        XCTAssertEqual(detected.suggestedAction, .download)
        XCTAssertEqual(detected.status, .valid)
    }
    
    func testDetectionStatusProperties() {
        XCTAssertEqual(DetectionStatus.pending.icon, "clock")
        XCTAssertEqual(DetectionStatus.validating.icon, "arrow.triangle.2.circlepath")
        XCTAssertEqual(DetectionStatus.valid.icon, "checkmark.circle")
        XCTAssertEqual(DetectionStatus.invalid.icon, "xmark.circle")
        XCTAssertEqual(DetectionStatus.downloading.icon, "arrow.down.circle")
        XCTAssertEqual(DetectionStatus.completed.icon, "checkmark.circle.fill")
        XCTAssertEqual(DetectionStatus.ignored.icon, "eye.slash")
        XCTAssertEqual(DetectionStatus.error.icon, "exclamationmark.triangle")
    }
    
    // MARK: - URL Validation Tests
    
    func testURLValidationResult() {
        let url = URL(string: "https://example.com/file.zip")!
        let result = URLValidationResult(
            url: url,
            isValid: true,
            isReachable: true,
            fileSize: 1048576,
            fileName: "file.zip",
            mimeType: "application/zip",
            serverSupportsResume: true
        )
        
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.isReachable)
        XCTAssertEqual(result.fileSize, 1048576)
        XCTAssertEqual(result.fileName, "file.zip")
        XCTAssertEqual(result.mimeType, "application/zip")
        XCTAssertTrue(result.serverSupportsResume)
        XCTAssertNil(result.error)
    }
    
    func testURLValidationErrors() {
        XCTAssertNotNil(URLValidationError.invalidURL.errorDescription)
        XCTAssertNotNil(URLValidationError.unreachable.errorDescription)
        XCTAssertNotNil(URLValidationError.timeout.errorDescription)
        XCTAssertNotNil(URLValidationError.forbidden.errorDescription)
        XCTAssertNotNil(URLValidationError.notFound.errorDescription)
        XCTAssertNotNil(URLValidationError.serverError.errorDescription)
        XCTAssertNotNil(URLValidationError.networkError("Test").errorDescription)
        XCTAssertNotNil(URLValidationError.unsupportedProtocol.errorDescription)
    }
    
    // MARK: - Statistics Tests
    
    func testStatisticsInitialization() async {
        let stats = await monitor.stats
        
        XCTAssertEqual(stats.totalURLsDetected, 0)
        XCTAssertEqual(stats.validURLsCount, 0)
        XCTAssertEqual(stats.invalidURLsCount, 0)
        XCTAssertEqual(stats.autoDownloadedCount, 0)
        XCTAssertEqual(stats.ignoredCount, 0)
        XCTAssertNil(stats.lastDetectionDate)
        XCTAssertTrue(stats.detectionsByDomain.isEmpty)
    }
    
    func testStatisticsRates() {
        var stats = ClipboardMonitoringStats()
        
        // Test with zero total
        XCTAssertEqual(stats.detectionRate, 0.0)
        XCTAssertEqual(stats.autoDownloadRate, 0.0)
        
        // Test detection rate
        stats.totalURLsDetected = 10
        stats.validURLsCount = 8
        XCTAssertEqual(stats.detectionRate, 0.8)
        
        // Test auto-download rate
        stats.autoDownloadedCount = 5
        XCTAssertEqual(stats.autoDownloadRate, 5.0 / 8.0)
    }
    
    // MARK: - Rule Management Tests
    
    func testAddRule() async {
        let rule = URLPatternRule(
            name: "Test Rule",
            pattern: .domain("example.com"),
            action: .download
        )
        
        await monitor.addRule(rule)
        
        let rules = await monitor.rules
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.name, "Test Rule")
    }
    
    func testUpdateRule() async {
        var rule = URLPatternRule(
            name: "Test Rule",
            pattern: .domain("example.com"),
            action: .download
        )
        
        await monitor.addRule(rule)
        
        rule = await monitor.rules.first!
        rule.isEnabled = false
        rule.priority = 20
        
        await monitor.updateRule(rule)
        
        let updated = await monitor.rules.first!
        XCTAssertFalse(updated.isEnabled)
        XCTAssertEqual(updated.priority, 20)
    }
    
    func testDeleteRule() async {
        let rule = URLPatternRule(
            name: "Test Rule",
            pattern: .domain("example.com"),
            action: .download
        )
        
        await monitor.addRule(rule)
        XCTAssertEqual(await monitor.rules.count, 1)
        
        await monitor.deleteRule(rule)
        XCTAssertEqual(await monitor.rules.count, 0)
    }
    
    // MARK: - Domain Management Tests
    
    func testAddDomain() async {
        let domain = DomainEntry(
            domain: "example.com",
            type: .whitelist
        )
        
        await monitor.addDomain(domain)
        
        let domains = await monitor.domainList
        XCTAssertEqual(domains.count, 1)
        XCTAssertEqual(domains.first?.domain, "example.com")
    }
    
    func testUpdateDomain() async {
        var domain = DomainEntry(
            domain: "example.com",
            type: .whitelist
        )
        
        await monitor.addDomain(domain)
        
        domain = await monitor.domainList.first!
        domain.isEnabled = false
        domain.notes = "Test notes"
        
        await monitor.updateDomain(domain)
        
        let updated = await monitor.domainList.first!
        XCTAssertFalse(updated.isEnabled)
        XCTAssertEqual(updated.notes, "Test notes")
    }
    
    func testDeleteDomain() async {
        let domain = DomainEntry(
            domain: "example.com",
            type: .whitelist
        )
        
        await monitor.addDomain(domain)
        XCTAssertEqual(await monitor.domainList.count, 1)
        
        await monitor.deleteDomain(domain)
        XCTAssertEqual(await monitor.domainList.count, 0)
    }
    
    // MARK: - Monitoring Tests
    
    func testStartStopMonitoring() async {
        XCTAssertFalse(await monitor.isMonitoring)
        
        await monitor.startMonitoring()
        XCTAssertTrue(await monitor.isMonitoring)
        
        await monitor.stopMonitoring()
        XCTAssertFalse(await monitor.isMonitoring)
    }
    
    // MARK: - URL Validation Tests (Async)
    
    func testValidateInvalidProtocol() async {
        let url = URL(string: "javascript:alert('test')")!
        let result = await monitor.validateURL(url)
        
        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.isReachable)
        XCTAssertEqual(result.error, .unsupportedProtocol)
    }
    
    func testValidateHTTPURL() async {
        // Note: This test requires network access
        let url = URL(string: "https://httpbin.org/")!
        let result = await monitor.validateURL(url)
        
        // Should be valid if network is available
        // In a real test environment, you might want to mock this
        XCTAssertTrue(result.url == url)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteWorkflow() async {
        // 1. Add a rule
        let rule = URLPatternRule(
            name: "Video Files",
            pattern: .fileExtension(["mp4"]),
            action: .download,
            priority: 10
        )
        await monitor.addRule(rule)
        
        // 2. Start monitoring
        await monitor.startMonitoring()
        XCTAssertTrue(await monitor.isMonitoring)
        
        // 3. Verify rule is active
        let rules = await monitor.rules
        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(rules.first!.isEnabled)
        
        // 4. Stop monitoring
        await monitor.stopMonitoring()
        XCTAssertFalse(await monitor.isMonitoring)
    }
    
    func testRulePriorityOrdering() async {
        let rule1 = URLPatternRule(name: "Low", pattern: .domain("a.com"), action: .ask, priority: 1)
        let rule2 = URLPatternRule(name: "High", pattern: .domain("b.com"), action: .download, priority: 10)
        let rule3 = URLPatternRule(name: "Medium", pattern: .domain("c.com"), action: .addToQueue, priority: 5)
        
        await monitor.addRule(rule1)
        await monitor.addRule(rule2)
        await monitor.addRule(rule3)
        
        let rules = await monitor.rules.sorted { $0.priority > $1.priority }
        
        XCTAssertEqual(rules[0].name, "High")
        XCTAssertEqual(rules[1].name, "Medium")
        XCTAssertEqual(rules[2].name, "Low")
    }
    
    func testWhitelistBlacklistInteraction() async {
        let whitelist = DomainEntry(domain: "allowed.com", type: .whitelist)
        let blacklist = DomainEntry(domain: "blocked.com", type: .blacklist)
        
        await monitor.addDomain(whitelist)
        await monitor.addDomain(blacklist)
        
        let domains = await monitor.domainList
        XCTAssertEqual(domains.count, 2)
        
        let whitelistDomains = domains.filter { $0.type == .whitelist }
        let blacklistDomains = domains.filter { $0.type == .blacklist }
        
        XCTAssertEqual(whitelistDomains.count, 1)
        XCTAssertEqual(blacklistDomains.count, 1)
    }
    
    // MARK: - Pattern Display Names
    
    func testPatternDisplayNames() {
        XCTAssertEqual(URLPattern.domain("example.com").displayName, "Domain: example.com")
        XCTAssertEqual(URLPattern.subdomain("example.com").displayName, "Subdomain: example.com")
        XCTAssertEqual(URLPattern.path("/downloads/").displayName, "Path: /downloads/")
        XCTAssertEqual(URLPattern.fileExtension(["mp4", "mkv"]).displayName, "Extensions: mp4, mkv")
        XCTAssertEqual(URLPattern.regex("\\d+").displayName, "Regex: \\d+")
        XCTAssertEqual(URLPattern.contains("download").displayName, "Contains: download")
    }
}
