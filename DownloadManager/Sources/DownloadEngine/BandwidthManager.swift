//
//  BandwidthManager.swift
//  Download Manager for Mac - Feature #10: Advanced Bandwidth Management
//
//  Created on February 16, 2026
//

import Foundation
import Combine
import SystemConfiguration
import Network

/// Manages bandwidth allocation and monitoring
@MainActor
class BandwidthManager: ObservableObject {
    
    static let shared = BandwidthManager()
    
    @Published var globalLimit: BandwidthLimit = BandwidthLimit()
    @Published var schedules: [BandwidthTimeSchedule] = []
    @Published var networkConfigurations: [BandwidthNetworkConfiguration] = []
    @Published var rules: [BandwidthRule] = []
    @Published var profiles: [BandwidthProfile] = []
    @Published var statistics: BandwidthStatistics = BandwidthStatistics()
    @Published var currentNetworkType: NetworkType = .unknown
    @Published var isMonitoring: Bool = false
    
    // Active limits (computed from schedules, network config, rules)
    @Published var activeLimit: BandwidthLimit = BandwidthLimit()
    
    // Per-download speed limits
    private var perDownloadLimits: [UUID: BandwidthLimit] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.rapiddownload.networkmonitor")
    
    private init() {
        loadGlobalLimit()
        loadSchedules()
        loadNetworkConfigurations()
        loadRules()
        loadProfiles()
        loadStatistics()
        
        detectCurrentNetwork()
        startNetworkMonitoring()
        startStatisticsMonitoring()
    }
    
    // MARK: - Global Limits
    
    /// Set global bandwidth limit
    func setGlobalLimit(_ limit: BandwidthLimit) {
        globalLimit = limit
        saveGlobalLimit()
        updateActiveLimit()
    }
    
    /// Apply bandwidth profile
    func applyProfile(_ profile: BandwidthProfile) {
        globalLimit = BandwidthLimit(
            isEnabled: true,
            downloadSpeed: profile.downloadSpeed,
            uploadSpeed: profile.uploadSpeed
        )
        saveGlobalLimit()
        updateActiveLimit()
    }
    
    // MARK: - Per-Download Limits
    
    /// Set speed limit for specific download
    func setDownloadLimit(_ taskId: UUID, limit: BandwidthLimit) {
        perDownloadLimits[taskId] = limit
        let bytes = limit.isEnabled && limit.downloadSpeed > 0 ? limit.downloadSpeed : nil
        applyEngineLimit(bytes, for: taskId)

        // Direct video tasks own a separate engine task.
        if let videoTask = VideoDownloadManager.shared.videoTasks.first(where: { $0.id == taskId }),
           let engineTask = videoTask.downloadTask {
            applyEngineLimit(bytes, for: engineTask.id)
        }
        VideoDownloadManager.shared.speedLimitChanged(for: taskId)
    }
    
    /// Get speed limit for specific download
    func getDownloadLimit(_ taskId: UUID) -> BandwidthLimit? {
        return perDownloadLimits[taskId]
    }
    
    /// Remove speed limit for specific download
    func removeDownloadLimit(_ taskId: UUID) {
        perDownloadLimits.removeValue(forKey: taskId)
        applyEngineLimit(nil, for: taskId)
        if let videoTask = VideoDownloadManager.shared.videoTasks.first(where: { $0.id == taskId }),
           let engineTask = videoTask.downloadTask {
            applyEngineLimit(nil, for: engineTask.id)
        }
        VideoDownloadManager.shared.speedLimitChanged(for: taskId)
    }

    /// Push a live limit into the engine; nil restores the task's own limit.
    private func applyEngineLimit(_ bytesPerSecond: Int64?, for taskId: UUID) {
        BandwidthGate.shared.setTaskLimit(bytesPerSecond, for: taskId)
    }
    
    /// Calculate effective speed limit for a download
    func getEffectiveLimit(for task: DownloadTask) -> BandwidthLimit {
        // Priority order:
        // 1. Per-download limit
        // 2. Matching rule
        // 3. Active schedule
        // 4. Network configuration
        // 5. Global limit
        
        // Check per-download limit first
        if let perDownloadLimit = perDownloadLimits[task.id], perDownloadLimit.isEnabled {
            return perDownloadLimit
        }
        
        // Check matching rules (highest priority first)
        let matchingRules = rules
            .filter { $0.isEnabled && $0.matches(task: task, networkType: currentNetworkType) }
            .sorted { $0.priority > $1.priority }
        
        if let rule = matchingRules.first {
            return rule.limit
        }
        
        // Return active limit (which considers schedules and network config)
        return activeLimit
    }
    
    /// Throttle speed for a download task
    func throttleSpeed(for taskId: UUID, currentSpeed: Int64) -> Int64 {
        // Find the download task
        guard let task = Thread.isMainThread ? DownloadManager.shared.downloadTasks.first(where: { $0.id == taskId }) : nil else {
            return currentSpeed
        }
        
        let effectiveLimit = getEffectiveLimit(for: task)
        
        guard effectiveLimit.isEnabled, effectiveLimit.downloadSpeed > 0 else {
            return currentSpeed // No limit
        }
        
        // Apply speed limit
        return min(currentSpeed, effectiveLimit.downloadSpeed)
    }
    
    // MARK: - Schedules
    
    /// Add bandwidth schedule
    func addSchedule(_ schedule: BandwidthTimeSchedule) {
        schedules.append(schedule)
        saveSchedules()
        updateActiveLimit()
    }
    
    /// Update bandwidth schedule
    func updateSchedule(_ schedule: BandwidthTimeSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
            saveSchedules()
            updateActiveLimit()
        }
    }
    
    /// Delete bandwidth schedule
    func deleteSchedule(_ schedule: BandwidthTimeSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        saveSchedules()
        updateActiveLimit()
    }
    
    /// Get active schedule at specific time
    func getActiveSchedule(at date: Date = Date()) -> BandwidthTimeSchedule? {
        return schedules
            .filter { $0.isActive(at: date) }
            .sorted(by: { $0.priority > $1.priority })
            .first
    }
    
    // MARK: - Network Configurations
    
    /// Add network configuration
    func addNetworkConfiguration(_ config: BandwidthNetworkConfiguration) {
        networkConfigurations.append(config)
        saveNetworkConfigurations()
        updateActiveLimit()
    }
    
    /// Update network configuration
    func updateNetworkConfiguration(_ config: BandwidthNetworkConfiguration) {
        if let index = networkConfigurations.firstIndex(where: { $0.id == config.id }) {
            networkConfigurations[index] = config
            saveNetworkConfigurations()
            updateActiveLimit()
        }
    }
    
    /// Delete network configuration
    func deleteNetworkConfiguration(_ config: BandwidthNetworkConfiguration) {
        networkConfigurations.removeAll { $0.id == config.id }
        saveNetworkConfigurations()
        updateActiveLimit()
    }
    
    /// Get configuration for current network
    func getCurrentNetworkConfiguration() -> BandwidthNetworkConfiguration? {
        return networkConfigurations.first { $0.networkType == currentNetworkType && $0.autoApply }
    }
    
    // MARK: - Rules
    
    /// Add bandwidth rule
    func addRule(_ rule: BandwidthRule) {
        rules.append(rule)
        saveRules()
    }
    
    /// Update bandwidth rule
    func updateRule(_ rule: BandwidthRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            saveRules()
        }
    }
    
    /// Delete bandwidth rule
    func deleteRule(_ rule: BandwidthRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }
    
    // MARK: - Profiles
    
    /// Add custom profile
    func addProfile(_ profile: BandwidthProfile) {
        profiles.append(profile)
        saveProfiles()
    }
    
    /// Update profile
    func updateProfile(_ profile: BandwidthProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
        }
    }
    
    /// Delete custom profile
    func deleteProfile(_ profile: BandwidthProfile) {
        guard !profile.isPredefined else { return }
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }
    
    // MARK: - Network Detection
    
    /// Detect current network type
    func detectCurrentNetwork() {
        // Use SystemConfiguration to detect network type
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            currentNetworkType = .unknown
            return
        }
        
        var flags: SCNetworkReachabilityFlags = []
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else {
            currentNetworkType = .unknown
            return
        }
        
        // Determine network type
        // Note: isWWAN is iOS-only, so we can't detect cellular on macOS
        if flags.contains(.reachable) {
            // Check for WiFi or Ethernet
            // This is a simplified check - in production, you might want more detailed detection
            currentNetworkType = .wifi
        } else {
            currentNetworkType = .unknown
        }
        
        updateActiveLimit()
    }
    
    /// Start monitoring network changes
    func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handleNetworkPathUpdate(path)
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    /// Handle network path changes
    private func handleNetworkPathUpdate(_ path: NWPath) {
        let oldType = currentNetworkType
        
        if path.usesInterfaceType(.wifi) {
            currentNetworkType = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            currentNetworkType = .ethernet
        } else if path.usesInterfaceType(.cellular) {
            currentNetworkType = .cellular
        } else if path.usesInterfaceType(.other) {
            currentNetworkType = .unknown
        } else {
            currentNetworkType = .unknown
        }
        
        if oldType != currentNetworkType {
            print("[BandwidthManager] Network changed: \(oldType.rawValue) → \(currentNetworkType.rawValue)")
            updateActiveLimit()
            
            // Check if downloads should be paused on metered network
            if currentNetworkType.isMetered {
                if let config = getCurrentNetworkConfiguration(), !config.allowMeteredDownloads {
                    // Pause all downloads (note: pauseAllDownloads() needs to be implemented in DownloadManager)
                    // For now, we just update the active limit
                    updateActiveLimit()
                }
            }
        }
    }
    
    // MARK: - Active Limit Calculation
    
    /// Update active bandwidth limit based on schedules and network
    private func updateActiveLimit() {
        // Priority order:
        // 1. Active schedule (if any)
        // 2. Network-specific configuration (if auto-apply)
        // 3. Global limit
        
        if let schedule = getActiveSchedule(), schedule.limit.isEnabled {
            activeLimit = schedule.limit
            return
        }
        
        if let networkConfig = getCurrentNetworkConfiguration(), networkConfig.limit.isEnabled {
            activeLimit = networkConfig.limit
            return
        }
        
        activeLimit = globalLimit
    }
    
    // MARK: - Statistics
    
    /// Start monitoring statistics
    func startStatisticsMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Update statistics every second
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatistics()
        }
    }
    
    /// Stop monitoring statistics
    func stopStatisticsMonitoring() {
        isMonitoring = false
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    /// Update bandwidth statistics
    private func updateStatistics() {
        guard Thread.isMainThread else { return }
        // Calculate current speeds from active downloads
        let activeDownloads = DownloadManager.shared.downloadTasks.filter { $0.state == .downloading }
        
        let totalDownloadSpeed = activeDownloads.reduce(Int64(0)) { $0 + $1.speed }
        let totalDownloadedBytes = activeDownloads.reduce(Int64(0)) { $0 + $1.downloadedBytes }
        
        // Record statistics
        if totalDownloadSpeed > 0 {
            statistics.recordDownload(bytes: totalDownloadedBytes, speed: totalDownloadSpeed)
        }
        
        saveStatistics()
    }
    
    /// Reset statistics
    func resetStatistics() {
        statistics.reset()
        saveStatistics()
    }
    
    /// Get bandwidth usage for time period
    func getUsageForPeriod(hours: Int) -> (downloaded: Int64, uploaded: Int64) {
        // Filter data points within time period
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        
        let recentDownloads = statistics.downloadSpeedHistory.filter { $0.timestamp >= cutoffDate }
        let recentUploads = statistics.uploadSpeedHistory.filter { $0.timestamp >= cutoffDate }
        
        let totalDownloaded = recentDownloads.reduce(Int64(0)) { $0 + $1.speed }
        let totalUploaded = recentUploads.reduce(Int64(0)) { $0 + $1.speed }
        
        return (totalDownloaded, totalUploaded)
    }
    
    // MARK: - Persistence
    
    private let globalLimitKey = "bandwidthManager.globalLimit"
    private let schedulesKey = "bandwidthManager.schedules"
    private let networkConfigsKey = "bandwidthManager.networkConfigurations"
    private let rulesKey = "bandwidthManager.rules"
    private let profilesKey = "bandwidthManager.profiles"
    private let statisticsKey = "bandwidthManager.statistics"
    
    private func loadGlobalLimit() {
        if let data = UserDefaults.standard.data(forKey: globalLimitKey),
           let limit = try? JSONDecoder().decode(BandwidthLimit.self, from: data) {
            globalLimit = limit
        }
    }
    
    private func saveGlobalLimit() {
        if let data = try? JSONEncoder().encode(globalLimit) {
            UserDefaults.standard.set(data, forKey: globalLimitKey)
        }
    }
    
    private func loadSchedules() {
        if let data = UserDefaults.standard.data(forKey: schedulesKey),
           let loaded = try? JSONDecoder().decode([BandwidthTimeSchedule].self, from: data) {
            schedules = loaded
        }
    }
    
    private func saveSchedules() {
        if let data = try? JSONEncoder().encode(schedules) {
            UserDefaults.standard.set(data, forKey: schedulesKey)
        }
    }
    
    private func loadNetworkConfigurations() {
        if let data = UserDefaults.standard.data(forKey: networkConfigsKey),
           let loaded = try? JSONDecoder().decode([BandwidthNetworkConfiguration].self, from: data) {
            networkConfigurations = loaded
        } else {
            // Create default configurations
            networkConfigurations = NetworkType.allCases.map { type in
                BandwidthNetworkConfiguration(
                    networkType: type,
                    limit: BandwidthLimit(
                        isEnabled: type.isMetered,
                        downloadSpeed: type.defaultSpeedLimit,
                        uploadSpeed: type.defaultSpeedLimit / 2
                    ),
                    autoApply: type.isMetered,
                    allowMeteredDownloads: false
                )
            }
            saveNetworkConfigurations()
        }
    }
    
    private func saveNetworkConfigurations() {
        if let data = try? JSONEncoder().encode(networkConfigurations) {
            UserDefaults.standard.set(data, forKey: networkConfigsKey)
        }
    }
    
    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let loaded = try? JSONDecoder().decode([BandwidthRule].self, from: data) {
            rules = loaded
        }
    }
    
    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }
    
    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let loaded = try? JSONDecoder().decode([BandwidthProfile].self, from: data) {
            profiles = BandwidthProfile.predefinedProfiles + loaded.filter { !$0.isPredefined }
        } else {
            profiles = BandwidthProfile.predefinedProfiles
        }
    }
    
    private func saveProfiles() {
        let customProfiles = profiles.filter { !$0.isPredefined }
        if let data = try? JSONEncoder().encode(customProfiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }
    
    private func loadStatistics() {
        if let data = UserDefaults.standard.data(forKey: statisticsKey),
           let loaded = try? JSONDecoder().decode(BandwidthStatistics.self, from: data) {
            statistics = loaded
        }
    }
    
    private func saveStatistics() {
        if let data = try? JSONEncoder().encode(statistics) {
            UserDefaults.standard.set(data, forKey: statisticsKey)
        }
    }
}
