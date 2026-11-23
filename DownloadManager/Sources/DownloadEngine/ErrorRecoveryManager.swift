//
//  ErrorRecoveryManager.swift
//  Download Manager
//
//  Feature #22: Advanced Error Recovery
//  Created on February 17, 2026
//

import Foundation
import Combine
import Network

/// Manager for advanced error recovery and retry logic
@MainActor
public class ErrorRecoveryManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = ErrorRecoveryManager()
    
    // MARK: - Published Properties
    
    @Published public var configuration: RecoveryConfiguration
    @Published public var statistics: RecoveryStatistics
    @Published public var activeRecoveries: [UUID: RecoveryAttempt] // Download task ID -> current attempt
    @Published public var recoveryHistory: [RecoveryResult]
    @Published public var downloadHealth: [UUID: DownloadHealth] // Download task ID -> health
    @Published public var currentConnectionType: ConnectionType
    @Published public var isRecovering: Bool
    
    // MARK: - Private Properties
    
    private let networkMonitor: NWPathMonitor
    private var monitorQueue = DispatchQueue(label: "com.downloadmanager.networkmonitor")
    private var recoveryTimers: [UUID: Timer] = [:]
    private var networkHistory: [NetworkChangeEvent] = []
    
    // UserDefaults keys
    private let configKey = "com.downloadmanager.errorRecoveryConfig"
    private let statsKey = "com.downloadmanager.errorRecoveryStats"
    private let historyKey = "com.downloadmanager.errorRecoveryHistory"
    
    // MARK: - Initialization
    
    private init() {
        self.configuration = RecoveryConfiguration()
        self.statistics = RecoveryStatistics()
        self.activeRecoveries = [:]
        self.recoveryHistory = []
        self.downloadHealth = [:]
        self.currentConnectionType = .unknown
        self.isRecovering = false
        self.networkMonitor = NWPathMonitor()
        
        loadConfiguration()
        loadStatistics()
        loadHistory()
        startNetworkMonitoring()
    }
    
    // MARK: - Configuration Management
    
    public func updateConfiguration(_ config: RecoveryConfiguration) {
        configuration = config
        saveConfiguration()
    }
    
    public func resetConfiguration() {
        configuration = RecoveryConfiguration()
        saveConfiguration()
    }
    
    private func saveConfiguration() {
        if let encoded = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(encoded, forKey: configKey)
        }
    }
    
    private func loadConfiguration() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(RecoveryConfiguration.self, from: data) {
            configuration = decoded
        }
    }
    
    // MARK: - Statistics Management
    
    public func resetStatistics() {
        statistics.reset()
        saveStatistics()
    }
    
    private func saveStatistics() {
        if let encoded = try? JSONEncoder().encode(statistics) {
            UserDefaults.standard.set(encoded, forKey: statsKey)
        }
    }
    
    private func loadStatistics() {
        if let data = UserDefaults.standard.data(forKey: statsKey),
           let decoded = try? JSONDecoder().decode(RecoveryStatistics.self, from: data) {
            statistics = decoded
        }
    }
    
    private func updateStatistics(
        error: DownloadErrorType,
        action: RecoveryAction,
        wasSuccessful: Bool,
        delay: TimeInterval
    ) {
        statistics.totalErrors += 1
        statistics.totalRecoveryAttempts += 1
        
        if wasSuccessful {
            statistics.successfulRecoveries += 1
        } else {
            statistics.failedRecoveries += 1
        }
        
        statistics.totalDelayTime += delay
        statistics.errorsByType[error, default: 0] += 1
        statistics.actionsByType[action, default: 0] += 1
        statistics.lastRecoveryDate = Date()
        
        if action == .tryMirror {
            statistics.mirrorFallbacksUsed += 1
        }
        
        if action == .resumePartial {
            if wasSuccessful {
                statistics.partialRecoveriesSuccessful += 1
            }
        }
        
        saveStatistics()
    }
    
    // MARK: - History Management
    
    public func addToHistory(_ result: RecoveryResult) {
        recoveryHistory.insert(result, at: 0)
        
        // Limit history size
        if recoveryHistory.count > configuration.maxHistoryEntries {
            recoveryHistory = Array(recoveryHistory.prefix(configuration.maxHistoryEntries))
        }
        
        saveHistory()
    }
    
    public func clearHistory() {
        recoveryHistory.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(recoveryHistory) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([RecoveryResult].self, from: data) {
            recoveryHistory = decoded
        }
    }
    
    // MARK: - Network Monitoring
    
    private func startNetworkMonitoring() {
        guard configuration.enableNetworkChangeDetection else { return }
        
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            Task { @MainActor in
                let previousType = self.currentConnectionType
                let newType = self.detectConnectionType(from: path)
                
                if previousType != newType {
                    self.currentConnectionType = newType
                    await self.handleNetworkChange(from: previousType, to: newType)
                }
            }
        }
        
        networkMonitor.start(queue: monitorQueue)
    }
    
    private func detectConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.status == .satisfied {
            return .unknown
        } else {
            return .unknown
        }
    }
    
    private func handleNetworkChange(from previous: ConnectionType, to current: ConnectionType) async {
        let affectedDownloads = Array(activeRecoveries.keys)
        
        let event = NetworkChangeEvent(
            previousNetwork: previous,
            currentNetwork: current,
            affectedDownloads: affectedDownloads
        )
        
        networkHistory.append(event)
        statistics.networkChangesDetected += 1
        saveStatistics()
        
        // If network improved, retry failed downloads
        if event.isImprovement {
            for downloadId in affectedDownloads {
                // In real implementation, would trigger retry via DownloadManager
                print("Network improved: \(previous.displayName) -> \(current.displayName), retrying download \(downloadId)")
            }
        }
    }
    
    // MARK: - Download Health Monitoring
    
    public func updateDownloadHealth(
        downloadId: UUID,
        errorOccurred: Bool = false,
        errorType: DownloadErrorType? = nil,
        currentSpeed: Double = 0,
        connections: Int = 1
    ) {
        var health = downloadHealth[downloadId] ?? DownloadHealth(
            downloadTaskId: downloadId,
            currentConnections: connections
        )
        
        if errorOccurred, let errorType = errorType {
            health.errorCount += 1
            health.lastErrorType = errorType
            health.lastErrorTime = Date()
            
            // Update status based on error count
            if health.errorCount >= 5 {
                health.status = .failing
            } else if health.errorCount >= 3 {
                health.status = .unstable
            } else if health.errorCount >= 1 {
                health.status = .warning
            }
            
            // Recommend reducing connections if many errors
            if health.errorCount > 2 && health.currentConnections > 1 {
                health.recommendedConnections = max(1, health.currentConnections - 1)
            }
        } else {
            // Update speed metrics
            health.averageSpeed = (health.averageSpeed + currentSpeed) / 2.0
            health.lastHealthCheck = Date()
            
            // If download is progressing well, mark as recovered
            if health.status != .healthy && health.errorCount > 0 {
                health.status = .recovered
            }
        }
        
        downloadHealth[downloadId] = health
    }
    
    public func getDownloadHealth(downloadId: UUID) -> DownloadHealth? {
        return downloadHealth[downloadId]
    }
    
    // MARK: - Error Recovery
    
    public func handleDownloadError(
        downloadId: UUID,
        error: DownloadErrorType,
        currentAttempt: Int,
        availableMirrors: [String] = [],
        currentConnections: Int = 1,
        partialDataAvailable: Bool = false
    ) async -> RecoveryAction? {
        guard configuration.isEnabled else { return nil }
        guard currentAttempt < configuration.maxRetryAttempts else { return .manualIntervention }
        guard error.isRecoverable else { return .manualIntervention }
        
        isRecovering = true
        defer { isRecovering = false }
        
        // Update health
        updateDownloadHealth(
            downloadId: downloadId,
            errorOccurred: true,
            errorType: error,
            connections: currentConnections
        )
        
        // Determine recovery action
        let action = determineRecoveryAction(
            error: error,
            attemptNumber: currentAttempt,
            availableMirrors: availableMirrors,
            currentConnections: currentConnections,
            partialDataAvailable: partialDataAvailable
        )
        
        // Calculate delay
        let delay = configuration.retryStrategy.delay(
            forAttempt: currentAttempt,
            baseDelay: configuration.baseDelay
        )
        
        // Create recovery attempt record
        let attempt = RecoveryAttempt(
            downloadTaskId: downloadId,
            attemptNumber: currentAttempt,
            errorType: error,
            strategy: configuration.retryStrategy,
            action: action,
            delayUsed: delay
        )
        
        activeRecoveries[downloadId] = attempt
        
        // Wait for delay
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Execute recovery action
        let success = await executeRecoveryAction(
            action: action,
            downloadId: downloadId,
            attempt: attempt
        )
        
        // Update statistics
        updateStatistics(
            error: error,
            action: action,
            wasSuccessful: success,
            delay: delay
        )
        
        // Remove from active recoveries
        activeRecoveries.removeValue(forKey: downloadId)
        
        return action
    }
    
    private func determineRecoveryAction(
        error: DownloadErrorType,
        attemptNumber: Int,
        availableMirrors: [String],
        currentConnections: Int,
        partialDataAvailable: Bool
    ) -> RecoveryAction {
        // Check if partial recovery is available and enabled
        if partialDataAvailable && configuration.enablePartialRecovery {
            return .resumePartial
        }
        
        // Check if mirror fallback is available and enabled
        if !availableMirrors.isEmpty && configuration.enableMirrorFallback && attemptNumber > 1 {
            return .tryMirror
        }
        
        // Check if we should reduce connections
        if configuration.reduceConnectionsOnError && currentConnections > configuration.minConnections {
            return .reduceConnections
        }
        
        // Use recommended strategy for error type
        switch error.recommendedStrategy {
        case .immediate, .linearDelay, .exponentialBackoff:
            return .retry
        case .none, .custom:
            return .manualIntervention
        }
    }
    
    private func executeRecoveryAction(
        action: RecoveryAction,
        downloadId: UUID,
        attempt: RecoveryAttempt
    ) async -> Bool {
        // In real implementation, would coordinate with DownloadManager
        // For now, return simulated success
        
        switch action {
        case .retry:
            print("Retrying download \(downloadId) - Attempt \(attempt.attemptNumber)")
            return true
            
        case .tryMirror:
            print("Trying mirror for download \(downloadId)")
            statistics.mirrorFallbacksUsed += 1
            return true
            
        case .reduceConnections:
            print("Reducing connections for download \(downloadId)")
            return true
            
        case .changeNetwork:
            print("Network change detected for download \(downloadId)")
            return false // Can't force network change
            
        case .resumePartial:
            print("Resuming partial download \(downloadId)")
            return true
            
        case .redownload:
            print("Redownloading from start \(downloadId)")
            return true
            
        case .skipFile:
            print("Skipping download \(downloadId)")
            return true
            
        case .manualIntervention:
            print("Manual intervention required for download \(downloadId)")
            return false
        }
    }
    
    // MARK: - Mirror Management Integration
    
    public func findAlternativeMirror(
        originalUrl: String,
        filename: String
    ) async -> String? {
        guard configuration.enableMirrorFallback else { return nil }
        
        // In real implementation, would integrate with MirrorManager from Feature #20
        // For now, return nil (no mirror found)
        return nil
    }
    
    // MARK: - Batch Recovery
    
    public func recoverFailedDownloads(
        downloadIds: [UUID]
    ) async -> [UUID: Bool] {
        var results: [UUID: Bool] = [:]
        
        for downloadId in downloadIds {
            // In real implementation, would get actual error info from DownloadManager
            let action = await handleDownloadError(
                downloadId: downloadId,
                error: .networkConnection,
                currentAttempt: 1
            )
            
            results[downloadId] = (action != nil && action != .manualIntervention)
        }
        
        return results
    }
    
    // MARK: - Smart Retry Decision
    
    public func shouldRetryDownload(
        downloadId: UUID,
        error: DownloadErrorType,
        attemptNumber: Int
    ) -> Bool {
        guard configuration.isEnabled && configuration.autoRetryOnFailure else {
            return false
        }
        
        guard attemptNumber < configuration.maxRetryAttempts else {
            return false
        }
        
        guard error.isRecoverable else {
            return false
        }
        
        // Check download health
        if let health = downloadHealth[downloadId], health.status == .failing {
            // Too many consecutive errors, don't retry automatically
            return false
        }
        
        return true
    }
    
    // MARK: - Connection Optimization
    
    public func optimizeConnections(
        downloadId: UUID,
        currentConnections: Int,
        averageSpeed: Double,
        errorRate: Double
    ) -> Int {
        guard configuration.reduceConnectionsOnError else {
            return currentConnections
        }
        
        // If error rate is high, reduce connections
        if errorRate > 0.3 && currentConnections > configuration.minConnections {
            return max(configuration.minConnections, currentConnections - 1)
        }
        
        // If speed is poor with many connections, reduce
        if averageSpeed < 100_000 && currentConnections > 2 { // < 100KB/s
            return max(configuration.minConnections, currentConnections / 2)
        }
        
        return currentConnections
    }
    
    // MARK: - Recovery Queue Management
    
    public func addToRecoveryQueue(
        downloadId: UUID,
        error: DownloadErrorType
    ) {
        // In real implementation, would queue for automated recovery
        print("Added download \(downloadId) to recovery queue for error: \(error.displayName)")
    }
    
    public func removeFromRecoveryQueue(downloadId: UUID) {
        activeRecoveries.removeValue(forKey: downloadId)
        recoveryTimers[downloadId]?.invalidate()
        recoveryTimers.removeValue(forKey: downloadId)
    }
    
    // MARK: - Notification Management
    
    private func sendRecoveryNotification(
        downloadId: UUID,
        wasSuccessful: Bool,
        action: RecoveryAction
    ) {
        if wasSuccessful && configuration.notifyOnRecovery {
            // In real implementation, would use NotificationManager
            print("Recovery successful for \(downloadId) using \(action.displayName)")
        } else if !wasSuccessful && configuration.notifyOnFailure {
            print("Recovery failed for \(downloadId)")
        }
    }
    
    // MARK: - Export & Reporting
    
    public func exportRecoveryHistory() -> String {
        var report = "Download Manager - Error Recovery Report\n"
        report += "Generated: \(Date())\n\n"
        
        report += "=== Configuration ===\n"
        report += "Auto Retry: \(configuration.autoRetryOnFailure)\n"
        report += "Max Attempts: \(configuration.maxRetryAttempts)\n"
        report += "Strategy: \(configuration.retryStrategy.displayName)\n"
        report += "Mirror Fallback: \(configuration.enableMirrorFallback)\n\n"
        
        report += "=== Statistics ===\n"
        report += "Total Errors: \(statistics.totalErrors)\n"
        report += "Recovery Attempts: \(statistics.totalRecoveryAttempts)\n"
        report += "Successful: \(statistics.successfulRecoveries)\n"
        report += "Failed: \(statistics.failedRecoveries)\n"
        report += "Success Rate: \(String(format: "%.1f%%", statistics.successRate))\n"
        report += "Mirror Fallbacks: \(statistics.mirrorFallbacksUsed)\n"
        report += "Network Changes: \(statistics.networkChangesDetected)\n\n"
        
        report += "=== Recent Recovery History ===\n"
        for result in recoveryHistory.prefix(20) {
            report += "[\(result.timestamp)] "
            report += "\(result.wasSuccessful ? "✅" : "❌") "
            report += "\(result.errorType.displayName) -> \(result.finalAction.displayName) "
            report += "(\(result.totalAttempts) attempts)\n"
        }
        
        return report
    }
}
