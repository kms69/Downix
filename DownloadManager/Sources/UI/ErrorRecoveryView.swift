//
//  ErrorRecoveryView.swift
//  Download Manager
//
//  Feature #22: Advanced Error Recovery
//  Created on February 17, 2026
//

import SwiftUI

public struct ErrorRecoveryView: View {
    @StateObject private var recoveryManager = ErrorRecoveryManager.shared
    @State private var selectedTab: Tab = .configuration
    @State private var showingResetAlert = false
    
    private enum Tab: String, CaseIterable {
        case configuration
        case active
        case history
        case statistics
        
        var icon: String {
            switch self {
            case .configuration: return "gear"
            case .active: return "arrow.clockwise.circle"
            case .history: return "clock"
            case .statistics: return "chart.bar"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // Sidebar
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue.capitalized, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Error Recovery")
        } detail: {
            // Detail view based on selected tab
            Group {
                switch selectedTab {
                case .configuration:
                    configurationView
                case .active:
                    activeRecoveriesView
                case .history:
                    historyView
                case .statistics:
                    statisticsView
                }
            }
        }
    }
    
    // MARK: - Configuration View
    
    private var configurationView: some View {
        Form {
            // General Settings
            Section("General") {
                Toggle("Enable Error Recovery", isOn: binding(\.isEnabled))
                Toggle("Auto Retry on Failure", isOn: binding(\.autoRetryOnFailure))
                
                if recoveryManager.configuration.autoRetryOnFailure {
                    Stepper(value: binding(\.maxRetryAttempts), in: 1...20) {
                        Text("Max Retry Attempts: \(recoveryManager.configuration.maxRetryAttempts)")
                    }
                }
            }
            
            // Retry Strategy
            Section("Retry Strategy") {
                Picker("Strategy", selection: binding(\.retryStrategy)) {
                    ForEach(RetryStrategy.allCases, id: \.self) { strategy in
                        Label(strategy.displayName, systemImage: strategy.icon)
                            .tag(strategy)
                    }
                }
                .pickerStyle(.menu)
                
                Text(recoveryManager.configuration.retryStrategy.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if recoveryManager.configuration.retryStrategy != .none {
                    HStack {
                        Text("Base Delay:")
                        Spacer()
                        Text("\(String(format: "%.1f", recoveryManager.configuration.baseDelay))s")
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: binding(\.baseDelay), in: 0.5...30, step: 0.5)
                }
            }
            
            // Recovery Features
            Section("Recovery Features") {
                Toggle("Mirror Fallback", isOn: binding(\.enableMirrorFallback))
                    .help("Try alternative download sources when primary fails")
                
                Toggle("Network Change Detection", isOn: binding(\.enableNetworkChangeDetection))
                    .help("Monitor network changes and adapt download strategy")
                
                Toggle("Partial Recovery", isOn: binding(\.enablePartialRecovery))
                    .help("Resume from partially downloaded content")
                
                Toggle("Reduce Connections on Error", isOn: binding(\.reduceConnectionsOnError))
                    .help("Automatically reduce parallel connections when errors occur")
                
                if recoveryManager.configuration.reduceConnectionsOnError {
                    Stepper(value: binding(\.minConnections), in: 1...8) {
                        Text("Minimum Connections: \(recoveryManager.configuration.minConnections)")
                    }
                }
            }
            
            // Notifications
            Section("Notifications") {
                Toggle("Notify on Recovery Success", isOn: binding(\.notifyOnRecovery))
                Toggle("Notify on Recovery Failure", isOn: binding(\.notifyOnFailure))
            }
            
            // Configuration Presets
            Section("Presets") {
                HStack(spacing: 12) {
                    presetButton("Minimal", config: .minimal)
                    presetButton("Conservative", config: .conservative)
                    presetButton("Balanced", config: .balanced)
                    presetButton("Aggressive", config: .aggressive)
                }
            }
            
            // Reset Section
            Section {
                Button(role: .destructive, action: { showingResetAlert = true }) {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset Configuration?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                recoveryManager.resetConfiguration()
            }
        } message: {
            Text("This will reset all error recovery settings to their default values.")
        }
    }
    
    private func presetButton(_ title: String, config: RecoveryConfiguration) -> some View {
        Button(title) {
            recoveryManager.updateConfiguration(config)
        }
        .buttonStyle(.bordered)
    }
    
    // MARK: - Active Recoveries View
    
    private var activeRecoveriesView: some View {
        Group {
            if recoveryManager.activeRecoveries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("No Active Recoveries")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("All downloads are running smoothly")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(recoveryManager.activeRecoveries.values), id: \.id) { attempt in
                        RecoveryAttemptRow(attempt: attempt)
                    }
                }
            }
        }
        .navigationTitle("Active Recoveries")
    }
    
    // MARK: - History View
    
    private var historyView: some View {
        VStack(spacing: 0) {
            if !recoveryManager.recoveryHistory.isEmpty {
                List {
                    ForEach(recoveryManager.recoveryHistory) { result in
                        RecoveryResultRow(result: result)
                    }
                }
                
                HStack {
                    Text("\(recoveryManager.recoveryHistory.count) recovery result(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Clear History") {
                        recoveryManager.clearHistory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "clock")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("No Recovery History")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Recovery attempts will appear here")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Recovery History")
    }
    
    // MARK: - Statistics View
    
    private var statisticsView: some View {
        Form {
            // Overview
            Section("Overview") {
                LabeledContent("Total Errors", value: "\(recoveryManager.statistics.totalErrors)")
                LabeledContent("Recovery Attempts", value: "\(recoveryManager.statistics.totalRecoveryAttempts)")
                LabeledContent("Successful", value: "\(recoveryManager.statistics.successfulRecoveries)")
                LabeledContent("Failed", value: "\(recoveryManager.statistics.failedRecoveries)")
                LabeledContent("Success Rate", value: String(format: "%.1f%%", recoveryManager.statistics.successRate))
            }
            
            // Recovery Actions
            Section("Recovery Features Used") {
                LabeledContent("Mirror Fallbacks", value: "\(recoveryManager.statistics.mirrorFallbacksUsed)")
                LabeledContent("Network Changes Detected", value: "\(recoveryManager.statistics.networkChangesDetected)")
                LabeledContent("Partial Recoveries", value: "\(recoveryManager.statistics.partialRecoveriesSuccessful)")
            }
            
            // Performance
            Section("Performance") {
                LabeledContent("Total Delay Time", value: formatDuration(recoveryManager.statistics.totalDelayTime))
                LabeledContent("Average Delay", value: formatDuration(recoveryManager.statistics.averageDelayTime))
            }
            
            // Error Breakdown
            if !recoveryManager.statistics.errorsByType.isEmpty {
                Section("Errors by Type") {
                    ForEach(Array(recoveryManager.statistics.errorsByType.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { errorType in
                        if let count = recoveryManager.statistics.errorsByType[errorType] {
                            HStack {
                                Label(errorType.displayName, systemImage: errorType.icon)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            // Action Breakdown
            if !recoveryManager.statistics.actionsByType.isEmpty {
                Section("Actions by Type") {
                    ForEach(Array(recoveryManager.statistics.actionsByType.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { action in
                        if let count = recoveryManager.statistics.actionsByType[action] {
                            HStack {
                                Label(action.displayName, systemImage: action.icon)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            // Most Common
            Section("Most Common") {
                if let mostCommonError = recoveryManager.statistics.mostCommonError {
                    LabeledContent("Error Type", value: mostCommonError.displayName)
                }
                if let mostCommonAction = recoveryManager.statistics.mostCommonAction {
                    LabeledContent("Recovery Action", value: mostCommonAction.displayName)
                }
            }
            
            // Last Activity
            if let lastDate = recoveryManager.statistics.lastRecoveryDate {
                Section("Last Activity") {
                    LabeledContent("Last Recovery", value: lastDate.formatted(date: .abbreviated, time: .shortened))
                }
            }
            
            // Network Status
            Section("Network Status") {
                HStack {
                    Label("Current Network", systemImage: recoveryManager.currentConnectionType.icon)
                    Spacer()
                    Text(recoveryManager.currentConnectionType.displayName)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Reset
            Section {
                Button(role: .destructive, action: {
                    recoveryManager.resetStatistics()
                }) {
                    Label("Reset Statistics", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Statistics")
    }
    
    // MARK: - Helper Views
    
    private func binding<T>(_ keyPath: WritableKeyPath<RecoveryConfiguration, T>) -> Binding<T> {
        Binding(
            get: { recoveryManager.configuration[keyPath: keyPath] },
            set: { newValue in
                var config = recoveryManager.configuration
                config[keyPath: keyPath] = newValue
                recoveryManager.updateConfiguration(config)
            }
        )
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}

// MARK: - Recovery Attempt Row

struct RecoveryAttemptRow: View {
    let attempt: RecoveryAttempt
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(attempt.errorType.displayName, systemImage: attempt.errorType.icon)
                    .font(.headline)
                
                Spacer()
                
                Text("Attempt \(attempt.attemptNumber)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }
            
            HStack(spacing: 12) {
                Label(attempt.strategy.displayName, systemImage: attempt.strategy.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label(attempt.action.displayName, systemImage: attempt.action.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if attempt.delayUsed > 0 {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Waiting \(String(format: "%.1f", attempt.delayUsed))s")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
            
            ProgressView()
                .progressViewStyle(.linear)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recovery Result Row

struct RecoveryResultRow: View {
    let result: RecoveryResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.wasSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.wasSuccessful ? .green : .red)
                
                Label(result.errorType.displayName, systemImage: result.errorType.icon)
                    .font(.headline)
                
                Spacer()
                
                Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 12) {
                Label(result.finalAction.displayName, systemImage: result.finalAction.icon)
                    .font(.caption)
                
                Text("\(result.totalAttempts) attempt(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(formatDuration(result.recoveryTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let notes = result.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ErrorRecoveryView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorRecoveryView()
    }
}
#endif
