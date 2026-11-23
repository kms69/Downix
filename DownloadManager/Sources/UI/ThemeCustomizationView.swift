import SwiftUI

/// Main view for theme and UI customization settings
public struct ThemeCustomizationView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedTab: Tab = .appearance
    @State private var showingThemeEditor = false
    @State private var showingImportSheet = false
    @State private var showingExportSheet = false
    @State private var editingTheme: AppTheme?
    @State private var themeToDelete: AppTheme?
    @State private var showingDeleteAlert = false
    
    private enum Tab: String, CaseIterable {
        case appearance = "Appearance"
        case layout = "Layout"
        case toolbar = "Toolbar"
        case menuBar = "Menu Bar"
        case advanced = "Advanced"
        
        var icon: String {
            switch self {
            case .appearance: return "paintpalette"
            case .layout: return "rectangle.3.offgrid"
            case .toolbar: return "menubar.rectangle"
            case .menuBar: return "menubar.arrow.down.rectangle"
            case .advanced: return "gearshape.2"
            }
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // Sidebar with tabs as per UI Design specification
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Customization")
        } detail: {
            // Main content area
            Group {
                switch selectedTab {
                case .appearance:
                    appearanceView
                case .layout:
                    layoutView
                case .toolbar:
                    toolbarView
                case .menuBar:
                    menuBarView
                case .advanced:
                    advancedView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .primaryAction) {
                    Button("Reset to Defaults") {
                        themeManager.resetToDefaults()
                    }
                }
            })
        }
        .sheet(isPresented: $showingThemeEditor) {
            if let theme = editingTheme {
                ThemeEditorView(theme: theme) { updatedTheme in
                    themeManager.updateCustomTheme(updatedTheme)
                    showingThemeEditor = false
                }
            } else {
                ThemeEditorView { newTheme in
                    themeManager.addCustomTheme(newTheme)
                    showingThemeEditor = false
                }
            }
        }
        .alert("Delete Theme", isPresented: $showingDeleteAlert, presenting: themeToDelete) { theme in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                themeManager.deleteCustomTheme(theme.id)
            }
        } message: { theme in
            Text("Are you sure you want to delete '\(theme.name)'? This action cannot be undone.")
        }
    }
    
    // MARK: - Appearance Tab
    
    private var appearanceView: some View {
        Form {
            Section("Appearance Mode") {
                Picker("Mode", selection: Binding(
                    get: { themeManager.config.appearanceMode },
                    set: { themeManager.setAppearanceMode($0) }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                Text("Choose how the app appears: follow system settings, always light, or always dark.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Themes") {
                // Built-in themes
                Text("Built-in Themes")
                    .font(.headline)
                
                ForEach(themeManager.getBuiltInThemes()) { theme in
                    themeRow(theme: theme)
                }
                
                // Custom themes
                if !themeManager.getCustomThemes().isEmpty {
                    Divider()
                    
                    HStack {
                        Text("Custom Themes")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            editingTheme = nil
                            showingThemeEditor = true
                        }) {
                            Label("New Theme", systemImage: "plus.circle")
                        }
                    }
                    
                    ForEach(themeManager.getCustomThemes()) { theme in
                        themeRow(theme: theme, isCustom: true)
                    }
                } else {
                    Button(action: {
                        editingTheme = nil
                        showingThemeEditor = true
                    }) {
                        Label("Create Custom Theme", systemImage: "plus.circle")
                    }
                }
            }
            
            Section("Auto Theme Switching") {
                Toggle("Enable Auto-Switching", isOn: Binding(
                    get: { themeManager.config.autoSwitchTheme },
                    set: { _ in
                        themeManager.setAutoSwitchTheme(
                            !themeManager.config.autoSwitchTheme,
                            lightThemeID: themeManager.config.lightModeThemeID,
                            darkThemeID: themeManager.config.darkModeThemeID
                        )
                    }
                ))
                
                if themeManager.config.autoSwitchTheme {
                    Picker("Light Mode Theme", selection: Binding(
                        get: { themeManager.config.lightModeThemeID ?? themeManager.allThemes[0].id },
                        set: { newValue in
                            themeManager.setAutoSwitchTheme(
                                true,
                                lightThemeID: newValue,
                                darkThemeID: themeManager.config.darkModeThemeID
                            )
                        }
                    )) {
                        ForEach(themeManager.allThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                    
                    Picker("Dark Mode Theme", selection: Binding(
                        get: { themeManager.config.darkModeThemeID ?? themeManager.allThemes[0].id },
                        set: { newValue in
                            themeManager.setAutoSwitchTheme(
                                true,
                                lightThemeID: themeManager.config.lightModeThemeID,
                                darkThemeID: newValue
                            )
                        }
                    )) {
                        ForEach(themeManager.allThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
    
    private func themeRow(theme: AppTheme, isCustom: Bool = false) -> some View {
        HStack {
            // Theme preview colors
            HStack(spacing: 4) {
                Circle()
                    .fill(theme.accentColor.color)
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(theme.secondaryAccentColor.color)
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(theme.successColor.color)
                    .frame(width: 20, height: 20)
            }
            
            Text(theme.name)
                .font(.body)
            
            Spacer()
            
            if themeManager.config.currentTheme.id == theme.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            if isCustom {
                Menu {
                    Button("Edit") {
                        editingTheme = theme
                        showingThemeEditor = true
                    }
                    
                    Button("Duplicate") {
                        _ = themeManager.duplicateTheme(theme)
                    }
                    
                    Button("Export") {
                        // Export functionality
                    }
                    
                    Divider()
                    
                    Button("Delete", role: .destructive) {
                        themeToDelete = theme
                        showingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            themeManager.setTheme(theme)
        }
    }
    
    // MARK: - Layout Tab
    
    private var layoutView: some View {
        Form {
            Section("Window Layout") {
                Picker("Layout Style", selection: Binding(
                    get: { themeManager.config.uiLayout.windowLayoutStyle },
                    set: { themeManager.setWindowLayoutStyle($0) }
                )) {
                    ForEach(WindowLayoutStyle.allCases) { style in
                        VStack(alignment: .leading) {
                            Label(style.displayName, systemImage: style.icon)
                            Text(style.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(style)
                    }
                }
                
                Picker("Sidebar", selection: Binding(
                    get: { themeManager.config.uiLayout.sidebarVisibility },
                    set: { themeManager.setSidebarVisibility($0) }
                )) {
                    ForEach(SidebarVisibility.allCases) { visibility in
                        Text(visibility.rawValue).tag(visibility)
                    }
                }
                
                Picker("Toolbar Style", selection: Binding(
                    get: { themeManager.config.uiLayout.toolbarStyle },
                    set: { themeManager.setToolbarStyle($0) }
                )) {
                    ForEach(ToolbarStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            }
            
            Section("Download List Columns") {
                Text("Customize which columns to display in the download list")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(themeManager.config.uiLayout.downloadListColumns) { column in
                    HStack {
                        Toggle(column.name, isOn: Binding(
                            get: { column.isVisible },
                            set: { _ in themeManager.toggleColumnVisibility(column.key) }
                        ))
                        
                        Spacer()
                        
                        if column.isVisible {
                            Text("\(Int(column.width))px")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Button("Reset Columns") {
                    themeManager.setDownloadListColumns(DownloadListColumn.defaultColumns)
                }
            }
            
            Section("Text Size") {
                Picker("Font Size", selection: Binding(
                    get: { themeManager.config.uiLayout.fontSize },
                    set: { newValue in
                        var layout = themeManager.config.uiLayout
                        layout.fontSize = newValue
                        themeManager.setUILayout(layout)
                    }
                )) {
                    ForEach(UILayoutConfig.FontSize.allCases) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("Status Bar") {
                Toggle("Show Status Bar", isOn: Binding(
                    get: { themeManager.config.uiLayout.showStatusBar },
                    set: { themeManager.toggleStatusBar($0) }
                ))
                
                if themeManager.config.uiLayout.showStatusBar {
                    Toggle("Show Download Speed", isOn: Binding(
                        get: { themeManager.config.uiLayout.showDownloadSpeed },
                        set: { newValue in
                            var layout = themeManager.config.uiLayout
                            layout.showDownloadSpeed = newValue
                            themeManager.setUILayout(layout)
                        }
                    ))
                    
                    Toggle("Show Network Status", isOn: Binding(
                        get: { themeManager.config.uiLayout.showNetworkStatus },
                        set: { newValue in
                            var layout = themeManager.config.uiLayout
                            layout.showNetworkStatus = newValue
                            themeManager.setUILayout(layout)
                        }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Layout")
    }
    
    // MARK: - Toolbar Tab
    
    private var toolbarView: some View {
        Form {
            Section("Toolbar Customization") {
                Text("Customize toolbar items and their order. Drag to reorder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(themeManager.config.uiLayout.toolbarItems) { item in
                        HStack {
                            Image(systemName: item.icon)
                                .foregroundColor(themeManager.effectiveTheme.accentColor.color)
                            
                            Toggle(item.name, isOn: Binding(
                                get: { item.isVisible },
                                set: { _ in themeManager.toggleToolbarItemVisibility(item.key) }
                            ))
                            
                            Spacer()
                            
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { source, destination in
                        themeManager.reorderToolbarItems(from: source, to: destination)
                    }
                }
                
                Button("Reset Toolbar") {
                    themeManager.setToolbarItems(ToolbarItemConfig.defaultItems)
                }
            }
            
            Section("Quick Actions") {
                Text("Toolbar items marked as visible will appear in the main toolbar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Toolbar")
    }
    
    // MARK: - Menu Bar Tab
    
    private var menuBarView: some View {
        Form {
            Section("Menu Bar Extra") {
                Toggle("Enable Menu Bar Extra", isOn: Binding(
                    get: { themeManager.config.menuBarConfig.isEnabled },
                    set: { themeManager.toggleMenuBarExtra($0) }
                ))
                
                if themeManager.config.menuBarConfig.isEnabled {
                    Toggle("Show Icon", isOn: Binding(
                        get: { themeManager.config.menuBarConfig.showIcon },
                        set: { newValue in
                            var config = themeManager.config.menuBarConfig
                            config.showIcon = newValue
                            themeManager.setMenuBarConfig(config)
                        }
                    ))
                    
                    Toggle("Show Download Speed", isOn: Binding(
                        get: { themeManager.config.menuBarConfig.showDownloadSpeed },
                        set: { newValue in
                            var config = themeManager.config.menuBarConfig
                            config.showDownloadSpeed = newValue
                            themeManager.setMenuBarConfig(config)
                        }
                    ))
                    
                    Toggle("Show Active Count", isOn: Binding(
                        get: { themeManager.config.menuBarConfig.showActiveCount },
                        set: { newValue in
                            var config = themeManager.config.menuBarConfig
                            config.showActiveCount = newValue
                            themeManager.setMenuBarConfig(config)
                        }
                    ))
                    
                    Picker("Icon Style", selection: Binding(
                        get: { themeManager.config.menuBarConfig.iconStyle },
                        set: { newValue in
                            var config = themeManager.config.menuBarConfig
                            config.iconStyle = newValue
                            themeManager.setMenuBarConfig(config)
                        }
                    )) {
                        ForEach(MenuBarConfig.IconStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    
                    Stepper("Update Interval: \(String(format: "%.1f", themeManager.config.menuBarConfig.updateInterval))s",
                            value: Binding(
                                get: { themeManager.config.menuBarConfig.updateInterval },
                                set: { newValue in
                                    var config = themeManager.config.menuBarConfig
                                    config.updateInterval = newValue
                                    themeManager.setMenuBarConfig(config)
                                }
                            ),
                            in: 0.5...5.0,
                            step: 0.5)
                }
            }
            
            Section("Preview") {
                Text("Menu bar preview would appear here")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Menu Bar")
    }
    
    // MARK: - Advanced Tab
    
    private var advancedView: some View {
        Form {
            Section("Effects") {
                Toggle("Enable Animations", isOn: Binding(
                    get: { themeManager.config.enableAnimations },
                    set: { themeManager.setAnimationsEnabled($0) }
                ))
                
                Toggle("Enable Transparency", isOn: Binding(
                    get: { themeManager.config.enableTransparency },
                    set: { themeManager.setTransparencyEnabled($0) }
                ))
            }
            
            Section("Import/Export") {
                Button("Import Theme") {
                    showingImportSheet = true
                }
                
                Button("Export Current Theme") {
                    showingExportSheet = true
                }
            }
            
            Section("Reset") {
                Button("Reset All Settings", role: .destructive) {
                    themeManager.resetToDefaults()
                }
            }
            
            Section("Information") {
                LabeledContent("Total Themes", value: "\(themeManager.allThemes.count)")
                LabeledContent("Custom Themes", value: "\(themeManager.getCustomThemes().count)")
                LabeledContent("Last Modified", value: themeManager.config.lastModified.formatted())
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
    }
}

// MARK: - Theme Editor View

private struct ThemeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var theme: AppTheme
    let onSave: (AppTheme) -> Void
    
    init(theme: AppTheme? = nil, onSave: @escaping (AppTheme) -> Void) {
        _theme = State(initialValue: theme ?? AppTheme(name: "New Theme"))
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Theme Name", text: $theme.name)
                }
                
                Section("Colors") {
                    ColorPicker("Accent Color", selection: Binding(
                        get: { theme.accentColor.color },
                        set: { theme.accentColor = CodableColor($0) }
                    ))
                    
                    ColorPicker("Secondary Accent", selection: Binding(
                        get: { theme.secondaryAccentColor.color },
                        set: { theme.secondaryAccentColor = CodableColor($0) }
                    ))
                    
                    ColorPicker("Background", selection: Binding(
                        get: { theme.backgroundColor.color },
                        set: { theme.backgroundColor = CodableColor($0) }
                    ))
                    
                    ColorPicker("Text Color", selection: Binding(
                        get: { theme.textColor.color },
                        set: { theme.textColor = CodableColor($0) }
                    ))
                    
                    ColorPicker("Progress Bar", selection: Binding(
                        get: { theme.progressBarColor.color },
                        set: { theme.progressBarColor = CodableColor($0) }
                    ))
                }
                
                Section("Status Colors") {
                    ColorPicker("Success", selection: Binding(
                        get: { theme.successColor.color },
                        set: { theme.successColor = CodableColor($0) }
                    ))
                    
                    ColorPicker("Warning", selection: Binding(
                        get: { theme.warningColor.color },
                        set: { theme.warningColor = CodableColor($0) }
                    ))
                    
                    ColorPicker("Error", selection: Binding(
                        get: { theme.errorColor.color },
                        set: { theme.errorColor = CodableColor($0) }
                    ))
                    
                    ColorPicker("Info", selection: Binding(
                        get: { theme.infoColor.color },
                        set: { theme.infoColor = CodableColor($0) }
                    ))
                }
                
                Section("Preview") {
                    VStack(spacing: 16) {
                        HStack {
                            Circle()
                                .fill(theme.accentColor.color)
                                .frame(width: 40, height: 40)
                            Circle()
                                .fill(theme.secondaryAccentColor.color)
                                .frame(width: 40, height: 40)
                            Circle()
                                .fill(theme.successColor.color)
                                .frame(width: 40, height: 40)
                            Circle()
                                .fill(theme.warningColor.color)
                                .frame(width: 40, height: 40)
                            Circle()
                                .fill(theme.errorColor.color)
                                .frame(width: 40, height: 40)
                        }
                        
                        ProgressView(value: 0.7)
                            .tint(theme.progressBarColor.color)
                        
                        Button("Sample Button") {}
                            .buttonStyle(.borderedProminent)
                            .tint(theme.accentColor.color)
                    }
                    .padding()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(theme.isBuiltIn ? "Edit Theme" : "Create Theme")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                SwiftUI.ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(theme)
                    }
                    .disabled(theme.name.isEmpty)
                }
            })
        }
    }
}
