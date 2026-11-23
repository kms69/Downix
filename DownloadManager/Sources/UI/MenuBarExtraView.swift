import SwiftUI

/// Menu Bar Extra view for quick access
struct MenuBarExtraView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("Downix Download Manager")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label("\(activeDownloadsCount)", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label(formatSpeed(totalSpeed), systemImage: "speedometer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            
            Divider()
            
            // Quick actions
            VStack(spacing: 0) {
                Button {
                    NotificationCenter.default.post(name: .showMainWindow, object: nil)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .showAddDownload, object: nil)
                    }
                } label: {
                    Label("Add Download", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                Divider()
                
                if activeDownloadsCount > 0 {
                    Button {
                        Task { @MainActor in
                            await downloadManager.pauseAll()
                        }
                    } label: {
                        Label("Pause All", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                } else {
                    Button {
                        Task { @MainActor in
                            await downloadManager.resumeAll()
                        }
                    } label: {
                        Label("Resume All", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                
                Divider()
                
                Button {
                    NotificationCenter.default.post(name: .showMainWindow, object: nil)
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Show Main Window", systemImage: "macwindow")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                        }
                    }
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Button {
                    UpdateAlert.run()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                Divider()
                
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 250)
    }
    
    private var activeDownloadsCount: Int {
        downloadManager.downloadTasks.filter { $0.status == .downloading }.count
    }
    
    private var totalSpeed: Double {
        downloadManager.downloadTasks
            .filter { $0.status == .downloading }
            .reduce(0.0) { $0 + Double($1.speed) }
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}
