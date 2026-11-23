//
//  FileVerificationView.swift
//  DownloadManager
//
//  Feature #21: File Verification & Integrity
//  UI for file verification settings and management
//

import SwiftUI

public struct FileVerificationView: View {
    
    @StateObject private var verificationManager = FileVerificationManager.shared
    @State private var selectedTab: Tab = .configuration
    @State private var showingManualVerification = false
    @State private var showingResetAlert = false
    
    private enum Tab: String, CaseIterable, Identifiable {
        case configuration = "Configuration"
        case active = "Active"
        case history = "History"
        case statistics = "Statistics"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .configuration: return "gearshape"
            case .active: return "arrow.triangle.2.circlepath"
            case .history: return "clock.arrow.circlepath"
            case .statistics: return "chart.bar"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // Sidebar
            List(Tab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("File Verification")
            .listStyle(.sidebar)
        } detail: {
            // Detail view based on selected tab
            Group {
                switch selectedTab {
                case .configuration:
                    configurationView
                case .active:
                    activeVerificationsView
                case .history:
                    historyView
                case .statistics:
                    statisticsView
                }
            }            .navigationTitle(selectedTab.rawValue)
        }
        .sheet(isPresented: $showingManualVerification) {
            ManualVerificationView()
        }
        .alert("Reset Configuration", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                verificationManager.resetConfiguration()
            }
        } message: {
            Text("Are you sure you want to reset verification configuration to defaults?")
        }
    }
    
    // MARK: - Configuration View
    
    private var configurationView: some View {
        Form {
            Section("General") {
                Toggle("Enable Verification", isOn: binding(\.isEnabled))
                Toggle("Auto-verify on Download Complete", isOn: binding(\.autoVerifyOnComplete))
                Toggle("Verify in Background", isOn: binding(\.verifyInBackground))
                Toggle("Show Notifications", isOn: binding(\.showNotifications))
            }
            
            Section("Algorithms") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Default Algorithms")
                        .font(.headline)
                    
                    ForEach(HashAlgorithm.allCases) { algorithm in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { verificationManager.configuration.defaultAlgorithms.contains(algorithm) },
                                set: { isOn in
                                    if isOn {
                                        verificationManager.configuration.defaultAlgorithms.append(algorithm)
                                    } else {
                                        verificationManager.configuration.defaultAlgorithms.removeAll { $0 == algorithm }
                                    }
                                    verificationManager.updateConfiguration(verificationManager.configuration)
                                }
                            )) {
                                HStack {
                                    Image(systemName: algorithm.iconName)
                                        .foregroundColor(algorithm.isSecure ? .green : .orange)
                                    VStack(alignment: .leading) {
                                        Text(algorithm.displayName)
                                            .font(.body)
                                        Text(algorithm.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                
                HStack {
                    Button("Use Secure (SHA-256 + SHA-512)") {
                        verificationManager.updateConfiguration(.secure)
                    }
                    Button("Use Fast (CRC-32)") {
                        verificationManager.updateConfiguration(.fast)
                    }
                }
            }
            
            Section("Failure Handling") {
                Picker("Action on Failure", selection: binding(\.failureAction)) {
                    ForEach(VerificationFailureAction.allCases) { action in
                        Label(action.rawValue, systemImage: action.icon)
                            .tag(action)
                    }
                }
                
                Text(verificationManager.configuration.failureAction.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if verificationManager.configuration.failureAction == .redownload {
                    Stepper("Max Retries: \(verificationManager.configuration.maxRetries)",
                            value: binding(\.maxRetries), in: 1...10)
                }
                
                if verificationManager.configuration.failureAction == .quarantine {
                    HStack {
                        Text("Quarantine Path:")
                        TextField("Path", text: Binding(
                            get: { verificationManager.configuration.quarantinePath ?? "" },
                            set: { verificationManager.configuration.quarantinePath = $0.isEmpty ? nil : $0 }
                        ))
                        Button("Choose") {
                            // File picker would go here
                        }
                    }
                }
            }
            
            Section("Performance") {
                Toggle("Skip Small Files", isOn: binding(\.skipVerificationForSmallFiles))
                
                if verificationManager.configuration.skipVerificationForSmallFiles {
                    Stepper("Threshold: \(verificationManager.configuration.smallFileThresholdMB) MB",
                            value: binding(\.smallFileThresholdMB), in: 1...100)
                }
                
                Stepper("Buffer Size: \(verificationManager.configuration.bufferSize) bytes",
                        value: binding(\.bufferSize), in: 4096...65536, step: 4096)
            }
            
            Section {
                Button("Reset to Defaults", role: .destructive) {
                    showingResetAlert = true
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Active Verifications View
    
    private var activeVerificationsView: some View {
        Group {
            if verificationManager.activeVerifications.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No Active Verifications")
                        .font(.title2)
                        .foregroundColor(.primary)
                    Text("File verifications will appear here when in progress")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(verificationManager.activeVerifications.values), id: \.id) { result in
                        VerificationResultRow(result: result, isActive: true)
                    }
                }
            }
        }
    }
    
    // MARK: - History View
    
    private var historyView: some View {
        Group {
            if verificationManager.verificationHistory.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("No Verification History")
                        .font(.title2)
                        .foregroundColor(.primary)
                    Text("Completed verifications will appear here")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    List {
                        ForEach(verificationManager.verificationHistory) { result in
                            VerificationResultRow(result: result, isActive: false)
                        }
                    }
                    
                    HStack {
                        Text("\(verificationManager.verificationHistory.count) verifications")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear History", role: .destructive) {
                            verificationManager.clearHistory()
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Statistics View
    
    private var statisticsView: some View {
        Form {
            Section("Overview") {
                LabeledContent("Total Verifications", value: "\(verificationManager.statistics.totalVerifications)")
                LabeledContent("Successful", value: "\(verificationManager.statistics.successfulVerifications)")
                LabeledContent("Failed", value: "\(verificationManager.statistics.failedVerifications)")
                LabeledContent("Skipped", value: "\(verificationManager.statistics.skippedVerifications)")
                LabeledContent("Success Rate", value: String(format: "%.1f%%", verificationManager.statistics.successRate))
            }
            
            Section("Performance") {
                LabeledContent("Total Bytes Verified", value: ByteCountFormatter.string(
                    fromByteCount: verificationManager.statistics.totalBytesVerified,
                    countStyle: .file
                ))
                LabeledContent("Total Time", value: formatDuration(verificationManager.statistics.totalVerificationTime))
                LabeledContent("Average Speed", value: formatSpeed(verificationManager.statistics.averageVerificationSpeed))
            }
            
            Section("By Algorithm") {
                ForEach(HashAlgorithm.allCases) { algorithm in
                    if let count = verificationManager.statistics.verificationsByAlgorithm[algorithm] {
                        LabeledContent {
                            Text("\(count)")
                        } label: {
                            Label(algorithm.displayName, systemImage: algorithm.iconName)
                        }
                    }
                }
            }
            
            if let lastDate = verificationManager.statistics.lastVerificationDate {
                Section {
                    LabeledContent("Last Verification", value: lastDate.formatted(date: .abbreviated, time: .shortened))
                }
            }
            
            Section {
                Button("Reset Statistics", role: .destructive) {
                    verificationManager.resetStatistics()
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Helper Functions
    
    private func binding<T>(_ keyPath: WritableKeyPath<VerificationConfig, T>) -> Binding<T> {
        Binding(
            get: { verificationManager.configuration[keyPath: keyPath] },
            set: { newValue in
                verificationManager.configuration[keyPath: keyPath] = newValue
                verificationManager.updateConfiguration(verificationManager.configuration)
            }
        )
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "0s"
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}

// MARK: - Verification Result Row

private struct VerificationResultRow: View {
    let result: VerificationResult
    let isActive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.status.icon)
                    .foregroundColor(statusColor)
                Text(URL(fileURLWithPath: result.filePath).lastPathComponent)
                    .font(.headline)
                Spacer()
                Text(result.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.2))
                    .cornerRadius(4)
            }
            
            if isActive {
                ProgressView(value: result.progress, total: 100)
                    .progressViewStyle(.linear)
            }
            
            HStack(spacing: 16) {
                Label("\(result.checksums.count) algorithms", systemImage: "number")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label(ByteCountFormatter.string(fromByteCount: result.fileSize, countStyle: .file), systemImage: "doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let duration = result.duration {
                    Label(String(format: "%.2fs", duration), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !result.checksums.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.checksums) { checksum in
                        HStack {
                            Image(systemName: checksum.isVerified ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(checksum.isVerified ? .green : .red)
                                .font(.caption)
                            Text(checksum.algorithm.displayName)
                                .font(.caption)
                            Spacer()
                            if let hash = checksum.actualHash {
                                Text(String(hash.prefix(16)) + "...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            
            if let error = result.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch result.status {
        case .verified: return .green
        case .failed: return .red
        case .verifying, .pending: return .blue
        case .skipped: return .orange
        case .notVerified, .unavailable: return .gray
        }
    }
}

// MARK: - Manual Verification View

private struct ManualVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var verificationManager = FileVerificationManager.shared
    
    @State private var filePath = ""
    @State private var selectedAlgorithms: Set<HashAlgorithm> = [.sha256]
    @State private var expectedHashes: [HashAlgorithm: String] = [:]
    @State private var isVerifying = false
    @State private var result: VerificationResult?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    HStack {
                        TextField("File Path", text: $filePath)
                        Button("Choose") {
                            // File picker would go here
                        }
                    }
                }
                
                Section("Algorithms") {
                    ForEach(HashAlgorithm.allCases) { algorithm in
                        Toggle(isOn: Binding(
                            get: { selectedAlgorithms.contains(algorithm) },
                            set: { if $0 { selectedAlgorithms.insert(algorithm) } else { selectedAlgorithms.remove(algorithm) } }
                        )) {
                            Label(algorithm.displayName, systemImage: algorithm.iconName)
                        }
                        
                        if selectedAlgorithms.contains(algorithm) {
                            TextField("Expected \(algorithm.displayName) (optional)", text: Binding(
                                get: { expectedHashes[algorithm] ?? "" },
                                set: { expectedHashes[algorithm] = $0.isEmpty ? nil : $0 }
                            ))
                            .font(.caption)
                        }
                    }
                }
                
                if let result = result {
                    Section("Result") {
                        VerificationResultRow(result: result, isActive: false)
                    }
                }
                
                Section {
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                        
                        Spacer()
                        
                        Button("Verify") {
                            Task {
                                await verifyFile()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(filePath.isEmpty || selectedAlgorithms.isEmpty || isVerifying)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Verify File")
            .disabled(isVerifying)
        }
    }
    
    private func verifyFile() async {
        isVerifying = true
        
        let checksums = selectedAlgorithms.map { algorithm in
            FileChecksum(algorithm: algorithm, expectedHash: expectedHashes[algorithm])
        }
        
        result = await verificationManager.verifyFile(
            filePath: filePath,
            downloadTaskId: UUID(),
            checksums: checksums
        )
        
        isVerifying = false
    }
}
