//
//  ClipboardMonitor.swift
//  Download Manager for Mac - Feature #17: URL Monitoring & Clipboard
//
//  Created on February 17, 2026
//

import Foundation
import AppKit
import Combine

/// Manager for monitoring clipboard and handling detected URLs
@MainActor
public class ClipboardMonitor: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = ClipboardMonitor()
    
    // MARK: - Published Properties
    
    @Published public var settings: ClipboardMonitoringSettings
    @Published public var rules: [URLPatternRule]
    @Published public var domainList: [DomainEntry]
    @Published public var detectedURLs: [DetectedURL]
    @Published public var stats: ClipboardMonitoringStats
    @Published public var isMonitoring: Bool
    
    // MARK: - Private Properties
    
    private var monitoringTimer: Timer?
    private var lastChangeCount: Int
    private let pasteboard: NSPasteboard
    private var processedURLs: Set<String>
    private let urlDetector: URLDetector
    
    // URL validation session
    private let validationSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config)
    }()
    
    // MARK: - Initialization
    
    private init() {
        self.settings = ClipboardMonitoringSettings()
        self.rules = []
        self.domainList = []
        self.detectedURLs = []
        self.stats = ClipboardMonitoringStats()
        self.isMonitoring = false
        self.lastChangeCount = 0
        self.pasteboard = NSPasteboard.general
        self.processedURLs = Set()
        self.urlDetector = URLDetector()
        
        loadSettings()
        loadRules()
        loadDomainList()
        loadStats()
    }
    
    // MARK: - Monitoring Control
    
    /// Start monitoring clipboard
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastChangeCount = pasteboard.changeCount
        
        monitoringTimer = Timer.scheduledTimer(
            withTimeInterval: settings.pollingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkClipboard()
            }
        }
        
        print("📋 Clipboard monitoring started")
    }
    
    /// Stop monitoring clipboard
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        print("📋 Clipboard monitoring stopped")
    }
    
    /// Check clipboard for new content
    private func checkClipboard() async {
        let currentChangeCount = pasteboard.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        guard let string = pasteboard.string(forType: .string) else { return }
        
        // Detect URLs in clipboard content
        let urls = urlDetector.detectURLs(in: string)
        
        for url in urls {
            await processDetectedURL(url)
        }
    }
    
    // MARK: - URL Processing
    
    /// Process a detected URL
    private func processDetectedURL(_ url: URL) async {
        // Skip if already processed
        let urlString = url.absoluteString
        guard !processedURLs.contains(urlString) else { return }
        processedURLs.insert(urlString)
        
        // Check domain list
        if let domainEntry = domainList.first(where: { $0.matches(url) }) {
            if domainEntry.type == .blacklist {
                print("⛔️ URL blocked by blacklist: \(url.absoluteString)")
                stats.ignoredCount += 1
                stats.totalURLsDetected += 1
                saveStats()
                return
            }
        }
        
        // Match against rules
        let matchedRules = rules
            .filter { $0.matches(url) }
            .sorted { $0.priority > $1.priority }
        
        // Determine action
        let action = matchedRules.first?.action ?? (settings.autoDownload ? .download : .ask)
        
        // Create detected URL
        var detected = DetectedURL(
            url: url,
            matchedRules: matchedRules,
            suggestedAction: action,
            status: .validating
        )
        
        // Add to detected list
        detectedURLs.insert(detected, at: 0)
        
        // Update stats
        stats.totalURLsDetected += 1
        stats.lastDetectionDate = Date()
        if let host = url.host {
            stats.detectionsByDomain[host, default: 0] += 1
        }
        
        // Validate URL
        let validation = await validateURL(url)
        detected.isValid = validation.isValid
        detected.fileSize = validation.fileSize
        detected.fileName = validation.fileName
        detected.mimeType = validation.mimeType
        detected.status = validation.isValid ? .valid : .invalid
        
        if let index = detectedURLs.firstIndex(where: { $0.id == detected.id }) {
            detectedURLs[index] = detected
        }
        
        if validation.isValid {
            stats.validURLsCount += 1
        } else {
            stats.invalidURLsCount += 1
        }
        
        saveStats()
        
        // Perform action
        await performAction(action, for: detected)
    }
    
    /// Validate a URL
    public func validateURL(_ url: URL) async -> ClipboardURLValidationResult {
        // Basic validation
        guard ["http", "https", "ftp"].contains(url.scheme?.lowercased()) else {
            return ClipboardURLValidationResult(
                url: url,
                isValid: false,
                isReachable: false,
                error: .unsupportedProtocol
            )
        }
        
        // HEAD request to check availability
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        
        do {
            let (_, response) = try await validationSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return ClipboardURLValidationResult(
                    url: url,
                    isValid: false,
                    isReachable: false,
                    error: .networkError("Invalid response")
                )
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                let fileSize = httpResponse.expectedContentLength > 0 ? httpResponse.expectedContentLength : nil
                let fileName = httpResponse.suggestedFilename ?? url.lastPathComponent
                let mimeType = httpResponse.mimeType
                let supportsResume = httpResponse.allHeaderFields["Accept-Ranges"] as? String == "bytes"
                
                return ClipboardURLValidationResult(
                    url: url,
                    isValid: true,
                    isReachable: true,
                    fileSize: fileSize,
                    fileName: fileName,
                    mimeType: mimeType,
                    serverSupportsResume: supportsResume
                )
                
            case 403:
                return ClipboardURLValidationResult(url: url, isValid: false, isReachable: false, error: .forbidden)
            case 404:
                return ClipboardURLValidationResult(url: url, isValid: false, isReachable: false, error: .notFound)
            case 500...599:
                return ClipboardURLValidationResult(url: url, isValid: false, isReachable: false, error: .serverError)
            default:
                return ClipboardURLValidationResult(
                    url: url,
                    isValid: false,
                    isReachable: false,
                    error: .networkError("Status code: \(httpResponse.statusCode)")
                )
            }
            
        } catch {
            return ClipboardURLValidationResult(
                url: url,
                isValid: false,
                isReachable: false,
                error: .networkError(error.localizedDescription)
            )
        }
    }
    
    /// Perform action for detected URL
    private func performAction(_ action: URLAction, for detected: DetectedURL) async {
        guard detected.isValid else { return }
        
        switch action {
        case .download:
            if settings.showConfirmation {
                // Show confirmation notification
                showNotification(for: detected)
            } else {
                // Auto-download
                startDownload(for: detected)
            }
            
        case .ask:
            // Show confirmation dialog
            showNotification(for: detected)
            
        case .ignore:
            // Do nothing
            if let index = detectedURLs.firstIndex(where: { $0.id == detected.id }) {
                detectedURLs[index].status = .ignored
            }
            stats.ignoredCount += 1
            saveStats()
            
        case .addToQueue:
            // Add to download queue without starting
            addToQueue(detected)
            
        case .copyToClipboard:
            // Already in clipboard, do nothing
            break
        }
    }
    
    // MARK: - Actions
    
    /// Start download for detected URL
    public func startDownload(for detected: DetectedURL) {
        guard detected.isValid else { return }
        
        // Update status
        if let index = detectedURLs.firstIndex(where: { $0.id == detected.id }) {
            detectedURLs[index].status = .downloading
        }
        
        stats.autoDownloadedCount += 1
        saveStats()
        
        // TODO: Integrate with DownloadManager
        print("⬇️ Starting download: \(detected.url.absoluteString)")
        
        if settings.soundEnabled {
            NSSound.beep()
        }
    }
    
    /// Add detected URL to queue
    public func addToQueue(_ detected: DetectedURL) {
        guard detected.isValid else { return }
        
        // TODO: Integrate with QueueManager
        print("➕ Added to queue: \(detected.url.absoluteString)")
        
        if let index = detectedURLs.firstIndex(where: { $0.id == detected.id }) {
            detectedURLs[index].status = .pending
        }
    }
    
    /// Show notification for detected URL
    private func showNotification(for detected: DetectedURL) {
        guard settings.notificationEnabled else { return }
        
        let notification = NSUserNotification()
        notification.title = "URL Detected"
        notification.informativeText = detected.fileName ?? detected.url.lastPathComponent
        notification.subtitle = "Click to download"
        notification.soundName = settings.soundEnabled ? NSUserNotificationDefaultSoundName : nil
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // MARK: - Rule Management
    
    /// Add a new rule
    public func addRule(_ rule: URLPatternRule) {
        rules.append(rule)
        saveRules()
    }
    
    /// Update existing rule
    public func updateRule(_ rule: URLPatternRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            saveRules()
        }
    }
    
    /// Delete rule
    public func deleteRule(_ rule: URLPatternRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }
    
    /// Delete rules at indices
    public func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        saveRules()
    }
    
    // MARK: - Domain List Management
    
    /// Add domain to list
    public func addDomain(_ entry: DomainEntry) {
        domainList.append(entry)
        saveDomainList()
    }
    
    /// Update domain entry
    public func updateDomain(_ entry: DomainEntry) {
        if let index = domainList.firstIndex(where: { $0.id == entry.id }) {
            domainList[index] = entry
            saveDomainList()
        }
    }
    
    /// Delete domain entry
    public func deleteDomain(_ entry: DomainEntry) {
        domainList.removeAll { $0.id == entry.id }
        saveDomainList()
    }
    
    /// Delete domains at indices
    public func deleteDomains(at offsets: IndexSet) {
        domainList.remove(atOffsets: offsets)
        saveDomainList()
    }
    
    // MARK: - Detected URLs Management
    
    /// Clear detected URLs
    public func clearDetectedURLs() {
        detectedURLs.removeAll()
    }
    
    /// Delete detected URL
    public func deleteDetectedURL(_ detected: DetectedURL) {
        detectedURLs.removeAll { $0.id == detected.id }
        processedURLs.remove(detected.url.absoluteString)
    }
    
    /// Clear statistics
    public func clearStats() {
        stats = ClipboardMonitoringStats()
        saveStats()
    }
    
    // MARK: - Settings Management
    
    /// Update settings
    public func updateSettings(_ newSettings: ClipboardMonitoringSettings) {
        settings = newSettings
        saveSettings()
        
        // Restart monitoring if interval changed
        if isMonitoring {
            stopMonitoring()
            startMonitoring()
        }
    }
    
    // MARK: - Persistence
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "ClipboardMonitoringSettings"),
           let loaded = try? JSONDecoder().decode(ClipboardMonitoringSettings.self, from: data) {
            settings = loaded
        }
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "ClipboardMonitoringSettings")
        }
    }
    
    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: "URLPatternRules"),
           let loaded = try? JSONDecoder().decode([URLPatternRule].self, from: data) {
            rules = loaded
        } else {
            // Create default rules
            rules = createDefaultRules()
            saveRules()
        }
    }
    
    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: "URLPatternRules")
        }
    }
    
    private func loadDomainList() {
        if let data = UserDefaults.standard.data(forKey: "DomainList"),
           let loaded = try? JSONDecoder().decode([DomainEntry].self, from: data) {
            domainList = loaded
        }
    }
    
    private func saveDomainList() {
        if let data = try? JSONEncoder().encode(domainList) {
            UserDefaults.standard.set(data, forKey: "DomainList")
        }
    }
    
    private func loadStats() {
        if let data = UserDefaults.standard.data(forKey: "ClipboardMonitoringStats"),
           let loaded = try? JSONDecoder().decode(ClipboardMonitoringStats.self, from: data) {
            stats = loaded
        }
    }
    
    private func saveStats() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: "ClipboardMonitoringStats")
        }
    }
    
    // MARK: - Default Rules
    
    private func createDefaultRules() -> [URLPatternRule] {
        return [
            URLPatternRule(
                name: "Video Files",
                pattern: .fileExtension(["mp4", "mkv", "avi", "mov", "wmv", "flv", "webm"]),
                action: .download,
                priority: 10
            ),
            URLPatternRule(
                name: "Audio Files",
                pattern: .fileExtension(["mp3", "m4a", "wav", "flac", "aac", "ogg"]),
                action: .download,
                priority: 9
            ),
            URLPatternRule(
                name: "Archives",
                pattern: .fileExtension(["zip", "rar", "7z", "tar", "gz", "bz2"]),
                action: .download,
                priority: 8
            ),
            URLPatternRule(
                name: "Documents",
                pattern: .fileExtension(["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx"]),
                action: .ask,
                priority: 7
            ),
            URLPatternRule(
                name: "Images",
                pattern: .fileExtension(["jpg", "jpeg", "png", "gif", "bmp", "svg", "webp"]),
                action: .ask,
                priority: 5
            ),
            URLPatternRule(
                name: "Software",
                pattern: .fileExtension(["dmg", "pkg", "app", "exe", "msi"]),
                action: .ask,
                priority: 6
            )
        ]
    }
}

// MARK: - URL Detector

/// Helper class for detecting URLs in text
private class URLDetector {
    
    private let urlDetector: NSDataDetector?
    
    init() {
        self.urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }
    
    /// Detect URLs in text
    func detectURLs(in text: String) -> [URL] {
        guard let detector = urlDetector else { return [] }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)
        
        var urls: [URL] = []
        
        for match in matches {
            if let url = match.url {
                // Filter out non-downloadable URLs
                if isDownloadableURL(url) {
                    urls.append(url)
                }
            }
        }
        
        return urls
    }
    
    /// Check if URL is likely downloadable
    private func isDownloadableURL(_ url: URL) -> Bool {
        // Must have HTTP/HTTPS/FTP scheme
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "ftp"].contains(scheme) else {
            return false
        }
        
        // Must have a host
        guard url.host != nil else { return false }
        
        // Check for common non-downloadable patterns
        let urlString = url.absoluteString.lowercased()
        
        // Skip common tracking/analytics URLs
        let skipPatterns = [
            "google-analytics.com",
            "doubleclick.net",
            "analytics",
            "tracking",
            "/track/",
            "/pixel/",
            ".js",
            ".css"
        ]
        
        for pattern in skipPatterns {
            if urlString.contains(pattern) {
                return false
            }
        }
        
        // Check for file extension (strong signal)
        let downloadableExtensions = [
            "mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v",
            "mp3", "m4a", "wav", "flac", "aac", "ogg", "wma",
            "zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "pkg",
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "tiff",
            "exe", "msi", "app", "apk", "iso", "img"
        ]
        
        let pathExtension = url.pathExtension.lowercased()
        if downloadableExtensions.contains(pathExtension) {
            return true
        }
        
        // Check for download indicators in URL
        let downloadIndicators = [
            "/download/",
            "/downloads/",
            "/file/",
            "/files/",
            "/get/",
            "/attachment/"
        ]
        
        for indicator in downloadIndicators {
            if urlString.contains(indicator) {
                return true
            }
        }
        
        // Default to true for URLs with path (potential download)
        return !url.path.isEmpty && url.path != "/"
    }
}
