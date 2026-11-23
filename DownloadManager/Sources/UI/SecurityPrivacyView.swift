import SwiftUI

/// View for security and privacy settings
public struct SecurityPrivacyView: View {
    @StateObject private var manager = SecurityPrivacyManager()
    @State private var selectedTab = 0
    @State private var showPasswordSheet = false
    @State private var showScanSheet = false
    @State private var passwordInput = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var scanFilePath = ""
    @State private var isScanning = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Encryption").tag(1)
                Text("Scanning").tag(2)
                Text("Privacy").tag(3)
                Text("Events").tag(4)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                overviewTab.tag(0)
                encryptionTab.tag(1)
                scanningTab.tag(2)
                privacyTab.tag(3)
                eventsTab.tag(4)
            }
            .tabViewStyle(.automatic)
        }
        .sheet(isPresented: $showPasswordSheet) {
            passwordSheetView
        }
        .sheet(isPresented: $showScanSheet) {
            scanSheetView
        }
        .alert("Security Alert", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "shield.fill")
                .font(.largeTitle)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Security & Privacy")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Protect your downloads and data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Security level indicator
            HStack(spacing: 8) {
                Image(systemName: manager.config.securityLevel.icon)
                    .foregroundColor(securityLevelColor)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(manager.config.securityLevel.displayName)
                        .font(.headline)
                    Text("Security Level")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .padding()
    }
    
    private var securityLevelColor: Color {
        switch manager.config.securityLevel {
        case .none: return .gray
        case .basic: return .yellow
        case .standard: return .orange
        case .high: return .blue
        case .maximum: return .green
        }
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Security level selector
                securityLevelSection
                
                // Quick stats
                statsSection
                
                // Feature status
                featuresSection
                
                // VPN status
                vpnStatusSection
            }
            .padding()
        }
    }
    
    private var securityLevelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security Level")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(SecurityLevel.allCases, id: \.self) { level in
                    Button(action: {
                        manager.updateSecurityLevel(level)
                    }) {
                        HStack {
                            Image(systemName: level.icon)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.displayName)
                                    .font(.headline)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if manager.config.securityLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(manager.config.securityLevel == level ? 
                                      Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var statsSection: some View {
        let stats = manager.getSecurityStats()
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                SecurityStatCard(
                    title: "Total Scans",
                    value: "\(stats.totalScans)",
                    icon: "magnifyingglass.circle",
                    color: .blue
                )
                
                SecurityStatCard(
                    title: "Threats Detected",
                    value: "\(stats.threatsDetected)",
                    icon: "exclamationmark.triangle",
                    color: .red
                )
                
                SecurityStatCard(
                    title: "Clean Files",
                    value: "\(stats.cleanFiles)",
                    icon: "checkmark.circle",
                    color: .green
                )
            }
        }
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Features")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(SecurityFeature.allCases, id: \.self) { feature in
                    HStack {
                        Image(systemName: feature.icon)
                            .frame(width: 25)
                            .foregroundColor(manager.config.isFeatureEnabled(feature) ? .green : .gray)
                        
                        Text(feature.displayName)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        if manager.config.isFeatureEnabled(feature) {
                            Text("Enabled")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.05))
            )
        }
    }
    
    private var vpnStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VPN Status")
                .font(.headline)
            
            HStack {
                Image(systemName: manager.vpnStatus.isConnected ? "network" : "network.slash")
                    .font(.title2)
                    .foregroundColor(manager.vpnStatus.isConnected ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.vpnStatus.isConnected ? "Connected" : "Not Connected")
                        .font(.headline)
                    
                    if manager.vpnStatus.isConnected, let connectedAt = manager.vpnStatus.connectedAt {
                        Text("Since \(connectedAt, style: .time)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.05))
            )
        }
    }
    
    // MARK: - Encryption Tab
    
    private var encryptionTab: some View {
        Form {
            Section {
                Toggle("Enable Encryption", isOn: $manager.config.encryption.isEnabled)
                
                if manager.config.encryption.isEnabled {
                    Picker("Algorithm", selection: $manager.config.encryption.algorithm) {
                        ForEach([
                            EncryptionConfig.EncryptionAlgorithm.aes256GCM,
                            .aes256CBC,
                            .chacha20
                        ], id: \.self) { algorithm in
                            Text(algorithm.displayName).tag(algorithm)
                        }
                    }
                    
                    Picker("Key Derivation", selection: $manager.config.encryption.keyDerivation) {
                        ForEach([
                            EncryptionConfig.KeyDerivationMethod.pbkdf2,
                            .argon2,
                            .scrypt
                        ], id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    
                    Toggle("Encrypt Filenames", isOn: $manager.config.encryption.encryptFilenames)
                    Toggle("Encrypt Metadata", isOn: $manager.config.encryption.encryptMetadata)
                }
            } header: {
                Text("Encryption Settings")
            } footer: {
                Text("End-to-end encryption protects your downloaded files using AES-256 encryption")
            }
            
            Section {
                Button("Set Master Password") {
                    showPasswordSheet = true
                }
                
                if manager.config.masterPassword != nil {
                    Button("Change Password") {
                        showPasswordSheet = true
                    }
                    
                    Button("Remove Password", role: .destructive) {
                        manager.config.masterPassword = nil
                        manager.saveConfiguration()
                    }
                }
            } header: {
                Text("Password Protection")
            }
        }
        .formStyle(.grouped)
        .onChange(of: manager.config.encryption) { _ in
            manager.saveConfiguration()
        }
    }
    
    // MARK: - Scanning Tab
    
    private var scanningTab: some View {
        Form {
            Section {
                Toggle("Enable Virus Scanning", isOn: $manager.config.virusScan.isEnabled)
                
                if manager.config.virusScan.isEnabled {
                    Picker("Scan Engine", selection: $manager.config.virusScan.scanEngine) {
                        ForEach([
                            VirusScanConfig.ScanEngine.clamav,
                            .macos,
                            .custom
                        ], id: \.self) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    
                    Toggle("Scan After Download", isOn: $manager.config.virusScan.scanAfterDownload)
                    Toggle("Scan Before Open", isOn: $manager.config.virusScan.scanBeforeOpen)
                    Toggle("Quarantine Threats", isOn: $manager.config.virusScan.quarantineThreats)
                    Toggle("Delete Threats", isOn: $manager.config.virusScan.deleteThreats)
                }
            } header: {
                Text("Virus Scanning")
            } footer: {
                Text("Automatically scan downloaded files for viruses and malware")
            }
            
            Section {
                Toggle("Enable Malicious Detection", isOn: $manager.config.maliciousDetection.isEnabled)
                
                if manager.config.maliciousDetection.isEnabled {
                    Toggle("Check Blacklist", isOn: $manager.config.maliciousDetection.checkBlacklist)
                    Toggle("Check Reputation", isOn: $manager.config.maliciousDetection.checkReputation)
                    Toggle("Block Suspicious URLs", isOn: $manager.config.maliciousDetection.blockSuspiciousURLs)
                    Toggle("Warn on Untrusted Sites", isOn: $manager.config.maliciousDetection.warnOnUntrustedSites)
                }
            } header: {
                Text("Malicious URL Detection")
            } footer: {
                Text("Check URLs against known malicious sites before downloading")
            }
            
            Section {
                Button("Scan File...") {
                    showScanSheet = true
                }
                
                Button("Clear Scan History") {
                    manager.clearScanHistory()
                }
            } header: {
                Text("Actions")
            }
            
            Section {
                if manager.scanResults.isEmpty {
                    Text("No scan results")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.scanResults.prefix(10)) { result in
                        scanResultRow(result)
                    }
                }
            } header: {
                Text("Recent Scans")
            }
        }
        .formStyle(.grouped)
        .onChange(of: manager.config.virusScan) { _ in
            manager.saveConfiguration()
        }
        .onChange(of: manager.config.maliciousDetection) { _ in
            manager.saveConfiguration()
        }
    }
    
    private func scanResultRow(_ result: SecurityScanResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: result.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.isClean ? .green : .red)
                
                Text(URL(fileURLWithPath: result.url).lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Spacer()
                
                Text(result.scanDate, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !result.isClean {
                ForEach(result.threats) { threat in
                    HStack {
                        Image(systemName: threat.type.icon)
                            .font(.caption)
                        
                        Text(threat.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 25)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Privacy Tab
    
    private var privacyTab: some View {
        Form {
            Section {
                Toggle("Enable Private Mode", isOn: Binding(
                    get: { manager.config.privateMode.isEnabled },
                    set: { newValue in
                        if newValue {
                            manager.enablePrivateMode()
                        } else {
                            manager.disablePrivateMode()
                        }
                    }
                ))
                
                if manager.config.privateMode.isEnabled {
                    Toggle("Disable History", isOn: $manager.config.privateMode.disableHistory)
                    Toggle("Disable Statistics", isOn: $manager.config.privateMode.disableStatistics)
                    Toggle("Clear on Exit", isOn: $manager.config.privateMode.clearOnExit)
                    Toggle("Disable Preview", isOn: $manager.config.privateMode.disablePreview)
                }
            } header: {
                Text("Private Mode")
            } footer: {
                Text("Private mode prevents saving download history and statistics")
            }
            
            Section {
                Toggle("Enable VPN Detection", isOn: $manager.config.vpnDetection.isEnabled)
                
                if manager.config.vpnDetection.isEnabled {
                    Toggle("Pause on VPN Disconnect", isOn: $manager.config.vpnDetection.pauseOnVPNDisconnect)
                    Toggle("Resume on VPN Connect", isOn: $manager.config.vpnDetection.resumeOnVPNConnect)
                    Toggle("Prefer VPN Connection", isOn: $manager.config.vpnDetection.preferVPNConnection)
                    Toggle("Notify on VPN Change", isOn: $manager.config.vpnDetection.notifyOnVPNChange)
                }
            } header: {
                Text("VPN Detection")
            } footer: {
                Text("Automatically detect VPN connections and adjust download behavior")
            }
            
            Section {
                Button("Clear Private Data") {
                    manager.clearPrivateData()
                    alertMessage = "Private data cleared"
                    showAlert = true
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .onChange(of: manager.config.privateMode) { _ in
            manager.saveConfiguration()
        }
        .onChange(of: manager.config.vpnDetection) { _ in
            manager.saveConfiguration()
        }
    }
    
    // MARK: - Events Tab
    
    private var eventsTab: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Security Events")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear") {
                    manager.clearEventLog()
                }
            }
            .padding()
            
            Divider()
            
            // Events list
            if manager.events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No security events")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.events) { event in
                        eventRow(event)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func eventRow(_ event: SecurityEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.type.icon)
                .font(.title3)
                .foregroundColor(severityColor(event.severity))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.type.displayName)
                    .font(.headline)
                
                Text(event.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(event.timestamp, style: .time)
                    Text("•")
                    Text(event.severity.displayName)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func severityColor(_ severity: SecurityThreat.ThreatSeverity) -> Color {
        switch severity {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
    
    // MARK: - Password Sheet
    
    private var passwordSheetView: some View {
        NavigationView {
            Form {
                if manager.config.masterPassword != nil {
                    Section {
                        SecureField("Current Password", text: $passwordInput)
                    } header: {
                        Text("Current Password")
                    }
                }
                
                Section {
                    SecureField("New Password", text: $newPassword)
                    SecureField("Confirm Password", text: $confirmPassword)
                } header: {
                    Text("New Password")
                }
            }
            .navigationTitle("Set Master Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPasswordSheet = false
                        clearPasswordFields()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePassword()
                    }
                    .disabled(newPassword.isEmpty || newPassword != confirmPassword)
                }
            }
        }
    }
    
    private func savePassword() {
        // Verify current password if one exists
        if let _ = manager.config.masterPassword {
            guard manager.authenticate(password: passwordInput) else {
                alertMessage = "Current password is incorrect"
                showAlert = true
                return
            }
        }
        
        do {
            try manager.setMasterPassword(newPassword)
            showPasswordSheet = false
            clearPasswordFields()
            alertMessage = "Password set successfully"
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
    
    private func clearPasswordFields() {
        passwordInput = ""
        newPassword = ""
        confirmPassword = ""
    }
    
    // MARK: - Scan Sheet
    
    private var scanSheetView: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isScanning {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Scanning file...")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section {
                            TextField("File Path", text: $scanFilePath)
                            
                            Button("Choose File...") {
                                // In real app, show file picker
                            }
                        } header: {
                            Text("File to Scan")
                        }
                        
                        Section {
                            Button("Start Scan") {
                                performScan()
                            }
                            .disabled(scanFilePath.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Scan File")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showScanSheet = false
                        scanFilePath = ""
                    }
                    .disabled(isScanning)
                }
            }
        }
    }
    
    private func performScan() {
        let fileURL = URL(fileURLWithPath: scanFilePath)
        
        isScanning = true
        
        Task {
            do {
                let result = try await manager.scanFile(fileURL)
                
                await MainActor.run {
                    isScanning = false
                    showScanSheet = false
                    scanFilePath = ""
                    
                    if result.isClean {
                        alertMessage = "File is clean"
                    } else {
                        alertMessage = "Threats detected: \(result.threats.count)"
                    }
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    isScanning = false
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}

// MARK: - Security Stat Card

struct SecurityStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

// MARK: - Preview

struct SecurityPrivacyView_Previews: PreviewProvider {
    static var previews: some View {
        SecurityPrivacyView()
            .frame(width: 800, height: 600)
    }
}
