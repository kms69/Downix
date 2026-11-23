import SwiftUI

/// Main view for torrent management
struct TorrentView: View {
    @StateObject private var manager = TorrentManager.shared
    @State private var selectedTorrent: Torrent?
    @State private var showingAddTorrent = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var filterState: TorrentState? = nil
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let selected = selectedTorrent {
                torrentDetail(selected)
            } else {
                emptyState
            }
        }
        .navigationTitle("Torrents")
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingAddTorrent) {
            AddTorrentView()
        }
        .sheet(isPresented: $showingSettings) {
            TorrentSettingsView()
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search torrents...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: filterState == nil) {
                        filterState = nil
                    }
                    FilterChip(title: "Downloading", isSelected: filterState == .downloading) {
                        filterState = .downloading
                    }
                    FilterChip(title: "Seeding", isSelected: filterState == .seeding) {
                        filterState = .seeding
                    }
                    FilterChip(title: "Completed", isSelected: filterState == .completed) {
                        filterState = .completed
                    }
                    FilterChip(title: "Paused", isSelected: filterState == .paused) {
                        filterState = .paused
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            
            Divider()
            
            // Torrent list
            List(filteredTorrents, selection: $selectedTorrent) { torrent in
                TorrentListItem(torrent: torrent)
                    .tag(torrent)
                    .contextMenu {
                       torrentContextMenu(torrent)
                    }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            // Bottom stats
            statsBar
        }
    }
    
    // MARK: - Detail View
    
    private func torrentDetail(_ torrent: Torrent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: torrent.state.icon)
                            .font(.largeTitle)
                            .foregroundColor(color(for: torrent.state.color))
                        
                        VStack(alignment: .leading) {
                            Text(torrent.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(torrent.state.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            if torrent.state == .downloading || torrent.state == .seeding {
                                Button(action: { Task { @MainActor in manager.pauseTorrent(torrent.id) }}) {
                                    Image(systemName: "pause.fill")
                                }
                            } else if torrent.state == .paused {
                                Button(action: { Task { @MainActor in manager.resumeTorrent(torrent.id) }}) {
                                    Image(systemName: "play.fill")
                                }
                            } else {
                                Button(action: { Task { @MainActor in manager.startTorrent(torrent.id) }}) {
                                    Image(systemName: "play.fill")
                                }
                            }
                            
                            Button(action: { Task { @MainActor in manager.stopTorrent(torrent.id) }}) {
                                Image(systemName: "stop.fill")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    // Progress bar
                    ProgressView(value: torrent.progress)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text("\(Int(torrent.progress * 100))%")
                            .font(.caption)
                        Spacer()
                        Text(torrent.formattedDownloaded + " / " + torrent.formattedSize)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
                
                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    TorrentStatCard(title: "Download Speed", value: torrent.formattedSpeed, icon: "arrow.down.circle.fill", color: .green)
                    TorrentStatCard(title: "Upload Speed", value: torrent.formattedUploadSpeed, icon: "arrow.up.circle.fill", color: .blue)
                    TorrentStatCard(title: "ETA", value: torrent.formattedETA, icon: "clock.fill", color: .orange)
                    TorrentStatCard(title: "Ratio", value: torrent.formattedRatio, icon: "arrow.triangle.2.circlepath", color: .purple)
                    TorrentStatCard(title: "Seeders", value: "\(torrent.seeders)", icon: "person.3.fill", color: .green)
                    TorrentStatCard(title: "Peers", value: "\(torrent.peers.count)", icon: "network", color: .blue)
                }
                
                // Tabs
                TabView {
                    // Files tab
                    filesTab(torrent)
                        .tabItem {
                            Label("Files", systemImage: "doc.fill")
                        }
                    
                    // Peers tab
                    peersTab(torrent)
                        .tabItem {
                            Label("Peers", systemImage: "person.3.fill")
                        }
                    
                    // Trackers tab
                    trackersTab(torrent)
                        .tabItem {
                            Label("Trackers", systemImage: "server.rack")
                        }
                    
                    // Info tab
                    infoTab(torrent)
                        .tabItem {
                            Label("Info", systemImage: "info.circle")
                        }
                }
                .frame(height: 400)
            }
            .padding()
        }
    }
    
    // MARK: - Tabs
    
    private func filesTab(_ torrent: Torrent) -> some View {
        List(torrent.files) { file in
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(file.path)
                        .font(.body)
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                ProgressView(value: file.progress)
                    .frame(width: 100)
                
                Picker("", selection: .constant(file.priority)) {
                    ForEach([TorrentFile.FilePriority.skip, .low, .normal, .high], id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }
        }
    }
    
    private func peersTab(_ torrent: Torrent) -> some View {
        List(torrent.peers) { peer in
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(peer.ipAddress)
                            .font(.body)
                            .fontWeight(.medium)
                        
                        if peer.isEncrypted {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                    
                    Text(peer.client + (peer.country.map { " • \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    HStack {
                        Image(systemName: "arrow.down")
                            .font(.caption)
                        Text(ByteCountFormatter.string(fromByteCount: peer.downloadSpeed, countStyle: .file) + "/s")
                            .font(.caption)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.up")
                            .font(.caption)
                        Text(ByteCountFormatter.string(fromByteCount: peer.uploadSpeed, countStyle: .file) + "/s")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
                
                ProgressView(value: peer.progress)
                    .frame(width: 60)
            }
        }
    }
    
    private func trackersTab(_ torrent: Torrent) -> some View {
        List(torrent.trackers) { tracker in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: tracker.status.icon)
                        .foregroundColor(color(for: tracker.status))
                    
                    Text(tracker.url)
                        .font(.body)
                    
                    Spacer()
                    
                    Text("Tier \(tracker.tier)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("\(tracker.seeders) seeders", systemImage: "arrow.up.circle")
                    Label("\(tracker.leechers) leechers", systemImage: "arrow.down.circle")
                    
                    if let lastAnnounce = tracker.lastAnnounce {
                        Text("Last: \(lastAnnounce, style: .relative)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
    
    private func infoTab(_ torrent: Torrent) -> some View {
        Form {
            Section("General") {
                TorrentInfoRow(label: "Name", value: torrent.name)
                TorrentInfoRow(label: "Info Hash", value: torrent.infoHash)
                TorrentInfoRow(label: "Save Location", value: torrent.saveLocation.path)
                TorrentInfoRow(label: "Size", value: torrent.formattedSize)
            }
            
            Section("Dates") {
                TorrentInfoRow(label: "Added", value: torrent.dateAdded.formatted())
                if let started = torrent.dateStarted {
                    TorrentInfoRow(label: "Started", value: started.formatted())
                }
                if let completed = torrent.dateCompleted {
                    TorrentInfoRow(label: "Completed", value: completed.formatted())
                }
            }
            
            Section("Transfer") {
                TorrentInfoRow(label: "Downloaded", value: torrent.formattedDownloaded)
                TorrentInfoRow(label: "Uploaded", value: torrent.formattedUploaded)
                TorrentInfoRow(label: "Ratio", value: torrent.formattedRatio)
            }
            
            if let category = torrent.category {
                Section("Organization") {
                    TorrentInfoRow(label: "Category", value: category)
                    if !torrent.tags.isEmpty {
                        TorrentInfoRow(label: "Tags", value: torrent.tags.joined(separator: ", "))
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Torrent Selected")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select a torrent from the list or add a new one")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button(action: { showingAddTorrent = true }) {
                Label("Add Torrent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Helpers
    
    private var filteredTorrents: [Torrent] {
        manager.torrents
            .filter { torrent in
                if let state = filterState, torrent.state != state {
                    return false
                }
                if !searchText.isEmpty && !torrent.name.localizedCaseInsensitiveContains(searchText) {
                    return false
                }
                return true
            }
    }
    
    private var statsBar: some View {
        let stats = manager.getStatistics()
        
        return VStack(spacing: 4) {
            HStack {
                Label("↓ \(ByteCountFormatter.string(fromByteCount: stats.globalDownloadSpeed, countStyle: .file))/s",
                      systemImage: "arrow.down.circle.fill")
                    .foregroundColor(.green)
                
                Spacer()
                
                Label("↑ \(ByteCountFormatter.string(fromByteCount: stats.globalUploadSpeed, countStyle: .file))/s",
                      systemImage: "arrow.up.circle.fill")
                    .foregroundColor(.blue)
            }
            .font(.caption)
            
            Text("\(stats.activeTorrents) active • \(stats.totalTorrents) total")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }
    
    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddTorrent = true }) {
                    Label("Add Torrent", systemImage: "plus")
                }
            }
            
            ToolbarItem {
                Button(action: { showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }
    
    private func torrentContextMenu(_ torrent: Torrent) -> some View {
        Group {
            if torrent.state == .downloading || torrent.state == .seeding {
                Button("Pause", action: { Task { @MainActor in manager.pauseTorrent(torrent.id) }})
            } else if torrent.state == .paused {
                Button("Resume", action: { Task { @MainActor in manager.resumeTorrent(torrent.id) }})
            } else {
                Button("Start", action: { Task { @MainActor in manager.startTorrent(torrent.id) }})
            }
            
            Button("Stop", action: { Task { @MainActor in manager.stopTorrent(torrent.id) }})
            
            Divider()
            
            Button("Verify Data", action: { Task { try? await manager.verifyTorrent(torrent.id) }})
            Button("Reannounce", action: { Task { await manager.reannounce(torrent.id) }})
            
            Divider()
            
            Button("Remove", role: .destructive, action: { 
                Task { @MainActor in try? manager.removeTorrent(torrent.id) }
            })
            Button("Remove and Delete Files", role: .destructive, action: { 
                Task { @MainActor in try? manager.removeTorrent(torrent.id, deleteFiles: true) }
            })
        }
    }
    
    private func color(for colorName: String) -> Color {
        switch colorName {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .primary
        }
    }
    
    private func color(for status: TorrentTracker.TrackerStatus) -> Color {
        switch status {
        case .working: return .green
        case .updating: return .blue
        case .notContacted: return .gray
        case .error: return .red
        case .disabled: return .secondary
        }
    }
}

// MARK: - Supporting Views

struct TorrentListItem: View {
    let torrent: Torrent
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: torrent.state.icon)
                .foregroundColor(color(for: torrent.state.color))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(torrent.name)
                    .font(.body)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("\(Int(torrent.progress * 100))%")
                        .font(.caption)
                    
                    if torrent.state == .downloading || torrent.state == .seeding {
                        Text("↓ \(torrent.formattedSpeed)")
                            .font(.caption)
                        Text("↑ \(torrent.formattedUploadSpeed)")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: torrent.health.icon)
                .foregroundColor(color(for: torrent.health.color))
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
    
    private func color(for colorName: String) -> Color {
        switch colorName {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .primary
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct TorrentStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct TorrentInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Add Torrent View

struct AddTorrentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = TorrentManager.shared
    
    @State private var method: AddMethod = .magnetLink
    @State private var magnetLink = ""
    @State private var selectedFile: URL?
    @State private var saveLocation: URL?
    @State private var errorMessage: String?
    
    enum AddMethod {
        case magnetLink
        case torrentFile
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Method", selection: $method) {
                        Text("Magnet Link").tag(AddMethod.magnetLink)
                        Text("Torrent File").tag(AddMethod.torrentFile)
                    }
                    .pickerStyle(.segmented)
                }
                
                if method == .magnetLink {
                    Section("Magnet Link") {
                        TextEditor(text: $magnetLink)
                            .frame(height: 80)
                            .font(.system(.body, design: .monospaced))
                    }
                } else {
                    Section("Torrent File") {
                        Button("Select File...") {
                            // File picker would go here
                        }
                        
                        if let file = selectedFile {
                            Text(file.lastPathComponent)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Save Location") {
                    Button("Choose Folder...") {
                        // Folder picker would go here
                    }
                    
                    if let location = saveLocation {
                        Text(location.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Torrent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTorrent()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }
    
    private var canAdd: Bool {
        method == .magnetLink ? !magnetLink.isEmpty : selectedFile != nil
    }
    
    private func addTorrent() {
        do {
            if method == .magnetLink {
                _ = try manager.addTorrent(magnetLink: magnetLink, saveLocation: saveLocation)
            } else if let file = selectedFile {
                _ = try manager.addTorrent(filePath: file, saveLocation: saveLocation)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Settings View

struct TorrentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = TorrentManager.shared
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Connections") {
                    Stepper("Max Connections: \(manager.maxConnections)", value: $manager.maxConnections, in: 10...1000, step: 10)
                    Stepper("Per Torrent: \(manager.maxConnectionsPerTorrent)", value: $manager.maxConnectionsPerTorrent, in: 5...200, step: 5)
                }
                
                Section("Protocol") {
                    Toggle("Enable DHT", isOn: $manager.protocolSettings.dhtEnabled)
                    Toggle("Enable PEX", isOn: $manager.protocolSettings.pexEnabled)
                    Toggle("Enable LSD", isOn: $manager.protocolSettings.lsdEnabled)
                    Toggle("Enable μTP", isOn: $manager.protocolSettings.utpEnabled)
                    
                    Picker("Encryption", selection: $manager.protocolSettings.encryptionPolicy) {
                        Text("Disabled").tag(TorrentProtocol.EncryptionPolicy.disabled)
                        Text("Enabled").tag(TorrentProtocol.EncryptionPolicy.enabled)
                        Text("Required").tag(TorrentProtocol.EncryptionPolicy.required)
                    }
                }
                
                Section("Speed Limits") {
                    Toggle("Download Limit", isOn: .constant(manager.globalDownloadLimit != nil))
                    if manager.globalDownloadLimit != nil {
                        Text("TODO: Speed slider")
                    }
                    
                    Toggle("Upload Limit", isOn: .constant(manager.globalUploadLimit != nil))
                    if manager.globalUploadLimit != nil {
                        Text("TODO: Speed slider")
                    }
                }
            }
            .navigationTitle("Torrent Settings")
            .toolbar(content: {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            })
        }
    }
}

