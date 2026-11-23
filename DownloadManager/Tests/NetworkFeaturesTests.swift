import XCTest
@testable import DownloadManager

@MainActor
final class NetworkFeaturesTests: XCTestCase {
    
    var networkManager: NetworkManager!
    
    override func setUp() async throws {
        try await super.setUp()
        networkManager = NetworkManager.shared
        networkManager.resetToDefaults()
    }
    
    override func tearDown() async throws {
        networkManager.resetToDefaults()
        try await super.tearDown()
    }
    
    // MARK: - Proxy Configuration Tests
    
    func testProxyTypeEnum() async throws {
        let types = [ProxyType.none, .http, .https, .socks5, .system]
        XCTAssertEqual(types.count, ProxyType.allCases.count)
        
        XCTAssertTrue(ProxyType.http.requiresAuthentication)
        XCTAssertFalse(ProxyType.none.requiresAuthentication)
        
        XCTAssertEqual(ProxyType.http.defaultPort, 8080)
        XCTAssertEqual(ProxyType.socks5.defaultPort, 1080)
    }
    
    func testProxyConfigCreation() async throws {
        let proxy = ProxyConfig(
            name: "Test Proxy",
            type: .http,
            host: "proxy.example.com",
            port: 8080
        )
        
        XCTAssertEqual(proxy.name, "Test Proxy")
        XCTAssertEqual(proxy.type, .http)
        XCTAssertEqual(proxy.host, "proxy.example.com")
        XCTAssertEqual(proxy.port, 8080)
        XCTAssertTrue(proxy.isEnabled)
    }
    
    func testProxyValidation() async throws {
        var proxy = ProxyConfig(name: "Invalid", type: .http, host: "", port: 8080)
        XCTAssertFalse(proxy.isValid)
        
        proxy.host = "example.com"
        proxy.port = 0
        XCTAssertFalse(proxy.isValid)
        
        proxy.port = 8080
        XCTAssertTrue(proxy.isValid)
        
        proxy.requiresAuthentication = true
        XCTAssertFalse(proxy.isValid) // No username
        
        proxy.username = "user"
        XCTAssertTrue(proxy.isValid)
    }
    
    func testProxyURL() async throws {
        let simpleProxy = ProxyConfig(
            name: "Simple",
            type: .http,
            host: "proxy.com",
            port: 8080
        )
        XCTAssertNotNil(simpleProxy.url)
        XCTAssertEqual(simpleProxy.url?.scheme, "http")
        
        var authProxy = ProxyConfig(
            name: "Auth",
            type: .http,
            host: "proxy.com",
            port: 8080,
            requiresAuthentication: true,
            username: "user",
            password: "pass"
        )
        XCTAssertNotNil(authProxy.url)
        XCTAssertTrue(authProxy.url?.absoluteString.contains("user:pass") ?? false)
    }
    
    func testAddProxy() async throws {
        let proxy = ProxyConfig(name: "Test", type: .http, host: "proxy.com", port: 8080)
        networkManager.addProxy(proxy)
        
        let proxies = networkManager.getAllProxies()
        XCTAssertEqual(proxies.count, 1)
        XCTAssertEqual(proxies.first?.name, "Test")
    }
    
    func testUpdateProxy() async throws {
        var proxy = ProxyConfig(name: "Original", type: .http, host: "proxy.com", port: 8080)
        networkManager.addProxy(proxy)
        
        proxy.name = "Updated"
        networkManager.updateProxy(proxy)
        
        let proxies = networkManager.getAllProxies()
        XCTAssertEqual(proxies.first?.name, "Updated")
    }
    
    func testDeleteProxy() async throws {
        let proxy = ProxyConfig(name: "Delete Me", type: .http, host: "proxy.com", port: 8080)
        networkManager.addProxy(proxy)
        XCTAssertEqual(networkManager.getAllProxies().count, 1)
        
        networkManager.deleteProxy(proxy.id)
        XCTAssertEqual(networkManager.getAllProxies().count, 0)
    }
    
    func testSetActiveProxy() async throws {
        let proxy = ProxyConfig(name: "Active", type: .http, host: "proxy.com", port: 8080)
        networkManager.addProxy(proxy)
        
        networkManager.setActiveProxy(proxy.id)
        XCTAssertEqual(networkManager.configuration.activeProxyID, proxy.id)
        
        let active = networkManager.getActiveProxy()
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.name, "Active")
    }
    
    func testGetSystemProxySettings() async throws {
        let systemProxy = networkManager.getSystemProxySettings()
        // May or may not exist depending on system configuration
        if let proxy = systemProxy {
            XCTAssertFalse(proxy.host.isEmpty)
            XCTAssertGreaterThan(proxy.port, 0)
        }
    }
    
    // MARK: - VPN Detection Tests
    
    func testVPNStatusEnum() async throws {
        let statuses: [VPNStatus] = [.disconnected, .connecting, .connected, .disconnecting, .unknown]
        
        for status in statuses {
            XCTAssertFalse(status.icon.isEmpty)
            XCTAssertFalse(status.displayName.isEmpty)
        }
        
        XCTAssertEqual(VPNStatus.connected.icon, "shield.fill")
        XCTAssertEqual(VPNStatus.disconnected.icon, "shield.slash")
    }
    
    func testVPNConfig() async throws {
        let config = VPNConfig(
            isEnabled: true,
            autoDetect: true,
            pauseDownloadsOnDisconnect: true,
            resumeDownloadsOnConnect: true,
            showNotifications: true
        )
        
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.autoDetect)
        XCTAssertTrue(config.pauseDownloadsOnDisconnect)
        XCTAssertTrue(config.resumeDownloadsOnConnect)
    }
    
    func testUpdateVPNConfig() async throws {
        var config = networkManager.configuration.vpnConfig
        config.isEnabled = true
        config.pauseDownloadsOnDisconnect = true
        
        networkManager.updateVPNConfig(config)
        
        XCTAssertTrue(networkManager.configuration.vpnConfig.isEnabled)
        XCTAssertTrue(networkManager.configuration.vpnConfig.pauseDownloadsOnDisconnect)
    }
    
    func testVPNDetection() async throws {
        await networkManager.detectVPNStatus()
        
        // Status should be one of the valid values
        let validStatuses: [VPNStatus] = [.disconnected, .connecting, .connected, .disconnecting, .unknown]
        XCTAssertTrue(validStatuses.contains(networkManager.currentVPNStatus))
    }
    
    // MARK: - Network Interface Tests
    
    func testNetworkInterfaceType() async throws {
        let types = NetworkInterfaceType.allCases
        XCTAssertGreaterThan(types.count, 0)
        
        XCTAssertEqual(NetworkInterfaceType.wifi.icon, "wifi")
        XCTAssertEqual(NetworkInterfaceType.ethernet.icon, "cable.connector")
    }
    
    func testNetworkInterfaceCreation() async throws {
        let interface = NetworkInterface(
            name: "en0",
            displayName: "Wi-Fi",
            type: .wifi,
            isActive: true,
            ipAddress: "192.168.1.100"
        )
        
        XCTAssertEqual(interface.name, "en0")
        XCTAssertEqual(interface.type, .wifi)
        XCTAssertTrue(interface.isActive)
        XCTAssertEqual(interface.ipAddress, "192.168.1.100")
    }
    
    func testInterfacePreference() async throws {
        let preference = InterfacePreference(
            automaticSelection: true,
            avoidMeteredConnections: true,
            preferFasterConnections: true
        )
        
        XCTAssertTrue(preference.automaticSelection)
        XCTAssertTrue(preference.avoidMeteredConnections)
        XCTAssertTrue(preference.preferFasterConnections)
    }
    
    func testDetectNetworkInterfaces() async throws {
        await networkManager.detectNetworkInterfaces()
        
        let interfaces = networkManager.availableInterfaces
        XCTAssertGreaterThan(interfaces.count, 0) // Should find at least one interface
        
        // Check if there's an active interface
        let hasActive = interfaces.contains { $0.isActive }
        XCTAssertTrue(hasActive) // Should have at least one active interface
    }
    
    func testUpdateInterfacePreference() async throws {
        var preference = InterfacePreference()
        preference.automaticSelection = false
        preference.avoidMeteredConnections = true
        
        networkManager.updateInterfacePreference(preference)
        
        XCTAssertFalse(networkManager.configuration.interfacePreference.automaticSelection)
        XCTAssertTrue(networkManager.configuration.interfacePreference.avoidMeteredConnections)
    }
    
    func testGetPreferredInterface() async throws {
        await networkManager.detectNetworkInterfaces()
        
        let preferred = networkManager.getPreferredInterface()
        // Should return the active interface or nil
        if let interface = preferred {
            XCTAssertTrue(interface.isActive)
        }
    }
    
    // MARK: - Mirror Management Tests
    
    func testMirrorServerCreation() async throws {
        let mirror = MirrorServer(
            name: "US Mirror",
            baseURL: URL(string: "https://mirror.example.com")!,
            priority: 1,
            isEnabled: true,
            region: "US"
        )
        
        XCTAssertEqual(mirror.name, "US Mirror")
        XCTAssertEqual(mirror.priority, 1)
        XCTAssertTrue(mirror.isEnabled)
        XCTAssertEqual(mirror.region, "US")
    }
    
    func testMirrorHealth() async throws {
        var mirror = MirrorServer(
            name: "Healthy",
            baseURL: URL(string: "https://example.com")!,
            lastResponseTime: 1.0,
            successRate: 0.95
        )
        
        XCTAssertTrue(mirror.isHealthy)
        
        mirror.lastResponseTime = 10.0
        XCTAssertFalse(mirror.isHealthy)
        
        mirror.lastResponseTime = 1.0
        mirror.successRate = 0.5
        XCTAssertFalse(mirror.isHealthy)
    }
    
    func testMirrorSelectionStrategy() async throws {
        let strategies = MirrorSelectionStrategy.allCases
        XCTAssertEqual(strategies.count, 5)
        
        for strategy in strategies {
            XCTAssertFalse(strategy.displayName.isEmpty)
            XCTAssertFalse(strategy.description.isEmpty)
        }
    }
    
    func testAddMirror() async throws {
        let mirror = MirrorServer(
            name: "Test Mirror",
            baseURL: URL(string: "https://mirror.com")!
        )
        
        networkManager.addMirror(mirror)
        
        let mirrors = networkManager.getAllMirrors()
        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors.first?.name, "Test Mirror")
    }
    
    func testUpdateMirror() async throws {
        var mirror = MirrorServer(
            name: "Original",
            baseURL: URL(string: "https://mirror.com")!
        )
        
        networkManager.addMirror(mirror)
        
        mirror.name = "Updated"
        networkManager.updateMirror(mirror)
        
        let mirrors = networkManager.getAllMirrors()
        XCTAssertEqual(mirrors.first?.name, "Updated")
    }
    
    func testDeleteMirror() async throws {
        let mirror = MirrorServer(
            name: "Delete Me",
            baseURL: URL(string: "https://mirror.com")!
        )
        
        networkManager.addMirror(mirror)
        XCTAssertEqual(networkManager.getAllMirrors().count, 1)
        
        networkManager.deleteMirror(mirror.id)
        XCTAssertEqual(networkManager.getAllMirrors().count, 0)
    }
    
    func testUpdateMirrorConfig() async throws {
        var config = networkManager.configuration.mirrorConfig
        config.isEnabled = true
        config.selectionStrategy = .fastest
        config.checkInterval = 600
        
        networkManager.updateMirrorConfig(config)
        
        XCTAssertTrue(networkManager.configuration.mirrorConfig.isEnabled)
        XCTAssertEqual(networkManager.configuration.mirrorConfig.selectionStrategy, .fastest)
        XCTAssertEqual(networkManager.configuration.mirrorConfig.checkInterval, 600)
    }
    
    func testGetBestMirror() async throws {
        // Add some mirrors
        let mirror1 = MirrorServer(
            name: "Fast",
            baseURL: URL(string: "https://fast.com")!,
            priority: 2,
            lastResponseTime: 0.5,
            successRate: 0.95
        )
        
        let mirror2 = MirrorServer(
            name: "Slow",
            baseURL: URL(string: "https://slow.com")!,
            priority: 1,
            lastResponseTime: 5.0,
            successRate: 0.85
        )
        
        networkManager.addMirror(mirror1)
        networkManager.addMirror(mirror2)
        
        var config = networkManager.configuration.mirrorConfig
        config.isEnabled = true
        config.selectionStrategy = .fastest
        networkManager.updateMirrorConfig(config)
        
        let best = networkManager.getBestMirror()
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.name, "Fast")
    }
    
    // MARK: - SSL Configuration Tests
    
    func testSSLValidationLevel() async throws {
        let levels = SSLValidationLevel.allCases
        XCTAssertEqual(levels.count, 4)
        
        for level in levels {
            XCTAssertFalse(level.displayName.isEmpty)
            XCTAssertFalse(level.description.isEmpty)
        }
    }
    
    func testSSLCertificateValidation() async throws {
        let now = Date()
        let validFrom = now.addingTimeInterval(-86400)
        let validUntil = now.addingTimeInterval(86400 * 30)
        
        let cert = SSLCertificate(
            domain: "example.com",
            issuer: "Let's Encrypt",
            subject: "example.com",
            validFrom: validFrom,
            validUntil: validUntil,
            fingerprint: "abc123",
            isTrusted: true
        )
        
        XCTAssertTrue(cert.isValid)
        XCTAssertFalse(cert.isExpired)
        XCTAssertGreaterThan(cert.daysUntilExpiration, 0)
    }
    
    func testSSLCertificateExpiration() async throws {
        let now = Date()
        let validFrom = now.addingTimeInterval(-86400 * 60)
        let validUntil = now.addingTimeInterval(-86400)
        
        let cert = SSLCertificate(
            domain: "expired.com",
            issuer: "CA",
            subject: "expired.com",
            validFrom: validFrom,
            validUntil: validUntil,
            fingerprint: "xyz789",
            isTrusted: true
        )
        
        XCTAssertFalse(cert.isValid)
        XCTAssertTrue(cert.isExpired)
        XCTAssertLessThan(cert.daysUntilExpiration, 0)
    }
    
    func testUpdateSSLConfig() async throws {
        var config = SSLConfig(
            validationLevel: .lenient,
            allowSelfSigned: true,
            checkRevocation: false
        )
        
        networkManager.updateSSLConfig(config)
        
        XCTAssertEqual(networkManager.configuration.sslConfig.validationLevel, .lenient)
        XCTAssertTrue(networkManager.configuration.sslConfig.allowSelfSigned)
        XCTAssertFalse(networkManager.configuration.sslConfig.checkRevocation)
    }
    
    func testPinnedCertificates() async throws {
        networkManager.addPinnedCertificate(domain: "example.com", fingerprint: "abc123")
        
        XCTAssertEqual(networkManager.configuration.sslConfig.pinnedCertificates["example.com"], "abc123")
        
        networkManager.removePinnedCertificate(domain: "example.com")
        
        XCTAssertNil(networkManager.configuration.sslConfig.pinnedCertificates["example.com"])
    }
    
    func testTrustedDomains() async throws {
        networkManager.addTrustedDomain("trusted.com")
        
        XCTAssertTrue(networkManager.configuration.sslConfig.trustedDomains.contains("trusted.com"))
        
        networkManager.removeTrustedDomain("trusted.com")
        
        XCTAssertFalse(networkManager.configuration.sslConfig.trustedDomains.contains("trusted.com"))
    }
    
    // MARK: - Headers and Cookies Tests
    
    func testHTTPHeaderCreation() async throws {
        let header = HTTPHeader(
            key: "X-Custom-Header",
            value: "CustomValue",
            isEnabled: true
        )
        
        XCTAssertEqual(header.key, "X-Custom-Header")
        XCTAssertEqual(header.value, "CustomValue")
        XCTAssertTrue(header.isValid)
    }
    
    func testHTTPHeaderValidation() async throws {
        let invalid = HTTPHeader(key: "", value: "value")
        XCTAssertFalse(invalid.isValid)
        
        let valid = HTTPHeader(key: "Key", value: "Value")
        XCTAssertTrue(valid.isValid)
    }
    
    func testAddCustomHeader() async throws {
        let header = HTTPHeader(key: "X-Test", value: "TestValue")
        networkManager.addCustomHeader(header)
        
        let headers = networkManager.configuration.headersCookiesConfig.customHeaders
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers.first?.key, "X-Test")
    }
    
    func testUpdateCustomHeader() async throws {
        var header = HTTPHeader(key: "X-Original", value: "OriginalValue")
        networkManager.addCustomHeader(header)
        
        header.value = "UpdatedValue"
        networkManager.updateCustomHeader(header)
        
        let headers = networkManager.configuration.headersCookiesConfig.customHeaders
        XCTAssertEqual(headers.first?.value, "UpdatedValue")
    }
    
    func testDeleteCustomHeader() async throws {
        let header = HTTPHeader(key: "X-Delete", value: "DeleteValue")
        networkManager.addCustomHeader(header)
        XCTAssertEqual(networkManager.configuration.headersCookiesConfig.customHeaders.count, 1)
        
        networkManager.deleteCustomHeader(header.id)
        XCTAssertEqual(networkManager.configuration.headersCookiesConfig.customHeaders.count, 0)
    }
    
    func testHTTPCookieCreation() async throws {
        let cookie = HTTPCookieInfo(
            name: "session",
            value: "abc123",
            domain: "example.com",
            path: "/"
        )
        
        XCTAssertEqual(cookie.name, "session")
        XCTAssertEqual(cookie.domain, "example.com")
        XCTAssertTrue(cookie.isValid)
    }
    
    func testHTTPCookieValidation() async throws {
let invalid = HTTPCookieInfo(name: "", value: "value", domain: "example.com")
        XCTAssertFalse(invalid.isValid)
        
        let valid = HTTPCookieInfo(name: "test", value: "value", domain: "example.com")
        XCTAssertTrue(valid.isValid)
    }
    
    func testHTTPCookieExpiration() async throws {
        let expired = HTTPCookieInfo(
            name: "old",
            value: "xyz",
            domain: "example.com",
            expires: Date().addingTimeInterval(-3600)
        )
        XCTAssertTrue(expired.isExpired)
        
        let fresh = HTTPCookieInfo(
            name: "new",
            value: "abc",
            domain: "example.com",
            expires: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(fresh.isExpired)
    }
    
    func testCookieConversionToHTTPCookie() async throws {
        let cookieInfo = HTTPCookieInfo(
            name: "test",
            value: "value",
            domain: "example.com",
            path: "/",
            isSecure: true
        )
        
        let httpCookie = cookieInfo.toHTTPCookie()
        XCTAssertNotNil(httpCookie)
        XCTAssertEqual(httpCookie?.name, "test")
        XCTAssertEqual(httpCookie?.domain, "example.com")
    }
    
    func testAddCustomCookie() async throws {
        let cookie = HTTPCookieInfo(name: "test", value: "value", domain: "example.com")
        networkManager.addCustomCookie(cookie)
        
        let cookies = networkManager.configuration.headersCookiesConfig.customCookies
        XCTAssertEqual(cookies.count, 1)
        XCTAssertEqual(cookies.first?.name, "test")
    }
    
    func testUpdateCustomCookie() async throws {
        var cookie = HTTPCookieInfo(name: "test", value: "original", domain: "example.com")
        networkManager.addCustomCookie(cookie)
        
        cookie.value = "updated"
        networkManager.updateCustomCookie(cookie)
        
        let cookies = networkManager.configuration.headersCookiesConfig.customCookies
        XCTAssertEqual(cookies.first?.value, "updated")
    }
    
    func testDeleteCustomCookie() async throws {
        let cookie = HTTPCookieInfo(name: "delete", value: "me", domain: "example.com")
        networkManager.addCustomCookie(cookie)
        XCTAssertEqual(networkManager.configuration.headersCookiesConfig.customCookies.count, 1)
        
        networkManager.deleteCustomCookie(cookie.id)
        XCTAssertEqual(networkManager.configuration.headersCookiesConfig.customCookies.count, 0)
    }
    
    func testGetHeadersForURL() async throws {
        let header = HTTPHeader(
            key: "X-Custom",
            value: "Value",
            isEnabled: true,
            applyToAllDownloads: true
        )
        networkManager.addCustomHeader(header)
        
        let url = URL(string: "https://example.com/test")!
        let headers = networkManager.getHeadersForURL(url)
        
        XCTAssertEqual(headers["X-Custom"], "Value")
        XCTAssertNotNil(headers["User-Agent"]) // Should include default user agent
    }
    
    func testGetCookiesForURL() async throws {
        let cookie = HTTPCookieInfo(
            name: "test",
            value: "value",
            domain: "example.com",
            isEnabled: true
        )
        networkManager.addCustomCookie(cookie)
        
        let url = URL(string: "https://example.com/test")!
        let cookies = networkManager.getCookiesForURL(url)
        
        XCTAssertEqual(cookies.count, 1)
        XCTAssertEqual(cookies.first?.name, "test")
    }
    
    func testUpdateHeadersCookiesConfig() async throws {
        var config = HeadersCookiesConfig(
            sendUserAgent: false,
            userAgent: "Custom/1.0",
            sendReferrer: false
        )
        
        networkManager.updateHeadersCookiesConfig(config)
        
        XCTAssertFalse(networkManager.configuration.headersCookiesConfig.sendUserAgent)
        XCTAssertEqual(networkManager.configuration.headersCookiesConfig.userAgent, "Custom/1.0")
    }
    
    // MARK: - Network Statistics Tests
    
    func testNetworkStatistics() async throws {
        let stats = NetworkStatistics(
            totalBytesSent: 1000,
            totalBytesReceived: 5000,
            totalConnections: 10,
            failedConnections: 1
        )
        
        XCTAssertEqual(stats.totalBytesReceived, 5000)
        XCTAssertEqual(stats.totalConnections, 10)
        XCTAssertEqual(stats.successRate, 0.9)
    }
    
    func testUpdateStatistics() async throws {
        networkManager.resetStatistics()
        
        networkManager.updateStatistics(
            bytesSent: 500,
            bytesReceived: 2000,
            downloadSpeed: 1.5,
            uploadSpeed: 0.5,
            connectionSuccess: true,
            usedProxy: false
        )
        
        XCTAssertEqual(networkManager.networkStatistics.totalBytesSent, 500)
        XCTAssertEqual(networkManager.networkStatistics.totalBytesReceived, 2000)
        XCTAssertEqual(networkManager.networkStatistics.directConnections, 1)
    }
    
    func testResetStatistics() async throws {
        networkManager.updateStatistics(bytesSent: 1000, bytesReceived: 5000)
        
        networkManager.resetStatistics()
        
        XCTAssertEqual(networkManager.networkStatistics.totalBytesSent, 0)
        XCTAssertEqual(networkManager.networkStatistics.totalBytesReceived, 0)
    }
    
    // MARK: - Configuration Management Tests
    
    func testSaveAndLoadConfiguration() async throws {
        // Modify configuration
        let proxy = ProxyConfig(name: "Test", type: .http, host: "proxy.com", port: 8080)
        networkManager.addProxy(proxy)
        
        networkManager.saveConfiguration()
        
        // Configuration should persist
        let savedConfig = networkManager.configuration
        XCTAssertEqual(savedConfig.proxyConfigs.count, 1)
    }
    
    func testResetToDefaults() async throws {
        // Add some data
        let proxy = ProxyConfig(name: "Test", type: .http, host: "proxy.com", port: 8080)
        networkManager.addProxy(proxy)
        
        networkManager.resetToDefaults()
        
        XCTAssertEqual(networkManager.getAllProxies().count, 0)
        XCTAssertEqual(networkManager.configuration.timeout, 30.0)
        XCTAssertEqual(networkManager.configuration.retryAttempts, 3)
    }
    
    func testCreateURLSessionConfiguration() async throws {
        let sessionConfig = networkManager.createURLSessionConfiguration()
        
        XCTAssertNotNil(sessionConfig)
        XCTAssertEqual(sessionConfig.timeoutIntervalForRequest, 30.0)
        XCTAssertNotNil(sessionConfig.httpAdditionalHeaders)
    }
    
    func testURLSessionConfigurationWithProxy() async throws {
        let proxy = ProxyConfig(name: "Test", type: .http, host: "proxy.com", port: 8080)
        networkManager.addProxy(proxy)
        networkManager.setActiveProxy(proxy.id)
        
        let sessionConfig = networkManager.createURLSessionConfiguration()
        
        XCTAssertNotNil(sessionConfig.connectionProxyDictionary)
    }
    
    // MARK: - Complete Network Configuration Tests
    
    func testCompleteNetworkConfiguration() async throws {
        let config = NetworkConfiguration.default
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config.timeout, 30.0)
        XCTAssertEqual(config.retryAttempts, 3)
        XCTAssertTrue(config.followRedirects)
        XCTAssertEqual(config.maxRedirects, 5)
    }
    
    func testGetActiveProxyFromConfiguration() async throws {
        let proxyID = UUID()
        let proxy = ProxyConfig(id: proxyID, name: "Active", type: .http, host: "proxy.com", port: 8080)
        
        var config = NetworkConfiguration.default
        config.proxyConfigs = [proxy]
        config.activeProxyID = proxyID
        
        let active = config.getActiveProxy()
        XCTAssertNotNil(active)
        XCTAssertEqual(active?.name, "Active")
    }
    
    // MARK: - JSON Encoding/Decoding Tests
    
    func testProxyConfigCodable() async throws {
        let proxy = ProxyConfig(
            name: "Test",
            type: .socks5,
            host: "localhost",
            port: 1080,
            requiresAuthentication: true,
            username: "user",
            password: "pass"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(proxy)
        let decoded = try decoder.decode(ProxyConfig.self, from: data)
        
        XCTAssertEqual(decoded.name, proxy.name)
        XCTAssertEqual(decoded.type, proxy.type)
        XCTAssertEqual(decoded.host, proxy.host)
    }
    
    func testNetworkConfigurationCodable() async throws {
        let config = NetworkConfiguration.default
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(NetworkConfiguration.self, from: data)
        
        XCTAssertEqual(decoded.timeout, config.timeout)
        XCTAssertEqual(decoded.retryAttempts, config.retryAttempts)
    }
    
    func testNetworkStatisticsCodable() async throws {
        let stats = NetworkStatistics(
            totalBytesSent: 1000,
            totalBytesReceived: 5000,
            totalConnections: 10
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(stats)
        let decoded = try decoder.decode(NetworkStatistics.self, from: data)
        
        XCTAssertEqual(decoded.totalBytesReceived, stats.totalBytesReceived)
        XCTAssertEqual(decoded.totalConnections, stats.totalConnections)
    }
}
