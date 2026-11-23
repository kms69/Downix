import Foundation

// Note: Using VideoPlatform, VideoQuality, and VideoFormat from VideoDownload.swift
// which are now public and shared across features

// MARK: - Stream Type

/// Type of video stream
public enum StreamType: String, Codable {
    case progressive = "Progressive"
    case adaptive = "Adaptive (HLS/DASH)"
    case live = "Live Stream"
    case m3u8 = "M3U8 Playlist"
    
    var displayName: String {
        rawValue
    }
    
    var icon: String {
        switch self {
        case .progressive: return "arrow.down.circle"
        case .adaptive: return "waveform.path"
        case .live: return "record.circle"
        case .m3u8: return "list.bullet"
        }
    }
}

// MARK: - Video Info

/// Information about a video
public struct VideoInfo: Codable, Identifiable {
    public let id: UUID
    public var url: String
    public var platform: VideoPlatform
    public var title: String?
    public var description: String?
    public var duration: TimeInterval?
    public var thumbnailURL: String?
    public var author: String?
    public var viewCount: Int?
    public var uploadDate: Date?
    public var availableQualities: [VideoQuality]
    public var availableFormats: [VideoFormat]
    public var streamType: StreamType
    public var isLiveStream: Bool
    public var metadata: [String: String]
    
    public init(
        id: UUID = UUID(),
        url: String,
        platform: VideoPlatform,
        title: String? = nil,
        description: String? = nil,
        duration: TimeInterval? = nil,
        thumbnailURL: String? = nil,
        author: String? = nil,
        viewCount: Int? = nil,
        uploadDate: Date? = nil,
        availableQualities: [VideoQuality] = [],
        availableFormats: [VideoFormat] = [.mp4],
        streamType: StreamType = .progressive,
        isLiveStream: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.url = url
        self.platform = platform
        self.title = title
        self.description = description
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.author = author
        self.viewCount = viewCount
        self.uploadDate = uploadDate
        self.availableQualities = availableQualities
        self.availableFormats = availableFormats
        self.streamType = streamType
        self.isLiveStream = isLiveStream
        self.metadata = metadata
    }
    
    public var formattedDuration: String? {
        guard let duration = duration else { return nil }
        
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    public var formattedViewCount: String? {
        guard let viewCount = viewCount else { return nil }
        
        if viewCount >= 1_000_000 {
            return String(format: "%.1fM views", Double(viewCount) / 1_000_000)
        } else if viewCount >= 1_000 {
            return String(format: "%.1fK views", Double(viewCount) / 1_000)
        } else {
            return "\(viewCount) views"
        }
    }
}

// Note: VideoDownloadOptions is now shared from VideoDownload.swift

// MARK: - M3U8 Segment

/// Segment in M3U8 playlist
public struct M3U8Segment: Codable, Identifiable {
    public let id: UUID
    public var url: String
    public var duration: TimeInterval
    public var sequence: Int
    public var byteRange: Range<Int64>?
    
    public init(
        id: UUID = UUID(),
        url: String,
        duration: TimeInterval,
        sequence: Int,
        byteRange: Range<Int64>? = nil
    ) {
        self.id = id
        self.url = url
        self.duration = duration
        self.sequence = sequence
        self.byteRange = byteRange
    }
}

// MARK: - M3U8 Playlist

/// M3U8 playlist information
public struct M3U8Playlist: Codable {
    public var url: String
    public var version: Int
    public var targetDuration: TimeInterval
    public var segments: [M3U8Segment]
    public var totalDuration: TimeInterval
    public var isLive: Bool
    
    public init(
        url: String,
        version: Int = 3,
        targetDuration: TimeInterval = 10,
        segments: [M3U8Segment] = [],
        totalDuration: TimeInterval = 0,
        isLive: Bool = false
    ) {
        self.url = url
        self.version = version
        self.targetDuration = targetDuration
        self.segments = segments
        self.totalDuration = totalDuration
        self.isLive = isLive
    }
    
    public var segmentCount: Int {
        segments.count
    }
}

// MARK: - Live Stream Info

/// Information about live stream
public struct LiveStreamInfo: Codable, Identifiable {
    public let id: UUID
    public var url: String
    public var platform: VideoPlatform
    public var title: String?
    public var streamer: String?
    public var viewerCount: Int?
    public var startedAt: Date?
    public var isLive: Bool
    public var qualityOptions: [VideoQuality]
    
    public init(
        id: UUID = UUID(),
        url: String,
        platform: VideoPlatform,
        title: String? = nil,
        streamer: String? = nil,
        viewerCount: Int? = nil,
        startedAt: Date? = nil,
        isLive: Bool = true,
        qualityOptions: [VideoQuality] = []
    ) {
        self.id = id
        self.url = url
        self.platform = platform
        self.title = title
        self.streamer = streamer
        self.viewerCount = viewerCount
        self.startedAt = startedAt
        self.isLive = isLive
        self.qualityOptions = qualityOptions
    }
    
    public var formattedViewerCount: String? {
        guard let viewerCount = viewerCount else { return nil }
        
        if viewerCount >= 1_000_000 {
            return String(format: "%.1fM watching", Double(viewerCount) / 1_000_000)
        } else if viewerCount >= 1_000 {
            return String(format: "%.1fK watching", Double(viewerCount) / 1_000)
        } else {
            return "\(viewerCount) watching"
        }
    }
    
    public var streamDuration: TimeInterval? {
        guard let startedAt = startedAt else { return nil }
        return Date().timeIntervalSince(startedAt)
    }
}

// MARK: - Embedded Video

/// Embedded video detected on webpage
public struct EmbeddedVideo: Codable, Identifiable {
    public let id: UUID
    public var pageURL: String
    public var videoURL: String
    public var platform: VideoPlatform
    public var title: String?
    public var thumbnailURL: String?
    public var embedType: EmbedType
    
    public enum EmbedType: String, Codable {
        case iframe = "iFrame"
        case video = "Video Tag"
        case object = "Object/Embed"
        case script = "Script"
        
        var displayName: String {
            rawValue
        }
    }
    
    public init(
        id: UUID = UUID(),
        pageURL: String,
        videoURL: String,
        platform: VideoPlatform,
        title: String? = nil,
        thumbnailURL: String? = nil,
        embedType: EmbedType = .iframe
    ) {
        self.id = id
        self.pageURL = pageURL
        self.videoURL = videoURL
        self.platform = platform
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.embedType = embedType
    }
}

// MARK: - Video Extraction Result

/// Result of video extraction
public struct VideoExtractionResult: Codable {
    public var success: Bool
    public var videoInfo: VideoInfo?
    public var directURL: String?
    public var m3u8Playlist: M3U8Playlist?
    public var error: String?
    public var extractionTime: TimeInterval
    
    public init(
        success: Bool,
        videoInfo: VideoInfo? = nil,
        directURL: String? = nil,
        m3u8Playlist: M3U8Playlist? = nil,
        error: String? = nil,
        extractionTime: TimeInterval = 0
    ) {
        self.success = success
        self.videoInfo = videoInfo
        self.directURL = directURL
        self.m3u8Playlist = m3u8Playlist
        self.error = error
        self.extractionTime = extractionTime
    }
}

// MARK: - Video Download Progress

/// Progress of video download
public struct VideoDownloadProgress: Codable {
    public var videoPlatform: VideoPlatform
    public var currentSegment: Int
    public var totalSegments: Int
    public var bytesDownloaded: Int64
    public var totalBytes: Int64?
    public var speed: Double
    public var timeRemaining: TimeInterval?
    
    public init(
        videoPlatform: VideoPlatform,
        currentSegment: Int = 0,
        totalSegments: Int = 1,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64? = nil,
        speed: Double = 0,
        timeRemaining: TimeInterval? = nil
    ) {
        self.videoPlatform = videoPlatform
        self.currentSegment = currentSegment
        self.totalSegments = totalSegments
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.speed = speed
        self.timeRemaining = timeRemaining
    }
    
    public var segmentProgress: Double {
        guard totalSegments > 0 else { return 0 }
        return Double(currentSegment) / Double(totalSegments)
    }
    
    public var byteProgress: Double {
        guard let totalBytes = totalBytes, totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }
    
    public var overallProgress: Double {
        // Average of segment and byte progress
        let segmentProg = segmentProgress
        let byteProg = byteProgress
        
        if byteProg > 0 {
            return (segmentProg + byteProg) / 2.0
        } else {
            return segmentProg
        }
    }
}

// MARK: - Video Platform Credentials

/// Credentials for platform authentication
public struct VideoPlatformCredentials: Codable {
    public var platform: VideoPlatform
    public var username: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var expiresAt: Date?
    public var cookies: [String: String]
    
    public init(
        platform: VideoPlatform,
        username: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        cookies: [String: String] = [:]
    ) {
        self.platform = platform
        self.username = username
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.cookies = cookies
    }
    
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}

// MARK: - Advanced Video Error

/// Errors related to advanced video features
public enum AdvancedVideoError: Error, LocalizedError {
    case unsupportedPlatform(String)
    case extractionFailed(String)
    case invalidURL(String)
    case videoNotFound
    case authenticationRequired(VideoPlatform)
    case geoRestricted(String)
    case ageRestricted
    case privateVideo
    case liveStreamNotStarted
    case liveStreamEnded
    case m3u8ParseError(String)
    case watermarkRemovalFailed
    case conversionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform(let platform):
            return "Unsupported platform: \(platform)"
        case .extractionFailed(let reason):
            return "Video extraction failed: \(reason)"
        case .invalidURL(let url):
            return "Invalid video URL: \(url)"
        case .videoNotFound:
            return "Video not found or has been removed"
        case .authenticationRequired(let platform):
            return "Authentication required for \(platform.displayName)"
        case .geoRestricted(let region):
            return "Video is geo-restricted: \(region)"
        case .ageRestricted:
            return "Video is age-restricted"
        case .privateVideo:
            return "Video is private"
        case .liveStreamNotStarted:
            return "Live stream has not started yet"
        case .liveStreamEnded:
            return "Live stream has ended"
        case .m3u8ParseError(let reason):
            return "Failed to parse M3U8 playlist: \(reason)"
        case .watermarkRemovalFailed:
            return "Failed to remove watermark"
        case .conversionFailed(let reason):
            return "Video conversion failed: \(reason)"
        }
    }
}
