import Foundation
import Network
import SystemConfiguration

// MARK: - Proxy Configuration

/// Proxy protocol type
public enum ProxyType: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case http = "HTTP"
    case https = "HTTPS"
    case socks5 = "SOCKS5"
    case system = "System"
    
    public var id: String { rawValue }
    
    public var displayName: String { rawValue }
    
    public var requiresAuthentication: Bool {
        switch self {
        case .http, .https, .socks5:
            return true
        case .none, .system:
            return false
        }
    }
    
    public var defaultPort: Int {
        switch self {
        case .http: return 8080
        case .https: return 8443
        case .socks5: return 1080
        case .none, .system: return 0
        }
    }
}

/// Proxy authentication method
public enum ProxyAuthMethod: String, Codable, CaseIterable {
    case none = "None"
    case basic = "Basic"
    case digest = "Digest"
    case ntlm = "NTLM"
    
    public var displayName: String { rawValue }
}

/// Proxy configuration
public struct ProxyConfig: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var type: ProxyType
    public var host: String
    public var port: Int
    public var requiresAuthentication: Bool
    public var username: String
    public var password: String
    public var authMethod: ProxyAuthMethod
    public var bypassList: [String]
    public var isEnabled: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String = "New Proxy",
        type: ProxyType = .http,
        host: String = "",
        port: Int = 8080,
        requiresAuthentication: Bool = false,
        username: String = "",
        password: String = "",
        authMethod: ProxyAuthMethod = .basic,
        bypassList: [String] = [],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.requiresAuthentication = requiresAuthentication
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.bypassList = bypassList
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
    
    /// Validate proxy configuration
    public var isValid: Bool {
        guard !host.isEmpty, port > 0, port < 65536 else { return false }
        if requiresAuthentication && username.isEmpty { return false }
        return true
    }
    
    /// URL representation for URLSession
    public var url: URL? {
        guard isValid else { return nil }
        let scheme: String
        switch type {
        case .http: scheme = "http"
        case .https: scheme = "https"
        case .socks5: scheme = "socks5"
        case .none, .system: return nil
        }
        
        if requiresAuthentication && !username.isEmpty {
            return URL(string: "\(scheme)://\(username):\(password)@\(host):\(port)")
        } else {
            return URL(string: "\(scheme)://\(host):\(port)")
        }
    }
}

// MARK: - VPN Detection

/// VPN connection status
public enum VPNConnectionStatus: String, Codable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case disconnecting = "Disconnecting"
    case unknown = "Unknown"
    
    public var displayName: String { rawValue }
    
    public var icon: String {
        switch self {
        case .disconnected: return "shield.slash"
        case .connecting: return "shield.lefthalf.filled"
        case .connected: return "shield.fill"
        case .disconnecting: return "shield.lefthalf.filled"
        case .unknown: return "questionmark.shield"
        }
    }
    
    public var color: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting: return "orange"
        case .connected: return "green"
        case .disconnecting: return "orange"
        case .unknown: return "gray"
        }
    }
}

/// VPN configuration
public struct VPNConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var autoDetect: Bool
    public var pauseDownloadsOnDisconnect: Bool
    public var resumeDownloadsOnConnect: Bool
    public var showNotifications: Bool
    public var preferredInterface: String?
    
    public init(
        isEnabled: Bool = true,
        autoDetect: Bool = true,
        pauseDownloadsOnDisconnect: Bool = false,
        resumeDownloadsOnConnect: Bool = true,
        showNotifications: Bool = true,
        preferredInterface: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.autoDetect = autoDetect
        self.pauseDownloadsOnDisconnect = pauseDownloadsOnDisconnect
        self.resumeDownloadsOnConnect = resumeDownloadsOnConnect
        self.showNotifications = showNotifications
        self.preferredInterface = preferredInterface
    }
}

/// VPN connection information
public struct VPNConnection: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var status: VPNConnectionStatus
    public var interfaceName: String
    public var ipAddress: String?
    public var connectedAt: Date?
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        status: VPNConnectionStatus = .unknown,
        interfaceName: String,
        ipAddress: String? = nil,
        connectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.interfaceName = interfaceName
        self.ipAddress = ipAddress
        self.connectedAt = connectedAt
    }
}

// MARK: - Network Interface

/// Network interface type
public enum NetworkInterfaceType: String, Codable, CaseIterable {
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case cellular = "Cellular"
    case thunderbolt = "Thunderbolt"
    case usb = "USB"
    case other = "Other"
    
    public var displayName: String { rawValue }
    
    public var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .thunderbolt: return "bolt.fill"
        case .usb: return "cable.connector.horizontal"
        case .other: return "network"
        }
    }
}

/// Network interface
public struct NetworkInterface: Identifiable, Equatable, Codable {
    public let id: String
    public var name: String
    public var displayName: String
    public var type: NetworkInterfaceType
    public var isActive: Bool
    public var ipAddress: String?
    public var macAddress: String?
    public var isMetered: Bool
    public var speedMbps: Double?
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        displayName: String,
        type: NetworkInterfaceType = .other,
        isActive: Bool = false,
        ipAddress: String? = nil,
        macAddress: String? = nil,
        isMetered: Bool = false,
        speedMbps: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.type = type
        self.isActive = isActive
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.isMetered = isMetered
        self.speedMbps = speedMbps
    }
}

/// Network interface selection preference
public struct InterfacePreference: Codable, Equatable {
    public var preferredInterfaceID: String?
    public var automaticSelection: Bool
    public var avoidMeteredConnections: Bool
    public var preferFasterConnections: Bool
    
    public init(
        preferredInterfaceID: String? = nil,
        automaticSelection: Bool = true,
        avoidMeteredConnections: Bool = true,
        preferFasterConnections: Bool = true
    ) {
        self.preferredInterfaceID = preferredInterfaceID
        self.automaticSelection = automaticSelection
        self.avoidMeteredConnections = avoidMeteredConnections
        self.preferFasterConnections = preferFasterConnections
    }
}

// MARK: - Mirror Support

/// Mirror server configuration
public struct MirrorServer: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var baseURL: URL
    public var priority: Int
    public var isEnabled: Bool
    public var region: String
    public var lastResponseTime: TimeInterval?
    public var successRate: Double
    public var lastChecked: Date?
    
    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        priority: Int = 0,
        isEnabled: Bool = true,
        region: String = "Unknown",
        lastResponseTime: TimeInterval? = nil,
        successRate: Double = 1.0,
        lastChecked: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.priority = priority
        self.isEnabled = isEnabled
        self.region = region
        self.lastResponseTime = lastResponseTime
        self.successRate = successRate
        self.lastChecked = lastChecked
    }
    
    /// Check if mirror is healthy
    public var isHealthy: Bool {
        guard let responseTime = lastResponseTime else { return false }
        return responseTime < 5.0 && successRate > 0.8
    }
}

/// Mirror selection strategy
public enum MirrorSelectionStrategy: String, Codable, CaseIterable {
    case automatic = "Automatic"
    case fastest = "Fastest"
    case nearest = "Nearest"
    case priority = "Priority"
    case manual = "Manual"
    
    public var displayName: String { rawValue }
    
    public var description: String {
        switch self {
        case .automatic:
            return "Automatically select best mirror"
        case .fastest:
            return "Always use fastest responding mirror"
        case .nearest:
            return "Prefer geographically nearest mirror"
        case .priority:
            return "Use mirrors in priority order"
        case .manual:
            return "Manually select mirror"
        }
    }
}

/// Mirror configuration
public struct MirrorConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var selectionStrategy: MirrorSelectionStrategy
    public var autoDetect: Bool
    public var checkInterval: TimeInterval
    public var maxRetries: Int
    public var timeoutSeconds: Double
    public var servers: [MirrorServer]
    
    public init(
        isEnabled: Bool = false,
        selectionStrategy: MirrorSelectionStrategy = .automatic,
        autoDetect: Bool = true,
        checkInterval: TimeInterval = 300,
        maxRetries: Int = 3,
        timeoutSeconds: Double = 5.0,
        servers: [MirrorServer] = []
    ) {
        self.isEnabled = isEnabled
        self.selectionStrategy = selectionStrategy
        self.autoDetect = autoDetect
        self.checkInterval = checkInterval
        self.maxRetries = maxRetries
        self.timeoutSeconds = timeoutSeconds
        self.servers = servers
    }
}

// MARK: - SSL Certificate Handling

/// SSL certificate validation level
public enum SSLValidationLevel: String, Codable, CaseIterable {
    case strict = "Strict"
    case normal = "Normal"
    case lenient = "Lenient"
    case disabled = "Disabled"
    
    public var displayName: String { rawValue }
    
    public var description: String {
        switch self {
        case .strict:
            return "Validate all certificates, reject self-signed"
        case .normal:
            return "Standard certificate validation"
        case .lenient:
            return "Allow self-signed certificates"
        case .disabled:
            return "Skip certificate validation (not recommended)"
        }
    }
}

/// SSL certificate information
public struct SSLCertificate: Codable, Identifiable, Equatable {
    public let id: UUID
    public var domain: String
    public var issuer: String
    public var subject: String
    public var validFrom: Date
    public var validUntil: Date
    public var fingerprint: String
    public var isTrusted: Bool
    public var isSelfSigned: Bool
    
    public init(
        id: UUID = UUID(),
        domain: String,
        issuer: String,
        subject: String,
        validFrom: Date,
        validUntil: Date,
        fingerprint: String,
        isTrusted: Bool = true,
        isSelfSigned: Bool = false
    ) {
        self.id = id
        self.domain = domain
        self.issuer = issuer
        self.subject = subject
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.fingerprint = fingerprint
        self.isTrusted = isTrusted
        self.isSelfSigned = isSelfSigned
    }
    
    /// Check if certificate is valid
    public var isValid: Bool {
        let now = Date()
        return now >= validFrom && now <= validUntil && isTrusted
    }
    
    /// Check if certificate is expired
    public var isExpired: Bool {
        return Date() > validUntil
    }
    
    /// Days until expiration
    public var daysUntilExpiration: Int {
        let interval = validUntil.timeIntervalSince(Date())
        return Int(interval / 86400)
    }
}

/// SSL configuration
public struct SSLConfig: Codable, Equatable {
    public var validationLevel: SSLValidationLevel
    public var allowSelfSigned: Bool
    public var allowExpired: Bool
    public var checkRevocation: Bool
    public var pinnedCertificates: [String: String]
    public var trustedDomains: [String]
    
    public init(
        validationLevel: SSLValidationLevel = .normal,
        allowSelfSigned: Bool = false,
        allowExpired: Bool = false,
        checkRevocation: Bool = true,
        pinnedCertificates: [String: String] = [:],
        trustedDomains: [String] = []
    ) {
        self.validationLevel = validationLevel
        self.allowSelfSigned = allowSelfSigned
        self.allowExpired = allowExpired
        self.checkRevocation = checkRevocation
        self.pinnedCertificates = pinnedCertificates
        self.trustedDomains = trustedDomains
    }
}

// MARK: - Custom Headers and Cookies

/// HTTP header
public struct HTTPHeader: Codable, Identifiable, Equatable {
    public let id: UUID
    public var key: String
    public var value: String
    public var isEnabled: Bool
    public var applyToAllDownloads: Bool
    public var domainPattern: String?
    
    public init(
        id: UUID = UUID(),
        key: String,
        value: String,
        isEnabled: Bool = true,
        applyToAllDownloads: Bool = false,
        domainPattern: String? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
        self.applyToAllDownloads = applyToAllDownloads
        self.domainPattern = domainPattern
    }
    
    /// Validate header
    public var isValid: Bool {
        !key.isEmpty && !value.isEmpty
    }
}

/// HTTP cookie
public struct HTTPCookieInfo: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var expires: Date?
    public var isSecure: Bool
    public var isHTTPOnly: Bool
    public var sameSite: String?
    public var isEnabled: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expires: Date? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false,
        sameSite: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSite = sameSite
        self.isEnabled = isEnabled
    }
    
    /// Check if cookie is valid
    public var isValid: Bool {
        !name.isEmpty && !value.isEmpty && !domain.isEmpty
    }
    
    /// Check if cookie is expired
    public var isExpired: Bool {
        guard let expires = expires else { return false }
        return Date() > expires
    }
    
    /// Convert to HTTPCookie
    public func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        
        if let expires = expires {
            properties[.expires] = expires
        }
        
        if isSecure {
            properties[.secure] = true
        }
        
        if isHTTPOnly {
            properties[.init("HttpOnly")] = true
        }
        
        if let sameSite = sameSite {
            properties[.sameSitePolicy] = sameSite
        }
        
        return HTTPCookie(properties: properties)
    }
}

/// Headers and cookies configuration
public struct HeadersCookiesConfig: Codable, Equatable {
    public var customHeaders: [HTTPHeader]
    public var customCookies: [HTTPCookieInfo]
    public var sendUserAgent: Bool
    public var userAgent: String
    public var sendReferrer: Bool
    public var sendAcceptLanguage: Bool
    public var acceptLanguage: String
    
    public init(
        customHeaders: [HTTPHeader] = [],
        customCookies: [HTTPCookieInfo] = [],
        sendUserAgent: Bool = true,
        userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        sendReferrer: Bool = true,
        sendAcceptLanguage: Bool = true,
        acceptLanguage: String = "en-US,en;q=0.9"
    ) {
        self.customHeaders = customHeaders
        self.customCookies = customCookies
        self.sendUserAgent = sendUserAgent
        self.userAgent = userAgent
        self.sendReferrer = sendReferrer
        self.sendAcceptLanguage = sendAcceptLanguage
        self.acceptLanguage = acceptLanguage
    }
}

// MARK: - Complete Network Configuration

/// Complete network configuration
public struct NetworkConfiguration: Codable, Equatable {
    public var proxyConfigs: [ProxyConfig]
    public var activeProxyID: UUID?
    public var vpnConfig: VPNConfig
    public var interfacePreference: InterfacePreference
    public var mirrorConfig: MirrorConfig
    public var sslConfig: SSLConfig
    public var headersCookiesConfig: HeadersCookiesConfig
    public var timeout: TimeInterval
    public var retryAttempts: Int
    public var followRedirects: Bool
    public var maxRedirects: Int
    public var lastModified: Date
    
    public init(
        proxyConfigs: [ProxyConfig] = [],
        activeProxyID: UUID? = nil,
        vpnConfig: VPNConfig = VPNConfig(),
        interfacePreference: InterfacePreference = InterfacePreference(),
        mirrorConfig: MirrorConfig = MirrorConfig(),
        sslConfig: SSLConfig = SSLConfig(),
        headersCookiesConfig: HeadersCookiesConfig = HeadersCookiesConfig(),
        timeout: TimeInterval = 30.0,
        retryAttempts: Int = 3,
        followRedirects: Bool = true,
        maxRedirects: Int = 5,
        lastModified: Date = Date()
    ) {
        self.proxyConfigs = proxyConfigs
        self.activeProxyID = activeProxyID
        self.vpnConfig = vpnConfig
        self.interfacePreference = interfacePreference
        self.mirrorConfig = mirrorConfig
        self.sslConfig = sslConfig
        self.headersCookiesConfig = headersCookiesConfig
        self.timeout = timeout
        self.retryAttempts = retryAttempts
        self.followRedirects = followRedirects
        self.maxRedirects = maxRedirects
        self.lastModified = lastModified
    }
    
    /// Get active proxy configuration
    public func getActiveProxy() -> ProxyConfig? {
        guard let id = activeProxyID else { return nil }
        return proxyConfigs.first { $0.id == id && $0.isEnabled }
    }
    
    /// Default configuration
    public static var `default`: NetworkConfiguration {
        NetworkConfiguration()
    }
}

// MARK: - Network Statistics

/// Network statistics
public struct NetworkStatistics: Codable, Equatable {
    public var totalBytesSent: Int64
    public var totalBytesReceived: Int64
    public var averageDownloadSpeed: Double
    public var averageUploadSpeed: Double
    public var peakDownloadSpeed: Double
    public var peakUploadSpeed: Double
    public var totalConnections: Int
    public var failedConnections: Int
    public var proxyConnections: Int
    public var directConnections: Int
    public var recordedAt: Date
    
    public init(
        totalBytesSent: Int64 = 0,
        totalBytesReceived: Int64 = 0,
        averageDownloadSpeed: Double = 0,
        averageUploadSpeed: Double = 0,
        peakDownloadSpeed: Double = 0,
        peakUploadSpeed: Double = 0,
        totalConnections: Int = 0,
        failedConnections: Int = 0,
        proxyConnections: Int = 0,
        directConnections: Int = 0,
        recordedAt: Date = Date()
    ) {
        self.totalBytesSent = totalBytesSent
        self.totalBytesReceived = totalBytesReceived
        self.averageDownloadSpeed = averageDownloadSpeed
        self.averageUploadSpeed = averageUploadSpeed
        self.peakDownloadSpeed = peakDownloadSpeed
        self.peakUploadSpeed = peakUploadSpeed
        self.totalConnections = totalConnections
        self.failedConnections = failedConnections
        self.proxyConnections = proxyConnections
        self.directConnections = directConnections
        self.recordedAt = recordedAt
    }
    
    /// Success rate
    public var successRate: Double {
        guard totalConnections > 0 else { return 0 }
        return Double(totalConnections - failedConnections) / Double(totalConnections)
    }
}
