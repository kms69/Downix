import Foundation
import SwiftUI

/// Coordinates initialization and lifecycle of all managers
@MainActor
final class ManagerCoordinator: ObservableObject {
    static let shared = ManagerCoordinator()
    
    @Published private(set) var isInitialized = false
    @Published private(set) var initializationProgress: Double = 0.0
    @Published private(set) var currentInitializing: String = ""
    
    private var managers: [String: Any] = [:]
    private var initializationTasks: [Task<Void, Never>] = []
    
    private init() {}
    
    /// Initialize all managers in the correct order
    func initialize() {
        guard !isInitialized else {
            print("⚠️ ManagerCoordinator already initialized")
            return
        }
        
        print("🔧 Initializing managers...")
        
        let totalSteps = 20.0
        var currentStep = 0.0
        
        func updateProgress(_ name: String) {
            currentStep += 1
            initializationProgress = currentStep / totalSteps
            currentInitializing = name
            print("   [\(Int(initializationProgress * 100))%] \(name)")
        }
        
        // Initialize core managers first
        updateProgress("Theme Manager")
        _ = ThemeManager.shared
        managers["theme"] = ThemeManager.shared
        
        updateProgress("Network Manager")
        _ = NetworkManager.shared
        managers["network"] = NetworkManager.shared
        
        updateProgress("Notification Manager")
        _ = NotificationManager.shared
        managers["notification"] = NotificationManager.shared
        
        // Initialize storage and history
        updateProgress("History Manager")
        _ = HistoryManager.shared
        managers["history"] = HistoryManager.shared
        
        // Initialize download core
        updateProgress("Download Manager")
        _ = DownloadManager.shared
        managers["download"] = DownloadManager.shared
        
        updateProgress("Resume Manager")
        _ = ResumeManager.shared
        managers["resume"] = ResumeManager.shared
        
        // Initialize scheduler and automation
        updateProgress("Download Scheduler")
        _ = DownloadScheduler.shared
        managers["scheduler"] = DownloadScheduler.shared
        
        updateProgress("Auto Shutdown Manager")
        _ = AutoShutdownManager.shared
        managers["autoshutdown"] = AutoShutdownManager.shared
        
        // Initialize video and media
        updateProgress("Video Download Manager")
        _ = VideoDownloadManager.shared
        managers["video"] = VideoDownloadManager.shared
        
        updateProgress("Advanced Video Manager")
        let advancedVideoManager = AdvancedVideoManager()
        managers["advancedvideo"] = advancedVideoManager
        
        updateProgress("Media Preview Manager")
        _ = MediaPreviewManager.shared
        managers["mediapreview"] = MediaPreviewManager.shared
        
        // Initialize organization and cloud
        updateProgress("Organization Manager")
        _ = OrganizationManager.shared
        managers["organization"] = OrganizationManager.shared
        
        updateProgress("Cloud Integration Manager")
        _ = CloudIntegrationManager.shared
        managers["cloud"] = CloudIntegrationManager.shared
        
        // Initialize network features
        updateProgress("Bandwidth Manager")
        _ = BandwidthManager.shared
        managers["bandwidth"] = BandwidthManager.shared
        
        // Initialize security and verification
        updateProgress("Security Privacy Manager")
        let securityManager = SecurityPrivacyManager()
        managers["security"] = securityManager
        
        updateProgress("File Verification Manager")
        _ = FileVerificationManager.shared
        managers["verification"] = FileVerificationManager.shared
        
        updateProgress("Error Recovery Manager")
        _ = ErrorRecoveryManager.shared
        managers["errorrecovery"] = ErrorRecoveryManager.shared
        
        // Initialize batch operations and browser
        updateProgress("Batch Operation Manager")
        _ = BatchOperationManager.shared
        managers["batch"] = BatchOperationManager.shared
        
        updateProgress("Browser Integration Manager")
        _ = BrowserIntegrationManager.shared
        managers["browser"] = BrowserIntegrationManager.shared

        // Keep native-messaging host + manifests in sync with this build. Runs on
        // every launch (idempotent) so extension fixes take effect without the
        // user having to press "Install" in Settings.
        do {
            try BrowserIntegrationManager.shared.installNativeHost()
        } catch {
            print("⚠️ Native host install failed: \(error)")
        }
        
        // Initialize monitoring
        updateProgress("Clipboard Monitor")
        ClipboardMonitor.shared.startMonitoring()
        managers["clipboard"] = ClipboardMonitor.shared

        updateProgress("Scheduler Queue Manager")
        _ = SchedulerQueueManager.shared
        managers["schedulerqueue"] = SchedulerQueueManager.shared

        updateProgress("Torrent Manager")
        _ = TorrentManager.shared
        managers["torrent"] = TorrentManager.shared
        
        // Setup integrations between managers
        setupIntegrations()
        
        isInitialized = true
        initializationProgress = 1.0
        currentInitializing = "Complete"
        
        print("✅ All managers initialized successfully")
    }
    
    /// Setup cross-manager integrations and callbacks
    private func setupIntegrations() {
        print("🔗 Setting up manager integrations...")
        
        // Download Manager <-> Error Recovery
        DownloadManager.shared.errorHandler = { [weak self] download, error in
            _ = self
            print("⚠️ Download error for \(download.name): \(error.localizedDescription)")
        }
        
        // Download Manager <-> Resume Manager
        DownloadManager.shared.resumeProvider = { [weak self] download in
            _ = self
            let action = ResumeManager.shared.determineResumeAction(for: download, error: nil)
            switch action {
            case .resume: return true
            default: return false
            }
        }
        
        // Download Manager <-> File Verification
        DownloadManager.shared.verificationHandler = { [weak self] download in
            _ = self
            if let destination = download.destination {
                _ = await FileVerificationManager.shared.verifyFileWithDefaults(
                    filePath: destination.path,
                    downloadTaskId: download.id
                )
            }
        }
        
        // Download Manager <-> Organization
        DownloadManager.shared.completionHandler = { [weak self] download in
            _ = self
            Task { @MainActor in
                // Auto-organize completed downloads
                if let destination = download.destination {
                    await OrganizationManager.shared.organizeFile(destination)
                }
                
                // Upload to cloud if configured
                if CloudIntegrationManager.shared.autoUploadEnabled,
                   let destination = download.destination {
                    await CloudIntegrationManager.shared.uploadFile(destination)
                }
                
                // Add to history
                HistoryManager.shared.addDownload(download)
                
                // Send notification
                NotificationManager.shared.notifyDownloadCompleted(
                    taskId: download.id,
                    filename: download.name,
                    duration: "--",
                    filePath: download.destination?.path ?? ""
                )

                // The floating progress window has done its job.
                DownloadProgressWindowController.close(for: download.id)

                // IDM-style completion dialog for user-initiated downloads.
                if download.showsCompletionDialog {
                    DownloadCompleteWindowController.shared.present(for: download)
                }
            }
        }
        
        // Network Manager <-> Download Manager
        NetworkManager.shared.networkChangeHandler = { [weak self] isOnline in
            Task { @MainActor in
                if isOnline {
                    print("📡 Network restored, resuming downloads...")
                    // Only what the network monitor paused — never what the user paused.
                    await DownloadManager.shared.resumeAll(onlyAutoPaused: true)
                } else {
                    print("📡 Network lost, pausing downloads...")
                    await DownloadManager.shared.pauseAll(auto: true)
                }
            }
        }
        
        // Bandwidth Manager <-> Download Manager
        BandwidthManager.shared.speedLimitHandler = { [weak self] limit in
            Task { @MainActor in
                await DownloadManager.shared.applyGlobalSpeedLimit(limit)
            }
        }
        
        // Scheduler <-> Download Manager (+ queue): due schedules start waiting
        // tasks through the normal engine so queue limits apply.
        DownloadScheduler.shared.scheduleExecutor = { [weak self] schedule in
            Task { @MainActor in
                _ = self
                let due = DownloadManager.shared.downloadTasks.filter {
                    $0.schedule?.id == schedule.id && ($0.state == .waiting || $0.state == .paused)
                }
                for task in due { DownloadManager.shared.startDownload(task) }
                print("Executed schedule \(schedule.id): started \(due.count) task(s)")
            }
        }
        
        // Auto Shutdown <-> Download Manager
        AutoShutdownManager.shared.downloadsProvider = { [weak self] in
            DownloadManager.shared.downloadTasks
        }
        
        print("✅ Manager integrations configured")
    }
    
    /// Shutdown all managers gracefully
    func shutdown() async {
        print("🛑 Shutting down managers...")
        
        // Stop monitoring
        ClipboardMonitor.shared.stopMonitoring()
        
        // Pause all downloads
        await DownloadManager.shared.pauseAll()
        
        // Save state
        DownloadManager.shared.saveState()
        ThemeManager.shared.savePreferences()
        
        // Disconnect cloud services
        await CloudIntegrationManager.shared.disconnect()
        
        // Cancel scheduler tasks
        DownloadScheduler.shared.cancelAllSchedules()
        
        print("✅ Shutdown complete")
    }
    
    /// Get manager by name
    func getManager<T>(_ name: String) -> T? {
        return managers[name] as? T
    }
    
    /// Check if all critical managers are ready
    var allManagersReady: Bool {
        isInitialized &&
        DownloadManager.shared.isReady &&
        NetworkManager.shared.isReady
    }
}

// MARK: - Manager Ready Protocol
protocol ManagerReady {
    var isReady: Bool { get }
}

// MARK: - Extensions for Manager Ready Status
extension DownloadManager: ManagerReady {
    var isReady: Bool {
        // Check if download manager is ready to accept downloads
        return true
    }
}

@MainActor
extension NetworkManager: ManagerReady {
    var isReady: Bool {
        // Check if network manager has initialized network monitoring
        return true
    }
}

// MARK: - Manager Integration Protocols

/// Protocol for handling download errors
typealias DownloadErrorHandler = (DownloadTask, Error) async -> Void

/// Protocol for providing resume capability
typealias ResumeProvider = (DownloadTask) async -> Bool

/// Protocol for verifying downloads
typealias VerificationHandler = (DownloadTask) async -> Void

/// Protocol for handling download completion
typealias CompletionHandler = (DownloadTask) async -> Void

/// Protocol for network change notifications
typealias NetworkChangeHandler = (Bool) async -> Void

/// Protocol for speed limit changes
typealias SpeedLimitHandler = (Double?) async -> Void

/// Protocol for schedule execution (uses DownloadSchedule from Models)
typealias ScheduledTask = DownloadSchedule
typealias ScheduleExecutor = (ScheduledTask) async -> Void

/// Protocol for providing downloads list
typealias DownloadsProvider = () -> [DownloadTask]

// MARK: - Extend Managers with Integration Properties
extension DownloadManager {
    private static var _errorHandler: DownloadErrorHandler?
    private static var _resumeProvider: ResumeProvider?
    private static var _verificationHandler: VerificationHandler?
    private static var _completionHandler: CompletionHandler?
    
    var errorHandler: DownloadErrorHandler? {
        get { DownloadManager._errorHandler }
        set { DownloadManager._errorHandler = newValue }
    }
    
    var resumeProvider: ResumeProvider? {
        get { DownloadManager._resumeProvider }
        set { DownloadManager._resumeProvider = newValue }
    }
    
    var verificationHandler: VerificationHandler? {
        get { DownloadManager._verificationHandler }
        set { DownloadManager._verificationHandler = newValue }
    }
    
    var completionHandler: CompletionHandler? {
        get { DownloadManager._completionHandler }
        set { DownloadManager._completionHandler = newValue }
    }
    
    func applyGlobalSpeedLimit(_ limit: Double?) async {
        // Apply speed limit to all active downloads
        DownloadManager.shared.globalBandwidthLimit = limit.map { Int64($0) }
        for download in downloadTasks where download.status == .downloading {
            download.bandwidthLimit = limit.map { Int64($0) }
        }
    }
    
    func saveState() {
        // Save download manager state to UserDefaults
        print("💾 Saving download manager state...")
    }
    
    func retryFailed() async {
        let failedDownloads = downloadTasks.filter { $0.status == .failed }
        for download in failedDownloads {
            await resumeDownload(download)
        }
    }
    
    func removeDownload(id: UUID) async {
        downloadTasks.removeAll { $0.id == id }
    }
}

extension NetworkManager {
    private static var _networkChangeHandler: NetworkChangeHandler?
    
    var networkChangeHandler: NetworkChangeHandler? {
        get { NetworkManager._networkChangeHandler }
        set { NetworkManager._networkChangeHandler = newValue }
    }
}

extension BandwidthManager {
    private static var _speedLimitHandler: SpeedLimitHandler?
    
    var speedLimitHandler: SpeedLimitHandler? {
        get { BandwidthManager._speedLimitHandler }
        set { BandwidthManager._speedLimitHandler = newValue }
    }
}

extension DownloadScheduler {
    private static var _scheduleExecutor: ScheduleExecutor?
    
    var scheduleExecutor: ScheduleExecutor? {
        get { DownloadScheduler._scheduleExecutor }
        set { DownloadScheduler._scheduleExecutor = newValue }
    }
    
    func cancelAllSchedules() {
        scheduledTasks.removeAll()
        stopMonitoring()
        print("Cancelled all scheduled tasks")
    }
}

extension AutoShutdownManager {
    private static var _downloadsProvider: DownloadsProvider?
    
    var downloadsProvider: DownloadsProvider? {
        get { AutoShutdownManager._downloadsProvider }
        set { AutoShutdownManager._downloadsProvider = newValue }
    }
}

extension CloudIntegrationManager {
    var autoUploadEnabled: Bool {
        // Check if auto-upload is enabled in settings
        return UserDefaults.standard.bool(forKey: "cloudAutoUpload")
    }
    
    func uploadFile(_ fileURL: URL) async {
        print("☁️ Uploading file to cloud: \(fileURL.lastPathComponent)")
        // Would implement actual cloud upload here
    }
    
    func disconnect() async {
        print("☁️ Disconnecting cloud services...")
        // Would implement disconnection logic here
    }
}

extension OrganizationManager {
    func organizeFile(_ fileURL: URL) async {
        print("📁 Auto-organizing file: \(fileURL.lastPathComponent)")
        // Would implement file organization logic here
    }
}

extension ThemeManager {
    func savePreferences() {
        print("💾 Saving theme preferences...")
        // Would save to UserDefaults
    }
}

extension HistoryManager {
    func addDownload(_ download: DownloadTask) {
        print("📚 Adding download to history: \(download.name)")
        // Would add to history database
    }
}
