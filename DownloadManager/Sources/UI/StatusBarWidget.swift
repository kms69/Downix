import SwiftUI

/// Status bar widget component for bottom of main window
/// Displays active downloads, global speed, network status, and quick actions
public struct StatusBarWidget: View {
    @StateObject private var themeManager = ThemeManager.shared
    @State private var activeDownloads = 0
    @State private var completedDownloads = 0
    @State private var failedDownloads = 0
    @State private var globalSpeed: Double = 0
    @State private var networkStatus: NetworkStatus = .connected
    @State private var timer: Timer?
    
    public init() {}
    
    public var body: some View {
        if themeManager.config.statusBarConfig.position != .hidden {
            statusBarContent
                .frame(height: 28)
                .background(statusBarBackground)
                .onAppear {
                    startUpdating()
                }
                .onDisappear {
                    stopUpdating()
                }
        }
    }
    
    private var statusBarContent: some View {
        HStack(spacing: 16) {
            // Active downloads indicator
            if themeManager.config.statusBarConfig.showActiveDownloads {
                activeDownloadsView
            }
            
            Divider()
                .frame(height: 16)
            
            // Global download speed
            if themeManager.config.statusBarConfig.showGlobalSpeed {
                globalSpeedView
            }
            
            Divider()
                .frame(height: 16)
            
            // Network status
            if themeManager.config.statusBarConfig.showNetworkStatus {
                networkStatusView
            }
            
            Spacer()
            
            // Quick actions
            if themeManager.config.statusBarConfig.showQuickActions {
                quickActionsView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    private var statusBarBackground: some View {
        Group {
            if themeManager.config.enableTransparency {
                Color.gray.opacity(0.05)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }
    
    // MARK: - Active Downloads View
    
    private var activeDownloadsView: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(activeDownloads > 0 ? 
                    themeManager.effectiveTheme.accentColor.color : 
                    .secondary)
                .imageScale(.medium)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(activeDownloads) Active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text("\(completedDownloads) done")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    if failedDownloads > 0 {
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        
                        Text("\(failedDownloads) failed")
                            .font(.system(size: 9))
                            .foregroundColor(themeManager.effectiveTheme.errorColor.color)
                    }
                }
            }
        }
        .help("Active downloads: \(activeDownloads)")
    }
    
    // MARK: - Global Speed View
    
    private var globalSpeedView: some View {
        HStack(spacing: 8) {
            Image(systemName: "speedometer")
                .foregroundColor(.secondary)
                .imageScale(.medium)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(formatSpeed(globalSpeed))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                
                Text("Download Speed")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            // Mini speed graph
            if globalSpeed > 0 {
                SpeedGraphView()
                    .frame(width: 40, height: 20)
            }
        }
        .help("Global download speed: \(formatSpeed(globalSpeed))")
    }
    
    // MARK: - Network Status View
    
    private var networkStatusView: some View {
        HStack(spacing: 6) {
            Image(systemName: networkStatus.icon)
                .foregroundColor(networkStatus.color)
                .imageScale(.medium)
            
            Text(networkStatus.displayName)
                .font(.system(size: 11))
                .foregroundColor(.primary)
        }
        .help("Network: \(networkStatus.displayName)")
    }
    
    // MARK: - Quick Actions View
    
    private var quickActionsView: some View {
        HStack(spacing: 8) {
            Button(action: {
                // Pause all action
            }) {
                Image(systemName: "pause.circle")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Pause all downloads")
            
            Button(action: {
                // Resume all action
            }) {
                Image(systemName: "play.circle")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Resume all downloads")
            
            Button(action: {
                // Clear completed action
            }) {
                Image(systemName: "trash")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Clear completed downloads")
            
            Menu {
                Button("Open Downloads Folder") {}
                Button("View History") {}
                Button("Show Statistics") {}
                Divider()
                Button("Settings") {}
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
            }
            .menuStyle(.borderlessButton)
            .help("More actions")
        }
    }
    
    // MARK: - Helper Methods
    
    private func startUpdating() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Simulate data updates (in real app, get from DownloadManager)
            activeDownloads = Int.random(in: 0...5)
            completedDownloads = Int.random(in: 10...50)
            failedDownloads = Int.random(in: 0...3)
            globalSpeed = Double.random(in: 0...10000000)
            networkStatus = NetworkStatus.allCases.randomElement() ?? .connected
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
        formatter.zeroPadsFractionDigits = false
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}

// MARK: - Network Status Enum

private enum NetworkStatus: String, CaseIterable {
    case connected = "Connected"
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case cellular = "Cellular"
    case vpn = "VPN"
    case offline = "Offline"
    
    var icon: String {
        switch self {
        case .connected: return "wifi"
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .vpn: return "lock.shield"
        case .offline: return "wifi.slash"
        }
    }
    
    var color: Color {
        switch self {
        case .connected, .wifi, .ethernet, .cellular: return .green
        case .vpn: return .blue
        case .offline: return .red
        }
    }
    
    var displayName: String {
        return rawValue
    }
}

// MARK: - Speed Graph View

private struct SpeedGraphView: View {
    @State private var dataPoints: [Double] = Array(repeating: 0, count: 20)
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !dataPoints.isEmpty else { return }
                
                let width = geometry.size.width
                let height = geometry.size.height
                let pointWidth = width / CGFloat(dataPoints.count - 1)
                
                // Normalize data points
                let maxValue = dataPoints.max() ?? 1
                let normalizedPoints = dataPoints.map { $0 / maxValue }
                
                // Start path
                path.move(to: CGPoint(x: 0, y: height))
                
                // Draw line
                for (index, value) in normalizedPoints.enumerated() {
                    let x = CGFloat(index) * pointWidth
                    let y = height - (CGFloat(value) * height)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                // Close path
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.5),
                        Color.blue.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Path { path in
                guard !dataPoints.isEmpty else { return }
                
                let width = geometry.size.width
                let height = geometry.size.height
                let pointWidth = width / CGFloat(dataPoints.count - 1)
                
                let maxValue = dataPoints.max() ?? 1
                let normalizedPoints = dataPoints.map { $0 / maxValue }
                
                path.move(to: CGPoint(x: 0, y: height - (CGFloat(normalizedPoints[0]) * height)))
                
                for (index, value) in normalizedPoints.enumerated() {
                    let x = CGFloat(index) * pointWidth
                    let y = height - (CGFloat(value) * height)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.blue, lineWidth: 1.5)
        }
        .onAppear {
            startSimulation()
        }
        .onDisappear {
            stopSimulation()
        }
    }
    
    private func startSimulation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            dataPoints.removeFirst()
            dataPoints.append(Double.random(in: 0...1))
        }
    }
    
    private func stopSimulation() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Compact Status Bar (Alternative Layout)

/// Compact version of status bar for minimal layout style
public struct CompactStatusBarWidget: View {
    @StateObject private var themeManager = ThemeManager.shared
    @State private var activeDownloads = 0
    @State private var globalSpeed: Double = 0
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 12) {
            // Download indicator
            Label("\(activeDownloads)", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(activeDownloads > 0 ? 
                    themeManager.effectiveTheme.accentColor.color : 
                    .secondary)
            
            Divider()
                .frame(height: 12)
            
            // Speed indicator
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(formatSpeed(globalSpeed))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 24)
        .background(Color.gray.opacity(0.05))
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}

// MARK: - Status Bar Position

extension View {
    /// Applies status bar to a view based on configuration
    @ViewBuilder
    public func statusBar(_ statusBar: some View) -> some View {
        let config = ThemeManager.shared.config.statusBarConfig
        
        switch config.position {
        case .top:
            VStack(spacing: 0) {
                statusBar
                Divider()
                self
            }
        case .bottom:
            VStack(spacing: 0) {
                self
                Divider()
                statusBar
            }
        case .hidden:
            self
        }
    }
}