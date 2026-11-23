import Foundation
import Network
import SystemConfiguration
import Combine

/// Network manager for handling all network-related operations
@MainActor
public class NetworkManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = NetworkManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var configuration: NetworkConfiguration
    @Published public private(set) var currentVPNStatus: VPNConnectionStatus = .unknown
    @Published public private(set) var currentVPNConnection: VPNConnection?
    @Published public private(set) var availableInterfaces: [NetworkInterface] = []
    @Published public private(set) var activeInterface: NetworkInterface?
    @Published public private(set) var isNetworkAvailable: Bool = true
    @Published public private(set) var networkStatistics: NetworkStatistics = NetworkStatistics()
    
    // MARK: - Private Properties
    
    private let userDefaultsKey = "com.downloadmanager.networkConfiguration"
    private let statisticsKey = "com.downloadmanager.networkStatistics"
    private var networkMonitor: NWPathMonitor?
    private var vpnMonitorTimer: Timer?
    private var mirrorCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        self.configuration = Self.loadConfiguration()
        self.networkStatistics = Self.loadStatistics()
        
        Task {
            await setupNetworkMonitoring()
            await detectNetworkInterfaces()
            await detectVPNStatus()
            await startMirrorChecking()
        }
    }
    
    // MARK: - Configuration Management
    
    /// Save configuration to UserDefaults
    public func saveConfiguration() {
        ActiveProxyStore.shared.update(configuration.getActiveProxy())
        do {
            let data = try JSONEncoder().encode(configuration)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            configuration.lastModified = Date()
        } catch {
            print("Failed to save network configuration: \(error)")
        }
    }
    
    /// Load configuration from UserDefaults
    private static func loadConfiguration() -> NetworkConfiguration {
        guard let data = UserDefaults.standard.data(forKey: "com.downloadmanager.networkConfiguration"),
              let config = try? JSONDecoder().decode(NetworkConfiguration.self, from: data) else {
            return .default
        }
        return config
    }
    
    /// Save statistics
    private func saveStatistics() {
        do {
            let data = try JSONEncoder().encode(networkStatistics)
            UserDefaults.standard.set(data, forKey: statisticsKey)
        } catch {
            print("Failed to save network statistics: \(error)")
        }
    }
    
    /// Load statistics
    private static func loadStatistics() -> NetworkStatistics {
        guard let data = UserDefaults.standard.data(forKey: "com.downloadmanager.networkStatistics"),
              let stats = try? JSONDecoder().decode(NetworkStatistics.self, from: data) else {
            return NetworkStatistics()
        }
        return stats
    }
    
    /// Reset to defaults
    public func resetToDefaults() {
        configuration = .default
        networkStatistics = NetworkStatistics()
        saveConfiguration()
        saveStatistics()
    }
    
    // MARK: - Proxy Management
    
    /// Get all proxy configurations
    public func getAllProxies() -> [ProxyConfig] {
        return configuration.proxyConfigs
    }
    
    /// Get active proxy configuration
    public func getActiveProxy() -> ProxyConfig? {
        return configuration.getActiveProxy()
    }
    
    /// Add proxy configuration
    public func addProxy(_ proxy: ProxyConfig) {
        configuration.proxyConfigs.append(proxy)
        saveConfiguration()
    }
    
    /// Update proxy configuration
    public func updateProxy(_ proxy: ProxyConfig) {
        if let index = configuration.proxyConfigs.firstIndex(where: { $0.id == proxy.id }) {
            configuration.proxyConfigs[index] = proxy
            saveConfiguration()
        }
    }
    
    /// Delete proxy configuration
    public func deleteProxy(_ proxyID: UUID) {
        configuration.proxyConfigs.removeAll { $0.id == proxyID }
        if configuration.activeProxyID == proxyID {
            configuration.activeProxyID = nil
        }
        saveConfiguration()
    }
    
    /// Set active proxy
    public func setActiveProxy(_ proxyID: UUID?) {
        configuration.activeProxyID = proxyID
        saveConfiguration()
    }
    
    /// Test proxy connection
    public func testProxy(_ proxy: ProxyConfig) async -> (success: Bool, responseTime: TimeInterval, error: String?) {
        let startTime = Date()
        
        // Create URLSession with proxy configuration
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 10
        
        sessionConfig.connectionProxyDictionary = ProxySession.dictionary(for: proxy)
        
        let session = URLSession(configuration: sessionConfig)
        defer { session.finishTasksAndInvalidate() }
        
        do {
            let url = URL(string: "https://www.google.com")!
            let (_, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return (false, 0, "Invalid response")
            }
            
            let responseTime = Date().timeIntervalSince(startTime)
            return (true, responseTime, nil)
        } catch {
            return (false, 0, error.localizedDescription)
        }
    }
    
    /// Get system proxy settings
    public func getSystemProxySettings() -> ProxyConfig? {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        
        var proxy = ProxyConfig(name: "System Proxy", type: .system)
        
        if let httpEnabled = proxySettings[kCFNetworkProxiesHTTPEnable as String] as? Bool,
           httpEnabled,
           let host = proxySettings[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = proxySettings[kCFNetworkProxiesHTTPPort as String] as? Int {
            proxy.host = host
            proxy.port = port
            proxy.type = .http
        }
        
        return proxy.host.isEmpty ? nil : proxy
    }
    
    // MARK: - VPN Detection
    
    /// Detect VPN status
    public func detectVPNStatus() async {
        let status = await checkVPNConnection()
        await MainActor.run {
            let previousStatus = currentVPNStatus
            currentVPNStatus = status
            
            // Handle VPN state changes
            if previousStatus != status {
                handleVPNStatusChange(from: previousStatus, to: status)
            }
        }
    }
    
    /// Check VPN connection
    private func checkVPNConnection() async -> VPNConnectionStatus {
        // Check for VPN interfaces
        if let interfaces = CopyNetworkInterfaces() {
            for interface in interfaces {
                let name = interface.lowercased()
                if name.contains("utun") || name.contains("ppp") || name.contains("ipsec") {
                    // Check if interface is active
                    if await isInterfaceActive(interface) {
                        await MainActor.run {
                            currentVPNConnection = VPNConnection(
                                name: "VPN Connection",
                                status: .connected,
                                interfaceName: interface,
                                connectedAt: Date()
                            )
                        }
                        return .connected
                    }
                }
            }
        }
        
        await MainActor.run {
            currentVPNConnection = nil
        }
        return .disconnected
    }
    
    /// Copy network interfaces
    private func CopyNetworkInterfaces() -> [String]? {
        var interfaces: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            if !interfaces.contains(name) {
                interfaces.append(name)
            }
        }
        
        return interfaces
    }
    
    /// Check if interface is active
    private func isInterfaceActive(_ interfaceName: String) async -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            if name == interfaceName {
                let flags = Int32(interface.ifa_flags)
                return (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            }
        }
        
        return false
    }
    
    /// Handle VPN status change
    private func handleVPNStatusChange(from oldStatus: VPNConnectionStatus, to newStatus: VPNConnectionStatus) {
        if configuration.vpnConfig.showNotifications {
            // Send notification
            NotificationCenter.default.post(
                name: NSNotification.Name("VPNStatusChanged"),
                object: nil,
                userInfo: ["oldStatus": oldStatus, "newStatus": newStatus]
            )
        }
        
        // Handle pause/resume based on configuration
        if newStatus == .disconnected && configuration.vpnConfig.pauseDownloadsOnDisconnect {
            NotificationCenter.default.post(name: NSNotification.Name("PauseAllDownloads"), object: nil)
        } else if newStatus == .connected && configuration.vpnConfig.resumeDownloadsOnConnect {
            NotificationCenter.default.post(name: NSNotification.Name("ResumeAllDownloads"), object: nil)
        }
    }
    
    /// Update VPN configuration
    public func updateVPNConfig(_ config: VPNConfig) {
        configuration.vpnConfig = config
        saveConfiguration()
    }
    
    /// Start VPN monitoring
    private func startVPNMonitoring() {
        vpnMonitorTimer?.invalidate()
        vpnMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.detectVPNStatus()
            }
        }
    }
    
    // MARK: - Network Interface Management
    
    /// Detect network interfaces
    public func detectNetworkInterfaces() async {
        var interfaces: [NetworkInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            await MainActor.run {
                availableInterfaces = []
            }
            return
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        var processedNames = Set<String>()
        
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            // Skip if already processed
            guard !processedNames.contains(name) else { continue }
            processedNames.insert(name)
            
            // Determine interface type
            let type = getInterfaceType(name)
            
            // Get IP address if available
            var ipAddress: String?
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var addr = interface.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                if let ip = String(cString: inet_ntoa(addr), encoding: .utf8) {
                    ipAddress = ip
                }
            }
            
            // Check if active
            let flags = Int32(interface.ifa_flags)
            let isActive = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            
            interfaces.append(NetworkInterface(
                name: name,
                displayName: getInterfaceDisplayName(name),
                type: type,
                isActive: isActive,
                ipAddress: ipAddress
            ))
        }
        
        await MainActor.run {
            availableInterfaces = interfaces
            activeInterface = interfaces.first { $0.isActive }
        }
    }
    
    /// Get interface type from name
    private func getInterfaceType(_ name: String) -> NetworkInterfaceType {
        let lowercased = name.lowercased()
        if lowercased.hasPrefix("en") && lowercased.contains("wi") {
            return .wifi
        } else if lowercased.hasPrefix("en") {
            return .ethernet
        } else if lowercased.hasPrefix("pdp") {
            return .cellular
        } else if lowercased.contains("thunderbolt") {
            return .thunderbolt
        } else if lowercased.contains("usb") {
            return .usb
        }
        return .other
    }
    
    /// Get interface display name
    private func getInterfaceDisplayName(_ name: String) -> String {
        let type = getInterfaceType(name)
        switch type {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .thunderbolt: return "Thunderbolt"
        case .usb: return "USB Ethernet"
        case .other: return name
        }
    }
    
    /// Update interface preference
    public func updateInterfacePreference(_ preference: InterfacePreference) {
        configuration.interfacePreference = preference
        saveConfiguration()
    }
    
    /// Get preferred interface
    public func getPreferredInterface() -> NetworkInterface? {
        if let preferredID = configuration.interfacePreference.preferredInterfaceID {
            return availableInterfaces.first { $0.id == preferredID }
        }
        
        if configuration.interfacePreference.automaticSelection {
            // Prefer faster, non-metered connections
            return availableInterfaces
                .filter { $0.isActive }
                .filter { !configuration.interfacePreference.avoidMeteredConnections || !$0.isMetered }
                .sorted { ($0.speedMbps ?? 0) > ($1.speedMbps ?? 0) }
                .first
        }
        
        return activeInterface
    }
    
    // MARK: - Mirror Management
    
    /// Get all mirrors
    public func getAllMirrors() -> [MirrorServer] {
        return configuration.mirrorConfig.servers
    }
    
    /// Add mirror server
    public func addMirror(_ mirror: MirrorServer) {
        configuration.mirrorConfig.servers.append(mirror)
        saveConfiguration()
    }
    
    /// Update mirror server
    public func updateMirror(_ mirror: MirrorServer) {
        if let index = configuration.mirrorConfig.servers.firstIndex(where: { $0.id == mirror.id }) {
            configuration.mirrorConfig.servers[index] = mirror
            saveConfiguration()
        }
    }
    
    /// Delete mirror server
    public func deleteMirror(_ mirrorID: UUID) {
        configuration.mirrorConfig.servers.removeAll { $0.id == mirrorID }
        saveConfiguration()
    }
    
    /// Check mirror health
    public func checkMirrorHealth(_ mirror: MirrorServer) async -> (isHealthy: Bool, responseTime: TimeInterval, error: String?) {
        let startTime = Date()
        
        do {
            let (_, response) = try await URLSession.shared.data(from: mirror.baseURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return (false, 0, "Invalid response")
            }
            
            let responseTime = Date().timeIntervalSince(startTime)
            return (true, responseTime, nil)
        } catch {
            return (false, 0, error.localizedDescription)
        }
    }
    
    /// Check all mirrors
    public func checkAllMirrors() async {
        for (index, mirror) in configuration.mirrorConfig.servers.enumerated() {
            let (isHealthy, responseTime, _) = await checkMirrorHealth(mirror)
            
            await MainActor.run {
                configuration.mirrorConfig.servers[index].lastResponseTime = responseTime
                configuration.mirrorConfig.servers[index].lastChecked = Date()
                
                // Update success rate (simple exponential moving average)
                let currentRate = configuration.mirrorConfig.servers[index].successRate
                let newRate = isHealthy ? 1.0 : 0.0
                configuration.mirrorConfig.servers[index].successRate = 0.7 * currentRate + 0.3 * newRate
            }
        }
        
        saveConfiguration()
    }
    
    /// Get best mirror
    public func getBestMirror() -> MirrorServer? {
        let enabledMirrors = configuration.mirrorConfig.servers.filter { $0.isEnabled }
        
        guard !enabledMirrors.isEmpty else { return nil }
        
        switch configuration.mirrorConfig.selectionStrategy {
        case .automatic, .fastest:
            return enabledMirrors
                .filter { $0.isHealthy }
                .sorted { ($0.lastResponseTime ?? .infinity) < ($1.lastResponseTime ?? .infinity) }
                .first
            
        case .nearest:
            // For simplicity, use fastest as proxy for nearest
            return enabledMirrors
                .filter { $0.isHealthy }
                .sorted { ($0.lastResponseTime ?? .infinity) < ($1.lastResponseTime ?? .infinity) }
                .first
            
        case .priority:
            return enabledMirrors
                .sorted { $0.priority < $1.priority }
                .first
            
        case .manual:
            return nil
        }
    }
    
    /// Update mirror configuration
    public func updateMirrorConfig(_ config: MirrorConfig) {
        configuration.mirrorConfig = config
        saveConfiguration()
        
        if config.isEnabled {
            Task {
                await startMirrorChecking()
            }
        }
    }
    
    /// Start periodic mirror checking
    private func startMirrorChecking() async {
        guard configuration.mirrorConfig.isEnabled else { return }
        
        mirrorCheckTimer?.invalidate()
        
        // Initial check
        await checkAllMirrors()
        
        // Schedule periodic checks
        await MainActor.run {
            mirrorCheckTimer = Timer.scheduledTimer(
                withTimeInterval: configuration.mirrorConfig.checkInterval,
                repeats: true
            ) { [weak self] _ in
                Task {
                    await self?.checkAllMirrors()
                }
            }
        }
    }
    
    // MARK: - SSL Configuration
    
    /// Update SSL configuration
    public func updateSSLConfig(_ config: SSLConfig) {
        configuration.sslConfig = config
        saveConfiguration()
    }
    
    /// Add pinned certificate
    public func addPinnedCertificate(domain: String, fingerprint: String) {
        configuration.sslConfig.pinnedCertificates[domain] = fingerprint
        saveConfiguration()
    }
    
    /// Remove pinned certificate
    public func removePinnedCertificate(domain: String) {
        configuration.sslConfig.pinnedCertificates.removeValue(forKey: domain)
        saveConfiguration()
    }
    
    /// Add trusted domain
    public func addTrustedDomain(_ domain: String) {
        if !configuration.sslConfig.trustedDomains.contains(domain) {
            configuration.sslConfig.trustedDomains.append(domain)
            saveConfiguration()
        }
    }
    
    /// Remove trusted domain
    public func removeTrustedDomain(_ domain: String) {
        configuration.sslConfig.trustedDomains.removeAll { $0 == domain }
        saveConfiguration()
    }
    
    // MARK: - Headers and Cookies
    
    /// Update headers and cookies configuration
    public func updateHeadersCookiesConfig(_ config: HeadersCookiesConfig) {
        configuration.headersCookiesConfig = config
        saveConfiguration()
    }
    
    /// Add custom header
    public func addCustomHeader(_ header: HTTPHeader) {
        configuration.headersCookiesConfig.customHeaders.append(header)
        saveConfiguration()
    }
    
    /// Update custom header
    public func updateCustomHeader(_ header: HTTPHeader) {
        if let index = configuration.headersCookiesConfig.customHeaders.firstIndex(where: { $0.id == header.id }) {
            configuration.headersCookiesConfig.customHeaders[index] = header
            saveConfiguration()
        }
    }
    
    /// Delete custom header
    public func deleteCustomHeader(_ headerID: UUID) {
        configuration.headersCookiesConfig.customHeaders.removeAll { $0.id == headerID }
        saveConfiguration()
    }
    
    /// Add custom cookie
    public func addCustomCookie(_ cookie: HTTPCookieInfo) {
        configuration.headersCookiesConfig.customCookies.append(cookie)
        saveConfiguration()
    }
    
    /// Update custom cookie
    public func updateCustomCookie(_ cookie: HTTPCookieInfo) {
        if let index = configuration.headersCookiesConfig.customCookies.firstIndex(where: { $0.id == cookie.id }) {
            configuration.headersCookiesConfig.customCookies[index] = cookie
            saveConfiguration()
        }
    }
    
    /// Delete custom cookie
    public func deleteCustomCookie(_ cookieID: UUID) {
        configuration.headersCookiesConfig.customCookies.removeAll { $0.id == cookieID }
        saveConfiguration()
    }
    
    /// Get headers for URL
    public func getHeadersForURL(_ url: URL) -> [String: String] {
        var headers: [String: String] = [:]
        
        // Add custom headers
        for header in configuration.headersCookiesConfig.customHeaders where header.isEnabled {
            if header.applyToAllDownloads {
                headers[header.key] = header.value
            } else if let pattern = header.domainPattern, url.host?.contains(pattern) == true {
                headers[header.key] = header.value
            }
        }
        
        // Add user agent
        if configuration.headersCookiesConfig.sendUserAgent {
            headers["User-Agent"] = configuration.headersCookiesConfig.userAgent
        }
        
        // Add accept language
        if configuration.headersCookiesConfig.sendAcceptLanguage {
            headers["Accept-Language"] = configuration.headersCookiesConfig.acceptLanguage
        }
        
        // Add referrer if enabled
        if configuration.headersCookiesConfig.sendReferrer {
            headers["Referer"] = url.absoluteString
        }
        
        return headers
    }
    
    /// Get cookies for URL
    public func getCookiesForURL(_ url: URL) -> [HTTPCookie] {
        return configuration.headersCookiesConfig.customCookies
            .filter { $0.isEnabled && !$0.isExpired }
            .filter { url.host?.contains($0.domain) == true }
            .compactMap { $0.toHTTPCookie() }
    }
    
    // MARK: - Network Monitoring
    
    /// Setup network monitoring
    private func setupNetworkMonitoring() async {
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = path.status == .satisfied
                
                // Post notification on network change
                NotificationCenter.default.post(
                    name: NSNotification.Name("NetworkAvailabilityChanged"),
                    object: nil,
                    userInfo: ["isAvailable": path.status == .satisfied]
                )
            }
        }
        
        let queue = DispatchQueue(label: "com.downloadmanager.networkmonitor")
        monitor.start(queue: queue)
        
        // Start VPN monitoring
        await MainActor.run {
            startVPNMonitoring()
        }
    }
    
    /// Update network statistics
    public func updateStatistics(bytesSent: Int64 = 0, bytesReceived: Int64 = 0, downloadSpeed: Double = 0, uploadSpeed: Double = 0, connectionSuccess: Bool = true, usedProxy: Bool = false) {
        networkStatistics.totalBytesSent += bytesSent
        networkStatistics.totalBytesReceived += bytesReceived
        networkStatistics.totalConnections += 1
        
        if !connectionSuccess {
            networkStatistics.failedConnections += 1
        }
        
        if usedProxy {
            networkStatistics.proxyConnections += 1
        } else {
            networkStatistics.directConnections += 1
        }
        
        // Update peak speeds
        if downloadSpeed > networkStatistics.peakDownloadSpeed {
            networkStatistics.peakDownloadSpeed = downloadSpeed
        }
        if uploadSpeed > networkStatistics.peakUploadSpeed {
            networkStatistics.peakUploadSpeed = uploadSpeed
        }
        
        // Update average speeds (simple moving average)
        let totalConnections = Double(networkStatistics.totalConnections)
        networkStatistics.averageDownloadSpeed = (networkStatistics.averageDownloadSpeed * (totalConnections - 1) + downloadSpeed) / totalConnections
        networkStatistics.averageUploadSpeed = (networkStatistics.averageUploadSpeed * (totalConnections - 1) + uploadSpeed) / totalConnections
        
        networkStatistics.recordedAt = Date()
        
        saveStatistics()
    }
    
    /// Reset statistics
    public func resetStatistics() {
        networkStatistics = NetworkStatistics()
        saveStatistics()
    }
    
    /// Create URLSession configuration with current settings
    public func createURLSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        
        // Set timeout
        config.timeoutIntervalForRequest = configuration.timeout
        config.timeoutIntervalForResource = configuration.timeout * 2
        
        // Configure proxy if enabled
        if let proxy = getActiveProxy(), proxy.isValid {
            var proxyDict: [String: Any] = [:]
            
            switch proxy.type {
            case .http, .https:
                proxyDict[kCFNetworkProxiesHTTPEnable as String] = 1
                proxyDict[kCFNetworkProxiesHTTPProxy as String] = proxy.host
                proxyDict[kCFNetworkProxiesHTTPPort as String] = proxy.port
                proxyDict[kCFNetworkProxiesHTTPSEnable as String] = 1
                proxyDict[kCFNetworkProxiesHTTPSProxy as String] = proxy.host
                proxyDict[kCFNetworkProxiesHTTPSPort as String] = proxy.port
                
            case .socks5:
                proxyDict[kCFNetworkProxiesSOCKSEnable as String] = 1
                proxyDict[kCFNetworkProxiesSOCKSProxy as String] = proxy.host
                proxyDict[kCFNetworkProxiesSOCKSPort as String] = proxy.port
                
            case .system:
                proxyDict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
                
            case .none:
                break
            }
            
            config.connectionProxyDictionary = proxyDict
        }
        
        // Configure HTTP additional headers
        config.httpAdditionalHeaders = [
            "User-Agent": configuration.headersCookiesConfig.userAgent,
            "Accept-Language": configuration.headersCookiesConfig.acceptLanguage
        ]
        
        // Configure redirects
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpMaximumConnectionsPerHost = 6
        
        return config
    }
    
    // MARK: - General Configuration Updates
    
    /// Update timeout value
    public func updateTimeout(_ timeout: TimeInterval) {
        configuration.timeout = timeout
        saveConfiguration()
    }
    
    /// Update retry attempts
    public func updateRetryAttempts(_ attempts: Int) {
        configuration.retryAttempts = attempts
        saveConfiguration()
    }
    
    /// Update follow redirects setting
    public func updateFollowRedirects(_ follow: Bool) {
        configuration.followRedirects = follow
        saveConfiguration()
    }
    
    /// Update max redirects
    public func updateMaxRedirects(_ max: Int) {
        configuration.maxRedirects = max
        saveConfiguration()
    }
    
    // MARK: - Cleanup
    
    deinit {
        networkMonitor?.cancel()
        vpnMonitorTimer?.invalidate()
        mirrorCheckTimer?.invalidate()
    }
}
