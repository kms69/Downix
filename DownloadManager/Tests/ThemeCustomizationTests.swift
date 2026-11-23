import XCTest
@testable import DownloadManager

@MainActor
final class ThemeCustomizationTests: XCTestCase {
    
    var themeManager: ThemeManager!
    
    override func setUp() async throws {
        // Reset to defaults before each test
        themeManager = ThemeManager.shared
        themeManager.resetToDefaults()
    }
    
    override func tearDown() async throws {
        themeManager.resetToDefaults()
        themeManager = nil
    }
    
    // MARK: - Appearance Mode Tests
    
    func testAppearanceModeDefault() {
        XCTAssertEqual(themeManager.getAppearanceMode(), .system)
    }
    
    func testSetAppearanceModeLight() {
        themeManager.setAppearanceMode(.light)
        XCTAssertEqual(themeManager.getAppearanceMode(), .light)
        XCTAssertEqual(themeManager.currentColorScheme, .light)
    }
    
    func testSetAppearanceModeDark() {
        themeManager.setAppearanceMode(.dark)
        XCTAssertEqual(themeManager.getAppearanceMode(), .dark)
        XCTAssertEqual(themeManager.currentColorScheme, .dark)
    }
    
    func testSetAppearanceModeSystem() {
        themeManager.setAppearanceMode(.system)
        XCTAssertEqual(themeManager.getAppearanceMode(), .system)
        XCTAssertNil(themeManager.currentColorScheme)
    }
    
    // MARK: - Theme Management Tests
    
    func testDefaultTheme() {
        let theme = themeManager.getCurrentTheme()
        XCTAssertEqual(theme.name, "Default")
        XCTAssertTrue(theme.isBuiltIn)
    }
    
    func testSetTheme() {
        let blueTheme = AppTheme.blue
        themeManager.setTheme(blueTheme)
        
        XCTAssertEqual(themeManager.getCurrentTheme().name, "Blue")
        XCTAssertEqual(themeManager.effectiveTheme.name, "Blue")
    }
    
    func testGetAllThemes() {
        let allThemes = themeManager.getAllThemes()
        XCTAssertGreaterThanOrEqual(allThemes.count, 5) // At least 5 built-in themes
    }
    
    func testGetBuiltInThemes() {
        let builtInThemes = themeManager.getBuiltInThemes()
        XCTAssertEqual(builtInThemes.count, 5)
        XCTAssertTrue(builtInThemes.allSatisfy { $0.isBuiltIn })
    }
    
    func testGetCustomThemes() {
        let customThemes = themeManager.getCustomThemes()
        XCTAssertEqual(customThemes.count, 0) // No custom themes initially
    }
    
    func testAddCustomTheme() {
        let customTheme = AppTheme(name: "Custom Test Theme")
        themeManager.addCustomTheme(customTheme)
        
        let customThemes = themeManager.getCustomThemes()
        XCTAssertEqual(customThemes.count, 1)
        XCTAssertEqual(customThemes.first?.name, "Custom Test Theme")
        XCTAssertFalse(customThemes.first?.isBuiltIn ?? true)
    }
    
    func testUpdateCustomTheme() {
        var customTheme = AppTheme(name: "Custom Theme")
        themeManager.addCustomTheme(customTheme)
        
        customTheme = themeManager.getCustomThemes().first!
        customTheme.name = "Updated Custom Theme"
        themeManager.updateCustomTheme(customTheme)
        
        let updatedTheme = themeManager.getCustomThemes().first!
        XCTAssertEqual(updatedTheme.name, "Updated Custom Theme")
    }
    
    func testDeleteCustomTheme() {
        let customTheme = AppTheme(name: "To Delete")
        themeManager.addCustomTheme(customTheme)
        
        XCTAssertEqual(themeManager.getCustomThemes().count, 1)
        
        let themeID = themeManager.getCustomThemes().first!.id
        themeManager.deleteCustomTheme(themeID)
        
        XCTAssertEqual(themeManager.getCustomThemes().count, 0)
    }
    
    func testDuplicateTheme() {
        let originalTheme = AppTheme.purple
        let duplicatedTheme = themeManager.duplicateTheme(originalTheme)
        
        XCTAssertTrue(duplicatedTheme.name.contains("Copy"))
        XCTAssertFalse(duplicatedTheme.isBuiltIn)
        XCTAssertEqual(themeManager.getCustomThemes().count, 1)
    }
    
    func testCannotUpdateBuiltInTheme() {
        var blueTheme = AppTheme.blue
        blueTheme.name = "Modified Blue"
        
        themeManager.updateCustomTheme(blueTheme)
        
        // Should not update because it's built-in
        let allThemes = themeManager.getAllThemes()
        let actualBlueTheme = allThemes.first { $0.id == blueTheme.id }
        XCTAssertEqual(actualBlueTheme?.name, "Blue")
    }
    
    // MARK: - Auto Theme Switching Tests
    
    func testAutoThemeSwitchingDisabledByDefault() {
        XCTAssertFalse(themeManager.config.autoSwitchTheme)
    }
    
    func testEnableAutoThemeSwitching() {
        let lightTheme = AppTheme.default
        let darkTheme = AppTheme.purple
        
        themeManager.setAutoSwitchTheme(true, lightThemeID: lightTheme.id, darkThemeID: darkTheme.id)
        
        XCTAssertTrue(themeManager.config.autoSwitchTheme)
        XCTAssertEqual(themeManager.config.lightModeThemeID, lightTheme.id)
        XCTAssertEqual(themeManager.config.darkModeThemeID, darkTheme.id)
    }
    
    func testDisableAutoThemeSwitching() {
        themeManager.setAutoSwitchTheme(true)
        themeManager.setAutoSwitchTheme(false)
        
        XCTAssertFalse(themeManager.config.autoSwitchTheme)
    }
    
    // MARK: - UI Layout Tests
    
    func testDefaultUILayout() {
        let layout = themeManager.config.uiLayout
        XCTAssertEqual(layout.windowLayoutStyle, .standard)
        XCTAssertEqual(layout.sidebarVisibility, .visible)
        XCTAssertEqual(layout.toolbarStyle, .automatic)
        XCTAssertTrue(layout.showStatusBar)
    }
    
    func testSetWindowLayoutStyle() {
        themeManager.setWindowLayoutStyle(.compact)
        XCTAssertEqual(themeManager.config.uiLayout.windowLayoutStyle, .compact)
    }
    
    func testSetSidebarVisibility() {
        themeManager.setSidebarVisibility(.hidden)
        XCTAssertEqual(themeManager.config.uiLayout.sidebarVisibility, .hidden)
    }
    
    func testSetToolbarStyle() {
        themeManager.setToolbarStyle(.minimal)
        XCTAssertEqual(themeManager.config.uiLayout.toolbarStyle, .minimal)
    }
    
    func testToggleStatusBar() {
        themeManager.toggleStatusBar(false)
        XCTAssertFalse(themeManager.config.uiLayout.showStatusBar)
        
        themeManager.toggleStatusBar(true)
        XCTAssertTrue(themeManager.config.uiLayout.showStatusBar)
    }
    
    func testSetFontSize() {
        var layout = themeManager.config.uiLayout
        layout.fontSize = .large
        themeManager.setUILayout(layout)
        
        XCTAssertEqual(themeManager.config.uiLayout.fontSize, .large)
    }
    
    // MARK: - Download List Columns Tests
    
    func testDefaultDownloadListColumns() {
        let columns = themeManager.config.uiLayout.downloadListColumns
        XCTAssertGreaterThan(columns.count, 0)
        XCTAssertTrue(columns.contains { $0.key == .filename })
        XCTAssertTrue(columns.contains { $0.key == .progress })
    }
    
    func testToggleColumnVisibility() {
        themeManager.toggleColumnVisibility(.category)
        
        let column = themeManager.config.uiLayout.downloadListColumns.first { $0.key == .category }
        // Category is hidden by default, so it should be visible after toggle
        XCTAssertTrue(column?.isVisible ?? false)
    }
    
    func testGetVisibleColumns() {
        let visibleColumns = themeManager.getVisibleColumns()
        XCTAssertTrue(visibleColumns.allSatisfy { $0.isVisible })
        XCTAssertEqual(visibleColumns, visibleColumns.sorted { $0.order < $1.order })
    }
    
    func testSetDownloadListColumns() {
        let customColumns = [
            DownloadListColumn(name: "Test", key: .filename, order: 0)
        ]
        themeManager.setDownloadListColumns(customColumns)
        
        XCTAssertEqual(themeManager.config.uiLayout.downloadListColumns.count, 1)
    }
    
    // MARK: - Toolbar Items Tests
    
    func testDefaultToolbarItems() {
        let items = themeManager.config.uiLayout.toolbarItems
        XCTAssertGreaterThan(items.count, 0)
        XCTAssertTrue(items.contains { $0.key == .addURL })
        XCTAssertTrue(items.contains { $0.key == .settings })
    }
    
    func testToggleToolbarItemVisibility() {
        let initialState = themeManager.config.uiLayout.toolbarItems.first { $0.key == .scheduler }?.isVisible ?? false
        
        themeManager.toggleToolbarItemVisibility(.scheduler)
        
        let newState = themeManager.config.uiLayout.toolbarItems.first { $0.key == .scheduler }?.isVisible ?? false
        XCTAssertNotEqual(initialState, newState)
    }
    
    func testGetVisibleToolbarItems() {
        let visibleItems = themeManager.getVisibleToolbarItems()
        XCTAssertTrue(visibleItems.allSatisfy { $0.isVisible })
        XCTAssertEqual(visibleItems, visibleItems.sorted { $0.order < $1.order })
    }
    
    func testReorderToolbarItems() {
        let initialOrder = themeManager.config.uiLayout.toolbarItems.map { $0.key }
        
        themeManager.reorderToolbarItems(from: IndexSet(integer: 0), to: 2)
        
        let newOrder = themeManager.config.uiLayout.toolbarItems.map { $0.key }
        XCTAssertNotEqual(initialOrder, newOrder)
    }
    
    func testResetToDefaultLayout() {
        themeManager.setWindowLayoutStyle(.minimal)
        themeManager.setSidebarVisibility(.hidden)
        
        themeManager.resetToDefaultLayout()
        
        XCTAssertEqual(themeManager.config.uiLayout.windowLayoutStyle, .standard)
        XCTAssertEqual(themeManager.config.uiLayout.sidebarVisibility, .visible)
    }
    
    // MARK: - Menu Bar Configuration Tests
    
    func testDefaultMenuBarConfig() {
        let config = themeManager.config.menuBarConfig
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.showIcon)
        XCTAssertTrue(config.showDownloadSpeed)
        XCTAssertTrue(config.showActiveCount)
    }
    
    func testToggleMenuBarExtra() {
        themeManager.toggleMenuBarExtra(false)
        XCTAssertFalse(themeManager.config.menuBarConfig.isEnabled)
        
        themeManager.toggleMenuBarExtra(true)
        XCTAssertTrue(themeManager.config.menuBarConfig.isEnabled)
    }
    
    func testSetMenuBarConfig() {
        var config = MenuBarConfig()
        config.iconStyle = .minimal
        config.updateInterval = 2.0
        
        themeManager.setMenuBarConfig(config)
        
        XCTAssertEqual(themeManager.config.menuBarConfig.iconStyle, .minimal)
        XCTAssertEqual(themeManager.config.menuBarConfig.updateInterval, 2.0)
    }
    
    // MARK: - Status Bar Configuration Tests
    
    func testDefaultStatusBarConfig() {
        let config = themeManager.config.statusBarConfig
        XCTAssertEqual(config.position, .bottom)
        XCTAssertTrue(config.showGlobalSpeed)
        XCTAssertTrue(config.showActiveDownloads)
    }
    
    func testSetStatusBarConfig() {
        var config = StatusBarConfig()
        config.position = .top
        config.showNetworkStatus = false
        
        themeManager.setStatusBarConfig(config)
        
        XCTAssertEqual(themeManager.config.statusBarConfig.position, .top)
        XCTAssertFalse(themeManager.config.statusBarConfig.showNetworkStatus)
    }
    
    // MARK: - Animation & Effects Tests
    
    func testDefaultAnimationsEnabled() {
        XCTAssertTrue(themeManager.config.enableAnimations)
    }
    
    func testSetAnimationsEnabled() {
        themeManager.setAnimationsEnabled(false)
        XCTAssertFalse(themeManager.config.enableAnimations)
    }
    
    func testDefaultTransparencyEnabled() {
        XCTAssertTrue(themeManager.config.enableTransparency)
    }
    
    func testSetTransparencyEnabled() {
        themeManager.setTransparencyEnabled(false)
        XCTAssertFalse(themeManager.config.enableTransparency)
    }
    
    // MARK: - Theme Export/Import Tests
    
    func testExportThemeJSON() {
        let theme = AppTheme.purple
        let data = themeManager.exportTheme(theme, format: .json, author: "Test Author", description: "Test theme")
        
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }
    
    func testExportThemePlist() {
        let theme = AppTheme.green
        let data = themeManager.exportTheme(theme, format: .plist)
        
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }
    
    func testImportThemeJSON() {
        let originalTheme = AppTheme(name: "Export Test")
        let exportedData = themeManager.exportTheme(originalTheme, format: .json)!
        
        let importedTheme = themeManager.importTheme(from: exportedData, format: .json)
        
        XCTAssertNotNil(importedTheme)
        XCTAssertEqual(importedTheme?.name, "Export Test")
        XCTAssertEqual(themeManager.getCustomThemes().count, 1)
    }
    
    // MARK: - Persistence Tests
    
    func testConfigPersistence() {
        themeManager.setAppearanceMode(.dark)
        themeManager.setWindowLayoutStyle(.compact)
        
        // Simulate app restart by creating new instance
        let newManager = ThemeManager.shared
        
        XCTAssertEqual(newManager.getAppearanceMode(), .dark)
        XCTAssertEqual(newManager.config.uiLayout.windowLayoutStyle, .compact)
    }
    
    func testResetToDefaults() {
        // Make several changes
        themeManager.setTheme(AppTheme.purple)
        themeManager.setAppearanceMode(.dark)
        themeManager.setWindowLayoutStyle(.minimal)
        themeManager.addCustomTheme(AppTheme(name: "Custom"))
        
        // Reset
        themeManager.resetToDefaults()
        
        // Verify reset
        XCTAssertEqual(themeManager.getCurrentTheme().name, "Default")
        XCTAssertEqual(themeManager.getAppearanceMode(), .system)
        XCTAssertEqual(themeManager.config.uiLayout.windowLayoutStyle, .standard)
        XCTAssertEqual(themeManager.getCustomThemes().count, 0)
    }
    
    // MARK: - Model Tests
    
    func testAppearanceModeColorScheme() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }
    
    func testCodableColor() {
        let color = CodableColor(red: 0.5, green: 0.3, blue: 0.8, opacity: 1.0)
        XCTAssertEqual(color.red, 0.5)
        XCTAssertEqual(color.green, 0.3)
        XCTAssertEqual(color.blue, 0.8)
        XCTAssertEqual(color.opacity, 1.0)
    }
    
    func testWindowLayoutStyleDescription() {
        XCTAssertFalse(WindowLayoutStyle.standard.description.isEmpty)
        XCTAssertFalse(WindowLayoutStyle.compact.description.isEmpty)
        XCTAssertFalse(WindowLayoutStyle.detailed.description.isEmpty)
        XCTAssertFalse(WindowLayoutStyle.minimal.description.isEmpty)
    }
    
    func testDownloadListColumnDefaults() {
        let columns = DownloadListColumn.defaultColumns
        XCTAssertEqual(columns.count, 9)
        XCTAssertTrue(columns.first?.isVisible ?? false)
    }
    
    func testToolbarItemDefaults() {
        let items = ToolbarItem.defaultItems
        XCTAssertGreaterThan(items.count, 0)
        XCTAssertNotNil(items.first { $0.key == .addURL })
    }
    
    func testFontSizeValues() {
        XCTAssertEqual(UILayoutConfig.FontSize.small.size, 11)
        XCTAssertEqual(UILayoutConfig.FontSize.medium.size, 13)
        XCTAssertEqual(UILayoutConfig.FontSize.large.size, 15)
        XCTAssertEqual(UILayoutConfig.FontSize.extraLarge.size, 17)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteThemeCustomization() {
        // Create custom theme
        let customTheme = AppTheme(
            name: "Integration Test Theme",
            accentColor: CodableColor(red: 0.2, green: 0.5, blue: 0.9, opacity: 1.0)
        )
        themeManager.addCustomTheme(customTheme)
        
        // Set appearance mode
        themeManager.setAppearanceMode(.dark)
        
        // Configure UI layout
        themeManager.setWindowLayoutStyle(.detailed)
        themeManager.setSidebarVisibility(.visible)
        
        // Configure menu bar
        themeManager.toggleMenuBarExtra(true)
        
        // Verify all settings
        XCTAssertEqual(themeManager.getCustomThemes().count, 1)
        XCTAssertEqual(themeManager.getAppearanceMode(), .dark)
        XCTAssertEqual(themeManager.config.uiLayout.windowLayoutStyle, .detailed)
        XCTAssertTrue(themeManager.config.menuBarConfig.isEnabled)
    }
}
