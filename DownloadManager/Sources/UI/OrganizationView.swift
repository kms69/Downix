//
//  OrganizationView.swift
//  Download Manager for Mac - Feature #8: Smart Organization
//
//  Created on February 15, 2026
//

import SwiftUI

struct OrganizationView: View {
    
    @ObservedObject var manager = OrganizationManager.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    
    @State private var selectedTab = 0
    @State private var showingRuleEditor = false
    @State private var showingTagEditor = false
    @State private var editingRule: OrganizationRule?
    @State private var editingTag: DownloadTag?
    @State private var searchFilter = SearchFilter()
    @State private var searchResults: [DownloadTask] = []
    @State private var duplicates: [DuplicateDetectionResult] = []
    @State private var suggestions: [OrganizationSuggestion] = []
    @State private var isScanning = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab selection
            Picker("View", selection: $selectedTab) {
                Text("Rules").tag(0)
                Text("Tags").tag(1)
                Text("Search").tag(2)
                Text("Duplicates").tag(3)
                Text("Statistics").tag(4)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                rulesView.tag(0)
                tagsView.tag(1)
                searchView.tag(2)
                duplicatesView.tag(3)
                statisticsView.tag(4)
            }
        }
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorView(rule: editingRule) { rule in
                if editingRule != nil {
                    manager.updateRule(rule)
                } else {
                    manager.addRule(rule)
                }
                editingRule = nil
            }
        }
        .sheet(isPresented: $showingTagEditor) {
            TagEditorView(tag: editingTag) { tag in
                if editingTag != nil {
                    manager.updateTag(tag)
                } else {
                    manager.addNewTag(tag)
                }
                editingTag = nil
            }
        }
        .onAppear {
            loadSuggestions()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Organization")
                    .font(.title2)
                    .bold()
                Text("\(manager.statistics.activeRules) active rules • \(manager.tags.count) tags")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !suggestions.isEmpty {
                suggestionButton
            }
        }
        .padding()
    }
    
    private var suggestionButton: some View {
        Menu {
            ForEach(suggestions) { suggestion in
                Button {
                    applySuggestion(suggestion)
                } label: {
                    VStack(alignment: .leading) {
                        Text(suggestion.description)
                        Text("\(Int(suggestion.confidence * 100))% confidence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } label: {
            Label("Suggestions (\(suggestions.count))", systemImage: "lightbulb.fill")
                .foregroundColor(.orange)
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
                
                Spacer()
                
                Text("\(manager.rules.count) rules")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Rules list
            if manager.rules.isEmpty {
                emptyStateView(
                    icon: "slider.horizontal.3",
                    title: "No Rules Yet",
                    message: "Create rules to automatically organize your downloads"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(manager.rules.sorted { $0.priority > $1.priority }) { rule in
                            RuleCardView(rule: rule) {
                                editingRule = rule
                                showingRuleEditor = true
                            } onDelete: {
                                manager.deleteRule(rule)
                            } onToggle: {
                                var updated = rule
                                updated.isEnabled.toggle()
                                manager.updateRule(updated)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Tags View
    
    private var tagsView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    editingTag = nil
                    showingTagEditor = true
                } label: {
                    Label("Add Tag", systemImage: "plus")
                }
                
                Spacer()
                
                Text("\(manager.tags.count) tags")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Tags grid
            if manager.tags.isEmpty {
                emptyStateView(
                    icon: "tag",
                    title: "No Tags Yet",
                    message: "Create tags to categorize and organize your downloads"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150, maximum: 200))
                    ], spacing: 12) {
                        ForEach(manager.tags.sorted { $0.usageCount > $1.usageCount }) { tag in
                            TagCardView(tag: tag) {
                                editingTag = tag
                                showingTagEditor = true
                            } onDelete: {
                                manager.deleteTag(tag)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Search View
    
    private var searchView: some View {
        VStack(spacing: 0) {
            // Search filters
            SearchFilterView(filter: $searchFilter)
                .padding()
            
            Divider()
            
            // Search button
            HStack {
                Button {
                    performSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .keyboardShortcut(.return)
                
                if !searchResults.isEmpty {
                    Button {
                        searchResults = []
                        searchFilter = SearchFilter()
                    } label: {
                        Text("Clear")
                    }
                }
                
                Spacer()
                
                Text("\(searchResults.count) results")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Results
            if searchResults.isEmpty && searchFilter.text?.isEmpty != false {
                emptyStateView(
                    icon: "magnifyingglass",
                    title: "Advanced Search",
                    message: "Set filters and search your downloads"
                )
            } else if searchResults.isEmpty {
                emptyStateView(
                    icon: "exclamationmark.magnifyingglass",
                    title: "No Results",
                    message: "Try adjusting your search filters"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(searchResults) { task in
                            SearchResultCardView(task: task, tags: manager.getTags(for: task))
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Duplicates View
    
    private var duplicatesView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    scanForDuplicates()
                } label: {
                    Label("Scan for Duplicates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isScanning)
                
                Spacer()
                
                if !duplicates.isEmpty {
                    Text("Found \(duplicates.count) duplicate groups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Divider()
            
            // Results
            if duplicates.isEmpty && !isScanning {
                emptyStateView(
                    icon: "doc.on.doc",
                    title: "No Duplicates Found",
                    message: "Scan your downloads to find duplicate files"
                )
            } else if isScanning {
                ProgressView("Scanning for duplicates...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(duplicates) { result in
                            DuplicateGroupCardView(result: result) {
                                manager.removeDuplicates(result, keepOriginal: true)
                                scanForDuplicates()
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
                // Overview
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCardView(
                        title: "Rules Created",
                        value: "\(manager.statistics.totalRulesCreated)",
                        icon: "slider.horizontal.3",
                        color: .blue
                    )
                    
                    StatCardView(
                        title: "Active Rules",
                        value: "\(manager.statistics.activeRules)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    StatCardView(
                        title: "Total Matches",
                        value: "\(manager.statistics.totalMatches)",
                        icon: "sparkles",
                        color: .purple
                    )
                    
                    StatCardView(
                        title: "Files Organized",
                        value: "\(manager.statistics.filesOrganized)",
                        icon: "tray.full",
                        color: .orange
                    )
                    
                    StatCardView(
                        title: "Tags Created",
                        value: "\(manager.statistics.tagsCreated)",
                        icon: "tag.fill",
                        color: .pink
                    )
                    
                    StatCardView(
                        title: "Duplicates Found",
                        value: "\(manager.statistics.duplicatesFound)",
                        icon: "doc.on.doc.fill",
                        color: .red
                    )
                }
                
                // Space reclaimed
                VStack(alignment: .leading, spacing: 8) {
                    Text("Space Reclaimed")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "externaldrive.fill")
                            .font(.title)
                            .foregroundColor(.green)
                        
                        Text(ByteCountFormatter.string(fromByteCount: manager.statistics.spaceReclaimed, countStyle: .file))
                            .font(.title2)
                            .bold()
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
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
    
    // MARK: - Actions
    
    private func performSearch() {
        searchResults = manager.searchDownloads(filter: searchFilter)
    }
    
    private func scanForDuplicates() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let results = manager.findDuplicates()
            DispatchQueue.main.async {
                duplicates = results
                isScanning = false
            }
        }
    }
    
    private func loadSuggestions() {
        DispatchQueue.global(qos: .utility).async {
            let results = manager.getSuggestions()
            DispatchQueue.main.async {
                suggestions = results
            }
        }
    }
    
    private func applySuggestion(_ suggestion: OrganizationSuggestion) {
        switch suggestion.type {
        case .createRule:
            if let rule = suggestion.suggestedRule {
                editingRule = rule
                showingRuleEditor = true
            }
            
        case .mergeDuplicates:
            scanForDuplicates()
            selectedTab = 3
            
        case .addTag:
            selectedTab = 1
            
        default:
            break
        }
    }
}

// MARK: - Rule Card View

struct RuleCardView: View {
    let rule: OrganizationRule
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void
    
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
                    Button("Toggle", action: onToggle)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            // Conditions
            VStack(alignment: .leading, spacing: 4) {
                Text("Conditions (\(rule.conditions.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(Array(rule.conditions.prefix(2).enumerated()), id: \.offset) { _, condition in
                    Text("• \(condition.description)")
                        .font(.caption)
                }
                
                if rule.conditions.count > 2 {
                    Text("• +\(rule.conditions.count - 2) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Actions
            VStack(alignment: .leading, spacing: 4) {
                Text("Actions (\(rule.actions.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(Array(rule.actions.prefix(2).enumerated()), id: \.offset) { _, action in
                    Text("• \(action.description)")
                        .font(.caption)
                }
                
                if rule.actions.count > 2 {
                    Text("• +\(rule.actions.count - 2) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Statistics
            HStack {
                Text("\(rule.matchCount) matches")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastMatch = rule.lastMatchedAt {
                    Text("• Last: \(lastMatch, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Tag Card View

struct TagCardView: View {
    let tag: DownloadTag
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(tag.color.swiftUIColor)
                    .frame(width: 12, height: 12)
                
                Text(tag.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Menu {
                    Button("Edit", action: onEdit)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            Text("\(tag.usageCount) downloads")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Search Filter View

struct SearchFilterView: View {
    @Binding var filter: SearchFilter
    
    var body: some View {
        VStack(spacing: 12) {
            TextField("Search text", text: Binding(
                get: { filter.text ?? "" },
                set: { filter.text = $0.isEmpty ? nil : $0 }
            ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            // Additional filters can be added here
        }
    }
}

// MARK: - Search Result Card View

struct SearchResultCardView: View {
    let task: DownloadTask
    let tags: [DownloadTag]
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.filename)
                    .font(.headline)
                
                HStack {
                    ForEach(tags.prefix(3)) { tag in
                        TagBadgeView(tag: tag)
                    }
                    
                    if tags.count > 3 {
                        Text("+\(tags.count - 3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Tag Badge View

struct TagBadgeView: View {
    let tag: DownloadTag
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.color.swiftUIColor)
                .frame(width: 6, height: 6)
            
            Text(tag.name)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.color.swiftUIColor.opacity(0.2))
        .cornerRadius(4)
    }
}

// MARK: - Duplicate Group Card View

struct DuplicateGroupCardView: View {
    let result: DuplicateDetectionResult
    let onRemoveDuplicates: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.orange)
                
                Text("\(result.duplicates.count) duplicates found")
                    .font(.headline)
                
                Spacer()
                
                Button("Remove Duplicates", action: onRemoveDuplicates)
                    .buttonStyle(.borderedProminent)
            }
            
            Text("Original: \(result.original.filename)")
                .font(.subheadline)
            
            Text("Wasted space: \(ByteCountFormatter.string(fromByteCount: result.totalWastedSpace, countStyle: .file))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            ForEach(Array(result.duplicates.enumerated()), id: \.offset) { _, match in
                HStack {
                    Text(match.task.filename)
                        .font(.caption)
                    
                    Spacer()
                    
                    Text("\(Int(match.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Stat Card View

struct StatCardView: View {
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
                .font(.title)
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

// MARK: - Rule Editor View

struct RuleEditorView: View {
    let rule: OrganizationRule?
    let onSave: (OrganizationRule) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var priority: Int
    @State private var isEnabled: Bool
    @State private var conditions: [RuleCondition]
    @State private var actions: [RuleAction]
    
    init(rule: OrganizationRule?, onSave: @escaping (OrganizationRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        
        _name = State(initialValue: rule?.name ?? "")
        _priority = State(initialValue: rule?.priority ?? 5)
        _isEnabled = State(initialValue: rule?.isEnabled ?? true)
        _conditions = State(initialValue: rule?.conditions ?? [])
        _actions = State(initialValue: rule?.actions ?? [])
    }
    
    var body: some View {
        VStack {
            Text("Rule Editor")
                .font(.title2)
                .bold()
                .padding()
            
            Form {
                TextField("Rule Name", text: $name)
                
                Stepper("Priority: \(priority)", value: $priority, in: 0...100)
                
                Toggle("Enabled", isOn: $isEnabled)
                
                // Simplified editor - in a real app, this would be more comprehensive
                Text("Conditions: \(conditions.count)")
                Text("Actions: \(actions.count)")
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Save") {
                    let newRule = OrganizationRule(
                        id: rule?.id ?? UUID(),
                        name: name,
                        isEnabled: isEnabled,
                        priority: priority,
                        conditions: conditions,
                        actions: actions
                    )
                    onSave(newRule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Tag Editor View

struct TagEditorView: View {
    let tag: DownloadTag?
    let onSave: (DownloadTag) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var color: DownloadTag.TagColor
    
    init(tag: DownloadTag?, onSave: @escaping (DownloadTag) -> Void) {
        self.tag = tag
        self.onSave = onSave
        
        _name = State(initialValue: tag?.name ?? "")
        _color = State(initialValue: tag?.color ?? .blue)
    }
    
    var body: some View {
        VStack {
            Text("Tag Editor")
                .font(.title2)
                .bold()
                .padding()
            
            Form {
                TextField("Tag Name", text: $name)
                
                Picker("Color", selection: $color) {
                    ForEach(DownloadTag.TagColor.allCases, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(color.rawValue.capitalized)
                        }
                        .tag(color)
                    }
                }
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Save") {
                    let newTag = DownloadTag(id: tag?.id ?? UUID(), name: name, color: color)
                    onSave(newTag)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}

// MARK: - Tag Color Extension

extension DownloadTag.TagColor {
    var swiftUIColor: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}

// MARK: - Preview

struct OrganizationView_Previews: PreviewProvider {
    static var previews: some View {
        OrganizationView()
            .frame(width: 800, height: 600)
    }
}
