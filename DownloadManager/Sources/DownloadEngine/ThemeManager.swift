import Foundation
import SwiftUI
import AppKit
import Combine

/// Manager for theme and UI customization settings
@MainActor
public final class ThemeManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = ThemeManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var config: ThemeCustomizationConfig
    @Published public private(set) var allThemes: [AppTheme]
    @Published public private(set) var currentColorScheme: ColorScheme? {
        didSet { Self.applyAppAppearance(currentColorScheme) }
    }

    /// Floating panels are separate windows that do not inherit the main
    /// window's .preferredColorScheme; set the app-wide appearance so they match.
    static func appearance(for scheme: ColorScheme?) -> NSAppearance? {
        switch scheme {
        case .dark?:  return NSAppearance(named: .darkAqua)
        case .light?: return NSAppearance(named: .aqua)
        default:      return nil
        }
    }

    static func applyAppAppearance(_ scheme: ColorScheme?) {
        let appearance: NSAppearance?
        switch scheme {
        case .dark?:  appearance = NSAppearance(named: .darkAqua)
        case .light?: appearance = NSAppearance(named: .aqua)
        default:      appearance = nil
        }
        NSApplication.shared.appearance = appearance
    }
    @Published public private(set) var effectiveTheme: AppTheme {
        didSet { DownixAccent.apply(effectiveTheme) }
    }
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "themeCustomizationConfig"
    private let customThemesKey = "customThemes"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        // Load saved configuration
        let loadedConfig: ThemeCustomizationConfig
        if let data = userDefaults.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(ThemeCustomizationConfig.self, from: data) {
            loadedConfig = decoded
        } else {
            loadedConfig = .default
        }
        
        // Initialize properties
        self.config = loadedConfig
        self.allThemes = AppTheme.builtInThemes + loadedConfig.customThemes
        self.currentColorScheme = loadedConfig.appearanceMode.colorScheme
        Self.applyAppAppearance(loadedConfig.appearanceMode.colorScheme)
        self.effectiveTheme = loadedConfig.currentTheme
        DownixAccent.apply(loadedConfig.currentTheme)
        
        // Set up color scheme observation
        setupColorSchemeObservation()
    }
    
    // MARK: - Appearance Mode
    
    /// Update appearance mode
    public func setAppearanceMode(_ mode: AppearanceMode) {
        config.appearanceMode = mode
        currentColorScheme = mode.colorScheme
        config.lastModified = Date()
        
        // Update effective theme based on auto-switch settings
        updateEffectiveTheme()
        
        saveConfig()
    }
    
    /// Get current appearance mode
    public func getAppearanceMode() -> AppearanceMode {
        return config.appearanceMode
    }
    
    // MARK: - Theme Management
    
    /// Set current theme
    public func setTheme(_ theme: AppTheme) {
        config.currentTheme = theme
        effectiveTheme = theme
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Get current theme
    public func getCurrentTheme() -> AppTheme {
        return config.currentTheme
    }
    
    /// Get all available themes
    public func getAllThemes() -> [AppTheme] {
        return allThemes
    }
    
    /// Get built-in themes only
    public func getBuiltInThemes() -> [AppTheme] {
        return allThemes.filter { $0.isBuiltIn }
    }
    
    /// Get custom themes only
    public func getCustomThemes() -> [AppTheme] {
        return allThemes.filter { !$0.isBuiltIn }
    }
    
    /// Add custom theme
    public func addCustomTheme(_ theme: AppTheme) {
        var newTheme = theme
        newTheme.isBuiltIn = false
        
        config.customThemes.append(newTheme)
        allThemes = AppTheme.builtInThemes + config.customThemes
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Update existing custom theme
    public func updateCustomTheme(_ theme: AppTheme) {
        guard !theme.isBuiltIn else { return }
        
        if let index = config.customThemes.firstIndex(where: { $0.id == theme.id }) {
            var updatedTheme = theme
            updatedTheme.modifiedAt = Date()
            config.customThemes[index] = updatedTheme
            allThemes = AppTheme.builtInThemes + config.customThemes
            
            // Update current theme if it's the one being updated
            if config.currentTheme.id == theme.id {
                config.currentTheme = updatedTheme
                effectiveTheme = updatedTheme
            }
            
            config.lastModified = Date()
            saveConfig()
        }
    }
    
    /// Delete custom theme
    public func deleteCustomTheme(_ themeID: UUID) {
        config.customThemes.removeAll { $0.id == themeID }
        allThemes = AppTheme.builtInThemes + config.customThemes
        
        // Reset to default if deleted theme was current
        if config.currentTheme.id == themeID {
            config.currentTheme = .default
            effectiveTheme = .default
        }
        
        // Clear auto-switch references
        if config.lightModeThemeID == themeID {
            config.lightModeThemeID = nil
        }
        if config.darkModeThemeID == themeID {
            config.darkModeThemeID = nil
        }
        
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Duplicate theme
    public func duplicateTheme(_ theme: AppTheme) -> AppTheme {
        let newTheme = AppTheme(
            name: "\(theme.name) Copy",
            isBuiltIn: false,
            accentColor: theme.accentColor,
            secondaryAccentColor: theme.secondaryAccentColor,
            backgroundColor: theme.backgroundColor,
            secondaryBackgroundColor: theme.secondaryBackgroundColor,
            textColor: theme.textColor,
            secondaryTextColor: theme.secondaryTextColor,
            successColor: theme.successColor,
            warningColor: theme.warningColor,
            errorColor: theme.errorColor,
            infoColor: theme.infoColor,
            progressBarColor: theme.progressBarColor,
            borderColor: theme.borderColor
        )
        
        addCustomTheme(newTheme)
        return newTheme
    }
    
    // MARK: - Auto Theme Switching
    
    /// Enable/disable auto theme switching based on system appearance
    public func setAutoSwitchTheme(_ enabled: Bool, lightThemeID: UUID? = nil, darkThemeID: UUID? = nil) {
        config.autoSwitchTheme = enabled
        config.lightModeThemeID = lightThemeID
        config.darkModeThemeID = darkThemeID
        config.lastModified = Date()
        
        updateEffectiveTheme()
        saveConfig()
    }
    
    /// Update effective theme based on current appearance
    private func updateEffectiveTheme() {
        guard config.autoSwitchTheme else {
            effectiveTheme = config.currentTheme
            return
        }
        
        // Determine if we're in light or dark mode
        let isDarkMode = (currentColorScheme == .dark) || 
                        (currentColorScheme == nil && NSApp.effectiveAppearance.name == .darkAqua)
        
        if isDarkMode, let darkThemeID = config.darkModeThemeID,
           let darkTheme = allThemes.first(where: { $0.id == darkThemeID }) {
            effectiveTheme = darkTheme
        } else if !isDarkMode, let lightThemeID = config.lightModeThemeID,
                  let lightTheme = allThemes.first(where: { $0.id == lightThemeID }) {
            effectiveTheme = lightTheme
        } else {
            effectiveTheme = config.currentTheme
        }
    }
    
    /// Setup observation for system appearance changes
    private func setupColorSchemeObservation() {
        // Observe system appearance changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateEffectiveTheme()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - UI Layout Configuration
    
    /// Update UI layout configuration
    public func setUILayout(_ layout: UILayoutConfig) {
        config.uiLayout = layout
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Update window layout style
    public func setWindowLayoutStyle(_ style: WindowLayoutStyle) {
        config.uiLayout.windowLayoutStyle = style
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Update sidebar visibility
    public func setSidebarVisibility(_ visibility: SidebarVisibility) {
        config.uiLayout.sidebarVisibility = visibility
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Update toolbar style
    public func setToolbarStyle(_ style: ToolbarStyle) {
        config.uiLayout.toolbarStyle = style
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Update download list columns
    public func setDownloadListColumns(_ columns: [DownloadListColumn]) {
        config.uiLayout.downloadListColumns = columns
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Toggle column visibility
    public func toggleColumnVisibility(_ columnKey: DownloadListColumn.ColumnKey) {
        if let index = config.uiLayout.downloadListColumns.firstIndex(where: { $0.key == columnKey }) {
            config.uiLayout.downloadListColumns[index].isVisible.toggle()
            config.lastModified = Date()
            saveConfig()
        }
    }
    
    /// Update toolbar items
    public func setToolbarItems(_ items: [ToolbarItemConfig]) {
        config.uiLayout.toolbarItems = items
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Toggle toolbar item visibility
    public func toggleToolbarItemVisibility(_ itemKey: ToolbarItemConfig.ItemKey) {
        if let index = config.uiLayout.toolbarItems.firstIndex(where: { $0.key == itemKey }) {
            config.uiLayout.toolbarItems[index].isVisible.toggle()
            config.lastModified = Date()
            saveConfig()
        }
    }
    
    /// Reorder toolbar items
    public func reorderToolbarItems(from source: IndexSet, to destination: Int) {
        config.uiLayout.toolbarItems.move(fromOffsets: source, toOffset: destination)
        // Update order values
        for (index, _) in config.uiLayout.toolbarItems.enumerated() {
            config.uiLayout.toolbarItems[index].order = index
        }
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Reset to default layout
    public func resetToDefaultLayout() {
        config.uiLayout = UILayoutConfig()
        config.lastModified = Date()
        saveConfig()
    }
    
    // MARK: - Menu Bar Configuration
    
    /// Update menu bar configuration
    public func setMenuBarConfig(_ menuBarConfig: MenuBarConfig) {
        config.menuBarConfig = menuBarConfig
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Toggle menu bar extra
    public func toggleMenuBarExtra(_ enabled: Bool) {
        config.menuBarConfig.isEnabled = enabled
        config.lastModified = Date()
        saveConfig()
    }
    
    // MARK: - Status Bar Configuration
    
    /// Update status bar configuration
    public func setStatusBarConfig(_ statusBarConfig: StatusBarConfig) {
        config.statusBarConfig = statusBarConfig
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Toggle status bar visibility
    public func toggleStatusBar(_ visible: Bool) {
        config.uiLayout.showStatusBar = visible
        config.lastModified = Date()
        saveConfig()
    }
    
    // MARK: - Animation & Effects
    
    /// Enable/disable animations
    public func setAnimationsEnabled(_ enabled: Bool) {
        config.enableAnimations = enabled
        config.lastModified = Date()
        saveConfig()
    }
    
    /// Enable/disable transparency effects
    public func setTransparencyEnabled(_ enabled: Bool) {
        config.enableTransparency = enabled
        config.lastModified = Date()
        saveConfig()
    }
    
    // MARK: - Theme Import/Export
    
    /// Export theme to file
    public func exportTheme(_ theme: AppTheme, format: ThemeExportFormat, author: String? = nil, description: String? = nil) -> Data? {
        let package = ThemePackage(
            theme: theme,
            author: author,
            description: description
        )
        
        switch format {
        case .json:
            return try? JSONEncoder().encode(package)
        case .plist:
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            return try? encoder.encode(package)
        }
    }
    
    /// Import theme from data
    public func importTheme(from data: Data, format: ThemeExportFormat) -> AppTheme? {
        switch format {
        case .json:
            if let package = try? JSONDecoder().decode(ThemePackage.self, from: data) {
                addCustomTheme(package.theme)
                return package.theme
            }
        case .plist:
            if let package = try? PropertyListDecoder().decode(ThemePackage.self, from: data) {
                addCustomTheme(package.theme)
                return package.theme
            }
        }
        
        return nil
    }
    
    // MARK: - Persistence
    
    /// Save configuration to UserDefaults
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            userDefaults.set(data, forKey: configKey)
        }
    }
    
    /// Reset to default configuration
    public func resetToDefaults() {
        config = .default
        allThemes = AppTheme.builtInThemes
        currentColorScheme = config.appearanceMode.colorScheme
        effectiveTheme = config.currentTheme
        saveConfig()
    }
    
    // MARK: - Utility Methods
    
    /// Get visible columns
    public func getVisibleColumns() -> [DownloadListColumn] {
        return config.uiLayout.downloadListColumns.filter { $0.isVisible }.sorted { $0.order < $1.order }
    }
    
    /// Get visible toolbar items
    public func getVisibleToolbarItems() -> [ToolbarItemConfig] {
        return config.uiLayout.toolbarItems.filter { $0.isVisible }.sorted { $0.order < $1.order }
    }
    
    /// Apply theme colors to a view
    public func applyTheme(to view: some View) -> some View {
        view
            .tint(effectiveTheme.accentColor.color)
            .preferredColorScheme(currentColorScheme)
    }
    
    /// Get font size for current configuration
    public func getFont(_ style: Font.TextStyle = .body) -> Font {
        switch config.uiLayout.fontSize {
        case .small:
            return .system(size: 11)
        case .medium:
            return .system(size: 13)
        case .large:
            return .system(size: 15)
        case .extraLarge:
            return .system(size: 17)
        }
    }
}
