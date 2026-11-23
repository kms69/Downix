import Foundation
import Combine
import CryptoKit

/// Manager for torrent downloads and seeding
@MainActor
public class TorrentManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = TorrentManager()
    
    // MARK: - Published Properties
    
    @Published public var torrents: [Torrent] = []
    @Published public var protocolSettings: TorrentProtocol
    @Published public var globalDownloadLimit: Int64?  // bytes per second
    @Published public var globalUploadLimit: Int64?
    @Published public var maxConnections: Int
    @Published public var maxConnectionsPerTorrent: Int
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    private let saveURL: URL
    
    // MARK: - Initialization
    
    private init() {
        self.protocolSettings = TorrentProtocol()
        self.maxConnections = 200
        self.maxConnectionsPerTorrent = 50
        
        // Setup save location
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.saveURL = documentsPath.appendingPathComponent("Torrents.json")
        
        loadTorrents()
        startUpdateTimer()
    }
    
    // MARK: - Public Methods
    
    /// Add torrent from magnet link
    public func addTorrent(magnetLink: String, saveLocation: URL? = nil) throws -> Torrent {
        // Parse magnet link
        guard let components = parseMagnetLink(magnetLink) else {
            throw TorrentError.invalidMagnetLink
        }
        
        let saveDir = saveLocation ?? defaultSaveLocation()
        
        let torrent = Torrent(
            name: components.name ?? "Unknown Torrent",
            infoHash: components.infoHash,
            magnetLink: magnetLink,
            totalSize: 0,  // Will be updated after metadata download
            trackers: components.trackers.map { TorrentTracker(url: $0) },
            saveLocation: saveDir
        )
        
        torrents.append(torrent)
        saveTorrents()
        
        // Start metadata download
        Task {
            await downloadMetadata(for: torrent.id)
        }
        
        return torrent
    }
    
    /// Add torrent from .torrent file
    public func addTorrent(filePath: URL, saveLocation: URL? = nil) throws -> Torrent {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw TorrentError.torrentNotFound
        }
        
        // Parse .torrent file
        guard let metadata = try? parseTorrentFile(filePath) else {
            throw TorrentError.invalidTorrentFile
        }
        
        let saveDir = saveLocation ?? defaultSaveLocation()
        
        let torrent = Torrent(
            name: metadata.name,
            infoHash: metadata.infoHash,
            torrentFilePath: filePath,
            totalSize: metadata.totalSize,
            trackers: metadata.trackers.map { TorrentTracker(url: $0) },
            files: metadata.files,
            pieces: metadata.pieces,
            saveLocation: saveDir
        )
        
        torrents.append(torrent)
        saveTorrents()
        
        return torrent
    }
    
    /// Start downloading a torrent
    public func startTorrent(_ torrentId: UUID) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        torrents[index].state = .downloading
        torrents[index].dateStarted = Date()
        
        Task {
            await connectToTrackers(torrentId: torrentId)
            await connectToPeers(torrentId: torrentId)
            await downloadPieces(torrentId: torrentId)
        }
        
        saveTorrents()
    }
    
    /// Stop downloading/seeding a torrent
    public func stopTorrent(_ torrentId: UUID) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        torrents[index].state = .stopped
        torrents[index].peers.removeAll()
        
        saveTorrents()
    }
    
    /// Pause a torrent
    public func pauseTorrent(_ torrentId: UUID) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        torrents[index].state = .paused
        saveTorrents()
    }
    
    /// Resume a paused torrent
    public func resumeTorrent(_ torrentId: UUID) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        let previousState = torrents[index].state
        if previousState == .paused {
            torrents[index].state = torrents[index].isComplete ? .seeding : .downloading
            startTorrent(torrentId)
        }
    }
    
    /// Remove a torrent
    public func removeTorrent(_ torrentId: UUID, deleteFiles: Bool = false) throws {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else {
            throw TorrentError.torrentNotFound
        }
        
        let torrent = torrents[index]
        
        // Stop the torrent first
        stopTorrent(torrentId)
        
        // Delete files if requested
        if deleteFiles {
            try? FileManager.default.removeItem(at: torrent.saveLocation)
        }
        
        torrents.remove(at: index)
        saveTorrents()
    }
    
    /// Verify torrent data integrity
    public func verifyTorrent(_ torrentId: UUID) async throws {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else {
            throw TorrentError.torrentNotFound
        }
        
        torrents[index].state = .checking
        
        // Simulate piece verification
        for pieceIndex in torrents[index].pieces.indices {
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 second per piece
            torrents[index].pieces[pieceIndex].isVerified = true
        }
        
        torrents[index].state = .stopped
        saveTorrents()
    }
    
    /// Force reannounce to all trackers
    public func reannounce(_ torrentId: UUID) async {
        guard let torrent = torrents.first(where: { $0.id == torrentId }) else { return }
        
        await connectToTrackers(torrentId: torrentId)
    }
    
    /// Add a tracker to a torrent
    public func addTracker(to torrentId: UUID, url: String, tier: Int = 0) {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        let tracker = TorrentTracker(url: url, tier: tier)
        torrents[index].trackers.append(tracker)
        
        saveTorrents()
    }
    
    /// Remove a tracker from a torrent
    public func removeTracker(from torrentId: UUID, trackerId: UUID) {
        guard let torrentIndex = torrents.firstIndex(where: { $0.id == torrentId }),
              let trackerIndex = torrents[torrentIndex].trackers.firstIndex(where: { $0.id == trackerId }) else {
            return
        }
        
        torrents[torrentIndex].trackers.remove(at: trackerIndex)
        saveTorrents()
    }
    
    /// Update file priorities in a torrent
    public func updateFilePriority(torrentId: UUID, fileId: UUID, priority: TorrentFile.FilePriority) {
        guard let torrentIndex = torrents.firstIndex(where: { $0.id == torrentId }),
              let fileIndex = torrents[torrentIndex].files.firstIndex(where: { $0.id == fileId }) else {
            return
        }
        
        torrents[torrentIndex].files[fileIndex].priority = priority
        torrents[torrentIndex].files[fileIndex].isSelected = priority != .skip
        
        saveTorrents()
    }
    
    /// Get statistics for all torrents
    public func getStatistics() -> TorrentStatistics {
        let activeTorrents = torrents.filter { $0.state == .downloading || $0.state == .seeding }
        let seedingTorrents = torrents.filter { $0.state == .seeding }
        let downloadingTorrents = torrents.filter { $0.state == .downloading }
        
        let totalDownloaded = torrents.reduce(0) { $0 + $1.downloadedBytes }
        let totalUploaded = torrents.reduce(0) { $0 + $1.uploadedBytes }
        let globalDownloadSpeed = activeTorrents.reduce(0) { $0 + $1.downloadSpeed }
        let globalUploadSpeed = activeTorrents.reduce(0) { $0 + $1.uploadSpeed }
        
        let globalRatio = totalDownloaded > 0 ? Double(totalUploaded) / Double(totalDownloaded) : 0
        
        return TorrentStatistics(
            totalTorrents: torrents.count,
            activeTorrents: activeTorrents.count,
            seedingTorrents: seedingTorrents.count,
            downloadingTorrents: downloadingTorrents.count,
            totalDownloaded: totalDownloaded,
            totalUploaded: totalUploaded,
            globalDownloadSpeed: globalDownloadSpeed,
            globalUploadSpeed: globalUploadSpeed,
            globalRatio: globalRatio
        )
    }
    
    /// Pause all active torrents
    public func pauseAll() {
        for torrent in torrents where torrent.state == .downloading || torrent.state == .seeding {
            pauseTorrent(torrent.id)
        }
    }
    
    /// Resume all paused torrents
    public func resumeAll() {
        for torrent in torrents where torrent.state == .paused {
            resumeTorrent(torrent.id)
        }
    }
    
    /// Stop all active torrents
    public func stopAll() {
        for torrent in torrents where torrent.state != .stopped {
            stopTorrent(torrent.id)
        }
    }
    
    // MARK: - Private Methods
    
    private func defaultSaveLocation() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Torrents")
    }
    
    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTorrents()
            }
        }
    }
    
    private func updateTorrents() {
        for index in torrents.indices {
            guard torrents[index].state == .downloading || torrents[index].state == .seeding else {
                continue
            }
            
            // Update health based on current peers
            torrents[index].health = TorrentHealth.calculate(
                seeders: torrents[index].seeders,
                leechers: torrents[index].leechers
            )
            
            // Update ratio
            if torrents[index].downloadedBytes > 0 {
                torrents[index].ratio = Double(torrents[index].uploadedBytes) / Double(torrents[index].downloadedBytes)
            }
            
            // Check if download is complete
            if torrents[index].downloadedBytes >= torrents[index].totalSize && !torrents[index].isComplete {
                torrents[index].state = .completed
                torrents[index].dateCompleted = Date()
                
                // Start seeding if enabled
                if torrents[index].seedingConfig.enabled {
                    torrents[index].state = .seeding
                }
            }
            
            // Check seeding limits
            if torrents[index].state == .seeding {
                checkSeedingLimits(torrentIndex: index)
            }
        }
    }
    
    private func checkSeedingLimits(torrentIndex: Int) {
        let torrent = torrents[torrentIndex]
        let config = torrent.seedingConfig
        
        // Check ratio limit
        if let ratioLimit = config.ratioLimit, torrent.ratio >= ratioLimit {
            torrents[torrentIndex].state = .completed
            return
        }
        
        // Check time limit
        if let timeLimit = config.timeLimit,
           let dateCompleted = torrent.dateCompleted {
            let seedingTime = Date().timeIntervalSince(dateCompleted)
            if seedingTime >= timeLimit {
                torrents[torrentIndex].state = .completed
                return
            }
        }
    }
    
    private func parseMagnetLink(_ magnetLink: String) -> (infoHash: String, name: String?, trackers: [String])? {
        guard magnetLink.hasPrefix("magnet:?") else { return nil }
        
        var infoHash: String?
        var name: String?
        var trackers: [String] = []
        
        let components = magnetLink.dropFirst("magnet:?".count).components(separatedBy: "&")
        
        for component in components {
            let parts = component.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            
            let key = parts[0]
            let value = parts[1].removingPercentEncoding ?? parts[1]
            
            switch key {
            case "xt":
                // Extract info hash from urn:btih:HASH
                if value.hasPrefix("urn:btih:") {
                    infoHash = String(value.dropFirst("urn:btih:".count))
                }
            case "dn":
                name = value
            case "tr":
                trackers.append(value)
            default:
                break
            }
        }
        
        guard let hash = infoHash else { return nil }
        return (hash, name, trackers)
    }
    
    private func parseTorrentFile(_ fileURL: URL) throws -> (name: String, infoHash: String, totalSize: Int64, trackers: [String], files: [TorrentFile], pieces: [TorrentPiece]) {
        // Simplified torrent file parsing
        // In a real implementation, this would parse the bencoded .torrent file
        let data = try Data(contentsOf: fileURL)
        
        // For now, return dummy data
        let name = fileURL.deletingPathExtension().lastPathComponent
        let infoHash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        
        return (
            name: name,
            infoHash: String(infoHash.prefix(40)),
            totalSize: Int64(data.count) * 1024,  // Dummy size
            trackers: ["https://tracker.example.com:8080/announce"],
            files: [TorrentFile(path: name, size: Int64(data.count) * 1024)],
            pieces: []
        )
    }
    
    private func downloadMetadata(for torrentId: UUID) async {
        // Simulate metadata download from DHT/peers
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        // Update with metadata
        torrents[index].totalSize = 104857600  // 100 MB dummy size
        torrents[index].files = [
            TorrentFile(path: "file1.mp4", size: 52428800),
            TorrentFile(path: "file2.mp4", size: 52428800)
        ]
    }
    
    private func connectToTrackers(torrentId: UUID) async {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        for trackerIndex in torrents[index].trackers.indices {
            // Simulate tracker announce
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            
            torrents[index].trackers[trackerIndex].status = .working
            torrents[index].trackers[trackerIndex].lastAnnounce = Date()
            torrents[index].trackers[trackerIndex].nextAnnounce = Date().addingTimeInterval(1800)
            
            // Simulate getting peer info
            let seeders = Int.random(in: 5...50)
            let leechers = Int.random(in: 10...100)
            
            torrents[index].trackers[trackerIndex].seeders = seeders
            torrents[index].trackers[trackerIndex].leechers = leechers
            
            torrents[index].seeders = max(torrents[index].seeders, seeders)
            torrents[index].leechers = max(torrents[index].leechers, leechers)
        }
        
        saveTorrents()
    }
    
    private func connectToPeers(torrentId: UUID) async {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        // Simulate connecting to peers
        let peerCount = min(maxConnectionsPerTorrent, torrents[index].seeders + torrents[index].leechers)
        
        for _ in 0..<min(peerCount, 10) {  // Limit to 10 peers for demo
            let peer = TorrentPeer(
                peerId: UUID().uuidString,
                ipAddress: "\(Int.random(in: 1...255)).\(Int.random(in: 1...255)).\(Int.random(in: 1...255)).\(Int.random(in: 1...255))",
                port: Int.random(in: 49152...65535),
                client: ["μTorrent", "qBittorrent", "Transmission", "Deluge"].randomElement()!,
                progress: Double.random(in: 0...1),
                isSeeder: Bool.random(),
                isEncrypted: protocolSettings.encryptionPolicy != .disabled
            )
            
            torrents[index].peers.append(peer)
        }
    }
    
    private func downloadPieces(torrentId: UUID) async {
        guard let index = torrents.firstIndex(where: { $0.id == torrentId }) else { return }
        
        // Simulate downloading
        while torrents[index].state == .downloading && !torrents[index].isComplete {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            guard torrents.indices.contains(index) && torrents[index].state == .downloading else { break }
            
            // Simulate download progress
            let chunkSize: Int64 = Int64.random(in: 102400...1048576) // 100KB - 1MB per second
            torrents[index].downloadedBytes = min(
                torrents[index].downloadedBytes + chunkSize,
                torrents[index].totalSize
            )
            torrents[index].downloadSpeed = chunkSize
            
            // Simulate upload
            if torrents[index].downloadedBytes > 0 {
                let uploadChunk: Int64 = Int64.random(in: 51200...524288) // 50KB - 500KB per second
                torrents[index].uploadedBytes += uploadChunk
                torrents[index].uploadSpeed = uploadChunk
            }
            
            // Update peer speeds
            for peerIndex in torrents[index].peers.indices {
                torrents[index].peers[peerIndex].downloadSpeed = Int64.random(in: 10240...102400)
                torrents[index].peers[peerIndex].uploadSpeed = Int64.random(in: 10240...102400)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadTorrents() {
        guard FileManager.default.fileExists(atPath: saveURL.path),
              let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([Torrent].self, from: data) else {
            return
        }
        
        torrents = loaded
    }
    
    private func saveTorrents() {
        guard let data = try? JSONEncoder().encode(torrents) else { return }
        try? data.write(to: saveURL)
    }
}
