import XCTest
@testable import DownloadManager

@MainActor
final class SecurityPrivacyTests: XCTestCase {
    
    var manager: SecurityPrivacyManager!
    
    override func setUp() async throws {
        manager = SecurityPrivacyManager()
    }
    
    override func tearDown() async throws {
        manager = nil
    }
    
    // MARK: - Security Level Tests
    
    func testSecurityLevelDefault() {
        XCTAssertEqual(manager.config.securityLevel, .standard)
    }
    
    func testSecurityLevelDisplayNames() {
        XCTAssertEqual(SecurityLevel.none.displayName, "None")
        XCTAssertEqual(SecurityLevel.basic.displayName, "Basic")
        XCTAssertEqual(SecurityLevel.standard.displayName, "Standard")
        XCTAssertEqual(SecurityLevel.high.displayName, "High")
        XCTAssertEqual(SecurityLevel.maximum.displayName, "Maximum")
    }
    
    func testSecurityLevelFeatures() {
        XCTAssertEqual(SecurityLevel.none.features, [])
        XCTAssertEqual(SecurityLevel.basic.features, [.urlValidation])
        XCTAssertEqual(SecurityLevel.standard.features, [.urlValidation, .maliciousDetection])
        XCTAssertEqual(SecurityLevel.high.features, [.urlValidation, .maliciousDetection, .virusScanning])
        XCTAssertEqual(SecurityLevel.maximum.features, [.urlValidation, .maliciousDetection, .virusScanning, .encryption])
    }
    
    func testUpdateSecurityLevel() {
        manager.updateSecurityLevel(.maximum)
        
        XCTAssertEqual(manager.config.securityLevel, .maximum)
        XCTAssertTrue(manager.config.encryption.isEnabled)
        XCTAssertTrue(manager.config.virusScan.isEnabled)
        XCTAssertTrue(manager.config.maliciousDetection.isEnabled)
    }
    
    func testSecurityLevelIcons() {
        XCTAssertEqual(SecurityLevel.none.icon, "shield.slash")
        XCTAssertEqual(SecurityLevel.basic.icon, "shield")
        XCTAssertEqual(SecurityLevel.standard.icon, "shield.lefthalf.filled")
        XCTAssertEqual(SecurityLevel.high.icon, "shield.fill")
        XCTAssertEqual(SecurityLevel.maximum.icon, "checkmark.shield.fill")
    }
    
    // MARK: - Security Feature Tests
    
    func testSecurityFeatureDisplayNames() {
        XCTAssertEqual(SecurityFeature.urlValidation.displayName, "URL Validation")
        XCTAssertEqual(SecurityFeature.maliciousDetection.displayName, "Malicious URL Detection")
        XCTAssertEqual(SecurityFeature.virusScanning.displayName, "Virus Scanning")
        XCTAssertEqual(SecurityFeature.encryption.displayName, "End-to-End Encryption")
        XCTAssertEqual(SecurityFeature.passwordProtection.displayName, "Password Protection")
        XCTAssertEqual(SecurityFeature.privateMode.displayName, "Private Mode")
        XCTAssertEqual(SecurityFeature.vpnDetection.displayName, "VPN Detection")
    }
    
    func testIsFeatureEnabled() {
        manager.updateSecurityLevel(.standard)
        
        XCTAssertTrue(manager.config.isFeatureEnabled(.urlValidation))
        XCTAssertTrue(manager.config.isFeatureEnabled(.maliciousDetection))
        XCTAssertFalse(manager.config.isFeatureEnabled(.virusScanning))
        XCTAssertFalse(manager.config.isFeatureEnabled(.encryption))
    }
    
    // MARK: - Encryption Config Tests
    
    func testEncryptionConfigDefault() {
        let config = EncryptionConfig()
        
        XCTAssertFalse(config.isEnabled)
        XCTAssertEqual(config.algorithm, .aes256GCM)
        XCTAssertEqual(config.keyDerivation, .pbkdf2)
        XCTAssertFalse(config.encryptFilenames)
        XCTAssertFalse(config.encryptMetadata)
    }
    
    func testEncryptionAlgorithms() {
        XCTAssertEqual(EncryptionConfig.EncryptionAlgorithm.aes256GCM.displayName, "AES-256-GCM")
        XCTAssertEqual(EncryptionConfig.EncryptionAlgorithm.aes256CBC.displayName, "AES-256-CBC")
        XCTAssertEqual(EncryptionConfig.EncryptionAlgorithm.chacha20.displayName, "ChaCha20-Poly1305")
        
        XCTAssertEqual(EncryptionConfig.EncryptionAlgorithm.aes256GCM.keySize, 32)
        XCTAssertEqual(EncryptionConfig.EncryptionAlgorithm.aes256CBC.keySize, 32)
        XCTAssertEqual(EncryptionConfig.EncryptionAlgorithm.chacha20.keySize, 32)
    }
    
    func testKeyDerivationMethods() {
        XCTAssertEqual(EncryptionConfig.KeyDerivationMethod.pbkdf2.displayName, "PBKDF2")
        XCTAssertEqual(EncryptionConfig.KeyDerivationMethod.argon2.displayName, "Argon2")
        XCTAssertEqual(EncryptionConfig.KeyDerivationMethod.scrypt.displayName, "Scrypt")
    }
    
    func testEncryptionConfigCodable() throws {
        let config = EncryptionConfig(
            isEnabled: true,
            algorithm: .chacha20,
            keyDerivation: .argon2,
            encryptFilenames: true,
            encryptMetadata: true
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(EncryptionConfig.self, from: data)
        
        XCTAssertEqual(decoded.isEnabled, config.isEnabled)
        XCTAssertEqual(decoded.algorithm, config.algorithm)
        XCTAssertEqual(decoded.keyDerivation, config.keyDerivation)
        XCTAssertEqual(decoded.encryptFilenames, config.encryptFilenames)
        XCTAssertEqual(decoded.encryptMetadata, config.encryptMetadata)
    }
    
    // MARK: - Virus Scan Config Tests
    
    func testVirusScanConfigDefault() {
        let config = VirusScanConfig()
        
        XCTAssertFalse(config.isEnabled)
        XCTAssertEqual(config.scanEngine, .clamav)
        XCTAssertTrue(config.scanAfterDownload)
        XCTAssertTrue(config.scanBeforeOpen)
        XCTAssertTrue(config.quarantineThreats)
        XCTAssertFalse(config.deleteThreats)
    }
    
    func testVirusScanEngines() {
        XCTAssertEqual(VirusScanConfig.ScanEngine.clamav.displayName, "ClamAV")
        XCTAssertEqual(VirusScanConfig.ScanEngine.macos.displayName, "macOS XProtect")
        XCTAssertEqual(VirusScanConfig.ScanEngine.custom.displayName, "Custom")
    }
    
    func testVirusScanConfigCodable() throws {
        let config = VirusScanConfig(
            isEnabled: true,
            scanEngine: .macos,
            scanAfterDownload: false,
            scanBeforeOpen: false,
            quarantineThreats: false,
            deleteThreats: true
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VirusScanConfig.self, from: data)
        
        XCTAssertEqual(decoded.isEnabled, config.isEnabled)
        XCTAssertEqual(decoded.scanEngine, config.scanEngine)
        XCTAssertEqual(decoded.scanAfterDownload, config.scanAfterDownload)
        XCTAssertEqual(decoded.scanBeforeOpen, config.scanBeforeOpen)
        XCTAssertEqual(decoded.quarantineThreats, config.quarantineThreats)
        XCTAssertEqual(decoded.deleteThreats, config.deleteThreats)
    }
    
    // MARK: - Malicious Detection Config Tests
    
    func testMaliciousDetectionConfigDefault() {
        let config = MaliciousDetectionConfig()
        
        XCTAssertFalse(config.isEnabled)
        XCTAssertTrue(config.checkBlacklist)
        XCTAssertTrue(config.checkReputation)
        XCTAssertFalse(config.blockSuspiciousURLs)
        XCTAssertTrue(config.warnOnUntrustedSites)
    }
    
    func testMaliciousDetectionConfigCodable() throws {
        let config = MaliciousDetectionConfig(
            isEnabled: true,
            checkBlacklist: false,
            checkReputation: false,
            blockSuspiciousURLs: true,
            warnOnUntrustedSites: false
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MaliciousDetectionConfig.self, from: data)
        
        XCTAssertEqual(decoded.isEnabled, config.isEnabled)
        XCTAssertEqual(decoded.checkBlacklist, config.checkBlacklist)
        XCTAssertEqual(decoded.checkReputation, config.checkReputation)
        XCTAssertEqual(decoded.blockSuspiciousURLs, config.blockSuspiciousURLs)
        XCTAssertEqual(decoded.warnOnUntrustedSites, config.warnOnUntrustedSites)
    }
    
    // MARK: - Private Mode Config Tests
    
    func testPrivateModeConfigDefault() {
        let config = PrivateModeConfig()
        
        XCTAssertFalse(config.isEnabled)
        XCTAssertTrue(config.disableHistory)
        XCTAssertTrue(config.disableStatistics)
        XCTAssertTrue(config.clearOnExit)
        XCTAssertFalse(config.disablePreview)
    }
    
    func testPrivateModeConfigCodable() throws {
        let config = PrivateModeConfig(
            isEnabled: true,
            disableHistory: false,
            disableStatistics: false,
            clearOnExit: false,
            disablePreview: true
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PrivateModeConfig.self, from: data)
        
        XCTAssertEqual(decoded.isEnabled, config.isEnabled)
        XCTAssertEqual(decoded.disableHistory, config.disableHistory)
        XCTAssertEqual(decoded.disableStatistics, config.disableStatistics)
        XCTAssertEqual(decoded.clearOnExit, config.clearOnExit)
        XCTAssertEqual(decoded.disablePreview, config.disablePreview)
    }
    
    // MARK: - VPN Detection Config Tests
    
    func testVPNDetectionConfigDefault() {
        let config = VPNDetectionConfig()
        
        XCTAssertFalse(config.isEnabled)
        XCTAssertFalse(config.pauseOnVPNDisconnect)
        XCTAssertFalse(config.resumeOnVPNConnect)
        XCTAssertFalse(config.preferVPNConnection)
        XCTAssertTrue(config.notifyOnVPNChange)
    }
    
    func testVPNDetectionConfigCodable() throws {
        let config = VPNDetectionConfig(
            isEnabled: true,
            pauseOnVPNDisconnect: true,
            resumeOnVPNConnect: true,
            preferVPNConnection: true,
            notifyOnVPNChange: false
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VPNDetectionConfig.self, from: data)
        
        XCTAssertEqual(decoded.isEnabled, config.isEnabled)
        XCTAssertEqual(decoded.pauseOnVPNDisconnect, config.pauseOnVPNDisconnect)
        XCTAssertEqual(decoded.resumeOnVPNConnect, config.resumeOnVPNConnect)
        XCTAssertEqual(decoded.preferVPNConnection, config.preferVPNConnection)
        XCTAssertEqual(decoded.notifyOnVPNChange, config.notifyOnVPNChange)
    }
    
    // MARK: - Security Config Tests
    
    func testSecurityConfigDefault() {
        let config = SecurityConfig()
        
        XCTAssertEqual(config.securityLevel, .standard)
        XCTAssertFalse(config.encryption.isEnabled)
        XCTAssertFalse(config.virusScan.isEnabled)
        XCTAssertFalse(config.maliciousDetection.isEnabled)
        XCTAssertFalse(config.privateMode.isEnabled)
        XCTAssertFalse(config.vpnDetection.isEnabled)
        XCTAssertNil(config.masterPassword)
    }
    
    func testSecurityConfigCodable() throws {
        let config = SecurityConfig(
            securityLevel: .maximum,
            encryption: EncryptionConfig(isEnabled: true),
            virusScan: VirusScanConfig(isEnabled: true),
            maliciousDetection: MaliciousDetectionConfig(isEnabled: true),
            privateMode: PrivateModeConfig(isEnabled: true),
            vpnDetection: VPNDetectionConfig(isEnabled: true),
            masterPassword: "hashed_password"
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SecurityConfig.self, from: data)
        
        XCTAssertEqual(decoded.securityLevel, config.securityLevel)
        XCTAssertEqual(decoded.encryption.isEnabled, config.encryption.isEnabled)
        XCTAssertEqual(decoded.virusScan.isEnabled, config.virusScan.isEnabled)
        XCTAssertEqual(decoded.maliciousDetection.isEnabled, config.maliciousDetection.isEnabled)
        XCTAssertEqual(decoded.privateMode.isEnabled, config.privateMode.isEnabled)
        XCTAssertEqual(decoded.vpnDetection.isEnabled, config.vpnDetection.isEnabled)
        XCTAssertEqual(decoded.masterPassword, config.masterPassword)
    }
    
    // MARK: - Security Threat Tests
    
    func testSecurityThreatTypes() {
        XCTAssertEqual(SecurityThreat.ThreatType.virus.displayName, "Virus")
        XCTAssertEqual(SecurityThreat.ThreatType.malware.displayName, "Malware")
        XCTAssertEqual(SecurityThreat.ThreatType.trojan.displayName, "Trojan")
        XCTAssertEqual(SecurityThreat.ThreatType.ransomware.displayName, "Ransomware")
        XCTAssertEqual(SecurityThreat.ThreatType.spyware.displayName, "Spyware")
        XCTAssertEqual(SecurityThreat.ThreatType.adware.displayName, "Adware")
        XCTAssertEqual(SecurityThreat.ThreatType.phishing.displayName, "Phishing")
        XCTAssertEqual(SecurityThreat.ThreatType.maliciousURL.displayName, "Malicious URL")
        XCTAssertEqual(SecurityThreat.ThreatType.suspiciousFile.displayName, "Suspicious File")
    }
    
    func testThreatSeverity() {
        XCTAssertEqual(SecurityThreat.ThreatSeverity.low.displayName, "Low")
        XCTAssertEqual(SecurityThreat.ThreatSeverity.medium.displayName, "Medium")
        XCTAssertEqual(SecurityThreat.ThreatSeverity.high.displayName, "High")
        XCTAssertEqual(SecurityThreat.ThreatSeverity.critical.displayName, "Critical")
        
        XCTAssertLessThan(SecurityThreat.ThreatSeverity.low, .medium)
        XCTAssertLessThan(SecurityThreat.ThreatSeverity.medium, .high)
        XCTAssertLessThan(SecurityThreat.ThreatSeverity.high, .critical)
    }
    
    func testSecurityThreatCodable() throws {
        let threat = SecurityThreat(
            type: .virus,
            severity: .high,
            description: "Test virus detected",
            recommendation: "Delete immediately"
        )
        
        let data = try JSONEncoder().encode(threat)
        let decoded = try JSONDecoder().decode(SecurityThreat.self, from: data)
        
        XCTAssertEqual(decoded.type, threat.type)
        XCTAssertEqual(decoded.severity, threat.severity)
        XCTAssertEqual(decoded.description, threat.description)
        XCTAssertEqual(decoded.recommendation, threat.recommendation)
    }
    
    // MARK: - Threat Level Tests
    
    func testThreatLevel() {
        XCTAssertEqual(ThreatLevel.none.displayName, "None")
        XCTAssertEqual(ThreatLevel.low.displayName, "Low")
        XCTAssertEqual(ThreatLevel.medium.displayName, "Medium")
        XCTAssertEqual(ThreatLevel.high.displayName, "High")
        XCTAssertEqual(ThreatLevel.critical.displayName, "Critical")
    }
    
    func testThreatLevelFromSeverity() {
        XCTAssertEqual(ThreatLevel(from: .low), .low)
        XCTAssertEqual(ThreatLevel(from: .medium), .medium)
        XCTAssertEqual(ThreatLevel(from: .high), .high)
        XCTAssertEqual(ThreatLevel(from: .critical), .critical)
    }
    
    // MARK: - Security Scan Result Tests
    
    func testSecurityScanResultClean() {
        let result = SecurityScanResult(
            url: "/path/to/file.txt",
            threats: [],
            isClean: true,
            scanDuration: 0.5,
            engine: "Test Scanner"
        )
        
        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.threatLevel, .none)
        XCTAssertEqual(result.threats.count, 0)
    }
    
    func testSecurityScanResultWithThreats() {
        let threat = SecurityThreat(
            type: .virus,
            severity: .high,
            description: "Test virus",
            recommendation: "Delete"
        )
        
        let result = SecurityScanResult(
            url: "/path/to/file.txt",
            threats: [threat],
            isClean: false,
            scanDuration: 0.5,
            engine: "Test Scanner"
        )
        
        XCTAssertFalse(result.isClean)
        XCTAssertEqual(result.threatLevel, .high)
        XCTAssertEqual(result.threats.count, 1)
    }
    
    func testSecurityScanResultCodable() throws {
        let result = SecurityScanResult(
            url: "/path/to/file.txt",
            threats: [],
            isClean: true,
            scanDuration: 0.5,
            engine: "Test Scanner"
        )
        
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(SecurityScanResult.self, from: data)
        
        XCTAssertEqual(decoded.url, result.url)
        XCTAssertEqual(decoded.isClean, result.isClean)
        XCTAssertEqual(decoded.scanDuration, result.scanDuration, accuracy: 0.01)
        XCTAssertEqual(decoded.engine, result.engine)
    }
    
    // MARK: - URL Reputation Tests
    
    func testURLReputationTypes() {
        XCTAssertEqual(URLReputation.Reputation.trusted.displayName, "Trusted")
        XCTAssertEqual(URLReputation.Reputation.neutral.displayName, "Neutral")
        XCTAssertEqual(URLReputation.Reputation.suspicious.displayName, "Suspicious")
        XCTAssertEqual(URLReputation.Reputation.malicious.displayName, "Malicious")
        XCTAssertEqual(URLReputation.Reputation.unknown.displayName, "Unknown")
    }
    
    func testURLReputationCategories() {
        XCTAssertEqual(URLReputation.URLCategory.download.displayName, "Download")
        XCTAssertEqual(URLReputation.URLCategory.streaming.displayName, "Streaming")
        XCTAssertEqual(URLReputation.URLCategory.fileSharing.displayName, "File Sharing")
        XCTAssertEqual(URLReputation.URLCategory.cloudStorage.displayName, "Cloud Storage")
        XCTAssertEqual(URLReputation.URLCategory.phishing.displayName, "Phishing")
        XCTAssertEqual(URLReputation.URLCategory.malware.displayName, "Malware")
    }
    
    func testURLReputationDefault() {
        let reputation = URLReputation(url: "https://example.com")
        
        XCTAssertTrue(reputation.isSafe)
        XCTAssertEqual(reputation.reputation, .neutral)
        XCTAssertEqual(reputation.categories.count, 0)
    }
    
    func testURLReputationCodable() throws {
        let reputation = URLReputation(
            url: "https://example.com",
            isSafe: false,
            reputation: .malicious,
            categories: [.malware, .phishing]
        )
        
        let data = try JSONEncoder().encode(reputation)
        let decoded = try JSONDecoder().decode(URLReputation.self, from: data)
        
        XCTAssertEqual(decoded.url, reputation.url)
        XCTAssertEqual(decoded.isSafe, reputation.isSafe)
        XCTAssertEqual(decoded.reputation, reputation.reputation)
        XCTAssertEqual(decoded.categories, reputation.categories)
    }
    
    // MARK: - VPN Status Tests
    
    func testVPNStatusDefault() {
        let status = VPNStatus()
        
        XCTAssertFalse(status.isConnected)
        XCTAssertNil(status.vpnName)
        XCTAssertNil(status.ipAddress)
        XCTAssertNil(status.location)
        XCTAssertNil(status.connectedAt)
    }
    
    func testVPNStatusConnected() {
        let date = Date()
        let status = VPNStatus(
            isConnected: true,
            vpnName: "Test VPN",
            ipAddress: "192.168.1.1",
            location: "US",
            connectedAt: date
        )
        
        XCTAssertTrue(status.isConnected)
        XCTAssertEqual(status.vpnName, "Test VPN")
        XCTAssertEqual(status.ipAddress, "192.168.1.1")
        XCTAssertEqual(status.location, "US")
        XCTAssertEqual(status.connectedAt, date)
    }
    
    func testVPNStatusCodable() throws {
        let status = VPNStatus(
            isConnected: true,
            vpnName: "Test VPN",
            ipAddress: "192.168.1.1",
            location: "US"
        )
        
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(VPNStatus.self, from: data)
        
        XCTAssertEqual(decoded.isConnected, status.isConnected)
        XCTAssertEqual(decoded.vpnName, status.vpnName)
        XCTAssertEqual(decoded.ipAddress, status.ipAddress)
        XCTAssertEqual(decoded.location, status.location)
    }
    
    // MARK: - Security Event Tests
    
    func testSecurityEventTypes() {
        XCTAssertEqual(SecurityEvent.EventType.threatDetected.displayName, "Threat Detected")
        XCTAssertEqual(SecurityEvent.EventType.threatBlocked.displayName, "Threat Blocked")
        XCTAssertEqual(SecurityEvent.EventType.scanCompleted.displayName, "Scan Completed")
        XCTAssertEqual(SecurityEvent.EventType.encryptionEnabled.displayName, "Encryption Enabled")
        XCTAssertEqual(SecurityEvent.EventType.privateModeEnabled.displayName, "Private Mode Enabled")
        XCTAssertEqual(SecurityEvent.EventType.vpnConnected.displayName, "VPN Connected")
    }
    
    func testSecurityEventCodable() throws {
        let event = SecurityEvent(
            type: .threatDetected,
            severity: .high,
            message: "Test threat detected",
            details: ["file": "test.exe"]
        )
        
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SecurityEvent.self, from: data)
        
        XCTAssertEqual(decoded.type, event.type)
        XCTAssertEqual(decoded.severity, event.severity)
        XCTAssertEqual(decoded.message, event.message)
        XCTAssertEqual(decoded.details?["file"], event.details?["file"])
    }
    
    // MARK: - Encryption Result Tests
    
    func testEncryptionResult() {
        let result = EncryptionResult(
            success: true,
            originalSize: 1024,
            encryptedSize: 1100,
            algorithm: "AES-256-GCM",
            duration: 0.5
        )
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.originalSize, 1024)
        XCTAssertEqual(result.encryptedSize, 1100)
        XCTAssertEqual(result.algorithm, "AES-256-GCM")
        XCTAssertEqual(result.duration, 0.5, accuracy: 0.01)
        XCTAssertNil(result.error)
    }
    
    func testEncryptionResultWithError() {
        let result = EncryptionResult(
            success: false,
            originalSize: 1024,
            encryptedSize: 0,
            algorithm: "AES-256-GCM",
            duration: 0.1,
            error: "Encryption failed"
        )
        
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Encryption failed")
    }
    
    func testEncryptionResultCodable() throws {
        let result = EncryptionResult(
            success: true,
            originalSize: 1024,
            encryptedSize: 1100,
            algorithm: "AES-256-GCM",
            duration: 0.5
        )
        
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(EncryptionResult.self, from: data)
        
        XCTAssertEqual(decoded.success, result.success)
        XCTAssertEqual(decoded.originalSize, result.originalSize)
        XCTAssertEqual(decoded.encryptedSize, result.encryptedSize)
        XCTAssertEqual(decoded.algorithm, result.algorithm)
        XCTAssertEqual(decoded.duration, result.duration, accuracy: 0.01)
    }
    
    // MARK: - Manager Authentication Tests
    
    func testSetMasterPassword() throws {
        try manager.setMasterPassword("test123")
        
        XCTAssertNotNil(manager.config.masterPassword)
        XCTAssertNotEqual(manager.config.masterPassword, "test123") // Should be hashed
    }
    
    func testAuthenticateSuccess() throws {
        try manager.setMasterPassword("test123")
        
        let success = manager.authenticate(password: "test123")
        
        XCTAssertTrue(success)
        XCTAssertTrue(manager.isAuthenticated)
    }
    
    func testAuthenticateFailure() throws {
        try manager.setMasterPassword("test123")
        
        let success = manager.authenticate(password: "wrong")
        
        XCTAssertFalse(success)
        XCTAssertFalse(manager.isAuthenticated)
    }
    
    func testAuthenticateWithoutPassword() {
        let success = manager.authenticate(password: "anything")
        
        XCTAssertTrue(success)
        XCTAssertTrue(manager.isAuthenticated)
    }
    
    func testLogout() throws {
        try manager.setMasterPassword("test123")
        _ = manager.authenticate(password: "test123")
        
        XCTAssertTrue(manager.isAuthenticated)
        
        manager.logout()
        
        XCTAssertFalse(manager.isAuthenticated)
    }
    
    // MARK: - URL Validation Tests
    
    func testValidateURLSafe() async throws {
        let reputation = try await manager.validateURL("https://example.com/file.zip")
        
        XCTAssertTrue(reputation.isSafe)
        XCTAssertEqual(reputation.reputation, .trusted)
    }
    
    func testValidateURLMalicious() async throws {
        let reputation = try await manager.validateURL("https://malware.example.com/file.exe")
        
        XCTAssertFalse(reputation.isSafe)
        XCTAssertEqual(reputation.reputation, .malicious)
    }
    
    func testValidateURLInvalid() async {
        do {
            _ = try await manager.validateURL("not a url")
            XCTFail("Should throw error for invalid URL")
        } catch {
            XCTAssertTrue(error is SecurityError)
        }
    }
    
    func testCheckMaliciousURL() async {
        let isMalicious = await manager.checkMaliciousURL("https://malware.example.com/file.exe")
        XCTAssertTrue(isMalicious)
        
        let isSafe = await manager.checkMaliciousURL("https://example.com/file.zip")
        XCTAssertFalse(isSafe)
    }
    
    // MARK: - Virus Scanning Tests
    
    func testScanFileClean() async throws {
        let testFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_clean.txt")
        
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        let result = try await manager.scanFile(testFile)
        
        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.threats.count, 0)
        XCTAssertGreaterThan(result.scanDuration, 0)
    }
    
    func testScanFileSuspicious() async throws {
        let testFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_crack.exe")
        
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        let result = try await manager.scanFile(testFile)
        
        XCTAssertFalse(result.isClean)
        XCTAssertGreaterThan(result.threats.count, 0)
    }
    
    func testScanResultsStored() async throws {
        let testFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_scan.txt")
        
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        let initialCount = manager.scanResults.count
        
        _ = try await manager.scanFile(testFile)
        
        XCTAssertEqual(manager.scanResults.count, initialCount + 1)
    }
    
    // MARK: - Private Mode Tests
    
    func testEnablePrivateMode() {
        manager.enablePrivateMode()
        
        XCTAssertTrue(manager.config.privateMode.isEnabled)
        XCTAssertGreaterThan(manager.events.count, 0)
    }
    
    func testDisablePrivateMode() {
        manager.enablePrivateMode()
        manager.disablePrivateMode()
        
        XCTAssertFalse(manager.config.privateMode.isEnabled)
    }
    
    func testShouldRecordHistory() {
        XCTAssertTrue(manager.shouldRecordHistory())
        
        manager.config.privateMode.isEnabled = true
        manager.config.privateMode.disableHistory = true
        
        XCTAssertFalse(manager.shouldRecordHistory())
    }
    
    func testShouldRecordStatistics() {
        XCTAssertTrue(manager.shouldRecordStatistics())
        
        manager.config.privateMode.isEnabled = true
        manager.config.privateMode.disableStatistics = true
        
        XCTAssertFalse(manager.shouldRecordStatistics())
    }
    
    func testShouldShowPreview() {
        XCTAssertTrue(manager.shouldShowPreview())
        
        manager.config.privateMode.isEnabled = true
        manager.config.privateMode.disablePreview = true
        
        XCTAssertFalse(manager.shouldShowPreview())
    }
    
    // MARK: - VPN Detection Tests
    
    func testVPNStatusDefault() {
        XCTAssertFalse(manager.vpnStatus.isConnected)
    }
    
    func testRequiresVPN() {
        XCTAssertFalse(manager.requiresVPN())
        
        manager.config.vpnDetection.preferVPNConnection = true
        
        XCTAssertTrue(manager.requiresVPN())
        
        manager.vpnStatus.isConnected = true
        
        XCTAssertFalse(manager.requiresVPN())
    }
    
    // MARK: - Statistics Tests
    
    func testSecurityStatsEmpty() {
        let stats = manager.getSecurityStats()
        
        XCTAssertEqual(stats.totalScans, 0)
        XCTAssertEqual(stats.threatsDetected, 0)
        XCTAssertEqual(stats.cleanFiles, 0)
        XCTAssertEqual(stats.averageScanTime, 0)
        XCTAssertNil(stats.lastScanDate)
    }
    
    func testSecurityStatsWithScans() async throws {
        let testFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_stats.txt")
        
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        _ = try await manager.scanFile(testFile)
        
        let stats = manager.getSecurityStats()
        
        XCTAssertEqual(stats.totalScans, 1)
        XCTAssertGreaterThanOrEqual(stats.cleanFiles, 0)
        XCTAssertGreaterThan(stats.averageScanTime, 0)
        XCTAssertNotNil(stats.lastScanDate)
    }
    
    func testClearScanHistory() async throws {
        let testFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_clear.txt")
        
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }
        
        _ = try await manager.scanFile(testFile)
        
        XCTAssertGreaterThan(manager.scanResults.count, 0)
        
        manager.clearScanHistory()
        
        XCTAssertEqual(manager.scanResults.count, 0)
    }
    
    func testClearEventLog() {
        manager.enablePrivateMode()
        
        XCTAssertGreaterThan(manager.events.count, 0)
        
        manager.clearEventLog()
        
        XCTAssertEqual(manager.events.count, 0)
    }
    
    // MARK: - Configuration Persistence Tests
    
    func testSaveAndLoadConfiguration() {
        manager.updateSecurityLevel(.maximum)
        manager.saveConfiguration()
        
        let newManager = SecurityPrivacyManager()
        newManager.loadConfiguration()
        
        XCTAssertEqual(newManager.config.securityLevel, .maximum)
    }
}
