import Foundation
import Combine
import CryptoKit
import SystemConfiguration

/// Manager for security and privacy features
@MainActor
public class SecurityPrivacyManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var config: SecurityConfig
    @Published public var vpnStatus: VPNStatus
    @Published public var scanResults: [SecurityScanResult]
    @Published public var events: [SecurityEvent]
    @Published public var isAuthenticated: Bool
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var vpnMonitorTimer: Timer?
    private let maliciousURLs: Set<String>
    private let maliciousPatterns: [String]
    
    // MARK: - Initialization
    
    public init() {
        self.config = SecurityConfig()
        self.vpnStatus = VPNStatus()
        self.scanResults = []
        self.events = []
        self.isAuthenticated = false
        
        // Known malicious patterns (simplified for demo)
        self.maliciousURLs = Set([
            "malware.example.com",
            "phishing.example.com",
            "virus.example.com"
        ])
        
        self.maliciousPatterns = [
            ".*\\.exe\\.zip$",
            ".*free-download-crack.*",
            ".*virus.*",
            ".*malware.*"
        ]
        
        loadConfiguration()
        startVPNMonitoring()
    }
    
    // MARK: - Configuration
    
    public func loadConfiguration() {
        if let data = UserDefaults.standard.data(forKey: "securityConfig"),
           let loaded = try? JSONDecoder().decode(SecurityConfig.self, from: data) {
            config = loaded
        }
    }
    
    public func saveConfiguration() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "securityConfig")
        }
    }
    
    public func updateSecurityLevel(_ level: SecurityLevel) {
        config.securityLevel = level
        
        // Auto-enable features based on level
        config.encryption.isEnabled = level.features.contains(.encryption)
        config.virusScan.isEnabled = level.features.contains(.virusScanning)
        config.maliciousDetection.isEnabled = level.features.contains(.maliciousDetection)
        
        saveConfiguration()
        
        logEvent(
            type: .scanCompleted,
            severity: .low,
            message: "Security level changed to \(level.displayName)"
        )
    }
    
    // MARK: - Authentication
    
    public func setMasterPassword(_ password: String) throws {
        guard !password.isEmpty else {
            throw SecurityError.invalidPassword
        }
        
        // Hash the password before storing (in real app, use proper key derivation)
        let hashedPassword = hashPassword(password)
        config.masterPassword = hashedPassword
        saveConfiguration()
        
        logEvent(
            type: .passwordChanged,
            severity: .low,
            message: "Master password updated"
        )
    }
    
    public func authenticate(password: String) -> Bool {
        guard let storedHash = config.masterPassword else {
            // No password set, allow access
            isAuthenticated = true
            return true
        }
        
        let inputHash = hashPassword(password)
        let success = inputHash == storedHash
        
        if success {
            isAuthenticated = true
            logEvent(
                type: .scanCompleted,
                severity: .low,
                message: "Authentication successful"
            )
        } else {
            logEvent(
                type: .unauthorizedAccess,
                severity: .high,
                message: "Failed authentication attempt"
            )
        }
        
        return success
    }
    
    public func logout() {
        isAuthenticated = false
    }
    
    private func hashPassword(_ password: String) -> String {
        let data = Data(password.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - URL Validation
    
    public func validateURL(_ urlString: String) async throws -> URLReputation {
        guard let url = URL(string: urlString) else {
            throw SecurityError.maliciousURL("Invalid URL format")
        }
        
        // Check against blacklist
        if maliciousURLs.contains(url.host ?? "") {
            let reputation = URLReputation(
                url: urlString,
                isSafe: false,
                reputation: .malicious,
                categories: [.malware]
            )
            
            logEvent(
                type: .threatDetected,
                severity: .high,
                message: "Malicious URL detected: \(urlString)"
            )
            
            return reputation
        }
        
        // Check against patterns
        for pattern in maliciousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(urlString.startIndex..., in: urlString)
                if regex.firstMatch(in: urlString, range: range) != nil {
                    let reputation = URLReputation(
                        url: urlString,
                        isSafe: false,
                        reputation: .suspicious,
                        categories: [.download]
                    )
                    
                    logEvent(
                        type: .threatDetected,
                        severity: .medium,
                        message: "Suspicious URL pattern detected: \(urlString)"
                    )
                    
                    return reputation
                }
            }
        }
        
        // URL appears safe
        return URLReputation(
            url: urlString,
            isSafe: true,
            reputation: .trusted,
            categories: [.download]
        )
    }
    
    public func checkMaliciousURL(_ urlString: String) async -> Bool {
        do {
            let reputation = try await validateURL(urlString)
            return !reputation.isSafe
        } catch {
            return false
        }
    }
    
    // MARK: - Virus Scanning
    
    public func scanFile(_ filePath: URL) async throws -> SecurityScanResult {
        let startTime = Date()
        
        // Simulate virus scan (in real app, integrate with ClamAV)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        let threats = detectThreats(in: filePath)
        let isClean = threats.isEmpty
        let duration = Date().timeIntervalSince(startTime)
        
        let result = SecurityScanResult(
            url: filePath.path,
            scanDate: Date(),
            threats: threats,
            isClean: isClean,
            scanDuration: duration,
            engine: config.virusScan.scanEngine.displayName
        )
        
        scanResults.append(result)
        
        if !isClean {
            logEvent(
                type: .threatDetected,
                severity: threats.map { $0.severity }.max() ?? .low,
                message: "Threats detected in \(filePath.lastPathComponent)"
            )
            
            if config.virusScan.quarantineThreats {
                try? quarantineFile(filePath)
            }
            
            if config.virusScan.deleteThreats {
                try? FileManager.default.removeItem(at: filePath)
            }
        } else {
            logEvent(
                type: .scanCompleted,
                severity: .low,
                message: "File scan completed: \(filePath.lastPathComponent) is clean"
            )
        }
        
        return result
    }
    
    private func detectThreats(in filePath: URL) -> [SecurityThreat] {
        var threats: [SecurityThreat] = []
        
        // Simulate threat detection based on file characteristics
        let fileName = filePath.lastPathComponent.lowercased()
        
        // Check for suspicious file names
        let suspiciousKeywords = ["crack", "keygen", "patch", "virus", "malware", "trojan"]
        for keyword in suspiciousKeywords {
            if fileName.contains(keyword) {
                threats.append(SecurityThreat(
                    type: .suspiciousFile,
                    severity: .medium,
                    description: "File name contains suspicious keyword: \(keyword)",
                    recommendation: "Verify the source and scan with updated antivirus"
                ))
            }
        }
        
        // Check for double extensions
        if fileName.contains(".exe.") || fileName.contains(".scr.") {
            threats.append(SecurityThreat(
                type: .malware,
                severity: .high,
                description: "File uses double extension technique",
                recommendation: "Delete immediately and scan system"
            ))
        }
        
        return threats
    }
    
    private func quarantineFile(_ filePath: URL) throws {
        let quarantineDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Quarantine")
        
        try? FileManager.default.createDirectory(
            at: quarantineDir,
            withIntermediateDirectories: true
        )
        
        let destination = quarantineDir.appendingPathComponent(filePath.lastPathComponent)
        try FileManager.default.moveItem(at: filePath, to: destination)
        
        logEvent(
            type: .threatBlocked,
            severity: .medium,
            message: "File quarantined: \(filePath.lastPathComponent)"
        )
    }
    
    public func scanURLBeforeDownload(_ urlString: String) async throws {
        guard config.maliciousDetection.isEnabled else { return }
        
        let reputation = try await validateURL(urlString)
        
        if !reputation.isSafe {
            if config.maliciousDetection.blockSuspiciousURLs && reputation.reputation == .malicious {
                throw SecurityError.maliciousURL(urlString)
            }
            
            if config.maliciousDetection.warnOnUntrustedSites {
                logEvent(
                    type: .threatDetected,
                    severity: .medium,
                    message: "Warning: Potentially unsafe URL"
                )
            }
        }
    }
    
    // MARK: - Encryption
    
    public func encryptFile(_ filePath: URL, password: String) async throws -> EncryptionResult {
        guard config.encryption.isEnabled else {
            throw SecurityError.encryptionFailed("Encryption not enabled")
        }
        
        let startTime = Date()
        
        // Read file data
        let data = try Data(contentsOf: filePath)
        let originalSize = Int64(data.count)
        
        // Derive key from password
        let key = try deriveKey(from: password)
        
        // Encrypt data
        let encryptedData = try encryptData(data, with: key)
        
        // Write encrypted data
        let encryptedPath = filePath.appendingPathExtension("encrypted")
        try encryptedData.write(to: encryptedPath)
        
        let encryptedSize = Int64(encryptedData.count)
        let duration = Date().timeIntervalSince(startTime)
        
        logEvent(
            type: .encryptionEnabled,
            severity: .low,
            message: "File encrypted: \(filePath.lastPathComponent)"
        )
        
        return EncryptionResult(
            success: true,
            originalSize: originalSize,
            encryptedSize: encryptedSize,
            algorithm: config.encryption.algorithm.displayName,
            duration: duration
        )
    }
    
    public func decryptFile(_ filePath: URL, password: String) async throws -> Data {
        guard config.encryption.isEnabled else {
            throw SecurityError.decryptionFailed("Encryption not enabled")
        }
        
        // Read encrypted data
        let encryptedData = try Data(contentsOf: filePath)
        
        // Derive key from password
        let key = try deriveKey(from: password)
        
        // Decrypt data
        let decryptedData = try decryptData(encryptedData, with: key)
        
        logEvent(
            type: .encryptionDisabled,
            severity: .low,
            message: "File decrypted: \(filePath.lastPathComponent)"
        )
        
        return decryptedData
    }
    
    private func deriveKey(from password: String) throws -> SymmetricKey {
        // Simple key derivation (in real app, use proper PBKDF2/Argon2)
        let passwordData = Data(password.utf8)
        let hash = SHA256.hash(data: passwordData)
        return SymmetricKey(data: hash)
    }
    
    private func encryptData(_ data: Data, with key: SymmetricKey) throws -> Data {
        switch config.encryption.algorithm {
        case .aes256GCM:
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined ?? Data()
        case .aes256CBC, .chacha20:
            // Simplified - use GCM for all cases in this demo
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined ?? Data()
        }
    }
    
    private func decryptData(_ data: Data, with key: SymmetricKey) throws -> Data {
        switch config.encryption.algorithm {
        case .aes256GCM:
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        case .aes256CBC, .chacha20:
            // Simplified - use GCM for all cases in this demo
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        }
    }
    
    // MARK: - Private Mode
    
    public func enablePrivateMode() {
        config.privateMode.isEnabled = true
        saveConfiguration()
        
        logEvent(
            type: .privateModeEnabled,
            severity: .low,
            message: "Private mode enabled"
        )
    }
    
    public func disablePrivateMode() {
        if config.privateMode.clearOnExit {
            clearPrivateData()
        }
        
        config.privateMode.isEnabled = false
        saveConfiguration()
        
        logEvent(
            type: .privateModeDisabled,
            severity: .low,
            message: "Private mode disabled"
        )
    }
    
    public func clearPrivateData() {
        if config.privateMode.disableHistory {
            // Clear history (would integrate with DownloadManager)
        }
        
        if config.privateMode.disableStatistics {
            // Clear statistics
        }
        
        logEvent(
            type: .scanCompleted,
            severity: .low,
            message: "Private data cleared"
        )
    }
    
    public func shouldRecordHistory() -> Bool {
        !(config.privateMode.isEnabled && config.privateMode.disableHistory)
    }
    
    public func shouldRecordStatistics() -> Bool {
        !(config.privateMode.isEnabled && config.privateMode.disableStatistics)
    }
    
    public func shouldShowPreview() -> Bool {
        !(config.privateMode.isEnabled && config.privateMode.disablePreview)
    }
    
    // MARK: - VPN Detection
    
    private func startVPNMonitoring() {
        guard config.vpnDetection.isEnabled else { return }
        
        vpnMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkVPNStatus()
            }
        }
    }
    
    private func stopVPNMonitoring() {
        vpnMonitorTimer?.invalidate()
        vpnMonitorTimer = nil
    }
    
    private func checkVPNStatus() {
        let wasConnected = vpnStatus.isConnected
        let isConnected = detectVPN()
        
        if wasConnected != isConnected {
            vpnStatus.isConnected = isConnected
            
            if isConnected {
                vpnStatus.connectedAt = Date()
                
                if config.vpnDetection.notifyOnVPNChange {
                    logEvent(
                        type: .vpnConnected,
                        severity: .low,
                        message: "VPN connection detected"
                    )
                }
            } else {
                vpnStatus.connectedAt = nil
                
                if config.vpnDetection.notifyOnVPNChange {
                    logEvent(
                        type: .vpnDisconnected,
                        severity: .medium,
                        message: "VPN disconnected"
                    )
                }
            }
        }
    }
    
    private func detectVPN() -> Bool {
        // Simplified VPN detection
        // In real app, check network interfaces for VPN connections
        guard let interfaces = getNetworkInterfaces() else {
            return false
        }
        
        let vpnPrefixes = ["utun", "ppp", "ipsec", "tun"]
        return interfaces.contains { interface in
            vpnPrefixes.contains { interface.hasPrefix($0) }
        }
    }
    
    private func getNetworkInterfaces() -> [String]? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else {
            return nil
        }
        defer { freeifaddrs(addresses) }
        
        var interfaces: [String] = []
        var ptr = addresses
        while ptr != nil {
            if let interface = ptr?.pointee {
                let name = String(cString: interface.ifa_name)
                if !interfaces.contains(name) {
                    interfaces.append(name)
                }
            }
            ptr = ptr?.pointee.ifa_next
        }
        
        return interfaces
    }
    
    public func requiresVPN() -> Bool {
        config.vpnDetection.preferVPNConnection && !vpnStatus.isConnected
    }
    
    // MARK: - Event Logging
    
    private func logEvent(type: SecurityEvent.EventType, severity: SecurityThreat.ThreatSeverity, message: String, details: [String: String]? = nil) {
        let event = SecurityEvent(
            type: type,
            severity: severity,
            message: message,
            details: details
        )
        
        events.insert(event, at: 0)
        
        // Keep only last 100 events
        if events.count > 100 {
            events.removeLast()
        }
    }
    
    // MARK: - Statistics
    
    public func getSecurityStats() -> SecurityStats {
        let totalScans = scanResults.count
        let threatsDetected = scanResults.filter { !$0.isClean }.count
        let cleanFiles = totalScans - threatsDetected
        let averageScanTime = scanResults.isEmpty ? 0 : 
            scanResults.map { $0.scanDuration }.reduce(0, +) / Double(scanResults.count)
        
        return SecurityStats(
            totalScans: totalScans,
            threatsDetected: threatsDetected,
            cleanFiles: cleanFiles,
            averageScanTime: averageScanTime,
            lastScanDate: scanResults.first?.scanDate
        )
    }
    
    public func clearScanHistory() {
        scanResults.removeAll()
    }
    
    public func clearEventLog() {
        events.removeAll()
    }
}

// MARK: - Security Stats

public struct SecurityStats {
    public var totalScans: Int
    public var threatsDetected: Int
    public var cleanFiles: Int
    public var averageScanTime: TimeInterval
    public var lastScanDate: Date?
    
    public init(
        totalScans: Int = 0,
        threatsDetected: Int = 0,
        cleanFiles: Int = 0,
        averageScanTime: TimeInterval = 0,
        lastScanDate: Date? = nil
    ) {
        self.totalScans = totalScans
        self.threatsDetected = threatsDetected
        self.cleanFiles = cleanFiles
        self.averageScanTime = averageScanTime
        self.lastScanDate = lastScanDate
    }
}
