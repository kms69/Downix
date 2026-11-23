import Foundation

// MARK: - Torrent

/// Represents a torrent download with peer-to-peer sharing
public struct Torrent: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var infoHash: String  // SHA-1 hash of the info dictionary
    public var magnetLink: String?
    public var torrentFilePath: URL?
    
    public var totalSize: Int64
    public var downloadedBytes: Int64
    public var uploadedBytes: Int64
    
    public var state: TorrentState
    public var health: TorrentHealth
    
    public var seeders: Int
    public var leechers: Int
    public var peers: [TorrentPeer]
    public var trackers: [TorrentTracker]
    
    public var files: [TorrentFile]
    public var pieces: [TorrentPiece]
    
    public var downloadSpeed: Int64  // bytes per second
    public var uploadSpeed: Int64    // bytes per second
    public var ratio: Double         // upload/download ratio
    
    public var dateAdded: Date
    public var dateCompleted: Date?
    public var dateStarted: Date?
    
    public var saveLocation: URL
    public var category: String?
    public var tags: [String]
    
    // Seeding settings
    public var seedingConfig: SeedingConfig
    
    public init(
        id: UUID = UUID(),
        name: String,
        infoHash: String,
        magnetLink: String? = nil,
        torrentFilePath: URL? = nil,
        totalSize: Int64,
        downloadedBytes: Int64 = 0,
        uploadedBytes: Int64 = 0,
        state: TorrentState = .stopped,
        health: TorrentHealth = .unknown,
        seeders: Int = 0,
        leechers: Int = 0,
        peers: [TorrentPeer] = [],
        trackers: [TorrentTracker] = [],
        files: [TorrentFile] = [],
        pieces: [TorrentPiece] = [],
        downloadSpeed: Int64 = 0,
        uploadSpeed: Int64 = 0,
        ratio: Double = 0.0,
        dateAdded: Date = Date(),
        dateCompleted: Date? = nil,
        dateStarted: Date? = nil,
        saveLocation: URL,
        category: String? = nil,
        tags: [String] = [],
        seedingConfig: SeedingConfig = SeedingConfig()
    ) {
        self.id = id
        self.name = name
        self.infoHash = infoHash
        self.magnetLink = magnetLink
        self.torrentFilePath = torrentFilePath
        self.totalSize = totalSize
        self.downloadedBytes = downloadedBytes
        self.uploadedBytes = uploadedBytes
        self.state = state
        self.health = health
        self.seeders = seeders
        self.leechers = leechers
        self.peers = peers
        self.trackers = trackers
        self.files = files
        self.pieces = pieces
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.ratio = ratio
        self.dateAdded = dateAdded
        self.dateCompleted = dateCompleted
        self.dateStarted = dateStarted
        self.saveLocation = saveLocation
        self.category = category
        self.tags = tags
        self.seedingConfig = seedingConfig
    }
}

// MARK: - Computed Properties

extension Torrent {
    public var progress: Double {
        guard totalSize > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalSize)
    }
    
    public var isComplete: Bool {
        downloadedBytes >= totalSize
    }
    
    public var remainingBytes: Int64 {
        max(0, totalSize - downloadedBytes)
    }
    
    public var eta: TimeInterval? {
        guard downloadSpeed > 0 else { return nil }
        return Double(remainingBytes) / Double(downloadSpeed)
    }
    
    public var formattedSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: downloadSpeed) + "/s"
    }
    
    public var formattedUploadSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: uploadSpeed) + "/s"
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    public var formattedDownloaded: String {
        ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }
    
    public var formattedUploaded: String {
        ByteCountFormatter.string(fromByteCount: uploadedBytes, countStyle: .file)
    }
    
    public var formattedRatio: String {
        String(format: "%.2f", ratio)
    }
    
    public var formattedETA: String {
        guard let eta = eta else { return "∞" }
        
        let hours = Int(eta) / 3600
        let minutes = (Int(eta) % 3600) / 60
        let seconds = Int(eta) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

// MARK: - Torrent State

/// State of a torrent download
public enum TorrentState: String, Codable, Hashable {
    case stopped        // Not downloading or seeding
    case queued         // Waiting to start
    case checking       // Verifying existing data
    case downloading    // Downloading from peers
    case seeding        // Uploading to peers (complete)
    case paused         // Temporarily stopped
    case error          // Error occurred
    case completed      // Download complete, not seeding
    
    public var displayName: String {
        switch self {
        case .stopped: return "Stopped"
        case .queued: return "Queued"
        case .checking: return "Checking"
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .paused: return "Paused"
        case .error: return "Error"
        case .completed: return "Completed"
        }
    }
    
    public var icon: String {
        switch self {
        case .stopped: return "stop.circle"
        case .queued: return "clock"
        case .checking: return "checkmark.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .seeding: return "arrow.up.circle.fill"
        case .paused: return "pause.circle"
        case .error: return "exclamationmark.triangle"
        case .completed: return "checkmark.circle.fill"
        }
    }
    
    public var color: String {
        switch self {
        case .stopped: return "gray"
        case .queued: return "orange"
        case .checking: return "blue"
        case .downloading: return "green"
        case .seeding: return "purple"
        case .paused: return "yellow"
        case .error: return "red"
        case .completed: return "green"
        }
    }
}

// MARK: - Torrent Health

/// Health status of a torrent based on peer availability
public enum TorrentHealth: String, Codable, Hashable {
    case excellent  // Many seeders
    case good       // Adequate seeders
    case fair       // Few seeders
    case poor       // Very few seeders
    case dead       // No seeders
    case unknown    // Not yet determined
    
    public var displayName: String {
        rawValue.capitalized
    }
    
    public var icon: String {
        switch self {
        case .excellent: return "heart.fill"
        case .good: return "heart"
        case .fair: return "heart.slash"
        case .poor: return "heart.slash.fill"
        case .dead: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }
    
    public var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "yellow"
        case .poor: return "orange"
        case .dead: return "red"
        case .unknown: return "gray"
        }
    }
    
    public static func calculate(seeders: Int, leechers: Int) -> TorrentHealth {
        if seeders == 0 {
            return .dead
        } else if seeders >= 50 {
            return .excellent
        } else if seeders >= 10 {
            return .good
        } else if seeders >= 3 {
            return .fair
        } else {
            return .poor
        }
    }
}

// MARK: - Torrent Peer

/// Represents a peer in the torrent swarm
public struct TorrentPeer: Identifiable, Codable, Hashable {
    public let id: UUID
    public var peerId: String
    public var ipAddress: String
    public var port: Int
    public var client: String  // BitTorrent client name
    public var country: String?
    
    public var downloadSpeed: Int64
    public var uploadSpeed: Int64
    public var progress: Double  // Their download progress (0-1)
    
    public var isSeeder: Bool
    public var isEncrypted: Bool
    public var isLocal: Bool
    
    public var connectedAt: Date
    
    public init(
        id: UUID = UUID(),
        peerId: String,
        ipAddress: String,
        port: Int,
        client: String = "Unknown",
        country: String? = nil,
        downloadSpeed: Int64 = 0,
        uploadSpeed: Int64 = 0,
        progress: Double = 0,
        isSeeder: Bool = false,
        isEncrypted: Bool = false,
        isLocal: Bool = false,
        connectedAt: Date = Date()
    ) {
        self.id = id
        self.peerId = peerId
        self.ipAddress = ipAddress
        self.port = port
        self.client = client
        self.country = country
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.progress = progress
        self.isSeeder = isSeeder
        self.isEncrypted = isEncrypted
        self.isLocal = isLocal
        self.connectedAt = connectedAt
    }
}

// MARK: - Torrent Tracker

/// Represents a tracker server for a torrent
public struct TorrentTracker: Identifiable, Codable, Hashable {
    public let id: UUID
    public var url: String
    public var tier: Int
    public var status: TrackerStatus
    public var seeders: Int
    public var leechers: Int
    public var downloaded: Int  // Times completed
    public var lastAnnounce: Date?
    public var nextAnnounce: Date?
    public var announceInterval: TimeInterval
    public var message: String?
    
    public enum TrackerStatus: String, Codable {
        case working
        case updating
        case notContacted
        case error
        case disabled
        
        public var displayName: String {
            switch self {
            case .working: return "Working"
            case .updating: return "Updating"
            case .notContacted: return "Not Contacted"
            case .error: return "Error"
            case .disabled: return "Disabled"
            }
        }
        
        public var icon: String {
            switch self {
            case .working: return "checkmark.circle.fill"
            case .updating: return "arrow.triangle.2.circlepath"
            case .notContacted: return "circle"
            case .error: return "xmark.circle.fill"
            case .disabled: return "nosign"
            }
        }
    }
    
    public init(
        id: UUID = UUID(),
        url: String,
        tier: Int = 0,
        status: TrackerStatus = .notContacted,
        seeders: Int = 0,
        leechers: Int = 0,
        downloaded: Int = 0,
        lastAnnounce: Date? = nil,
        nextAnnounce: Date? = nil,
        announceInterval: TimeInterval = 1800,
        message: String? = nil
    ) {
        self.id = id
        self.url = url
        self.tier = tier
        self.status = status
        self.seeders = seeders
        self.leechers = leechers
        self.downloaded = downloaded
        self.lastAnnounce = lastAnnounce
        self.nextAnnounce = nextAnnounce
        self.announceInterval = announceInterval
        self.message = message
    }
}

// MARK: - Torrent File

/// Represents an individual file within a torrent
public struct TorrentFile: Identifiable, Codable, Hashable {
    public let id: UUID
    public var path: String
    public var size: Int64
    public var downloadedBytes: Int64
    public var priority: FilePriority
    public var isSelected: Bool  // Whether to download this file
    
    public enum FilePriority: Int, Codable {
        case skip = 0
        case low = 1
        case normal = 2
        case high = 3
        
        public var displayName: String {
            switch self {
            case .skip: return "Skip"
            case .low: return "Low"
            case .normal: return "Normal"
            case .high: return "High"
            }
        }
    }
    
    public init(
        id: UUID = UUID(),
        path: String,
        size: Int64,
        downloadedBytes: Int64 = 0,
        priority: FilePriority = .normal,
        isSelected: Bool = true
    ) {
        self.id = id
        self.path = path
        self.size = size
        self.downloadedBytes = downloadedBytes
        self.priority = priority
        self.isSelected = isSelected
    }
    
    public var progress: Double {
        guard size > 0 else { return 0 }
        return Double(downloadedBytes) / Double(size)
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Torrent Piece

/// Represents a piece of the torrent for tracking download progress
public struct TorrentPiece: Identifiable, Codable, Hashable {
    public let id: UUID
    public var index: Int
    public var size: Int
    public var hash: String  // SHA-1 hash for verification
    public var isComplete: Bool
    public var isVerified: Bool
    
    public init(
        id: UUID = UUID(),
        index: Int,
        size: Int,
        hash: String,
        isComplete: Bool = false,
        isVerified: Bool = false
    ) {
        self.id = id
        self.index = index
        self.size = size
        self.hash = hash
        self.isComplete = isComplete
        self.isVerified = isVerified
    }
}

// MARK: - Seeding Config

/// Configuration for seeding behavior
public struct SeedingConfig: Codable, Hashable, Equatable {
    public var enabled: Bool
    public var ratioLimit: Double?  // Stop seeding at this ratio (nil = unlimited)
    public var timeLimit: TimeInterval?  // Stop seeding after this time (nil = unlimited)
    public var uploadSpeedLimit: Int64?  // bytes per second (nil = unlimited)
    public var seedOnlyWhenIdle: Bool
    
    public init(
        enabled: Bool = true,
        ratioLimit: Double? = 2.0,
        timeLimit: TimeInterval? = nil,
        uploadSpeedLimit: Int64? = nil,
        seedOnlyWhenIdle: Bool = false
    ) {
        self.enabled = enabled
        self.ratioLimit = ratioLimit
        self.timeLimit = timeLimit
        self.uploadSpeedLimit = uploadSpeedLimit
        self.seedOnlyWhenIdle = seedOnlyWhenIdle
    }
}

// MARK: - Torrent Protocol

/// Torrent protocol settings
public struct TorrentProtocol: Codable, Hashable, Equatable {
    public var dhtEnabled: Bool  // Distributed Hash Table
    public var pexEnabled: Bool  // Peer Exchange
    public var lsdEnabled: Bool  // Local Service Discovery
    public var utpEnabled: Bool  // Micro Transport Protocol
    public var encryptionPolicy: EncryptionPolicy
    
    public enum EncryptionPolicy: String, Codable {
        case disabled
        case enabled
        case required
        
        public var displayName: String {
            rawValue.capitalized
        }
    }
    
    public init(
        dhtEnabled: Bool = true,
        pexEnabled: Bool = true,
        lsdEnabled: Bool = true,
        utpEnabled: Bool = true,
        encryptionPolicy: EncryptionPolicy = .enabled
    ) {
        self.dhtEnabled = dhtEnabled
        self.pexEnabled = pexEnabled
        self.lsdEnabled = lsdEnabled
        self.utpEnabled = utpEnabled
        self.encryptionPolicy = encryptionPolicy
    }
}

// MARK: - Torrent Error

/// Errors related to torrent operations
public enum TorrentError: Error, LocalizedError {
    case invalidMagnetLink
    case invalidTorrentFile
    case trackerError(String)
    case diskError(String)
    case networkError(String)
    case pieceVerificationFailed
    case noPeersAvailable
    case torrentNotFound
    
    public var errorDescription: String? {
        switch self {
        case .invalidMagnetLink:
            return "Invalid magnet link format"
        case .invalidTorrentFile:
            return "Invalid torrent file"
        case .trackerError(let message):
            return "Tracker error: \(message)"
        case .diskError(let message):
            return "Disk error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .pieceVerificationFailed:
            return "Piece verification failed"
        case .noPeersAvailable:
            return "No peers available"
        case .torrentNotFound:
            return "Torrent not found"
        }
    }
}

// MARK: - Torrent Statistics

/// Statistics for torrent operations
public struct TorrentStatistics: Codable {
    public var totalTorrents: Int
    public var activeTorrents: Int
    public var seedingTorrents: Int
    public var downloadingTorrents: Int
    
    public var totalDownloaded: Int64
    public var totalUploaded: Int64
    public var globalDownloadSpeed: Int64
    public var globalUploadSpeed: Int64
    public var globalRatio: Double
    
    public var sessionDownloaded: Int64
    public var sessionUploaded: Int64
    
    public init(
        totalTorrents: Int = 0,
        activeTorrents: Int = 0,
        seedingTorrents: Int = 0,
        downloadingTorrents: Int = 0,
        totalDownloaded: Int64 = 0,
        totalUploaded: Int64 = 0,
        globalDownloadSpeed: Int64 = 0,
        globalUploadSpeed: Int64 = 0,
        globalRatio: Double = 0.0,
        sessionDownloaded: Int64 = 0,
        sessionUploaded: Int64 = 0
    ) {
        self.totalTorrents = totalTorrents
        self.activeTorrents = activeTorrents
        self.seedingTorrents = seedingTorrents
        self.downloadingTorrents = downloadingTorrents
        self.totalDownloaded = totalDownloaded
        self.totalUploaded = totalUploaded
        self.globalDownloadSpeed = globalDownloadSpeed
        self.globalUploadSpeed = globalUploadSpeed
        self.globalRatio = globalRatio
        self.sessionDownloaded = sessionDownloaded
        self.sessionUploaded = sessionUploaded
    }
}
