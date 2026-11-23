//
//  CloudIntegrationView.swift
//  Download Manager for Mac - Feature #9: Cloud Integration
//
//  Created on February 16, 2026
//

import SwiftUI

struct CloudIntegrationView: View {
    
    @ObservedObject var manager = CloudIntegrationManager.shared
    
    @State private var selectedTab = 0
    @State private var showingAccountEditor = false
    @State private var showingRuleEditor = false
    @State private var editingAccount: CloudAccount?
    @State private var editingRule: CloudUploadRule?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab selection
            Picker("View", selection: $selectedTab) {
                Text("Accounts").tag(0)
                Text("Uploads").tag(1)
                Text("Rules").tag(2)
                Text("Statistics").tag(3)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                accountsView.tag(0)
                uploadsView.tag(1)
                rulesView.tag(2)
                statisticsView.tag(3)
            }
        }
        .sheet(isPresented: $showingAccountEditor) {
            AccountEditorView(account: editingAccount) { account in
                if editingAccount != nil {
                    manager.updateAccount(account)
                } else {
                    manager.addAccount(account)
                }
                editingAccount = nil
            }
        }
        .sheet(isPresented: $showingRuleEditor) {
            CloudUploadRuleEditorView(rule: editingRule, accounts: manager.accounts) { rule in
                if editingRule != nil {
                    manager.updateUploadRule(rule)
                } else {
                    manager.addUploadRule(rule)
                }
                editingRule = nil
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cloud Integration")
                    .font(.title2)
                    .bold()
                Text("\(manager.accounts.count) accounts • \(activeUploadsCount) active uploads")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                manager.checkAllAccountSpaces()
            } label: {
                Label("Refresh All", systemImage: "arrow.clockwise")
            }
        }
        .padding()
    }
    
    private var activeUploadsCount: Int {
        manager.uploadTasks.filter { $0.state == .uploading }.count
    }
    
    // MARK: - Accounts View
    
    private var accountsView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    editingAccount = nil
                    showingAccountEditor = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                
                Spacer()
                
                Text("\(manager.accounts.count) accounts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Accounts list
            if manager.accounts.isEmpty {
                emptyStateView(
                    icon: "cloud",
                    title: "No Cloud Accounts",
                    message: "Add a cloud storage account to enable automatic uploads"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(manager.accounts) { account in
                            AccountCardView(account: account) {
                                // Edit
                                editingAccount = account
                                showingAccountEditor = true
                            } onDelete: {
                                manager.deleteAccount(account)
                            } onAuthenticate: {
                                manager.authenticateAccount(account) { result in
                                    switch result {
                                    case .success:
                                        print("Authentication successful")
                                    case .failure(let error):
                                        print("Authentication failed: \(error)")
                                    }
                                }
                            } onRefresh: {
                                manager.refreshAccountSpace(account)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Uploads View
    
    private var uploadsView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(manager.uploadTasks.count) uploads")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    manager.uploadTasks.removeAll { $0.state == .completed }
                } label: {
                    Text("Clear Completed")
                }
                .disabled(manager.uploadTasks.filter { $0.state == .completed }.isEmpty)
            }
            .padding()
            
            Divider()
            
            // Uploads list
            if manager.uploadTasks.isEmpty {
                emptyStateView(
                    icon: "arrow.up.doc",
                    title: "No Uploads",
                    message: "Files will be uploaded automatically based on your account settings and rules"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(manager.uploadTasks) { uploadTask in
                            UploadTaskCardView(uploadTask: uploadTask) {
                                manager.cancelUpload(uploadTask)
                            } onRetry: {
                                manager.retryUpload(uploadTask)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Rules View
    
    private var rulesView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    editingRule = nil
                    showingRuleEditor = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .disabled(manager.accounts.isEmpty)
                
                Spacer()
                
                Text("\(manager.uploadRules.count) rules")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Rules list
            if manager.uploadRules.isEmpty {
                emptyStateView(
                    icon: "slider.horizontal.3",
                    title: "No Upload Rules",
                    message: "Create rules to automatically upload files to specific cloud accounts"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(manager.uploadRules.sorted { $0.priority > $1.priority }) { rule in
                            UploadRuleCardView(rule: rule, accounts: manager.accounts) {
                                editingRule = rule
                                showingRuleEditor = true
                            } onDelete: {
                                manager.deleteUploadRule(rule)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Statistics View
    
    private var statisticsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Upload statistics
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    CloudStatCardView(
                        title: "Total Uploads",
                        value: "\(manager.statistics.totalUploads)",
                        icon: "arrow.up.circle.fill",
                        color: .blue
                    )
                    
                    CloudStatCardView(
                        title: "Successful",
                        value: "\(manager.statistics.successfulUploads)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    CloudStatCardView(
                        title: "Failed",
                        value: "\(manager.statistics.failedUploads)",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                    
                    CloudStatCardView(
                        title: "Success Rate",
                        value: String(format: "%.1f%%", manager.statistics.successRate),
                        icon: "percent",
                        color: .purple
                    )
                    
                    CloudStatCardView(
                        title: "Data Uploaded",
                        value: ByteCountFormatter.string(fromByteCount: manager.statistics.totalBytesUploaded, countStyle: .file),
                        icon: "arrow.up.doc.fill",
                        color: .orange
                    )
                    
                    CloudStatCardView(
                        title: "Avg Speed",
                        value: formatSpeed(manager.statistics.averageUploadSpeed),
                        icon: "speedometer",
                        color: .cyan
                    )
                }
                
                Divider()
                    .padding(.vertical)
                
                // Account space overview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage Space")
                        .font(.headline)
                    
                    ForEach(manager.accounts.filter { $0.isAuthenticated }) { account in
                        AccountSpaceView(account: account)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helper Views
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title3)
                .bold()
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}

// MARK: - Account Card View

struct AccountCardView: View {
    let account: CloudAccount
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAuthenticate: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: account.provider.icon)
                    .font(.title2)
                    .foregroundColor(providerColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.accountName)
                        .font(.headline)
                    
                    if let email = account.email {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if !account.isAuthenticated {
                    Button("Authenticate", action: onAuthenticate)
                        .buttonStyle(.bordered)
                }
                
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Refresh Space", action: onRefresh)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            if account.isAuthenticated {
                VStack(alignment: .leading, spacing: 8) {
                    // Space bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                            
                            Rectangle()
                                .fill(spaceColor)
                                .frame(width: geometry.size.width * CGFloat(account.usagePercentage / 100))
                        }
                        .frame(height: 8)
                        .cornerRadius(4)
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(ByteCountFormatter.string(fromByteCount: account.usedSpace, countStyle: .file)) used of \(ByteCountFormatter.string(fromByteCount: account.totalSpace, countStyle: .file))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f%%", account.usagePercentage))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Settings summary
            HStack {
                if account.settings.autoUpload {
                    Label("Auto-upload", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                if account.settings.syncDownloadHistory {
                    Label("Sync history", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                if !account.isEnabled {
                    Label("Disabled", systemImage: "pause.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var providerColor: Color {
        switch account.provider.color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        default: return .gray
        }
    }
    
    private var spaceColor: Color {
        if account.usagePercentage >= 95 {
            return .red
        } else if account.usagePercentage >= 80 {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Upload Task Card View

struct UploadTaskCardView: View {
    @ObservedObject var uploadTask: CloudUploadTask
    let onCancel: () -> Void
    let onRetry: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: uploadTask.account.provider.icon)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(uploadTask.downloadTask.filename)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(uploadTask.account.accountName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: uploadTask.state.icon)
                    .foregroundColor(stateColor)
                
                if uploadTask.state == .uploading {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                    }
                } else if uploadTask.state == .failed {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            
            if uploadTask.state == .uploading || uploadTask.state == .completed {
                ProgressView(value: uploadTask.progress)
                    .progressViewStyle(.linear)
                
                HStack {
                    Text("\(Int(uploadTask.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if uploadTask.state == .uploading {
                        Text(formatSpeed(uploadTask.uploadSpeed))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let remaining = uploadTask.remainingTime {
                            Text("• \(formatTime(remaining)) left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if let error = uploadTask.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var stateColor: Color {
        switch uploadTask.state.color {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        default: return .gray
        }
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

// MARK: - Upload Rule Card View

struct UploadRuleCardView: View {
    let rule: CloudUploadRule
    let accounts: [CloudAccount]
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(rule.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(rule.name)
                    .font(.headline)
                
                Spacer()
                
                Text("Priority: \(rule.priority)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Menu {
                    Button("Edit", action: onEdit)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            if let account = accounts.first(where: { $0.id == rule.accountId }) {
                HStack {
                    Image(systemName: account.provider.icon)
                        .foregroundColor(.blue)
                    Text(account.accountName)
                        .font(.subheadline)
                }
            }
            
            Text("Destination: \(rule.destinationPath)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !rule.conditions.isEmpty {
                Text("Conditions: \(rule.conditions.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Cloud Stat Card View

struct CloudStatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .bold()
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Account Space View

struct AccountSpaceView: View {
    let account: CloudAccount
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: account.provider.icon)
                    .foregroundColor(.blue)
                Text(account.accountName)
                    .font(.subheadline)
                
                Spacer()
                
                Text(String(format: "%.1f%%", account.usagePercentage))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    
                    Rectangle()
                        .fill(spaceColor)
                        .frame(width: geometry.size.width * CGFloat(account.usagePercentage / 100))
                }
                .frame(height: 8)
                .cornerRadius(4)
            }
            .frame(height: 8)
            
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: account.usedSpace, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(ByteCountFormatter.string(fromByteCount: account.totalSpace, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var spaceColor: Color {
        if account.usagePercentage >= 95 {
            return .red
        } else if account.usagePercentage >= 80 {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - Account Editor View

struct AccountEditorView: View {
    let account: CloudAccount?
    let onSave: (CloudAccount) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var provider: CloudProvider
    @State private var accountName: String
    @State private var email: String
    @State private var isEnabled: Bool
    @State private var autoUpload: Bool
    @State private var uploadPath: String
    @State private var syncHistory: Bool
    
    init(account: CloudAccount?, onSave: @escaping (CloudAccount) -> Void) {
        self.account = account
        self.onSave = onSave
        
        _provider = State(initialValue: account?.provider ?? .iCloudDrive)
        _accountName = State(initialValue: account?.accountName ?? "")
        _email = State(initialValue: account?.email ?? "")
        _isEnabled = State(initialValue: account?.isEnabled ?? true)
        _autoUpload = State(initialValue: account?.settings.autoUpload ?? false)
        _uploadPath = State(initialValue: account?.settings.uploadPath ?? "/Downloads")
        _syncHistory = State(initialValue: account?.settings.syncDownloadHistory ?? false)
    }
    
    var body: some View {
        VStack {
            Text("Cloud Account")
                .font(.title2)
                .bold()
                .padding()
            
            Form {
                Picker("Provider", selection: $provider) {
                    ForEach(CloudProvider.allCases) { provider in
                        HStack {
                            Image(systemName: provider.icon)
                            Text(provider.rawValue)
                        }
                        .tag(provider)
                    }
                }
                
                TextField("Account Name", text: $accountName)
                TextField("Email (optional)", text: $email)
                TextField("Upload Path", text: $uploadPath)
                
                Toggle("Enabled", isOn: $isEnabled)
                Toggle("Auto Upload", isOn: $autoUpload)
                Toggle("Sync Download History", isOn: $syncHistory)
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Save") {
                    var settings = account?.settings ?? CloudAccountSettings()
                    settings.autoUpload = autoUpload
                    settings.uploadPath = uploadPath
                    settings.syncDownloadHistory = syncHistory
                    
                    let newAccount = CloudAccount(
                        id: account?.id ?? UUID(),
                        provider: provider,
                        accountName: accountName,
                        email: email.isEmpty ? nil : email,
                        isEnabled: isEnabled,
                        isAuthenticated: account?.isAuthenticated ?? false,
                        totalSpace: account?.totalSpace ?? 0,
                        usedSpace: account?.usedSpace ?? 0,
                        settings: settings
                    )
                    onSave(newAccount)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(accountName.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }
}

// MARK: - Cloud Upload Rule Editor View

struct CloudUploadRuleEditorView: View {
    let rule: CloudUploadRule?
    let accounts: [CloudAccount]
    let onSave: (CloudUploadRule) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var isEnabled: Bool
    @State private var accountId: UUID
    @State private var destinationPath: String
    @State private var priority: Int
    
    init(rule: CloudUploadRule?, accounts: [CloudAccount], onSave: @escaping (CloudUploadRule) -> Void) {
        self.rule = rule
        self.accounts = accounts
        self.onSave = onSave
        
        _name = State(initialValue: rule?.name ?? "")
        _isEnabled = State(initialValue: rule?.isEnabled ?? true)
        _accountId = State(initialValue: rule?.accountId ?? accounts.first?.id ?? UUID())
        _destinationPath = State(initialValue: rule?.destinationPath ?? "/Downloads")
        _priority = State(initialValue: rule?.priority ?? 0)
    }
    
    var body: some View {
        VStack {
            Text("Upload Rule")
                .font(.title2)
                .bold()
                .padding()
            
            Form {
                TextField("Rule Name", text: $name)
                
                Picker("Cloud Account", selection: $accountId) {
                    ForEach(accounts) { account in
                        Text(account.accountName).tag(account.id)
                    }
                }
                
                TextField("Destination Path", text: $destinationPath)
                
                Stepper("Priority: \(priority)", value: $priority, in: 0...100)
                
                Toggle("Enabled", isOn: $isEnabled)
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Save") {
                    let newRule = CloudUploadRule(
                        id: rule?.id ?? UUID(),
                        name: name,
                        isEnabled: isEnabled,
                        accountId: accountId,
                        conditions: rule?.conditions ?? [],
                        destinationPath: destinationPath,
                        priority: priority
                    )
                    onSave(newRule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || accounts.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Preview

struct CloudIntegrationView_Previews: PreviewProvider {
    static var previews: some View {
        CloudIntegrationView()
            .frame(width: 800, height: 600)
    }
}
