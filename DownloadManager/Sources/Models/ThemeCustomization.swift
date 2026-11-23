import Foundation
import SwiftUI

// MARK: - Theme Models

/// Represents the appearance mode of the application
public enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    public var id: String { rawValue }
    
    /// Display name for UI
    public var displayName: String {
        return rawValue
    }
    
    /// Icon for the appearance mode
    public var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    
    /// Returns the appropriate ColorScheme
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Represents a custom theme configuration
public struct AppTheme: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var isBuiltIn: Bool
    public var accentColor: CodableColor
    public var secondaryAccentColor: CodableColor
    public var backgroundColor: CodableColor
    public var secondaryBackgroundColor: CodableColor
    public var textColor: CodableColor
    public var secondaryTextColor: CodableColor
    public var successColor: CodableColor
    public var warningColor: CodableColor
    public var errorColor: CodableColor
    public var infoColor: CodableColor
    public var progressBarColor: CodableColor
    public var borderColor: CodableColor
    public var createdAt: Date
    public var modifiedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        isBuiltIn: Bool = false,
        accentColor: CodableColor = CodableColor(.blue),
        secondaryAccentColor: CodableColor = CodableColor(.teal),
        backgroundColor: CodableColor = CodableColor(.white),
        secondaryBackgroundColor: CodableColor = CodableColor(.gray.opacity(0.1)),
        textColor: CodableColor = CodableColor(.primary),
        secondaryTextColor: CodableColor = CodableColor(.secondary),
        successColor: CodableColor = CodableColor(.green),
        warningColor: CodableColor = CodableColor(.orange),
        errorColor: CodableColor = CodableColor(.red),
        infoColor: CodableColor = CodableColor(.blue),
        progressBarColor: CodableColor = CodableColor(.blue),
        borderColor: CodableColor = CodableColor(.gray.opacity(0.3)),
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.accentColor = accentColor
        self.secondaryAccentColor = secondaryAccentColor
        self.backgroundColor = backgroundColor
        self.secondaryBackgroundColor = secondaryBackgroundColor
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.successColor = successColor
        self.warningColor = warningColor
        self.errorColor = errorColor
        self.infoColor = infoColor
        self.progressBarColor = progressBarColor
        self.borderColor = borderColor
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
    
    /// Built-in default theme
    public static var `default`: AppTheme {
        AppTheme(name: "Default", isBuiltIn: true,
                 accentColor: CodableColor(Color(hexString: "#10b981")),
                 secondaryAccentColor: CodableColor(Color(hexString: "#2dd4bf")),
                 progressBarColor: CodableColor(Color(hexString: "#10b981")))
    }
    
    /// Built-in blue theme
    public static var blue: AppTheme {
        AppTheme(
            name: "Blue",
            isBuiltIn: true,
            accentColor: CodableColor(.blue),
            secondaryAccentColor: CodableColor(.cyan),
            progressBarColor: CodableColor(.blue)
        )
    }
    
    /// Built-in purple theme
    public static var purple: AppTheme {
        AppTheme(
            name: "Purple",
            isBuiltIn: true,
            accentColor: CodableColor(.purple),
            secondaryAccentColor: CodableColor(.pink),
            progressBarColor: CodableColor(.purple)
        )
    }
    
    /// Built-in green theme
    public static var green: AppTheme {
        AppTheme(
            name: "Green",
            isBuiltIn: true,
            accentColor: CodableColor(.green),
            secondaryAccentColor: CodableColor(.mint),
            progressBarColor: CodableColor(.green)
        )
    }
    
    /// Built-in orange theme
    public static var orange: AppTheme {
        AppTheme(
            name: "Orange",
            isBuiltIn: true,
            accentColor: CodableColor(.orange),
            secondaryAccentColor: CodableColor(.yellow),
            progressBarColor: CodableColor(.orange)
        )
    }
    
    /// All built-in themes
    public static var builtInThemes: [AppTheme] {
        [.default, .blue, .purple, .green, .orange]
    }
}

/// Codable wrapper for SwiftUI Color
public struct CodableColor: Codable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double
    
    public init(_ color: Color) {
        // Convert to RGB components
        // Note: This is a simplified conversion for SwiftUI colors
        let components = color.components
        self.red = components.red
        self.green = components.green
        self.blue = components.blue
        self.opacity = components.opacity
    }
    
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
    
    /// Convert to SwiftUI Color
    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// Extension to extract color components
extension Color {
    var components: (red: Double, green: Double, blue: Double, opacity: Double) {
        #if canImport(UIKit)
        typealias NativeColor = UIColor
        #elseif canImport(AppKit)
        typealias NativeColor = NSColor
        #endif
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        // Convert to device RGB colorspace first to handle catalog/dynamic colors
        let nativeColor = NativeColor(self)
        #if canImport(AppKit)
        let convertedColor = nativeColor.usingColorSpace(.deviceRGB) ?? nativeColor.usingColorSpace(.genericRGB) ?? nativeColor
        convertedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        nativeColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

// MARK: - UI Layout Customization

/// Represents the layout style for the main window
public enum WindowLayoutStyle: String, Codable, CaseIterable, Identifiable {
    case standard = "Standard"
    case compact = "Compact"
    case detailed = "Detailed"
    case minimal = "Minimal"
    
    public var id: String { rawValue }
    
    public var displayName: String { rawValue }
    
    public var description: String {
        switch self {
        case .standard:
            return "Balanced view with sidebar and details"
        case .compact:
            return "Space-efficient, minimized sidebar"
        case .detailed:
            return "Maximum information display"
        case .minimal:
            return "Clean, distraction-free interface"
        }
    }
    
    public var icon: String {
        switch self {
        case .standard: return "rectangle.split.3x1"
        case .compact: return "rectangle.compress.vertical"
        case .detailed: return "rectangle.split.3x3"
        case .minimal: return "rectangle"
        }
    }
}

/// Represents sidebar visibility preference
public enum SidebarVisibility: String, Codable, CaseIterable, Identifiable {
    case visible = "Always Visible"
    case hidden = "Always Hidden"
    case auto = "Auto-hide"
    
    public var id: String { rawValue }
}

/// Represents toolbar style
public enum ToolbarStyle: String, Codable, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case expanded = "Expanded"
    case compact = "Compact"
    case minimal = "Minimal"
    
    public var id: String { rawValue }
}

/// Represents columns to display in download list
public struct DownloadListColumn: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var key: ColumnKey
    public var isVisible: Bool
    public var width: Double
    public var order: Int
    
    public init(
        id: UUID = UUID(),
        name: String,
        key: ColumnKey,
        isVisible: Bool = true,
        width: Double = 150,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.isVisible = isVisible
        self.width = width
        self.order = order
    }
    
    public enum ColumnKey: String, Codable, CaseIterable {
        case filename = "Filename"
        case progress = "Progress"
        case size = "Size"
        case speed = "Speed"
        case timeRemaining = "Time Remaining"
        case status = "Status"
        case dateAdded = "Date Added"
        case category = "Category"
        case source = "Source"
    }
    
    /// Default columns configuration
    public static var defaultColumns: [DownloadListColumn] {
        [
            DownloadListColumn(name: "Filename", key: .filename, width: 300, order: 0),
            DownloadListColumn(name: "Progress", key: .progress, width: 150, order: 1),
            DownloadListColumn(name: "Size", key: .size, width: 100, order: 2),
            DownloadListColumn(name: "Speed", key: .speed, width: 100, order: 3),
            DownloadListColumn(name: "Time", key: .timeRemaining, width: 100, order: 4),
            DownloadListColumn(name: "Status", key: .status, width: 100, order: 5),
            DownloadListColumn(name: "Date Added", key: .dateAdded, isVisible: false, width: 150, order: 6),
            DownloadListColumn(name: "Category", key: .category, isVisible: false, width: 120, order: 7),
            DownloadListColumn(name: "Source", key: .source, isVisible: false, width: 200, order: 8)
        ]
    }
}

/// Represents toolbar items configuration
public struct ToolbarItemConfig: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var key: ItemKey
    public var isVisible: Bool
    public var order: Int
    
    public init(
        id: UUID = UUID(),
        name: String,
        key: ItemKey,
        isVisible: Bool = true,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.isVisible = isVisible
        self.order = order
    }
    
    public enum ItemKey: String, Codable, CaseIterable {
        case addURL = "Add URL"
        case pauseAll = "Pause All"
        case resumeAll = "Resume All"
        case settings = "Settings"
        case search = "Search"
        case scheduler = "Scheduler"
        case history = "History"
        case statistics = "Statistics"
        case clearCompleted = "Clear Completed"
        case importURLs = "Import URLs"
        case exportList = "Export List"
    }
    
    public var icon: String {
        switch key {
        case .addURL: return "plus.circle"
        case .pauseAll: return "pause.circle"
        case .resumeAll: return "play.circle"
        case .settings: return "gear"
        case .search: return "magnifyingglass"
        case .scheduler: return "calendar"
        case .history: return "clock"
        case .statistics: return "chart.bar"
        case .clearCompleted: return "trash"
        case .importURLs: return "square.and.arrow.down"
        case .exportList: return "square.and.arrow.up"
        }
    }
    
    /// Default toolbar items
    public static var defaultItems: [ToolbarItemConfig] {
        [
            ToolbarItemConfig(name: "Add URL", key: .addURL, order: 0),
            ToolbarItemConfig(name: "Pause All", key: .pauseAll, order: 1),
            ToolbarItemConfig(name: "Resume All", key: .resumeAll, order: 2),
            ToolbarItemConfig(name: "Settings", key: .settings, order: 3),
            ToolbarItemConfig(name: "Search", key: .search, order: 4),
            ToolbarItemConfig(name: "Scheduler", key: .scheduler, isVisible: false, order: 5),
            ToolbarItemConfig(name: "History", key: .history, isVisible: false, order: 6),
            ToolbarItemConfig(name: "Statistics", key: .statistics, isVisible: false, order: 7),
            ToolbarItemConfig(name: "Clear Completed", key: .clearCompleted, isVisible: false, order: 8),
            ToolbarItemConfig(name: "Import URLs", key: .importURLs, isVisible: false, order: 9),
            ToolbarItemConfig(name: "Export List", key: .exportList, isVisible: false, order: 10)
        ]
    }
}

/// UI Layout configuration
public struct UILayoutConfig: Codable, Equatable {
    public var windowLayoutStyle: WindowLayoutStyle
    public var sidebarVisibility: SidebarVisibility
    public var toolbarStyle: ToolbarStyle
    public var showStatusBar: Bool
    public var showDownloadSpeed: Bool
    public var showNetworkStatus: Bool
    public var downloadListColumns: [DownloadListColumn]
    public var toolbarItems: [ToolbarItemConfig]
    public var sidebarWidth: Double
    public var fontSize: FontSize
    
    public init(
        windowLayoutStyle: WindowLayoutStyle = .standard,
        sidebarVisibility: SidebarVisibility = .visible,
        toolbarStyle: ToolbarStyle = .automatic,
        showStatusBar: Bool = true,
        showDownloadSpeed: Bool = true,
        showNetworkStatus: Bool = true,
        downloadListColumns: [DownloadListColumn] = DownloadListColumn.defaultColumns,
        toolbarItems: [ToolbarItemConfig] = ToolbarItemConfig.defaultItems,
        sidebarWidth: Double = 200,
        fontSize: FontSize = .medium
    ) {
        self.windowLayoutStyle = windowLayoutStyle
        self.sidebarVisibility = sidebarVisibility
        self.toolbarStyle = toolbarStyle
        self.showStatusBar = showStatusBar
        self.showDownloadSpeed = showDownloadSpeed
        self.showNetworkStatus = showNetworkStatus
        self.downloadListColumns = downloadListColumns
        self.toolbarItems = toolbarItems
        self.sidebarWidth = sidebarWidth
        self.fontSize = fontSize
    }
    
    public enum FontSize: String, Codable, CaseIterable, Identifiable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
        case extraLarge = "Extra Large"
        
        public var id: String { rawValue }
        
        public var size: CGFloat {
            switch self {
            case .small: return 11
            case .medium: return 13
            case .large: return 15
            case .extraLarge: return 17
            }
        }
    }
}

// MARK: - Menu Bar & Status Bar

/// Menu bar extra configuration
public struct MenuBarConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var showIcon: Bool
    public var showDownloadSpeed: Bool
    public var showActiveCount: Bool
    public var iconStyle: IconStyle
    public var updateInterval: TimeInterval
    
    public init(
        isEnabled: Bool = true,
        showIcon: Bool = true,
        showDownloadSpeed: Bool = true,
        showActiveCount: Bool = true,
        iconStyle: IconStyle = .standard,
        updateInterval: TimeInterval = 1.0
    ) {
        self.isEnabled = isEnabled
        self.showIcon = showIcon
        self.showDownloadSpeed = showDownloadSpeed
        self.showActiveCount = showActiveCount
        self.iconStyle = iconStyle
        self.updateInterval = updateInterval
    }
    
    public enum IconStyle: String, Codable, CaseIterable, Identifiable {
        case standard = "Standard"
        case minimal = "Minimal"
        case colorful = "Colorful"
        case monochrome = "Monochrome"
        
        public var id: String { rawValue }
    }
}

/// Status bar widget configuration
public struct StatusBarConfig: Codable, Equatable {
    public var position: Position
    public var showGlobalSpeed: Bool
    public var showActiveDownloads: Bool
    public var showNetworkStatus: Bool
    public var showQuickActions: Bool
    
    public init(
        position: Position = .bottom,
        showGlobalSpeed: Bool = true,
        showActiveDownloads: Bool = true,
        showNetworkStatus: Bool = true,
        showQuickActions: Bool = true
    ) {
        self.position = position
        self.showGlobalSpeed = showGlobalSpeed
        self.showActiveDownloads = showActiveDownloads
        self.showNetworkStatus = showNetworkStatus
        self.showQuickActions = showQuickActions
    }
    
    public enum Position: String, Codable, CaseIterable, Identifiable {
        case top = "Top"
        case bottom = "Bottom"
        case hidden = "Hidden"
        
        public var id: String { rawValue }
    }
}

// MARK: - Complete Theme Customization Configuration

/// Complete theme and customization settings
public struct ThemeCustomizationConfig: Codable, Equatable {
    public var appearanceMode: AppearanceMode
    public var currentTheme: AppTheme
    public var customThemes: [AppTheme]
    public var uiLayout: UILayoutConfig
    public var menuBarConfig: MenuBarConfig
    public var statusBarConfig: StatusBarConfig
    public var autoSwitchTheme: Bool
    public var lightModeThemeID: UUID?
    public var darkModeThemeID: UUID?
    public var enableAnimations: Bool
    public var enableTransparency: Bool
    public var lastModified: Date
    
    public init(
        appearanceMode: AppearanceMode = .system,
        currentTheme: AppTheme = .default,
        customThemes: [AppTheme] = [],
        uiLayout: UILayoutConfig = UILayoutConfig(),
        menuBarConfig: MenuBarConfig = MenuBarConfig(),
        statusBarConfig: StatusBarConfig = StatusBarConfig(),
        autoSwitchTheme: Bool = false,
        lightModeThemeID: UUID? = nil,
        darkModeThemeID: UUID? = nil,
        enableAnimations: Bool = true,
        enableTransparency: Bool = true,
        lastModified: Date = Date()
    ) {
        self.appearanceMode = appearanceMode
        self.currentTheme = currentTheme
        self.customThemes = customThemes
        self.uiLayout = uiLayout
        self.menuBarConfig = menuBarConfig
        self.statusBarConfig = statusBarConfig
        self.autoSwitchTheme = autoSwitchTheme
        self.lightModeThemeID = lightModeThemeID
        self.darkModeThemeID = darkModeThemeID
        self.enableAnimations = enableAnimations
        self.enableTransparency = enableTransparency
        self.lastModified = lastModified
    }
    
    /// Default configuration
    public static var `default`: ThemeCustomizationConfig {
        ThemeCustomizationConfig()
    }
}

// MARK: - Theme Export/Import

/// Format for exporting themes
public enum ThemeExportFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case plist = "Property List"
    
    public var id: String { rawValue }
    
    public var fileExtension: String {
        switch self {
        case .json: return "json"
        case .plist: return "plist"
        }
    }
}

/// Represents an exported theme package
public struct ThemePackage: Codable {
    public var theme: AppTheme
    public var version: String
    public var exportDate: Date
    public var author: String?
    public var description: String?
    
    public init(
        theme: AppTheme,
        version: String = "1.0",
        exportDate: Date = Date(),
        author: String? = nil,
        description: String? = nil
    ) {
        self.theme = theme
        self.version = version
        self.exportDate = exportDate
        self.author = author
        self.description = description
    }
}

/// The accent colours the Downix windows actually draw with (read by IdmStyle).
/// "Default" is the Downix emerald; any other theme supplies its own accent.
public enum DownixAccent {
    public static var isDefault = true
    public static var primary = Color(hexString: "#10b981")
    public static var secondary = Color(hexString: "#2dd4bf")

    public static func apply(_ theme: AppTheme) {
        if theme.name == "Default" {
            isDefault = true
            primary = Color(hexString: "#10b981")
            secondary = Color(hexString: "#2dd4bf")
        } else {
            isDefault = false
            primary = theme.accentColor.color
            secondary = theme.secondaryAccentColor.color
        }
    }
}
