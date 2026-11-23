//
//  ResumeView.swift
//  Download Manager for Mac - Feature #6: Resume Capability UI
//
//  Created on February 15, 2026
//

import SwiftUI

struct ResumeView: View {
    @ObservedObject var resumeManager = ResumeManager.shared
    @State private var selectedPreset: String = "Custom"
    @State private var showingAdvanced = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection
                
                // Statistics
                statisticsSection
                
                // Active Retries
                if !resumeManager.activeRetries.isEmpty {
                    activeRetriesSection
                }
                
                // Settings
                settingsSection
                
                // Advanced Settings
                if showingAdvanced {
                    advancedSettingsSection
                }
                
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text("Resume & Retry")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Automatically resume interrupted downloads and retry failed transfers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
        }
    }
    
    // MARK: - Statistics
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(
                    title: "Total Downloads",
                    value: "\(resumeManager.statistics.totalAttempts)",
                    color: .blue
                )
                
                StatCard(
                    title: "Success Rate",
                    value: "\(resumeManager.statistics.successRate.formatted(.number.precision(.fractionLength(1))))%",
                    color: .green
                )
                
                StatCard(
                    title: "Resumed",
                    value: "\(resumeManager.statistics.resumedDownloads)",
                    color: .orange
                )
                
                StatCard(
                    title: "Failed",
                    value: "\(resumeManager.statistics.failedDownloads)",
                    color: .red
                )
                
                StatCard(
                    title: "Avg Retries",
                    value: "\(resumeManager.statistics.averageRetries.formatted(.number.precision(.fractionLength(1))))",
                    color: .purple
                )
                
                StatCard(
                    title: "Data Saved",
                    value: ByteCountFormatter.string(
                        fromByteCount: resumeManager.statistics.totalDataResumed,
                        countStyle: .file
                    ),
                    color: .cyan
                )
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Active Retries
    
    private var activeRetriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.orange)
                Text("Active Retries")
                    .font(.headline)
                Spacer()
                Text("\(resumeManager.activeRetries.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
            }
            
            ForEach(Array(resumeManager.activeRetries.values), id: \.id) { retry in
                RetryCard(retry: retry)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Settings
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
            
            // Preset selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Preset Configuration")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Preset", selection: $selectedPreset) {
                    Text("Reliable (Aggressive Retry)").tag("Reliable")
                    Text("Fast (Minimal Retry)").tag("Fast")
                    Text("Manual (No Auto-Retry)").tag("Manual")
                    Text("Custom").tag("Custom")
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedPreset) { newValue in
                    applyPreset(newValue)
                }
            }
            
            Divider()
            
            // Retry Policy
            GroupBox(label: Label("Retry Policy", systemImage: "arrow.clockwise")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max Retries:")
                        Spacer()
                        Stepper(
                            "\(resumeManager.settings.retryPolicy.maxRetries)",
                            value: Binding(
                                get: { resumeManager.settings.retryPolicy.maxRetries },
                                set: { newValue in
                                    resumeManager.settings.retryPolicy.maxRetries = newValue
                                    selectedPreset = "Custom"
                                }
                            ),
                            in: 0...20
                        )
                        .frame(width: 120)
                    }
                    
                    HStack {
                        Text("Initial Delay:")
                        Spacer()
                        Stepper(
                            "\(resumeManager.settings.retryPolicy.initialDelay.formatted(.number.precision(.fractionLength(1))))s",
                            value: Binding(
                                get: { resumeManager.settings.retryPolicy.initialDelay },
                                set: { newValue in
                                    resumeManager.settings.retryPolicy.initialDelay = newValue
                                    selectedPreset = "Custom"
                                }
                            ),
                            in: 1...30,
                            step: 1
                        )
                        .frame(width: 120)
                    }
                    
                    HStack {
                        Text("Max Delay:")
                        Spacer()
                        Stepper(
                            "\(Int(resumeManager.settings.retryPolicy.maxDelay))s",
                            value: Binding(
                                get: { resumeManager.settings.retryPolicy.maxDelay },
                                set: { newValue in
                                    resumeManager.settings.retryPolicy.maxDelay = newValue
                                    selectedPreset = "Custom"
                                }
                            ),
                            in: 10...300,
                            step: 10
                        )
                        .frame(width: 120)
                    }
                }
                .padding(8)
            }
            
            // Resume Strategy
            GroupBox(label: Label("Resume Strategy", systemImage: "play.fill")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Strategy", selection: Binding(
                        get: { resumeManager.settings.resumeStrategy },
                        set: { newValue in
                            resumeManager.settings.resumeStrategy = newValue
                            selectedPreset = "Custom"
                        }
                    )) {
                        ForEach([ResumeStrategy.automatic, .resumeOnly, .restartOnly, .askUser], id: \.self) { strategy in
                            Text(strategy.description).tag(strategy)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(8)
            }
            
            // Quick toggles
            VStack(spacing: 12) {
                Toggle("Save Resume Data", isOn: Binding(
                    get: { resumeManager.settings.saveResumeData },
                    set: { newValue in
                        resumeManager.settings.saveResumeData = newValue
                        selectedPreset = "Custom"
                    }
                ))
                
                Toggle("Auto-Resume on App Launch", isOn: Binding(
                    get: { resumeManager.settings.enableAutoResume },
                    set: { newValue in
                        resumeManager.settings.enableAutoResume = newValue
                        selectedPreset = "Custom"
                    }
                ))
                
                Toggle("Verify File Integrity", isOn: Binding(
                    get: { resumeManager.settings.verifyFileIntegrity },
                    set: { newValue in
                        resumeManager.settings.verifyFileIntegrity = newValue
                        selectedPreset = "Custom"
                    }
                ))
            }
            
            // Advanced settings toggle
            Button(action: { showingAdvanced.toggle() }) {
                HStack {
                    Image(systemName: showingAdvanced ? "chevron.down" : "chevron.right")
                    Text("Advanced Settings")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Advanced Settings
    
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced Settings")
                .font(.headline)
            
            HStack {
                Text("Connection Timeout:")
                Spacer()
                Stepper(
                    "\(Int(resumeManager.settings.connectionTimeout))s",
                    value: Binding(
                        get: { resumeManager.settings.connectionTimeout },
                        set: { newValue in
                            resumeManager.settings.connectionTimeout = newValue
                            selectedPreset = "Custom"
                        }
                    ),
                    in: 10...300,
                    step: 10
                )
                .frame(width: 120)
            }
            
            Toggle("Cleanup Failed Downloads", isOn: Binding(
                get: { resumeManager.settings.cleanupFailedDownloads },
                set: { newValue in
                    resumeManager.settings.cleanupFailedDownloads = newValue
                    selectedPreset = "Custom"
                }
            ))
            
            if resumeManager.settings.cleanupFailedDownloads {
                HStack {
                    Text("Cleanup After:")
                    Spacer()
                    Stepper(
                        "\(resumeManager.settings.cleanupAfterDays) days",
                        value: Binding(
                            get: { resumeManager.settings.cleanupAfterDays },
                            set: { newValue in
                                resumeManager.settings.cleanupAfterDays = newValue
                                selectedPreset = "Custom"
                            }
                        ),
                        in: 1...30
                    )
                    .frame(width: 150)
                }
            }
            
            Button("Clean Up Old Resume Data Now") {
                resumeManager.cleanupOldResumeData()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func applyPreset(_ preset: String) {
        guard preset != "Custom" else { return }
        
        let newSettings: ResumeSettings
        switch preset {
        case "Reliable":
            newSettings = .reliable
        case "Fast":
            newSettings = .fast
        case "Manual":
            newSettings = .manual
        default:
            return
        }
        
        resumeManager.updateSettings(newSettings)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String?
    let color: Color
    
    init(title: String, value: String, icon: String? = nil, color: Color) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let icon = icon {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.title3)
                    Spacer()
                }
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Retry Card

struct RetryCard: View {
    let retry: RetryAttempt
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Retry Attempt #\(retry.attemptNumber)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(retry.error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text("Next retry in \(retry.delayBeforeRetry.formatted(.number.precision(.fractionLength(1))))s")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            
            Spacer()
            
            Text(formatTimestamp(retry.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.white.opacity(0.5))
        .cornerRadius(8)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

struct ResumeView_Previews: PreviewProvider {
    static var previews: some View {
        ResumeView()
            .frame(width: 700, height: 600)
    }
}
