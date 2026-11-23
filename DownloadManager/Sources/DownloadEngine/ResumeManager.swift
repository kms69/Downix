//
//  ResumeManager.swift
//  Download Manager for Mac - Feature #6: Resume Manager
//
//  Created on February 15, 2026
//

import Foundation
import Combine

/// Manages resume capability, auto-retry, and error recovery
class ResumeManager: ObservableObject {
    
    static let shared = ResumeManager()
    
    @Published var settings: ResumeSettings
    @Published var statistics: DownloadStatistics
    @Published var activeRetries: [UUID: RetryAttempt] = [:]
    
    private var resumeDataStore: [UUID: ResumeData] = [:]
    private var retryTimers: [UUID: Timer] = [:]
    private var retryHistory: [UUID: [RetryAttempt]] = [:]
    private let fileManager = FileManager.default
    private let resumeDataDirectory: URL
    
    private init() {
        self.settings = ResumeSettings()
        self.statistics = DownloadStatistics()
        
        // Set up resume data directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.resumeDataDirectory = appSupport.appendingPathComponent("DownloadManager/ResumeData", isDirectory: true)
        
        try? fileManager.createDirectory(at: resumeDataDirectory, withIntermediateDirectories: true)
        
        loadStatistics()
        loadResumeData()
        
        if settings.enableAutoResume {
            autoResumeInterruptedDownloads()
        }
    }
    
    // MARK: - Settings Management
    
    func updateSettings(_ newSettings: ResumeSettings) {
        DispatchQueue.main.async {
            self.settings = newSettings
        }
        saveSettings()
    }
    
    // MARK: - Resume Data Management
    
    func saveResumeData(_ data: ResumeData, for taskId: UUID) {
        guard settings.saveResumeData else { return }
        
        resumeDataStore[taskId] = data
        persistResumeData(data, for: taskId)
    }
    
    func getResumeData(for taskId: UUID) -> ResumeData? {
        return resumeDataStore[taskId]
    }
    
    func deleteResumeData(for taskId: UUID) {
        resumeDataStore.removeValue(forKey: taskId)
        
        let fileURL = resumeDataDirectory.appendingPathComponent("\(taskId.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
    }
    
    func hasResumeData(for taskId: UUID) -> Bool {
        return resumeDataStore[taskId] != nil
    }
    
    // MARK: - Retry Management
    
    func shouldRetry(task: DownloadTask, error: Error) -> Bool {
        let attempts = task.retryCount
        return settings.retryPolicy.shouldRetry(error: error, attempt: attempts)
    }
    
    func scheduleRetry(task: DownloadTask, error: Error, completion: @escaping () -> Void) {
        let attemptNumber = task.retryCount
        let delay = settings.retryPolicy.delayForAttempt(attemptNumber)
        
        let attempt = RetryAttempt(
            attemptNumber: attemptNumber + 1,
            error: error.localizedDescription,
            delayBeforeRetry: delay
        )
        
        // Record retry attempt
        DispatchQueue.main.async {
            self.activeRetries[task.id] = attempt
            
            if self.retryHistory[task.id] == nil {
                self.retryHistory[task.id] = []
            }
            self.retryHistory[task.id]?.append(attempt)
        }
        
        print("📡 Scheduling retry \(attemptNumber + 1)/\(settings.retryPolicy.maxRetries) in \(delay)s for task: \(task.filename)")
        
        // Schedule retry
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.activeRetries.removeValue(forKey: task.id)
                task.retryCount += 1
                completion()
            }
        }
        
        retryTimers[task.id] = timer
    }
    
    func cancelRetry(for taskId: UUID) {
        if let timer = retryTimers[taskId] {
            timer.invalidate()
            retryTimers.removeValue(forKey: taskId)
        }
        
        activeRetries.removeValue(forKey: taskId)
    }
    
    func getRetryHistory(for taskId: UUID) -> [RetryAttempt] {
        return retryHistory[taskId] ?? []
    }
    
    // MARK: - Resume Strategy
    
    func determineResumeAction(for task: DownloadTask, error: Error?) -> ResumeAction {
        // Check if we have resume data
        guard let resumeData = getResumeData(for: task.id) else {
            return .restart
        }
        
        // Check if resume is supported
        guard resumeData.canResume else {
            return settings.resumeStrategy == .resumeOnly ? .fail : .restart
        }
        
        // Apply strategy
        switch settings.resumeStrategy {
        case .automatic:
            return .resume(resumeData)
        case .resumeOnly:
            return .resume(resumeData)
        case .restartOnly:
            return .restart
        case .askUser:
            return .askUser(resumeData)
        }
    }
    
    enum ResumeAction {
        case resume(ResumeData)
        case restart
        case askUser(ResumeData)
        case fail
    }
    
    // MARK: - Server Capability Detection
    
    func checkResumeSupport(for url: URL) async throws -> ServerCapabilities {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = settings.connectionTimeout
        
        let (_, response) = try await ProxySession.makeSession().data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return ServerCapabilities()
        }
        
        let acceptsRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges") != "none"
        let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }
        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
        let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
        
        return ServerCapabilities(
            supportsRangeRequests: acceptsRanges,
            contentLength: contentLength,
            etag: etag,
            lastModified: lastModified
        )
    }
    
    struct ServerCapabilities {
        let supportsRangeRequests: Bool
        let contentLength: Int64?
        let etag: String?
        let lastModified: String?
        
        init(
            supportsRangeRequests: Bool = false,
            contentLength: Int64? = nil,
            etag: String? = nil,
            lastModified: String? = nil
        ) {
            self.supportsRangeRequests = supportsRangeRequests
            self.contentLength = contentLength
            self.etag = etag
            self.lastModified = lastModified
        }
    }
    
    // MARK: - Error Recovery
    
    func handleDownloadError(task: DownloadTask, error: Error) async {
        print("❌ Download error for \(task.filename): \(error.localizedDescription)")
        
        // Check if should retry
        guard shouldRetry(task: task, error: error) else {
            print("🛑 Max retries reached or error not retryable")
            recordFailure(task: task)
            return
        }
        
        // Schedule retry
        scheduleRetry(task: task, error: error) {
            Task {
                await self.attemptRecovery(task: task)
            }
        }
    }
    
    private func attemptRecovery(task: DownloadTask) async {
        print("🔄 Attempting recovery for \(task.filename)")
        
        let action = determineResumeAction(for: task, error: nil)
        
        switch action {
        case .resume(let resumeData):
            print("▶️ Resuming from \(resumeData.downloadedBytes) bytes")
            await resumeDownload(task: task, with: resumeData)
            
        case .restart:
            print("🔁 Restarting download from beginning")
            await restartDownload(task: task)
            
        case .askUser:
            print("❓ User intervention required")
            // In a real implementation, this would show a dialog
            await resumeDownload(task: task, with: getResumeData(for: task.id)!)
            
        case .fail:
            print("💥 Recovery failed - resume not supported")
            recordFailure(task: task)
        }
    }
    
    private func resumeDownload(task: DownloadTask, with resumeData: ResumeData) async {
        // Update statistics
        DispatchQueue.main.async {
            self.statistics.recordRestart(bytesReused: resumeData.downloadedBytes)
        }
        
        // Trigger download resume in DownloadManager
        await DownloadManager.shared.resumeDownload(task)
    }
    
    private func restartDownload(task: DownloadTask) async {
        // Delete partial file
        if let resumeData = getResumeData(for: task.id) {
            try? fileManager.removeItem(at: resumeData.partialFilePath)
        }
        
        // Clear resume data
        deleteResumeData(for: task.id)
        
        // Reset task
        task.downloadedBytes = 0
        task.progress = 0
        task.retryCount += 1
        
        // Restart download
        await DownloadManager.shared.startDownload(task)
    }
    
    // MARK: - Statistics
    
    func recordSuccess(task: DownloadTask, wasResumed: Bool) {
        statistics.recordSuccess(
            wasResumed: wasResumed,
            retries: task.retryCount,
            bytesDownloaded: task.totalBytes
        )
        
        deleteResumeData(for: task.id)
        retryHistory.removeValue(forKey: task.id)
        saveStatistics()
    }
    
    func recordFailure(task: DownloadTask) {
        statistics.recordFailure(retries: task.retryCount)
        
        if settings.cleanupFailedDownloads {
            deleteResumeData(for: task.id)
        }
        
        saveStatistics()
    }
    
    // MARK: - Auto-Resume
    
    private func autoResumeInterruptedDownloads() {
        print("🔄 Auto-resuming interrupted downloads...")
        
        // Load all resume data files
        guard let files = try? fileManager.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let resumeData = try? JSONDecoder().decode(ResumeData.self, from: data) else {
                continue
            }
            
            // Check if download is old enough to clean up
            if settings.cleanupFailedDownloads {
                let daysSinceUpdate = Calendar.current.dateComponents(
                    [.day],
                    from: resumeData.lastUpdated,
                    to: Date()
                ).day ?? 0
                
                if daysSinceUpdate > settings.cleanupAfterDays {
                    try? fileManager.removeItem(at: file)
                    continue
                }
            }
            
            // Create task from resume data and add to download manager
            let task = DownloadTask(
                url: resumeData.url,
                destinationPath: resumeData.destinationPath
            )
            task.downloadedBytes = resumeData.downloadedBytes
            task.totalBytes = resumeData.totalBytes
            task.state = .paused
            
            // Store resume data
            resumeDataStore[task.id] = resumeData
            
            print("📥 Found interrupted download: \(resumeData.url.lastPathComponent) (\(resumeData.progressPercentage.formatted(.number.precision(.fractionLength(1))))%)")
        }
    }
    
    // MARK: - Persistence
    
    private func persistResumeData(_ data: ResumeData, for taskId: UUID) {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(taskId.uuidString).json")
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            try jsonData.write(to: fileURL)
        } catch {
            print("Failed to save resume data: \(error)")
        }
    }
    
    private func loadResumeData() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let resumeData = try? JSONDecoder().decode(ResumeData.self, from: data),
                  let taskId = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                continue
            }
            
            resumeDataStore[taskId] = resumeData
        }
    }
    
    private func saveSettings() {
        let settingsURL = resumeDataDirectory.appendingPathComponent("settings.json")
        
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsURL)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
    
    private func saveStatistics() {
        let statsURL = resumeDataDirectory.appendingPathComponent("statistics.json")
        
        do {
            let data = try JSONEncoder().encode(statistics)
            try data.write(to: statsURL)
        } catch {
            print("Failed to save statistics: \(error)")
        }
    }
    
    private func loadStatistics() {
        let statsURL = resumeDataDirectory.appendingPathComponent("statistics.json")
        
        guard let data = try? Data(contentsOf: statsURL),
              let stats = try? JSONDecoder().decode(DownloadStatistics.self, from: data) else {
            return
        }
        
        statistics = stats
    }
    
    // MARK: - Cleanup
    
    func cleanupOldResumeData() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: resumeDataDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        
        let calendar = Calendar.current
        let now = Date()
        
        for file in files where file.pathExtension == "json" {
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                  let modDate = attributes[.modificationDate] as? Date else {
                continue
            }
            
            let daysSinceModification = calendar.dateComponents([.day], from: modDate, to: now).day ?? 0
            
            if daysSinceModification > settings.cleanupAfterDays {
                try? fileManager.removeItem(at: file)
                print("🗑️ Cleaned up old resume data: \(file.lastPathComponent)")
            }
        }
    }
}
