import SwiftUI

/// Network settings view
public struct NetworkSettingsView: View {
    
    @StateObject private var networkManager = NetworkManager.shared
    @State private var selectedTab: Tab = .proxy
    @State private var showingProxyEditor = false
    @State private var editingProxy: ProxyConfig?
    @State private var showingMirrorEditor = false
    @State private var editingMirror: MirrorServer?
    @State private var showingHeaderEditor = false
    @State private var editingHeader: HTTPHeader?
    @State private var showingCookieEditor = false
    @State private var editingCookie: HTTPCookieInfo?
    @State private var testingProxy: UUID?
    @State private var proxyTestResult: String?
    @State private var showingResetAlert = false
    
    // MARK: - Body
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                proxySettingsView
                HStack {
                    Spacer()
                    Button("Reset Network Settings", role: .destructive) { showingResetAlert = true }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingProxyEditor) {
            ProxyEditorView(
                proxy: editingProxy ?? ProxyConfig(),
                onSave: { proxy in
                    if let existing = editingProxy {
                        networkManager.updateProxy(proxy)
                    } else {
                        networkManager.addProxy(proxy)
                    }
                    showingProxyEditor = false
                    editingProxy = nil
                }
            )
        }
        .sheet(isPresented: $showingMirrorEditor) {
            MirrorEditorView(
                mirror: editingMirror ?? MirrorServer(name: "New Mirror", baseURL: URL(string: "https://example.com")!),
                onSave: { mirror in
                    if let existing = editingMirror {
                        networkManager.updateMirror(mirror)
                    } else {
                        networkManager.addMirror(mirror)
                    }
                    showingMirrorEditor = false
                    editingMirror = nil
                }
            )
        }
        .sheet(isPresented: $showingHeaderEditor) {
            HeaderEditorView(
                header: editingHeader ?? HTTPHeader(key: "", value: ""),
                onSave: { header in
                    if let existing = editingHeader {
                        networkManager.updateCustomHeader(header)
                    } else {
                        networkManager.addCustomHeader(header)
                    }
                    showingHeaderEditor = false
                    editingHeader = nil
                }
            )
        }
        .sheet(isPresented: $showingCookieEditor) {
            CookieEditorView(
                cookie: editingCookie ?? HTTPCookieInfo(name: "", value: "", domain: ""),
                onSave: { cookie in
                    if let existing = editingCookie {
                        networkManager.updateCustomCookie(cookie)
                    } else {
                        networkManager.addCustomCookie(cookie)
                    }
                    showingCookieEditor = false
                    editingCookie = nil
                }
            )
        }
        .alert("Reset Network Settings", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                networkManager.resetToDefaults()
            }
        } message: {
            Text("This will reset all network settings to defaults. This action cannot be undone.")
        }
    }
    
    // MARK: - Proxy Settings View
    
    private var proxySettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Proxy Configuration")
                .font(.headline)
            
            // Proxy list
            GroupBox {
                VStack(spacing: 12) {
                    ForEach(networkManager.getAllProxies()) { proxy in
                        proxyRow(proxy)
                    }
                    
                    if networkManager.getAllProxies().isEmpty {
                        Text("No proxy configurations")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    
                    Button(action: {
                        editingProxy = nil
                        showingProxyEditor = true
                    }) {
                        Label("Add Proxy", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // System proxy
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Proxy")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let systemProxy = networkManager.getSystemProxySettings() {
                        Text("\(systemProxy.host):\(systemProxy.port)")
                            .foregroundColor(.secondary)
                    } else {
                        Text("No system proxy configured")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
    }
    
    private func proxyRow(_ proxy: ProxyConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(proxy.name)
                        .fontWeight(.medium)
                    
                    if networkManager.configuration.activeProxyID == proxy.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                
                Text("\(proxy.type.displayName) • \(proxy.host):\(proxy.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let result = proxyTestResult, testingProxy == proxy.id {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("success") ? .green : .red)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: {
                    testingProxy = proxy.id
                    Task {
                        let result = await networkManager.testProxy(proxy)
                        proxyTestResult = result.success ? "Test successful (\(String(format: "%.0fms", result.responseTime * 1000)))" : "Test failed: \(result.error ?? "Unknown error")"
                    }
                }) {
                    Image(systemName: "network")
                }
                .buttonStyle(.borderless)
                .help("Test Proxy")
                
                Toggle("", isOn: Binding(
                    get: { networkManager.configuration.activeProxyID == proxy.id },
                    set: { isActive in
                        if isActive {
                            networkManager.setActiveProxy(proxy.id)
                        } else {
                            networkManager.setActiveProxy(nil)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                
                Menu {
                    Button("Edit") {
                        editingProxy = proxy
                        showingProxyEditor = true
                    }
                    Button("Duplicate") {
                        let newProxy = ProxyConfig(
                            name: "\(proxy.name) Copy",
                            type: proxy.type,
                            host: proxy.host,
                            port: proxy.port,
                            requiresAuthentication: proxy.requiresAuthentication,
                            username: proxy.username,
                            password: proxy.password,
                            authMethod: proxy.authMethod,
                            bypassList: proxy.bypassList,
                            isEnabled: proxy.isEnabled
                        )
                        networkManager.addProxy(newProxy)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        networkManager.deleteProxy(proxy.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - VPN Settings View
    
    private var vpnSettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VPN Detection & Handling")
                .font(.headline)
            
            // VPN status
            GroupBox {
                HStack {
                    Image(systemName: networkManager.currentVPNStatus.icon)
                        .foregroundColor(networkManager.currentVPNStatus.color == "green" ? .green : networkManager.currentVPNStatus.color == "orange" ? .orange : .gray)
                    
                    VStack(alignment: .leading) {
                        Text("VPN Status")
                            .font(.subheadline)
                        Text(networkManager.currentVPNStatus.displayName)
                            .fontWeight(.medium)
                        
                        if let vpnConnection = networkManager.currentVPNConnection {
                            Text(vpnConnection.interfaceName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Refresh") {
                        Task {
                            await networkManager.detectVPNStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // VPN configuration
            GroupBox {
                Form {
                    Toggle("Enable VPN Detection", isOn: Binding(
                        get: { networkManager.configuration.vpnConfig.isEnabled },
                        set: { value in
                            var config = networkManager.configuration.vpnConfig
                            config.isEnabled = value
                            networkManager.updateVPNConfig(config)
                        }
                    ))
                    
                    Toggle("Auto-detect VPN Changes", isOn: Binding(
                        get: { networkManager.configuration.vpnConfig.autoDetect },
                        set: { value in
                            var config = networkManager.configuration.vpnConfig
                            config.autoDetect = value
                            networkManager.updateVPNConfig(config)
                        }
                    ))
                    
                    Toggle("Pause Downloads on Disconnect", isOn: Binding(
                        get: { networkManager.configuration.vpnConfig.pauseDownloadsOnDisconnect },
                        set: { value in
                            var config = networkManager.configuration.vpnConfig
                            config.pauseDownloadsOnDisconnect = value
                            networkManager.updateVPNConfig(config)
                        }
                    ))
                    
                    Toggle("Resume Downloads on Connect", isOn: Binding(
                        get: { networkManager.configuration.vpnConfig.resumeDownloadsOnConnect },
                        set: { value in
                            var config = networkManager.configuration.vpnConfig
                            config.resumeDownloadsOnConnect = value
                            networkManager.updateVPNConfig(config)
                        }
                    ))
                    
                    Toggle("Show VPN Status Notifications", isOn: Binding(
                        get: { networkManager.configuration.vpnConfig.showNotifications },
                        set: { value in
                            var config = networkManager.configuration.vpnConfig
                            config.showNotifications = value
                            networkManager.updateVPNConfig(config)
                        }
                    ))
                }
                .formStyle(.grouped)
            }
        }
    }
    
    // MARK: - Network Interfaces View
    
    private var interfacesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Interfaces")
                .font(.headline)
            
            // Available interfaces
            GroupBox("Available Interfaces") {
                VStack(spacing: 12) {
                    ForEach(networkManager.availableInterfaces) { interface in
                        HStack {
                            Image(systemName: interface.type.icon)
                                .foregroundColor(interface.isActive ? .green : .gray)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(interface.displayName)
                                    .fontWeight(.medium)
                                Text(interface.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if let ip = interface.ipAddress {
                                    Text("IP: \(ip)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if interface.isActive {
                                Text("Active")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Button("Refresh Interfaces") {
                        Task {
                            await networkManager.detectNetworkInterfaces()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // Interface preferences
            GroupBox("Preferences") {
                Form {
                    Toggle("Automatic Interface Selection", isOn: Binding(
                        get: { networkManager.configuration.interfacePreference.automaticSelection },
                        set: { value in
                            var pref = networkManager.configuration.interfacePreference
                            pref.automaticSelection = value
                            networkManager.updateInterfacePreference(pref)
                        }
                    ))
                    
                    Toggle("Avoid Metered Connections", isOn: Binding(
                        get: { networkManager.configuration.interfacePreference.avoidMeteredConnections },
                        set: { value in
                            var pref = networkManager.configuration.interfacePreference
                            pref.avoidMeteredConnections = value
                            networkManager.updateInterfacePreference(pref)
                        }
                    ))
                    
                    Toggle("Prefer Faster Connections", isOn: Binding(
                        get: { networkManager.configuration.interfacePreference.preferFasterConnections },
                        set: { value in
                            var pref = networkManager.configuration.interfacePreference
                            pref.preferFasterConnections = value
                            networkManager.updateInterfacePreference(pref)
                        }
                    ))
                }
                .formStyle(.grouped)
            }
        }
    }
    
    // MARK: - Mirrors View
    
    private var mirrorsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mirror Servers")
                .font(.headline)
            
            // Mirror configuration
            GroupBox {
                Form {
                    Toggle("Enable Mirror Support", isOn: Binding(
                        get: { networkManager.configuration.mirrorConfig.isEnabled },
                        set: { value in
                            var config = networkManager.configuration.mirrorConfig
                            config.isEnabled = value
                            networkManager.updateMirrorConfig(config)
                        }
                    ))
                    
                    Picker("Selection Strategy", selection: Binding(
                        get: { networkManager.configuration.mirrorConfig.selectionStrategy },
                        set: { value in
                            var config = networkManager.configuration.mirrorConfig
                            config.selectionStrategy = value
                            networkManager.updateMirrorConfig(config)
                        }
                    )) {
                        ForEach(MirrorSelectionStrategy.allCases, id: \.rawValue) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    
                    Toggle("Auto-detect Mirrors", isOn: Binding(
                        get: { networkManager.configuration.mirrorConfig.autoDetect },
                        set: { value in
                            var config = networkManager.configuration.mirrorConfig
                            config.autoDetect = value
                            networkManager.updateMirrorConfig(config)
                        }
                    ))
                }
                .formStyle(.grouped)
            }
            
            // Mirror list
            GroupBox("Configured Mirrors") {
                VStack(spacing: 12) {
                    ForEach(networkManager.getAllMirrors()) { mirror in
                        mirrorRow(mirror)
                    }
                    
                    if networkManager.getAllMirrors().isEmpty {
                        Text("No mirror servers configured")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    
                    HStack {
                        Button(action: {
                            editingMirror = nil
                            showingMirrorEditor = true
                        }) {
                            Label("Add Mirror", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            Task {
                                await networkManager.checkAllMirrors()
                            }
                        }) {
                            Label("Check All", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
        }
    }
    
    private func mirrorRow(_ mirror: MirrorServer) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(mirror.name)
                    .fontWeight(.medium)
                
                Text(mirror.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let responseTime = mirror.lastResponseTime {
                    HStack(spacing: 8) {
                        Text("Response: \(Int(responseTime * 1000))ms")
                        Text("•")
                        Text("Success: \(Int(mirror.successRate * 100))%")
                    }
                    .font(.caption)
                    .foregroundColor(mirror.isHealthy ? .green : .orange)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if mirror.isHealthy {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                Toggle("", isOn: Binding(
                    get: { mirror.isEnabled },
                    set: { value in
                        var updated = mirror
                        updated.isEnabled = value
                        networkManager.updateMirror(updated)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                
                Menu {
                    Button("Edit") {
                        editingMirror = mirror
                        showingMirrorEditor = true
                    }
                    Button("Check Health") {
                        Task {
                            _ = await networkManager.checkMirrorHealth(mirror)
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        networkManager.deleteMirror(mirror.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - SSL Settings View
    
    private var sslSettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSL/TLS Configuration")
                .font(.headline)
            
            GroupBox {
                Form {
                    Picker("Validation Level", selection: Binding(
                        get: { networkManager.configuration.sslConfig.validationLevel },
                        set: { value in
                            var config = networkManager.configuration.sslConfig
                            config.validationLevel = value
                            networkManager.updateSSLConfig(config)
                        }
                    )) {
                        ForEach(SSLValidationLevel.allCases, id: \.rawValue) { level in
                            VStack(alignment: .leading) {
                                Text(level.displayName)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(level)
                        }
                    }
                    
                    Toggle("Allow Self-Signed Certificates", isOn: Binding(
                        get: { networkManager.configuration.sslConfig.allowSelfSigned },
                        set: { value in
                            var config = networkManager.configuration.sslConfig
                            config.allowSelfSigned = value
                            networkManager.updateSSLConfig(config)
                        }
                    ))
                    
                    Toggle("Allow Expired Certificates", isOn: Binding(
                        get: { networkManager.configuration.sslConfig.allowExpired },
                        set: { value in
                            var config = networkManager.configuration.sslConfig
                            config.allowExpired = value
                            networkManager.updateSSLConfig(config)
                        }
                    ))
                    
                    Toggle("Check Certificate Revocation", isOn: Binding(
                        get: { networkManager.configuration.sslConfig.checkRevocation },
                        set: { value in
                            var config = networkManager.configuration.sslConfig
                            config.checkRevocation = value
                            networkManager.updateSSLConfig(config)
                        }
                    ))
                }
                .formStyle(.grouped)
            }
            
            // Trusted domains
            GroupBox("Trusted Domains") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(networkManager.configuration.sslConfig.trustedDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Button(action: {
                                networkManager.removeTrustedDomain(domain)
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    
                    if networkManager.configuration.sslConfig.trustedDomains.isEmpty {
                        Text("No trusted domains")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Headers View
    
    private var headersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Headers & Cookies")
                .font(.headline)
            
            // Standard headers
            GroupBox("Standard Headers") {
                Form {
                    Toggle("Send User-Agent", isOn: Binding(
                        get: { networkManager.configuration.headersCookiesConfig.sendUserAgent },
                        set: { value in
                            var config = networkManager.configuration.headersCookiesConfig
                            config.sendUserAgent = value
                            networkManager.updateHeadersCookiesConfig(config)
                        }
                    ))
                    
                    if networkManager.configuration.headersCookiesConfig.sendUserAgent {
                        TextField("User-Agent", text: Binding(
                            get: { networkManager.configuration.headersCookiesConfig.userAgent },
                            set: { value in
                                var config = networkManager.configuration.headersCookiesConfig
                                config.userAgent = value
                                networkManager.updateHeadersCookiesConfig(config)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    
                    Toggle("Send Referrer", isOn: Binding(
                        get: { networkManager.configuration.headersCookiesConfig.sendReferrer },
                        set: { value in
                            var config = networkManager.configuration.headersCookiesConfig
                            config.sendReferrer = value
                            networkManager.updateHeadersCookiesConfig(config)
                        }
                    ))
                    
                    Toggle("Send Accept-Language", isOn: Binding(
                        get: { networkManager.configuration.headersCookiesConfig.sendAcceptLanguage },
                        set: { value in
                            var config = networkManager.configuration.headersCookiesConfig
                            config.sendAcceptLanguage = value
                            networkManager.updateHeadersCookiesConfig(config)
                        }
                    ))
                }
                .formStyle(.grouped)
            }
            
            // Custom headers
            GroupBox("Custom Headers") {
                VStack(spacing: 12) {
                    ForEach(networkManager.configuration.headersCookiesConfig.customHeaders) { header in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(header.key)
                                    .fontWeight(.medium)
                                Text(header.value)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { header.isEnabled },
                                set: { value in
                                    var updated = header
                                    updated.isEnabled = value
                                    networkManager.updateCustomHeader(updated)
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            
                            Button(action: {
                                networkManager.deleteCustomHeader(header.id)
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    
                    Button(action: {
                        editingHeader = nil
                        showingHeaderEditor = true
                    }) {
                        Label("Add Header", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // Custom cookies
            GroupBox("Custom Cookies") {
                VStack(spacing: 12) {
                    ForEach(networkManager.configuration.headersCookiesConfig.customCookies) { cookie in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(cookie.name)
                                    .fontWeight(.medium)
                                Text("\(cookie.domain) • \(cookie.path)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { cookie.isEnabled },
                                set: { value in
                                    var updated = cookie
                                    updated.isEnabled = value
                                    networkManager.updateCustomCookie(updated)
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            
                            Button(action: {
                                networkManager.deleteCustomCookie(cookie.id)
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    
                    Button(action: {
                        editingCookie = nil
                        showingCookieEditor = true
                    }) {
                        Label("Add Cookie", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
    }
    
    // MARK: - Advanced Settings View
    
    private var advancedSettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced Network Settings")
                .font(.headline)
            
            GroupBox("Connection Settings") {
                Form {
                    HStack {
                        Text("Request Timeout")
                        Spacer()
                        TextField("Seconds", value: Binding(
                            get: { networkManager.configuration.timeout },
                            set: { value in
                                networkManager.updateTimeout(value)
                            }
                        ), format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Retry Attempts")
                        Spacer()
                        Stepper("\(networkManager.configuration.retryAttempts)", value: Binding(
                            get: { networkManager.configuration.retryAttempts },
                            set: { value in
                                networkManager.updateRetryAttempts(value)
                            }
                        ), in: 0...10)
                    }
                    
                    Toggle("Follow Redirects", isOn: Binding(
                        get: { networkManager.configuration.followRedirects },
                        set: { value in
                            networkManager.updateFollowRedirects(value)
                        }
                    ))
                    
                    HStack {
                        Text("Max Redirects")
                        Spacer()
                        Stepper("\(networkManager.configuration.maxRedirects)", value: Binding(
                            get: { networkManager.configuration.maxRedirects },
                            set: { value in
                                networkManager.updateMaxRedirects(value)
                            }
                        ), in: 1...20)
                    }
                }
                .formStyle(.grouped)
            }
            
            // Network statistics
            GroupBox("Network Statistics") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Total Downloaded:")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: networkManager.networkStatistics.totalBytesReceived, countStyle: .file))
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Total Uploaded:")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: networkManager.networkStatistics.totalBytesSent, countStyle: .file))
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Total Connections:")
                        Spacer()
                        Text("\(networkManager.networkStatistics.totalConnections)")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Success Rate:")
                        Spacer()
                        Text(String(format: "%.1f%%", networkManager.networkStatistics.successRate * 100))
                            .fontWeight(.medium)
                            .foregroundColor(networkManager.networkStatistics.successRate > 0.9 ? .green : .orange)
                    }
                    
                    Button("Reset Statistics") {
                        networkManager.resetStatistics()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
    }
    
    // MARK: - Tab Enum
    
    private enum Tab: String, CaseIterable, Identifiable {
        case proxy = "Proxy"
        case vpn = "VPN"
        case interfaces = "Interfaces"
        case mirrors = "Mirrors"
        case ssl = "SSL/TLS"
        case headers = "Headers & Cookies"
        case advanced = "Advanced"
        
        var id: String { rawValue }
        
        var displayName: String { rawValue }
        
        var icon: String {
            switch self {
            case .proxy: return "network"
            case .vpn: return "shield.fill"
            case .interfaces: return "cable.connector"
            case .mirrors: return "server.rack"
            case .ssl: return "lock.fill"
            case .headers: return "doc.text"
            case .advanced: return "gearshape.2.fill"
            }
        }
    }
}

// MARK: - Proxy Editor View

struct ProxyEditorView: View {
    @State var proxy: ProxyConfig
    let onSave: (ProxyConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $proxy.name)
                
                Picker("Type", selection: $proxy.type) {
                    ForEach(ProxyType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                
                TextField("Host", text: $proxy.host)
                TextField("Port", value: $proxy.port, format: .number)
                
                Toggle("Requires Authentication", isOn: $proxy.requiresAuthentication)
                
                if proxy.requiresAuthentication {
                    TextField("Username", text: $proxy.username)
                    SecureField("Password", text: $proxy.password)
                    
                    Picker("Auth Method", selection: $proxy.authMethod) {
                        ForEach(ProxyAuthMethod.allCases, id: \.rawValue) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                }
                
                Toggle("Enabled", isOn: $proxy.isEnabled)
            }
            .navigationTitle(proxy.id == UUID() ? "New Proxy" : "Edit Proxy")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                SwiftUI.ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(proxy)
                        dismiss()
                    }
                    .disabled(!proxy.isValid)
                }
            })
        }
    }
}

// MARK: - Mirror Editor View

struct MirrorEditorView: View {
    @State var mirror: MirrorServer
    let onSave: (MirrorServer) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var urlString: String
    
    init(mirror: MirrorServer, onSave: @escaping (MirrorServer) -> Void) {
        self._mirror = State(initialValue: mirror)
        self.onSave = onSave
        self._urlString = State(initialValue: mirror.baseURL.absoluteString)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $mirror.name)
                
                TextField("Base URL", text: $urlString)
                    .autocorrectionDisabled()
                
                TextField("Region", text: $mirror.region)
                
                Stepper("Priority: \(mirror.priority)", value: $mirror.priority, in: 0...100)
                
                Toggle("Enabled", isOn: $mirror.isEnabled)
            }
            .navigationTitle("Mirror Server")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                SwiftUI.ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let url = URL(string: urlString) {
                            mirror.baseURL = url
                            onSave(mirror)
                            dismiss()
                        }
                    }
                    .disabled(urlString.isEmpty || URL(string: urlString) == nil)
                }
            })
        }
    }
}

// MARK: - Header Editor View

struct HeaderEditorView: View {
    @State var header: HTTPHeader
    let onSave: (HTTPHeader) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Header Name", text: $header.key)
                TextField("Value", text: $header.value)
                Toggle("Enabled", isOn: $header.isEnabled)
                Toggle("Apply to All Downloads", isOn: $header.applyToAllDownloads)
                
                if !header.applyToAllDownloads {
                    TextField("Domain Pattern (optional)", text: Binding(
                        get: { header.domainPattern ?? "" },
                        set: { header.domainPattern = $0.isEmpty ? nil : $0 }
                    ))
                }
            }
            .navigationTitle("Custom Header")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                SwiftUI.ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(header)
                        dismiss()
                    }
                    .disabled(!header.isValid)
                }
            })
        }
    }
}

// MARK: - Cookie Editor View

struct CookieEditorView: View {
    @State var cookie: HTTPCookieInfo
    let onSave: (HTTPCookieInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $cookie.name)
                TextField("Value", text: $cookie.value)
                TextField("Domain", text: $cookie.domain)
                TextField("Path", text: $cookie.path)
                
                Toggle("Secure", isOn: $cookie.isSecure)
                Toggle("HTTP Only", isOn: $cookie.isHTTPOnly)
                Toggle("Enabled", isOn: $cookie.isEnabled)
            }
            .navigationTitle("Custom Cookie")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                SwiftUI.ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(cookie)
                        dismiss()
                    }
                    .disabled(!cookie.isValid)
                }
            })
        }
    }
}
