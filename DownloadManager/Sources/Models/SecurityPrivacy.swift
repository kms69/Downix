import Foundation
import CryptoKit

// MARK: - Security Level

/// Security level for downloads
public enum SecurityLevel: String, Codable, CaseIterable {
    case none
    case basic
    case standard
    case high
    case maximum
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .basic: return "Basic"
        case .standard: return "Standard"
        case .high: return "High"
        case .maximum: return "Maximum"
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "shield.slash"
        case .basic: return "shield"
        case .standard: return "shield.lefthalf.filled"
        case .high: return "shield.fill"
        case .maximum: return "checkmark.shield.fill"
        }
    }
    
    var description: String {
        switch self {
        case .none:
            return "No security features enabled"
        case .basic:
            return "Basic URL validation only"
        case .standard:
            return "URL validation + malicious site detection"
        case .high:
            return "Standard + virus scanning"
        case .maximum:
            return "All security features including encryption"
        }
    }
    
    var features: [SecurityFeature] {
        switch self {
        case .none:
            return []
        case .basic:
            return [.urlValidation]
        case .standard:
            return [.urlValidation, .maliciousDetection]
        case .high:
            return [.urlValidation, .maliciousDetection, .virusScanning]
        case .maximum:
            return [.urlValidation, .maliciousDetection, .virusScanning, .encryption]
        }
    }
}

// MARK: - Security Feature

/// Individual security features
public enum SecurityFeature: String, Codable, CaseIterable {
    case urlValidation
    case maliciousDetection
    case virusScanning
    case encryption
    case passwordProtection
    case privateMode
    case vpnDetection
    
    var displayName: String {
        switch self {
        case .urlValidation: return "URL Validation"
        case .maliciousDetection: return "Malicious URL Detection"
        case .virusScanning: return "Virus Scanning"
        case .encryption: return "End-to-End Encryption"
        case .passwordProtection: return "Password Protection"
        case .privateMode: return "Private Mode"
        case .vpnDetection: return "VPN Detection"
        }
    }
    
    var icon: String {
        switch self {
        case .urlValidation: return "checkmark.circle"
        case .maliciousDetection: return "exclamationmark.shield"
        case .virusScanning: return "ant.circle"
        case .encryption: return "lock.fill"
        case .passwordProtection: return "key.fill"
        case .privateMode: return "eye.slash.fill"
        case .vpnDetection: return "network"
        }
    }
    
    var description: String {
        switch self {
        case .urlValidation:
            return "Validates URL format and accessibility"
        case .maliciousDetection:
            return "Checks URLs against known malicious sites"
        case .virusScanning:
            return "Scans downloaded files for viruses"
        case .encryption:
            return "Encrypts downloaded files using AES-256"
        case .passwordProtection:
            return "Protects download lists with password"
        case .privateMode:
            return "Downloads without saving history"
        case .vpnDetection:
            return "Detects and adapts to VPN connections"
        }
    }
}

// MARK: - Encryption Config

/// Configuration for file encryption
public struct EncryptionConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var algorithm: EncryptionAlgorithm
    public var keyDerivation: KeyDerivationMethod
    public var encryptFilenames: Bool
    public var encryptMetadata: Bool
    
    public enum EncryptionAlgorithm: String, Codable {
        case aes256GCM = "AES-256-GCM"
        case aes256CBC = "AES-256-CBC"
        case chacha20 = "ChaCha20-Poly1305"
        
        var displayName: String {
            rawValue
        }
        
        var keySize: Int {
            switch self {
            case .aes256GCM, .aes256CBC: return 32 // 256 bits
            case .chacha20: return 32 // 256 bits
            }
        }
    }
    
    public enum KeyDerivationMethod: String, Codable {
        case pbkdf2 = "PBKDF2"
        case argon2 = "Argon2"
        case scrypt = "Scrypt"
        
        var displayName: String {
            rawValue
        }
    }
    
    public init(
        isEnabled: Bool = false,
        algorithm: EncryptionAlgorithm = .aes256GCM,
        keyDerivation: KeyDerivationMethod = .pbkdf2,
        encryptFilenames: Bool = false,
        encryptMetadata: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.algorithm = algorithm
        self.keyDerivation = keyDerivation
        self.encryptFilenames = encryptFilenames
        self.encryptMetadata = encryptMetadata
    }
}

// MARK: - Virus Scan Config

/// Configuration for virus scanning
public struct VirusScanConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var scanEngine: ScanEngine
    public var scanAfterDownload: Bool
    public var scanBeforeOpen: Bool
    public var quarantineThreats: Bool
    public var deleteThreats: Bool
    
    public enum ScanEngine: String, Codable {
        case clamav = "ClamAV"
        case macos = "macOS XProtect"
        case custom = "Custom"
        
        var displayName: String {
            rawValue
        }
    }
    
    public init(
        isEnabled: Bool = false,
        scanEngine: ScanEngine = .clamav,
        scanAfterDownload: Bool = true,
        scanBeforeOpen: Bool = true,
        quarantineThreats: Bool = true,
        deleteThreats: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.scanEngine = scanEngine
        self.scanAfterDownload = scanAfterDownload
        self.scanBeforeOpen = scanBeforeOpen
        self.quarantineThreats = quarantineThreats
        self.deleteThreats = deleteThreats
    }
}

// MARK: - Malicious Detection Config

/// Configuration for malicious URL detection
public struct MaliciousDetectionConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var checkBlacklist: Bool
    public var checkReputation: Bool
    public var blockSuspiciousURLs: Bool
    public var warnOnUntrustedSites: Bool
    
    public init(
        isEnabled: Bool = false,
        checkBlacklist: Bool = true,
        checkReputation: Bool = true,
        blockSuspiciousURLs: Bool = false,
        warnOnUntrustedSites: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.checkBlacklist = checkBlacklist
        self.checkReputation = checkReputation
        self.blockSuspiciousURLs = blockSuspiciousURLs
        self.warnOnUntrustedSites = warnOnUntrustedSites
    }
}

// MARK: - Private Mode Config

/// Configuration for private mode
public struct PrivateModeConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var disableHistory: Bool
    public var disableStatistics: Bool
    public var clearOnExit: Bool
    public var disablePreview: Bool
    
    public init(
        isEnabled: Bool = false,
        disableHistory: Bool = true,
        disableStatistics: Bool = true,
        clearOnExit: Bool = true,
        disablePreview: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.disableHistory = disableHistory
        self.disableStatistics = disableStatistics
        self.clearOnExit = clearOnExit
        self.disablePreview = disablePreview
    }
}

// MARK: - VPN Detection Config

/// Configuration for VPN detection
public struct VPNDetectionConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var pauseOnVPNDisconnect: Bool
    public var resumeOnVPNConnect: Bool
    public var preferVPNConnection: Bool
    public var notifyOnVPNChange: Bool
    
    public init(
        isEnabled: Bool = false,
        pauseOnVPNDisconnect: Bool = false,
        resumeOnVPNConnect: Bool = false,
        preferVPNConnection: Bool = false,
        notifyOnVPNChange: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.pauseOnVPNDisconnect = pauseOnVPNDisconnect
        self.resumeOnVPNConnect = resumeOnVPNConnect
        self.preferVPNConnection = preferVPNConnection
        self.notifyOnVPNChange = notifyOnVPNChange
    }
}

// MARK: - Security Config

/// Main security configuration
public struct SecurityConfig: Codable {
    public var securityLevel: SecurityLevel
    public var encryption: EncryptionConfig
    public var virusScan: VirusScanConfig
    public var maliciousDetection: MaliciousDetectionConfig
    public var privateMode: PrivateModeConfig
    public var vpnDetection: VPNDetectionConfig
    public var masterPassword: String?
    
    public init(
        securityLevel: SecurityLevel = .standard,
        encryption: EncryptionConfig = EncryptionConfig(),
        virusScan: VirusScanConfig = VirusScanConfig(),
        maliciousDetection: MaliciousDetectionConfig = MaliciousDetectionConfig(),
        privateMode: PrivateModeConfig = PrivateModeConfig(),
        vpnDetection: VPNDetectionConfig = VPNDetectionConfig(),
        masterPassword: String? = nil
    ) {
        self.securityLevel = securityLevel
        self.encryption = encryption
        self.virusScan = virusScan
        self.maliciousDetection = maliciousDetection
        self.privateMode = privateMode
        self.vpnDetection = vpnDetection
        self.masterPassword = masterPassword
    }
    
    /// Check if feature is enabled based on security level
    public func isFeatureEnabled(_ feature: SecurityFeature) -> Bool {
        securityLevel.features.contains(feature)
    }
}

// MARK: - Security Scan Result

/// Result of a security scan
public struct SecurityScanResult: Codable, Identifiable {
    public let id: UUID
    public let url: String
    public var scanDate: Date
    public var threats: [SecurityThreat]
    public var isClean: Bool
    public var scanDuration: TimeInterval
    public var engine: String
    
    public init(
        id: UUID = UUID(),
        url: String,
        scanDate: Date = Date(),
        threats: [SecurityThreat] = [],
        isClean: Bool = true,
        scanDuration: TimeInterval = 0,
        engine: String = "Unknown"
    ) {
        self.id = id
        self.url = url
        self.scanDate = scanDate
        self.threats = threats
        self.isClean = isClean
        self.scanDuration = scanDuration
        self.engine = engine
    }
    
    public var threatLevel: ThreatLevel {
        guard !isClean else { return .none }
        
        let maxSeverity = threats.map { $0.severity }.max() ?? .low
        return ThreatLevel(from: maxSeverity)
    }
}

// MARK: - Security Threat

/// Detected security threat
public struct SecurityThreat: Codable, Identifiable {
    public let id: UUID
    public var type: ThreatType
    public var severity: ThreatSeverity
    public var description: String
    public var recommendation: String
    public var detectedAt: Date
    
    public enum ThreatType: String, Codable {
        case virus
        case malware
        case trojan
        case ransomware
        case spyware
        case adware
        case phishing
        case maliciousURL
        case suspiciousFile
        
        var displayName: String {
            switch self {
            case .virus: return "Virus"
            case .malware: return "Malware"
            case .trojan: return "Trojan"
            case .ransomware: return "Ransomware"
            case .spyware: return "Spyware"
            case .adware: return "Adware"
            case .phishing: return "Phishing"
            case .maliciousURL: return "Malicious URL"
            case .suspiciousFile: return "Suspicious File"
            }
        }
        
        var icon: String {
            switch self {
            case .virus: return "ant.circle.fill"
            case .malware: return "bandage.fill"
            case .trojan: return "ladybug.fill"
            case .ransomware: return "lock.circle.fill"
            case .spyware: return "eye.circle.fill"
            case .adware: return "megaphone.fill"
            case .phishing: return "fish.circle.fill"
            case .maliciousURL: return "link.circle.fill"
            case .suspiciousFile: return "doc.circle.fill"
            }
        }
    }
    
    public enum ThreatSeverity: Int, Codable, Comparable {
        case low = 1
        case medium = 2
        case high = 3
        case critical = 4
        
        var displayName: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .critical: return "Critical"
            }
        }
        
        var color: String {
            switch self {
            case .low: return "yellow"
            case .medium: return "orange"
            case .high: return "red"
            case .critical: return "purple"
            }
        }
        
        public static func < (lhs: ThreatSeverity, rhs: ThreatSeverity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    public init(
        id: UUID = UUID(),
        type: ThreatType,
        severity: ThreatSeverity,
        description: String,
        recommendation: String,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.description = description
        self.recommendation = recommendation
        self.detectedAt = detectedAt
    }
}

// MARK: - Threat Level

/// Overall threat level
public enum ThreatLevel: String, Codable {
    case none
    case low
    case medium
    case high
    case critical
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var icon: String {
        switch self {
        case .none: return "checkmark.shield.fill"
        case .low: return "exclamationmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        case .critical: return "xmark.octagon.fill"
        }
    }
    
    var color: String {
        switch self {
        case .none: return "green"
        case .low: return "yellow"
        case .medium: return "orange"
        case .high: return "red"
        case .critical: return "purple"
        }
    }
    
    init(from severity: SecurityThreat.ThreatSeverity) {
        switch severity {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        case .critical: self = .critical
        }
    }
}

// MARK: - URL Reputation

/// URL reputation information
public struct URLReputation: Codable {
    public var url: String
    public var isSafe: Bool
    public var reputation: Reputation
    public var categories: [URLCategory]
    public var lastChecked: Date
    
    public enum Reputation: String, Codable {
        case trusted
        case neutral
        case suspicious
        case malicious
        case unknown
        
        var displayName: String {
            rawValue.capitalized
        }
        
        var color: String {
            switch self {
            case .trusted: return "green"
            case .neutral: return "gray"
            case .suspicious: return "orange"
            case .malicious: return "red"
            case .unknown: return "blue"
            }
        }
    }
    
    public enum URLCategory: String, Codable {
        case download
        case streaming
        case fileSharing
        case cloudStorage
        case social
        case phishing
        case malware
        case spam
        case adult
        case gambling
        
        var displayName: String {
            switch self {
            case .download: return "Download"
            case .streaming: return "Streaming"
            case .fileSharing: return "File Sharing"
            case .cloudStorage: return "Cloud Storage"
            case .social: return "Social Media"
            case .phishing: return "Phishing"
            case .malware: return "Malware"
            case .spam: return "Spam"
            case .adult: return "Adult Content"
            case .gambling: return "Gambling"
            }
        }
    }
    
    public init(
        url: String,
        isSafe: Bool = true,
        reputation: Reputation = .neutral,
        categories: [URLCategory] = [],
        lastChecked: Date = Date()
    ) {
        self.url = url
        self.isSafe = isSafe
        self.reputation = reputation
        self.categories = categories
        self.lastChecked = lastChecked
    }
}

// MARK: - VPN Status

/// VPN connection status
public struct VPNStatus: Codable {
    public var isConnected: Bool
    public var vpnName: String?
    public var ipAddress: String?
    public var location: String?
    public var connectedAt: Date?
    
    public init(
        isConnected: Bool = false,
        vpnName: String? = nil,
        ipAddress: String? = nil,
        location: String? = nil,
        connectedAt: Date? = nil
    ) {
        self.isConnected = isConnected
        self.vpnName = vpnName
        self.ipAddress = ipAddress
        self.location = location
        self.connectedAt = connectedAt
    }
}

// MARK: - Security Event

/// Security-related event
public struct SecurityEvent: Codable, Identifiable {
    public let id: UUID
    public var type: EventType
    public var severity: SecurityThreat.ThreatSeverity
    public var message: String
    public var timestamp: Date
    public var details: [String: String]?
    
    public enum EventType: String, Codable {
        case threatDetected
        case threatBlocked
        case scanCompleted
        case encryptionEnabled
        case encryptionDisabled
        case privateModeEnabled
        case privateModeDisabled
        case vpnConnected
        case vpnDisconnected
        case passwordChanged
        case unauthorizedAccess
        
        var displayName: String {
            switch self {
            case .threatDetected: return "Threat Detected"
            case .threatBlocked: return "Threat Blocked"
            case .scanCompleted: return "Scan Completed"
            case .encryptionEnabled: return "Encryption Enabled"
            case .encryptionDisabled: return "Encryption Disabled"
            case .privateModeEnabled: return "Private Mode Enabled"
            case .privateModeDisabled: return "Private Mode Disabled"
            case .vpnConnected: return "VPN Connected"
            case .vpnDisconnected: return "VPN Disconnected"
            case .passwordChanged: return "Password Changed"
            case .unauthorizedAccess: return "Unauthorized Access"
            }
        }
        
        var icon: String {
            switch self {
            case .threatDetected, .threatBlocked: return "exclamationmark.shield"
            case .scanCompleted: return "checkmark.shield"
            case .encryptionEnabled: return "lock.fill"
            case .encryptionDisabled: return "lock.open.fill"
            case .privateModeEnabled: return "eye.slash.fill"
            case .privateModeDisabled: return "eye.fill"
            case .vpnConnected: return "network"
            case .vpnDisconnected: return "network.slash"
            case .passwordChanged: return "key.fill"
            case .unauthorizedAccess: return "exclamationmark.triangle.fill"
            }
        }
    }
    
    public init(
        id: UUID = UUID(),
        type: EventType,
        severity: SecurityThreat.ThreatSeverity,
        message: String,
        timestamp: Date = Date(),
        details: [String: String]? = nil
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.message = message
        self.timestamp = timestamp
        self.details = details
    }
}

// MARK: - Security Error

/// Security-related errors
public enum SecurityError: Error, LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidPassword
    case scanFailed(String)
    case threatDetected(SecurityThreat)
    case maliciousURL(String)
    case vpnNotConnected
    case unauthorizedAccess
    case invalidKey
    case corruptedData
    
    public var errorDescription: String? {
        switch self {
        case .encryptionFailed(let reason):
            return "Encryption failed: \(reason)"
        case .decryptionFailed(let reason):
            return "Decryption failed: \(reason)"
        case .invalidPassword:
            return "Invalid password"
        case .scanFailed(let reason):
            return "Virus scan failed: \(reason)"
        case .threatDetected(let threat):
            return "Threat detected: \(threat.description)"
        case .maliciousURL(let url):
            return "Malicious URL detected: \(url)"
        case .vpnNotConnected:
            return "VPN not connected"
        case .unauthorizedAccess:
            return "Unauthorized access attempt"
        case .invalidKey:
            return "Invalid encryption key"
        case .corruptedData:
            return "Data corrupted or tampered with"
        }
    }
}

// MARK: - Encryption Result

/// Result of encryption operation
public struct EncryptionResult: Codable {
    public var success: Bool
    public var originalSize: Int64
    public var encryptedSize: Int64
    public var algorithm: String
    public var duration: TimeInterval
    public var error: String?
    
    public init(
        success: Bool,
        originalSize: Int64,
        encryptedSize: Int64,
        algorithm: String,
        duration: TimeInterval,
        error: String? = nil
    ) {
        self.success = success
        self.originalSize = originalSize
        self.encryptedSize = encryptedSize
        self.algorithm = algorithm
        self.duration = duration
        self.error = error
    }
}
