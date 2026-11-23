import SwiftUI

// MARK: - Batch Operation View

/// Main view for batch download operations
public struct BatchOperationView: View {
    @StateObject private var manager = BatchOperationManager.shared
    @State private var showImportSheet = false
    @State private var showSessionHistory = false
    @State private var selectedTab: Tab = .importURLs
    
    enum Tab {
        case importURLs
        case patterns
        case sessions
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab bar
            Picker("View", selection: $selectedTab) {
                Label("Import", systemImage: "arrow.down.circle").tag(Tab.importURLs)
                Label("Patterns", systemImage: "text.badge.checkmark").tag(Tab.patterns)
                Label("Sessions", systemImage: "list.bullet.clipboard").tag(Tab.sessions)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                BatchImportView()
                    .tag(Tab.importURLs)
                
                BatchPatternsView()
                    .tag(Tab.patterns)
                
                BatchSessionsView()
                    .tag(Tab.sessions)
            }
            .tabViewStyle(.automatic)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "square.stack.3d.down.right")
                .font(.title)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Batch Operations")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Import and manage multiple downloads")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if manager.isProcessing {
                ProgressView(value: manager.progress)
                    .frame(width: 100)
                
                Text("\(Int(manager.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Batch Import View

struct BatchImportView: View {
    @StateObject private var manager = BatchOperationManager.shared
    @State private var config = BatchImportConfig()
    @State private var urlText = ""
    @State private var showFilePicker = false
    @State private var showResults = false
    @State private var currentResult: BatchOperationResult?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Source selection
                sourceSelectionSection
                
                // URL input
                urlInputSection
                
                // Options
                optionsSection
                
                // Sequential naming
                sequentialNamingSection
                
                // Rename patterns
                renamePatternsSection
                
                // Action buttons
                actionButtonsSection
                
                // Results
                if !manager.validationResults.isEmpty {
                    resultsSection
                }
            }
            .padding()
        }
        .sheet(isPresented: $showResults) {
            if let result = currentResult {
                BatchResultView(result: result)
            }
        }
    }
    
    private var sourceSelectionSection: some View {
        GroupBox(label: Label("Import Source", systemImage: "square.and.arrow.down")) {
            VStack(spacing: 12) {
                Picker("Source", selection: $config.source) {
                    ForEach(BatchImportSource.allCases, id: \.self) { source in
                        Label(source.displayName, systemImage: source.icon)
                            .tag(source)
                    }
                }
                .pickerStyle(.segmented)
                
                if config.source == .textFile {
                    HStack {
                        Text(config.sourceFilePath ?? "No file selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Choose File...") {
                            showFilePicker = true
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var urlInputSection: some View {
        GroupBox(label: Label("URLs", systemImage: "link")) {
            VStack(spacing: 12) {
                TextEditor(text: $urlText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .border(Color.gray.opacity(0.2))
                
                HStack {
                    Text("\(urlText.components(separatedBy: .newlines).filter { !$0.isEmpty }.count) URLs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Paste from Clipboard") {
                        if let clipboard = NSPasteboard.general.string(forType: .string) {
                            urlText = clipboard
                        }
                    }
                    
                    Button("Clear") {
                        urlText = ""
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var optionsSection: some View {
        GroupBox(label: Label("Options", systemImage: "slider.horizontal.3")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Validate URLs", isOn: $config.validateURLs)
                Toggle("Remove duplicates", isOn: $config.removeDuplicates)
                Toggle("Start downloads immediately", isOn: $config.startImmediately)
                
                Divider()
                
                HStack {
                    Text("Category:")
                    Picker("", selection: $config.targetCategory) {
                        Text("Auto-detect").tag(nil as BatchCategory?)
                        ForEach(BatchCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat as BatchCategory?)
                        }
                    }
                    .frame(width: 200)
                }
                
                HStack {
                    Text("Save to:")
                    TextField("Default downloads folder", text: Binding(
                        get: { config.targetDirectory ?? "" },
                        set: { config.targetDirectory = $0.isEmpty ? nil : $0 }
                    ))
                    
                    Button("Choose...") {
                        // File picker for destination
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var sequentialNamingSection: some View {
        GroupBox(label: Label("Sequential Naming", systemImage: "123.rectangle")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use sequential naming", isOn: $config.useSequentialNaming)
                    .onChange(of: config.useSequentialNaming) { newValue in
                        if newValue && config.sequentialPattern == nil {
                            config.sequentialPattern = .defaultPattern
                        }
                    }
                
                if config.useSequentialNaming, let pattern = config.sequentialPattern {
                    Divider()
                    
                    HStack {
                        Text("Base name:")
                        TextField("file", text: Binding(
                            get: { pattern.basePattern },
                            set: { 
                                var p = pattern
                                p.basePattern = $0
                                config.sequentialPattern = p
                            }
                        ))
                        .frame(width: 150)
                    }
                        
                        HStack {
                            Text("Start number:")
                            TextField("1", value: Binding(
                                get: { pattern.startNumber },
                                set: { 
                                    var p = pattern
                                    p.startNumber = $0
                                    config.sequentialPattern = p
                                }
                            ), format: .number)
                            .frame(width: 80)
                            
                            Text("Digits:")
                            TextField("3", value: Binding(
                                get: { pattern.numberDigits },
                                set: { 
                                    var p = pattern
                                    p.numberDigits = $0
                                    config.sequentialPattern = p
                                }
                            ), format: .number)
                            .frame(width: 60)
                        }
                        
                        HStack {
                            Text("Separator:")
                            TextField("_", text: Binding(
                                get: { pattern.separator },
                                set: { 
                                    var p = pattern
                                    p.separator = $0
                                    config.sequentialPattern = p
                                }
                            ))
                            .frame(width: 60)
                            
                            Text("Extension:")
                            TextField("Optional", text: Binding(
                            get: { pattern.fileExtension ?? "" },
                            set: { 
                                var p = pattern
                                p.fileExtension = $0.isEmpty ? nil : $0
                                config.sequentialPattern = p
                            }
                        ))
                        .frame(width: 100)
                    }
                    
                    // Preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(pattern.previewFilenames(count: 3), id: \.self) { filename in
                            Text(filename)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var renamePatternsSection: some View {
        GroupBox(label: Label("Rename Patterns", systemImage: "pencil.and.outline")) {
            VStack(spacing: 12) {
                HStack {
                    Text("Common patterns:")
                    
                    Spacer()
                    
                    Button("Remove Spaces") {
                        config.renamePatterns.append(.removeSpaces)
                    }
                    
                    Button("Remove Special Chars") {
                        config.renamePatterns.append(.removeSpecialChars)
                    }
                }
                
                if !config.renamePatterns.isEmpty {
                    Divider()
                    
                    ForEach(config.renamePatterns) { pattern in
                        HStack {
                            Image(systemName: "arrow.right")
                                .font(.caption)
                            
                            Text("Replace '\(pattern.findPattern)' with '\(pattern.replaceWith)'")
                                .font(.caption)
                            
                            Spacer()
                            
                            Button(action: {
                                config.renamePatterns.removeAll { $0.id == pattern.id }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: validateURLs) {
                Label("Validate URLs", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(urlText.isEmpty && config.source == .manualEntry)
            
            Button(action: processImport) {
                Label("Import Downloads", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlText.isEmpty && config.source == .manualEntry)
            
            Spacer()
            
            Button("Clear Results") {
                manager.clearValidationResults()
            }
            .disabled(manager.validationResults.isEmpty)
        }
    }
    
    private var resultsSection: some View {
        GroupBox(label: Label("Validation Results (\(manager.validationResults.count))", systemImage: "list.bullet.clipboard")) {
            VStack(spacing: 0) {
                // Summary
                HStack {
                    Label("\(manager.validationResults.filter { $0.isValid }.count) Valid", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Label("\(manager.validationResults.filter { !$0.isValid }.count) Invalid", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Results list
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(manager.validationResults) { result in
                            ValidationResultRow(result: result)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding(.vertical, 8)
        }
    }
    
    private func validateURLs() {
        let urls = urlText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        config.urls = urls
        
        Task {
            _ = await manager.validateURLs(urls, with: config)
        }
    }
    
    private func processImport() {
        let urls = urlText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        config.urls = urls
        
        Task {
            let result = await manager.processBatchImport(config: config)
            
            await MainActor.run {
                currentResult = result
                showResults = true
            }
        }
    }
}

// MARK: - Validation Result Row

struct ValidationResultRow: View {
    let result: URLValidationResult
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.isValid ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.url)
                    .font(.caption)
                    .lineLimit(1)
                
                if let filename = result.finalFilename {
                    Text("→ \(filename)")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                
                if let error = result.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            if let category = result.detectedCategory {
                Label(category.displayName, systemImage: category.icon)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(8)
        .background(result.isValid ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        .cornerRadius(4)
    }
}

// MARK: - Batch Patterns View

struct BatchPatternsView: View {
    @State private var urlPatterns: [URLPattern] = []
    @State private var renamePatterns: [BatchRenamePattern] = []
    @State private var showAddPattern = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // URL Patterns
                urlPatternsSection
                
                // Rename Patterns
                renamePatternsSection
                
                // Presets
                presetsSection
            }
            .padding()
        }
    }
    
    private var urlPatternsSection: some View {
        GroupBox(label: Label("URL Filter Patterns", systemImage: "line.3.horizontal.decrease.circle")) {
            VStack(spacing: 12) {
                HStack {
                    Text("Filter URLs by patterns (regex supported)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Add Pattern") {
                        urlPatterns.append(URLPattern(pattern: "", isRegex: false))
                    }
                }
                
                if !urlPatterns.isEmpty {
                    Divider()
                    
                    ForEach(urlPatterns) { pattern in
                        URLPatternRow(pattern: binding(for: pattern), onDelete: {
                            urlPatterns.removeAll { $0.id == pattern.id }
                        })
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var renamePatternsSection: some View {
        GroupBox(label: Label("Rename Patterns", systemImage: "pencil.line")) {
            VStack(spacing: 12) {
                HStack {
                    Text("Find and replace patterns in filenames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Add Pattern") {
                        renamePatterns.append(BatchRenamePattern(findPattern: "", replaceWith: ""))
                    }
                }
                
                if !renamePatterns.isEmpty {
                    Divider()
                    
                    ForEach(renamePatterns) { pattern in
                        RenamePatternRow(pattern: binding(for: pattern), onDelete: {
                            renamePatterns.removeAll { $0.id == pattern.id }
                        })
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var presetsSection: some View {
        GroupBox(label: Label("Common Presets", systemImage: "star")) {
            VStack(alignment: .leading, spacing: 12) {
                Text("URL Patterns:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 8) {
                    Button("Videos") {
                        urlPatterns.append(.videoPattern)
                    }
                    Button("Audio") {
                        urlPatterns.append(.audioPattern)
                    }
                    Button("Images") {
                        urlPatterns.append(.imagePattern)
                    }
                    Button("Documents") {
                        urlPatterns.append(.documentPattern)
                    }
                }
                
                Divider()
                
                Text("Rename Patterns:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 8) {
                    Button("Remove Spaces") {
                        renamePatterns.append(.removeSpaces)
                    }
                    Button("Remove Special") {
                        renamePatterns.append(.removeSpecialChars)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func binding(for pattern: URLPattern) -> Binding<URLPattern> {
        Binding(
            get: { pattern },
            set: { newValue in
                if let index = urlPatterns.firstIndex(where: { $0.id == pattern.id }) {
                    urlPatterns[index] = newValue
                }
            }
        )
    }
    
    private func binding(for pattern: BatchRenamePattern) -> Binding<BatchRenamePattern> {
        Binding(
            get: { pattern },
            set: { newValue in
                if let index = renamePatterns.firstIndex(where: { $0.id == pattern.id }) {
                    renamePatterns[index] = newValue
                }
            }
        )
    }
}

// MARK: - URL Pattern Row

struct URLPatternRow: View {
    @Binding var pattern: URLPattern
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Toggle("", isOn: $pattern.isEnabled)
                .labelsHidden()
            
            TextField("Pattern", text: $pattern.pattern)
                .textFieldStyle(.roundedBorder)
            
            Toggle("Regex", isOn: $pattern.isRegex)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Rename Pattern Row

struct RenamePatternRow: View {
    @Binding var pattern: BatchRenamePattern
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            TextField("Find", text: $pattern.findPattern)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            
            Image(systemName: "arrow.right")
                .font(.caption)
            
            TextField("Replace", text: $pattern.replaceWith)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            
            Toggle("Regex", isOn: $pattern.isRegex)
            Toggle("Case", isOn: $pattern.caseSensitive)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Batch Sessions View

struct BatchSessionsView: View {
    @StateObject private var manager = BatchOperationManager.shared
    
    var body: some View {
        VStack {
            if manager.sessions.isEmpty {
                EmptySessionsView()
            } else {
                List {
                    ForEach(manager.sessions) { session in
                        BatchSessionRow(session: session)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            manager.deleteSession(manager.sessions[index])
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Empty Sessions View

struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Import Sessions")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Your batch import history will appear here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Batch Session Row

struct BatchSessionRow: View {
    let session: BatchImportSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: session.status.icon)
                    .foregroundColor(colorForStatus(session.status))
                
                Text(session.name)
                    .font(.headline)
                
                Spacer()
                
                Text(session.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let result = session.result {
                HStack(spacing: 16) {
                    Label("\(result.totalCount) URLs", systemImage: "link")
                    Label("\(result.successCount) Success", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                    Label("\(result.failedCount) Failed", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Text("\(String(format: "%.1f", result.successRate))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func colorForStatus(_ status: BatchImportSession.SessionStatus) -> Color {
        switch status.color {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "gray": return .gray
        default: return .primary
        }
    }
}

// MARK: - Batch Result View

struct BatchResultView: View {
    let result: BatchOperationResult
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading) {
                    Text("Import Complete")
                        .font(.title)
                    
                    Text(result.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Statistics
            HStack(spacing: 40) {
                BatchStatCard(title: "Total", value: "\(result.totalCount)", color: .blue)
                BatchStatCard(title: "Success", value: "\(result.successCount)", color: .green)
                BatchStatCard(title: "Failed", value: "\(result.failedCount)", color: .red)
                BatchStatCard(title: "Success Rate", value: "\(String(format: "%.1f", result.successRate))%", color: .orange)
            }
            .padding()
            
            // Details
            if !result.validationResults.isEmpty {
                List(result.validationResults) { validationResult in
                    ValidationResultRow(result: validationResult)
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Batch Stat Card

struct BatchStatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 100)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}
