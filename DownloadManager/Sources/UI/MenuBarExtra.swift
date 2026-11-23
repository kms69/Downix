import SwiftUI
import AppKit

/// Menu Bar Extra component for quick access to download manager
@MainActor
public struct DownloadManagerMenuBarExtra: View {
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showingMainWindow = false
    
    public init() {}
    
    public var body: some View {
        if themeManager.config.menuBarConfig.isEnabled {
            MenuBarExtraContent()
        }
    }
}

/// Content view for menu bar extra
private struct MenuBarExtraContent: View {
    @StateObject private var themeManager = ThemeManager.shared
    @State private var activeDownloads = 0
    @State private var globalSpeed: Double = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header section
            headerView
            
            Divider()
            
            // Active downloads section (if any)
            if activeDownloads > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<min(activeDownloads, 5), id: \.self) { index in
                            activeDownloadRow(index: index)
                        }
                        
                        if activeDownloads > 5 {
                            Text("+ \(activeDownloads - 5) more downloads")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
                
                Divider()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No active downloads")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                
                Divider()
            }
            
            // Quick actions
            quickActionsView
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 300)
        .onAppear {
            startUpdating()
        }
        .onDisappear {
            stopUpdating()
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Downix Download Manager", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                Spacer()
            }
            
            if themeManager.config.menuBarConfig.showDownloadSpeed && globalSpeed > 0 {
                HStack {
                    Image(systemName: "speedometer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSpeed(globalSpeed))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            if themeManager.config.menuBarConfig.showActiveCount {
                HStack {
                    Image(systemName: "number.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(activeDownloads) active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(12)
    }
    
    private func activeDownloadRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc")
                    .foregroundColor(themeManager.effectiveTheme.accentColor.color)
                Text("Sample File \(index + 1).zip")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
            }
            
            ProgressView(value: Double.random(in: 0.1...0.9))
                .tint(themeManager.effectiveTheme.progressBarColor.color)
            
            HStack {
                Text("\(Int.random(in: 10...95))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatSpeed(Double.random(in: 100000...5000000)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }
    
    private var quickActionsView: some View {
        VStack(spacing: 0) {
            Button(action: {
                // Add URL action
            }) {
                Label("Add URL", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .hoverEffect()
            
            Button(action: {
                // Pause all action
            }) {
                Label("Pause All", systemImage: "pause.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .hoverEffect()
            
            Button(action: {
                // Resume all action
            }) {
                Label("Resume All", systemImage: "play.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .hoverEffect()
            
            Button(action: {
                // Show main window action
                NSApplication.shared.activate(ignoringOtherApps: true)
            }) {
                Label("Show Main Window", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .hoverEffect()
        }
        .padding(.vertical, 4)
    }
    
    private var footerView: some View {
        HStack {
            Button("Settings") {
                // Open settings
            }
            .buttonStyle(.plain)
            .font(.caption)
            
            Spacer()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(12)
    }
    
    private func startUpdating() {
        timer = Timer.scheduledTimer(withTimeInterval: themeManager.config.menuBarConfig.updateInterval, repeats: true) { _ in
            // Simulate data updates (in real app, get from DownloadManager)
            activeDownloads = Int.random(in: 0...10)
            globalSpeed = Double.random(in: 0...10000000)
        }
        timer?.fire()
    }
    
    private func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}

/// AppKit-based menu bar status item
public class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<MenuBarStatusView>?
    private let themeManager = ThemeManager.shared
    
    public static let shared = MenuBarController()
    
    private override init() {
        super.init()
    }
    
    @MainActor
    public func setup() {
        guard themeManager.config.menuBarConfig.isEnabled else {
            teardown()
            return
        }
        
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        
        let view = MenuBarStatusView()
        hostingView = NSHostingView(rootView: view)
        hostingView?.frame = NSRect(x: 0, y: 0, width: 80, height: 22)
        
        if let button = statusItem?.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            if let hostingView = hostingView {
                button.addSubview(hostingView)
            }
        }
        
        // Set up menu
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }
    
    public func teardown() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        hostingView = nil
    }
    
    public func update(activeDownloads: Int, globalSpeed: Double) {
        // Update the status view with new data
        if let hostingView = hostingView {
            hostingView.rootView = MenuBarStatusView(activeDownloads: activeDownloads, globalSpeed: globalSpeed)
        }
    }
}

extension MenuBarController: NSMenuDelegate {
    public func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        
        // Build menu dynamically
        let mainView = DownloadManagerMenuBarExtra()
        let hostingView = NSHostingView(rootView: mainView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        
        let menuItem = NSMenuItem()
        menuItem.view = hostingView
        menu.addItem(menuItem)
    }
}

/// Status view for menu bar button
private struct MenuBarStatusView: View {
    @StateObject private var themeManager = ThemeManager.shared
    var activeDownloads: Int = 0
    var globalSpeed: Double = 0
    
    var body: some View {
        HStack(spacing: 4) {
            if themeManager.config.menuBarConfig.showIcon {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
            }
            
            if themeManager.config.menuBarConfig.showActiveCount && activeDownloads > 0 {
                Text("\(activeDownloads)")
                    .font(.system(size: 11, weight: .medium))
            }
            
            if themeManager.config.menuBarConfig.showDownloadSpeed && globalSpeed > 0 {
                Text(formatSpeed(globalSpeed))
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }
    
    private var iconName: String {
        switch themeManager.config.menuBarConfig.iconStyle {
        case .standard:
            return activeDownloads > 0 ? "arrow.down.circle.fill" : "arrow.down.circle"
        case .minimal:
            return "arrow.down"
        case .colorful:
            return "arrow.down.circle.fill"
        case .monochrome:
            return "arrow.down.circle"
        }
    }
    
    private var iconColor: Color {
        switch themeManager.config.menuBarConfig.iconStyle {
        case .standard, .minimal, .monochrome:
            return .primary
        case .colorful:
            return activeDownloads > 0 ? themeManager.effectiveTheme.accentColor.color : .primary
        }
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 {
            return String(format: "%.0fB/s", bytesPerSecond)
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1fK/s", bytesPerSecond / 1024)
        } else if bytesPerSecond < 1024 * 1024 * 1024 {
            return String(format: "%.1fM/s", bytesPerSecond / (1024 * 1024))
        } else {
            return String(format: "%.2fG/s", bytesPerSecond / (1024 * 1024 * 1024))
        }
    }
}

// Custom hover effect for menu items
private struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func hoverEffect() -> some View {
        modifier(HoverEffectModifier())
    }
}
