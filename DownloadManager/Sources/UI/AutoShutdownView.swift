//
//  AutoShutdownView.swift
//  Download Manager for Mac - Feature #4: Auto Shutdown UI
//
//  Created on February 15, 2026
//

import SwiftUI

struct AutoShutdownView: View {
    @StateObject private var manager = AutoShutdownManager.shared
    @State private var showingAddSheet = false
    @State private var editingAction: AutoShutdownAction?
    @State private var selectedAction: AutoShutdownAction?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            if manager.actions.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    // Actions list
                    actionsListView
                        .frame(minWidth: 300)
                    
                    // Detail view
                    detailView
                        .frame(minWidth: 400)
                }
            }
            
            // Active warning banner
            if let warning = manager.activeWarning {
                warningBanner(warning)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddActionSheet(action: editingAction) { action in
                if editingAction != nil {
                    _ = manager.updateAction(action)
                } else {
                    _ = manager.addAction(action)
                }
                editingAction = nil
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Shutdown Actions")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(manager.actions.count) actions configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            statisticsView
            
            Spacer()
            
            Button(action: { showingAddSheet = true }) {
                Label("Add Action", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var statisticsView: some View {
        let stats = manager.getStatistics()
        
        return HStack(spacing: 20) {
            StatBadge(label: "Enabled", value: "\(stats.enabledActions)", color: .green)
            StatBadge(label: "Pending", value: "\(stats.pendingActions)", color: .blue)
            StatBadge(label: "Executed", value: "\(stats.executedActions)", color: .purple)
            StatBadge(label: "Failed", value: "\(stats.failedActions)", color: .red)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "power.circle")
                .font(.system(size: 72))
                .foregroundColor(.secondary)
            
            Text("No Auto-Shutdown Actions")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create actions to automatically shut down, sleep, or perform other tasks when downloads complete")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            
            Button(action: { showingAddSheet = true }) {
                Label("Create First Action", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Actions List
    
    private var actionsListView: some View {
        List(selection: $selectedAction) {
            ForEach(manager.actions) { action in
                ActionRowView(action: action)
                    .tag(action)
                    .contextMenu {
                        Button("Edit") {
                            editingAction = action
                            showingAddSheet = true
                        }
                        
                        Button(action.isEnabled ? "Disable" : "Enable") {
                            manager.setActionEnabled(!action.isEnabled, for: action.id)
                        }
                        
                        Divider()
                        
                        Button("Delete", role: .destructive) {
                            manager.removeAction(action)
                        }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
    
    // MARK: - Detail View
    
    private var detailView: some View {
        Group {
            if let action = selectedAction {
                ActionDetailView(action: action)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Select an action to view details")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Warning Banner
    
    private func warningBanner(_ warning: AutoShutdownManager.PendingAction) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Action Pending: \(warning.action.actionType.rawValue)")
                    .font(.headline)
                
                Text("Executing in \(warning.remainingSeconds) seconds...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Cancel") {
                manager.cancelPendingAction(warning.action.id)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .border(Color.orange, width: 2)
    }
}

// MARK: - Action Row View

struct ActionRowView: View {
    let action: AutoShutdownAction
    
    var body: some View {
        HStack {
            Image(systemName: action.actionType.icon)
                .font(.title2)
                .foregroundColor(statusColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(action.actionType.rawValue)
                    .font(.headline)
                
                Text(action.condition.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                ActionStatusBadge(status: action.executionStatus)
                
                if !action.isEnabled {
                    Text("Disabled")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(action.isEnabled ? 1.0 : 0.5)
    }
    
    private var statusColor: Color {
        switch action.executionStatus {
        case .pending: return .blue
        case .triggered: return .orange
        case .executing: return .purple
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Action Detail View

struct ActionDetailView: View {
    let action: AutoShutdownAction
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: action.actionType.icon)
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.actionType.rawValue)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(action.actionType.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Condition
                DetailSection(title: "Trigger Condition") {
                    HStack {
                        Image(systemName: action.condition.icon)
                        Text(action.condition.rawValue)
                        Spacer()
                    }
                    
                    // Condition-specific details
                    if let categoryID = action.categoryID {
                        DetailRow(label: "Category", value: categoryID)
                    }
                    if let taskID = action.taskID {
                        DetailRow(label: "Task ID", value: taskID.uuidString)
                    }
                    if let minutes = action.timeMinutes {
                        DetailRow(label: "Time", value: "\(minutes) minutes")
                    }
                    if let mb = action.dataMB {
                        DetailRow(label: "Data Amount", value: "\(mb) MB")
                    }
                }
                
                // Execution Settings
                DetailSection(title: "Execution Settings") {
                    DetailRow(label: "Delay", value: action.delayMinutes > 0 ? "\(action.delayMinutes) minutes" : "Immediate")
                    DetailRow(label: "Warning", value: action.showWarning ? "Yes (\(action.warningSeconds)s)" : "No")
                    DetailRow(label: "Status", value: action.executionStatus.rawValue)
                }
                
                // Script Details (if applicable)
                if action.actionType == .runScript {
                    DetailSection(title: "Script Configuration") {
                        if let path = action.scriptPath {
                            DetailRow(label: "Path", value: path)
                        }
                        if let command = action.scriptCommand {
                            DetailRow(label: "Command", value: command)
                        }
                        if let args = action.scriptArguments, !args.isEmpty {
                            DetailRow(label: "Arguments", value: args.joined(separator: " "))
                        }
                    }
                }
                
                // Metadata
                DetailSection(title: "Metadata") {
                    DetailRow(label: "Created", value: formatDate(action.createdAt))
                    DetailRow(label: "Modified", value: formatDate(action.lastModified))
                    if let executed = action.executedAt {
                        DetailRow(label: "Executed", value: formatDate(executed))
                    }
                    if let note = action.executionNote {
                        DetailRow(label: "Note", value: note)
                    }
                }
                
                // Validation
                let validation = action.validate()
                if !validation.isValid {
                    DetailSection(title: "Validation Errors") {
                        ForEach(validation.errors, id: \.self) { error in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Add/Edit Action Sheet

struct AddActionSheet: View {
    let action: AutoShutdownAction?
    let onSave: (AutoShutdownAction) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var actionType: ShutdownActionType
    @State private var condition: ShutdownCondition
    @State private var delayMinutes: Int
    @State private var showWarning: Bool
    @State private var warningSeconds: Int
    @State private var isEnabled: Bool
    
    @State private var categoryID: String
    @State private var timeMinutes: Int
    @State private var dataMB: Int64
    @State private var scriptPath: String
    @State private var scriptCommand: String
    
    init(action: AutoShutdownAction?, onSave: @escaping (AutoShutdownAction) -> Void) {
        self.action = action
        self.onSave = onSave
        
        _actionType = State(initialValue: action?.actionType ?? .shutdown)
        _condition = State(initialValue: action?.condition ?? .allDownloads)
        _delayMinutes = State(initialValue: action?.delayMinutes ?? 1)
        _showWarning = State(initialValue: action?.showWarning ?? true)
        _warningSeconds = State(initialValue: action?.warningSeconds ?? 30)
        _isEnabled = State(initialValue: action?.isEnabled ?? true)
        
        _categoryID = State(initialValue: action?.categoryID ?? "")
        _timeMinutes = State(initialValue: action?.timeMinutes ?? 60)
        _dataMB = State(initialValue: action?.dataMB ?? 100)
        _scriptPath = State(initialValue: action?.scriptPath ?? "")
        _scriptCommand = State(initialValue: action?.scriptCommand ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(action == nil ? "Add Action" : "Edit Action")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("Action Type") {
                    Picker("Type", selection: $actionType) {
                        ForEach(ShutdownActionType.macCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Trigger Condition") {
                    Picker("When", selection: $condition) {
                        ForEach(ShutdownCondition.allCases, id: \.self) { cond in
                            Label(cond.rawValue, systemImage: cond.icon)
                                .tag(cond)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    // Condition-specific fields
                    conditionFields
                }
                
                Section("Execution") {
                    HStack {
                        Text("Delay:")
                        TextField("Minutes", value: $delayMinutes, format: .number)
                            .frame(width: 80)
                        Text("minutes")
                    }
                    
                    Toggle("Show Warning", isOn: $showWarning)
                    
                    if showWarning {
                        HStack {
                            Text("Warning Time:")
                            TextField("Seconds", value: $warningSeconds, format: .number)
                                .frame(width: 80)
                            Text("seconds")
                        }
                    }
                }
                
                // Script fields
                if actionType == .runScript {
                    Section("Script Configuration") {
                        TextField("Script Path", text: $scriptPath)
                        TextField("Command", text: $scriptCommand)
                    }
                }
                
                Section("Status") {
                    Toggle("Enabled", isOn: $isEnabled)
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    saveAction()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 600, height: 600)
    }
    
    @ViewBuilder
    private var conditionFields: some View {
        switch condition {
        case .specificCategory:
            TextField("Category ID", text: $categoryID)
        case .timeElapsed:
            HStack {
                Text("Duration:")
                TextField("Minutes", value: $timeMinutes, format: .number)
                    .frame(width: 80)
                Text("minutes")
            }
        case .dataDownloaded:
            HStack {
                Text("Amount:")
                TextField("MB", value: $dataMB, format: .number)
                    .frame(width: 100)
                Text("MB")
            }
        default:
            EmptyView()
        }
    }
    
    private func saveAction() {
        let newAction = AutoShutdownAction(
            id: action?.id ?? UUID(),
            isEnabled: isEnabled,
            actionType: actionType,
            condition: condition,
            delayMinutes: delayMinutes,
            showWarning: showWarning,
            warningSeconds: warningSeconds,
            categoryID: condition == .specificCategory ? categoryID : nil,
            taskID: action?.taskID,
            timeMinutes: condition == .timeElapsed ? timeMinutes : nil,
            dataMB: condition == .dataDownloaded ? dataMB : nil,
            scriptPath: actionType == .runScript ? scriptPath : nil,
            scriptCommand: actionType == .runScript ? scriptCommand : nil,
            createdAt: action?.createdAt ?? Date(),
            lastModified: Date(),
            executionStatus: action?.executionStatus ?? .pending
        )
        
        onSave(newAction)
        dismiss()
    }
}

// MARK: - Helper Views

struct StatBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct ActionStatusBadge: View {
    let status: AutoShutdownAction.ExecutionStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    private var backgroundColor: Color {
        switch status {
        case .pending: return .blue
        case .triggered: return .orange
        case .executing: return .purple
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Preview

struct AutoShutdownView_Previews: PreviewProvider {
    static var previews: some View {
        AutoShutdownView()
            .frame(width: 900, height: 600)
    }
}
