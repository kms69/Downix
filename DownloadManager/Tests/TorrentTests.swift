import XCTest
@testable import DownloadManager

@MainActor
final class TorrentTests: XCTestCase {
    
    var manager: TorrentManager!
    
    override func setUp() async throws {
        manager = TorrentManager.shared
        // Clear any existing torrents
        for torrent in manager.torrents {
            try? manager.removeTorrent(torrent.id, deleteFiles: false)
        }
    }
    
    override func tearDown() async throws {
        manager = nil
    }
    
    // MARK: - Model Tests
    
    func testTorrentInitialization() {
        let saveLocation = URL(fileURLWithPath: "/tmp")
        let torrent = Torrent(
            name: "Test Torrent",
            infoHash: "1234567890abcdef1234567890abcdef12345678",
            totalSize: 104857600,
            saveLocation: saveLocation
        )
        
        XCTAssertEqual(torrent.name, "Test Torrent")
        XCTAssertEqual(torrent.totalSize, 104857600)
        XCTAssertEqual(torrent.downloadedBytes, 0)
        XCTAssertEqual(torrent.state, .stopped)
        XCTAssertEqual(torrent.progress, 0.0)
        XCTAssertFalse(torrent.isComplete)
    }
    
    func testTorrentProgress() {
        let torrent = Torrent(
            name: "Test",
            infoHash: "abc123",
            totalSize: 1000,
            downloadedBytes: 500,
            saveLocation: URL(fileURLWithPath: "/tmp")
        )
        
        XCTAssertEqual(torrent.progress, 0.5)
        XCTAssertEqual(torrent.remainingBytes, 500)
        XCTAssertFalse(torrent.isComplete)
    }
    
    func testTorrentCompletion() {
        let torrent = Torrent(
            name: "Test",
            infoHash: "abc123",
            totalSize: 1000,
            downloadedBytes: 1000,
            saveLocation: URL(fileURLWithPath: "/tmp")
        )
        
        XCTAssertEqual(torrent.progress, 1.0)
        XCTAssertTrue(torrent.isComplete)
        XCTAssertEqual(torrent.remainingBytes, 0)
    }
    
    func testTorrentRatio() {
        var torrent = Torrent(
            name: "Test",
            infoHash: "abc123",
            totalSize: 1000,
            downloadedBytes: 1000,
            uploadedBytes: 2000,
            saveLocation: URL(fileURLWithPath: "/tmp")
        )
        
        torrent.ratio = Double(torrent.uploadedBytes) / Double(torrent.downloadedBytes)
        XCTAssertEqual(torrent.ratio, 2.0)
        XCTAssertEqual(torrent.formattedRatio, "2.00")
    }
    
    func testTorrentETA() {
        let torrent = Torrent(
            name: "Test",
            infoHash: "abc123",
            totalSize: 10000,
            downloadedBytes: 5000,
            downloadSpeed: 1000,  // 1000 bytes per second
            saveLocation: URL(fileURLWithPath: "/tmp")
        )
        
        XCTAssertEqual(torrent.remainingBytes, 5000)
        XCTAssertEqual(torrent.eta, 5.0)  // 5 seconds
    }
    
    func testTorrentETANoSpeed() {
        let torrent = Torrent(
            name: "Test",
            infoHash: "abc123",
            totalSize: 10000,
            downloadedBytes: 5000,
            downloadSpeed: 0,
            saveLocation: URL(fileURLWithPath: "/tmp")
        )
        
        XCTAssertNil(torrent.eta)
    }
    
    // MARK: - State Tests
    
    func testTorrentStates() {
        XCTAssertEqual(TorrentState.stopped.displayName, "Stopped")
        XCTAssertEqual(TorrentState.downloading.displayName, "Downloading")
        XCTAssertEqual(TorrentState.seeding.displayName, "Seeding")
        XCTAssertEqual(TorrentState.paused.displayName, "Paused")
        
        XCTAssertEqual(TorrentState.stopped.icon, "stop.circle")
        XCTAssertEqual(TorrentState.downloading.icon, "arrow.down.circle.fill")
        XCTAssertEqual(TorrentState.seeding.icon, "arrow.up.circle.fill")
    }
    
    // MARK: - Health Tests
    
    func testTorrentHealthCalculation() {
        XCTAssertEqual(TorrentHealth.calculate(seeders: 0, leechers: 100), .dead)
        XCTAssertEqual(TorrentHealth.calculate(seeders: 2, leechers: 50), .poor)
        XCTAssertEqual(TorrentHealth.calculate(seeders: 5, leechers: 20), .fair)
        XCTAssertEqual(TorrentHealth.calculate(seeders: 15, leechers: 10), .good)
        XCTAssertEqual(TorrentHealth.calculate(seeders: 100, leechers: 50), .excellent)
    }
    
    // MARK: - Manager Tests
    
    func testAddTorrentFromMagnetLink() throws {
        let magnetLink = "magnet:?xt=urn:btih:1234567890abcdef1234567890abcdef12345678&dn=Test%20Torrent&tr=http://tracker.example.com:8080/announce"
        
        let torrent = try manager.addTorrent(magnetLink: magnetLink)
        
        XCTAssertEqual(torrent.infoHash, "1234567890abcdef1234567890abcdef12345678")
        XCTAssertEqual(torrent.name, "Test Torrent")
        XCTAssertEqual(torrent.magnetLink, magnetLink)
        XCTAssertEqual(torrent.trackers.count, 1)
        XCTAssertEqual(torrent.trackers[0].url, "http://tracker.example.com:8080/announce")
        XCTAssertEqual(manager.torrents.count, 1)
    }
    
    func testAddTorrentInvalidMagnetLink() {
        XCTAssertThrowsError(try manager.addTorrent(magnetLink: "invalid")) { error in
            XCTAssertEqual(error as? TorrentError, .invalidMagnetLink)
        }
    }
    
    func testStartTorrent() throws {
        let magnetLink = "magnet:?xt=urn:btih:abc123&dn=Test"
        let torrent = try manager.addTorrent(magnetLink: magnetLink)
        
        manager.startTorrent(torrent.id)
        
        let updated = manager.torrents.first { $0.id == torrent.id }
        XCTAssertEqual(updated?.state, .downloading)
        XCTAssertNotNil(updated?.dateStarted)
    }
    
    func testStopTorrent() throws {
        let magnetLink = "magnet:?xt=urn:btih:abc123&dn=Test"
        let torrent = try manager.addTorrent(magnetLink: magnetLink)
        
        manager.startTorrent(torrent.id)
        manager.stopTorrent(torrent.id)
        
        let updated = manager.torrents.first { $0.id == torrent.id }
        XCTAssertEqual(updated?.state, .stopped)
        XCTAssertEqual(updated?.peers.count, 0)
    }
    
    func testPauseTorrent() throws {
        let magnetLink = "magnet:?xt=urn:btih:abc123&dn=Test"
        let torrent = try manager.addTorrent(magnetLink: magnetLink)
        
        manager.startTorrent(torrent.id)
        manager.pauseTorrent(torrent.id)
        
        let updated = manager.torrents.first { $0.id == torrent.id }
        XCTAssertEqual(updated?.state, .paused)
    }
    
    func testResumeTorrent() throws {
        let magnetLink = "magnet:?xt=urn:btih:abc123&dn=Test"
        let torrent = try manager.addTorrent(magnetLink: magnetLink)
        
        manager.startTorrent(torrent.id)
        manager.pauseTorrent(torrent.id)
        manager.resumeTorrent(torrent.id)
        
        let updated = manager.torrents.first { $0.id == torrent.id }
        XCTAssertEqual(updated?.state, .downloading)
    }
    
    func testRemoveTorrent() throws {
        let magnetLink = "magnet:?xt=urn:btih:abc123&dn=Test"
        let torrent = try manager.addTorrent(magnetLink: magnetLink)
        
        XCTAssertEqual(manager.torrents.count, 1)
        
        try manager.removeTorrent(torrent.id)
        
        XCTAssertEqual(manager.torrents.count, 0)
    }
    
    func testRemoveNonexistentTorrent() {
        XCTAssertThrowsError(try manager.removeTorrent(UUID())) { error in
            XCTAssertEqual(error as? TorrentError, .torrentNotFound)
        }
    }
    
    func testPauseAll() throws {
        let torrent1 = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:abc123&dn=Test1")
        let torrent2 = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:def456&dn=Test2")
        
        manager.startTorrent(torrent1.id)
        manager.startTorrent(torrent2.id)
        
        manager.pauseAll()
        
        for torrent in manager.torrents {
            XCTAssertEqual(torrent.state, .paused)
        }
    }
    
    func testResumeAll() throws {
        let torrent1 = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:abc123&dn=Test1")
        let torrent2 = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:def456&dn=Test2")
        
        manager.startTorrent(torrent1.id)
        manager.startTorrent(torrent2.id)
        manager.pauseAll()
        manager.resumeAll()
        
        for torrent in manager.torrents {
            XCTAssertEqual(torrent.state, .downloading)
        }
    }
    
    func testStopAll() throws {
        let torrent1 = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:abc123&dn=Test1")
        let torrent2 = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:def456&dn=Test2")
        
        manager.startTorrent(torrent1.id)
        manager.startTorrent(torrent2.id)
        
        manager.stopAll()
        
        for torrent in manager.torrents {
            XCTAssertEqual(torrent.state, .stopped)
        }
    }
    
    // MARK: - Tracker Tests
    
    func testAddTracker() throws {
        let torrent = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:abc123&dn=Test")
        
        manager.addTracker(to: torrent.id, url: "http://newtracker.com:8080/announce", tier: 1)
        
        let updated = manager.torrents.first { $0.id == torrent.id }
        XCTAssertEqual(updated?.trackers.count, 1)  // Was 0 initially
    }
    
    func testRemoveTracker() throws {
        let magnetLink = "magnet:?xt=urn:btih:abc123&dn=Test&tr=http://tracker1.com"
        let torrent = try manager.addTorrent(magnetLink: magnetLink)
        
        guard let trackerId = torrent.trackers.first?.id else {
            XCTFail("No tracker found")
            return
        }
        
        manager.removeTracker(from: torrent.id, trackerId: trackerId)
        
        let updated = manager.torrents.first { $0.id == torrent.id }
        XCTAssertEqual(updated?.trackers.count, 0)
    }
    
    // MARK: - File Priority Tests
    
    func testUpdateFilePriority() throws {
        let torrent = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:abc123&dn=Test")
        
        // Add a file manually for testing
        if let index = manager.torrents.firstIndex(where: { $0.id == torrent.id }) {
            let file = TorrentFile(path: "test.mp4", size: 1000000)
            manager.torrents[index].files = [file]
            
            manager.updateFilePriority(torrentId: torrent.id, fileId: file.id, priority: .high)
            
            let updated = manager.torrents[index]
            XCTAssertEqual(updated.files[0].priority, .high)
            XCTAssertTrue(updated.files[0].isSelected)
            
            manager.updateFilePriority(torrentId: torrent.id, fileId: file.id, priority: .skip)
            let updated2 = manager.torrents[index]
            XCTAssertEqual(updated2.files[0].priority, .skip)
            XCTAssertFalse(updated2.files[0].isSelected)
        }
    }
    
    // MARK: - Statistics Tests
    
    func testGetStatistics() throws {
        XCTAssertEqual(manager.getStatistics().totalTorrents, 0)
        
        let torrent1 = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:abc123&dn=Test1")
        let torrent2 = try manager.addTorrent(magnetLink: "magnet:?xt=urn:btih:def456&dn=Test2")
        
        manager.startTorrent(torrent1.id)
        
        let stats = manager.getStatistics()
        
        XCTAssertEqual(stats.totalTorrents, 2)
        XCTAssertEqual(stats.activeTorrents, 1)
        XCTAssertEqual(stats.downloadingTorrents, 1)
        XCTAssertEqual(stats.seedingTorrents, 0)
    }
    
    // MARK: - Peer Tests
    
    func testTorrentPeerInitialization() {
        let peer = TorrentPeer(
            peerId: "TEST123",
            ipAddress: "192.168.1.1",
            port: 6881,
            client: "μTorrent",
            progress: 0.75,
            isSeeder: true
        )
        
        XCTAssertEqual(peer.peerId, "TEST123")
        XCTAssertEqual(peer.ipAddress, "192.168.1.1")
        XCTAssertEqual(peer.port, 6881)
        XCTAssertEqual(peer.client, "μTorrent")
        XCTAssertEqual(peer.progress, 0.75)
        XCTAssertTrue(peer.isSeeder)
    }
    
    // MARK: - Tracker Tests
    
    func testTrackerStatuses() {
        XCTAssertEqual(TorrentTracker.TrackerStatus.working.displayName, "Working")
        XCTAssertEqual(TorrentTracker.TrackerStatus.updating.displayName, "Updating")
        XCTAssertEqual(TorrentTracker.TrackerStatus.error.displayName, "Error")
    }
    
    // MARK: - File Tests
    
    func testTorrentFileProgress() {
        let file = TorrentFile(
            path: "test.mp4",
            size: 10000,
            downloadedBytes: 5000
        )
        
        XCTAssertEqual(file.progress, 0.5)
        XCTAssertEqual(file.formattedSize, "10 KB")
    }
    
    func testTorrentFilePriorities() {
        XCTAssertEqual(TorrentFile.FilePriority.skip.displayName, "Skip")
        XCTAssertEqual(TorrentFile.FilePriority.low.displayName, "Low")
        XCTAssertEqual(TorrentFile.FilePriority.normal.displayName, "Normal")
        XCTAssertEqual(TorrentFile.FilePriority.high.displayName, "High")
    }
    
    // MARK: - Seeding Config Tests
    
    func testSeedingConfigDefaults() {
        let config = SeedingConfig()
        
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.ratioLimit, 2.0)
        XCTAssertNil(config.timeLimit)
        XCTAssertNil(config.uploadSpeedLimit)
        XCTAssertFalse(config.seedOnlyWhenIdle)
    }
    
    func testSeedingConfigCustom() {
        let config = SeedingConfig(
            enabled: true,
            ratioLimit: 1.5,
            timeLimit: 3600,
            uploadSpeedLimit: 102400
        )
        
        XCTAssertEqual(config.ratioLimit, 1.5)
        XCTAssertEqual(config.timeLimit, 3600)
        XCTAssertEqual(config.uploadSpeedLimit, 102400)
    }
    
    // MARK: - Protocol Tests
    
    func testTorrentProtocolDefaults() {
        let protocolSettings = TorrentProtocol()
        
        XCTAssertTrue(protocolSettings.dhtEnabled)
        XCTAssertTrue(protocolSettings.pexEnabled)
        XCTAssertTrue(protocolSettings.lsdEnabled)
        XCTAssertTrue(protocolSettings.utpEnabled)
        XCTAssertEqual(protocolSettings.encryptionPolicy, .enabled)
    }
    
    func testEncryptionPolicies() {
        XCTAssertEqual(TorrentProtocol.EncryptionPolicy.disabled.displayName, "Disabled")
        XCTAssertEqual(TorrentProtocol.EncryptionPolicy.enabled.displayName, "Enabled")
        XCTAssertEqual(TorrentProtocol.EncryptionPolicy.required.displayName, "Required")
    }
    
    // MARK: - Piece Tests
    
    func testTorrentPiece() {
        let piece = TorrentPiece(
            index: 0,
            size: 262144,
            hash: "abc123def456",
            isComplete: true,
            isVerified: true
        )
        
        XCTAssertEqual(piece.index, 0)
        XCTAssertEqual(piece.size, 262144)
        XCTAssertTrue(piece.isComplete)
        XCTAssertTrue(piece.isVerified)
    }
    
    // MARK: - Integration Tests
    
    func testFullTorrentLifecycle() async throws {
        // Add torrent
        let magnetLink = "magnet:?xt=urn:btih:abc123&dn=Test%20Torrent"
        let torrent = try manager.addTorrent(magnetLink: magnetLink)
        
        XCTAssertEqual(manager.torrents.count, 1)
        XCTAssertEqual(torrent.state, .stopped)
        
        // Start torrent
        manager.startTorrent(torrent.id)
        XCTAssertEqual(manager.torrents[0].state, .downloading)
        
        // Wait for metadata
        try await Task.sleep(nanoseconds: 2_500_000_000)
        
        // Pause torrent
        manager.pauseTorrent(torrent.id)
        XCTAssertEqual(manager.torrents[0].state, .paused)
        
        // Resume torrent
        manager.resumeTorrent(torrent.id)
        XCTAssertEqual(manager.torrents[0].state, .downloading)
        
        // Stop torrent
        manager.stopTorrent(torrent.id)
        XCTAssertEqual(manager.torrents[0].state, .stopped)
        
        // Remove torrent
        try manager.removeTorrent(torrent.id)
        XCTAssertEqual(manager.torrents.count, 0)
    }
}

// MARK: - Error Conformance

extension TorrentError: Equatable {
    public static func == (lhs: TorrentError, rhs: TorrentError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidMagnetLink, .invalidMagnetLink),
             (.invalidTorrentFile, .invalidTorrentFile),
             (.pieceVerificationFailed, .pieceVerificationFailed),
             (.noPeersAvailable, .noPeersAvailable),
             (.torrentNotFound, .torrentNotFound):
            return true
        case (.trackerError(let a), .trackerError(let b)),
             (.diskError(let a), .diskError(let b)),
             (.networkError(let a), .networkError(let b)):
            return a == b
        default:
            return false
        }
    }
}
