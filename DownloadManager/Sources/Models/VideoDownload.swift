//
//  VideoDownload.swift
//  Download Manager for Mac - Feature #7: YouTube & Video Downloading
//
//  Created on February 15, 2026
//

import Foundation

// MARK: - Video Platform

/// Supported video platforms
public enum VideoPlatform: String, Codable, CaseIterable, Hashable {
    case youtube = "YouTube"
    case vimeo = "Vimeo"
    case dailymotion = "Dailymotion"
    case twitch = "Twitch"
    case facebook = "Facebook"
    case instagram = "Instagram"
    case twitter = "Twitter/X"
    case tiktok = "TikTok"
    case generic = "Other"
    
    var icon: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .vimeo: return "play.circle.fill"
        case .dailymotion: return "play.square.fill"
        case .twitch: return "tv.fill"
        case .facebook: return "f.square.fill"
        case .instagram: return "camera.fill"
        case .twitter: return "text.bubble.fill"
        case .tiktok: return "music.note"
        case .generic: return "video.fill"
        }
    }
    
    var displayName: String {
        rawValue
    }
    
    var urlPatterns: [String] {
        switch self {
        case .youtube:
            return ["youtube.com", "youtu.be", "youtube-nocookie.com"]
        case .vimeo:
            return ["vimeo.com"]
        case .dailymotion:
            return ["dailymotion.com"]
        case .twitch:
            return ["twitch.tv"]
        case .facebook:
            return ["facebook.com", "fb.watch"]
        case .instagram:
            return ["instagram.com"]
        case .twitter:
            return ["twitter.com", "x.com"]
        case .tiktok:
            return ["tiktok.com"]
        case .generic:
            return []
        }
    }
    
    /// Detect platform from URL
    static func detect(from url: URL) -> VideoPlatform {
        let host = url.host?.lowercased() ?? ""
        
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        } else if host.contains("vimeo.com") {
            return .vimeo
        } else if host.contains("dailymotion.com") {
            return .dailymotion
        } else if host.contains("twitch.tv") {
            return .twitch
        } else if host.contains("facebook.com") || host.contains("fb.watch") {
            return .facebook
        } else if host.contains("instagram.com") {
            return .instagram
        } else if host.contains("twitter.com") || host.contains("x.com") {
            return .twitter
        } else if host.contains("tiktok.com") {
            return .tiktok
        }
        
        return .generic
    }
    
    /// Detect platform from URL string
    static func detect(from urlString: String) -> VideoPlatform {
        let lowercased = urlString.lowercased()
        
        for platform in VideoPlatform.allCases where platform != .generic {
            if platform.urlPatterns.contains(where: { lowercased.contains($0) }) {
                return platform
            }
        }
        
        return .generic
    }
}

// MARK: - Video Quality

/// Video quality options
public enum VideoQuality: String, Codable, CaseIterable, Hashable {
    case best = "Best Available"
    case quality4K = "4K (2160p)"
    case quality2K = "2K (1440p)"
    case quality1080p = "1080p"
    case quality720p = "720p"
    case quality480p = "480p"
    case quality360p = "360p"
    case quality240p = "240p"
    case quality144p = "144p"
    case auto = "Auto"
    
    var displayName: String {
        rawValue
    }
    
    var height: Int? {
        switch self {
        case .best: return nil
        case .quality4K: return 2160
        case .quality2K: return 1440
        case .quality1080p: return 1080
        case .quality720p: return 720
        case .quality480p: return 480
        case .quality360p: return 360
        case .quality240p: return 240
        case .quality144p: return 144
        case .auto: return nil
        }
    }
    
    var description: String {
        rawValue
    }

    /// Maps a concrete video height (from yt-dlp) to the closest preset.
    static func from(height: Int) -> VideoQuality {
        switch height {
        case 2160...: return .quality4K
        case 1440..<2160: return .quality2K
        case 1080..<1440: return .quality1080p
        case 720..<1080: return .quality720p
        case 480..<720: return .quality480p
        case 360..<480: return .quality360p
        case 240..<360: return .quality240p
        case 1..<240: return .quality144p
        default: return .best
        }
    }
}

// MARK: - Video Format

/// Output video/audio formats
public enum VideoFormat: String, Codable, CaseIterable, Hashable {
    // Video formats
    case mp4 = "MP4"
    case mkv = "MKV"
    case webm = "WebM"
    case avi = "AVI"
    case mov = "MOV"
    
    // Audio formats
    case mp3 = "MP3"
    case m4a = "M4A"
    case aac = "AAC"
    case opus = "Opus"
    case flac = "FLAC"
    
    var isAudioOnly: Bool {
        switch self {
        case .mp3, .m4a, .aac, .opus, .flac:
            return true
        default:
            return false
        }
    }
    
    var fileExtension: String {
        rawValue.lowercased()
    }
    
    var description: String {
        if isAudioOnly {
            return "\(rawValue) (Audio)"
        } else {
            return "\(rawValue) (Video)"
        }
    }
    
    var mimeTypes: [String] {
        switch self {
        case .mp4:
            return ["video/mp4"]
        case .mkv:
            return ["video/x-matroska"]
        case .webm:
            return ["video/webm"]
        case .avi:
            return ["video/x-msvideo"]
        case .mov:
            return ["video/quicktime"]
        case .mp3:
            return ["audio/mpeg"]
        case .m4a:
            return ["audio/m4a", "audio/mp4"]
        case .aac:
            return ["audio/aac"]
        case .opus:
            return ["audio/opus"]
        case .flac:
            return ["audio/flac"]
        }
    }
}

// MARK: - Subtitle Track

/// Subtitle track information
struct SubtitleTrack: Codable, Identifiable {
    let id: String
    let language: String
    let languageCode: String
    let isAutoGenerated: Bool
    var url: URL?
    var format: SubtitleFormat = .srt
    
    enum SubtitleFormat: String, Codable {
        case srt = "SRT"
        case vtt = "VTT"
        case ass = "ASS"
        case ssa = "SSA"
    }
    
    var displayName: String {
        if isAutoGenerated {
            return "\(language) (Auto-generated)"
        }
        return language
    }
}

// MARK: - Video Metadata

/// Metadata extracted from video platforms
struct VideoMetadata: Codable {
    let title: String
    let description: String?
    let author: String?
    let channelId: String?
    let duration: TimeInterval
    let uploadDate: Date?
    let viewCount: Int?
    let likeCount: Int?
    let thumbnailURL: URL?
    let availableQualities: [VideoQuality]
    let availableSubtitles: [SubtitleTrack]
    let isLiveStream: Bool
    let isPlaylist: Bool
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedViews: String {
        guard let views = viewCount else { return "N/A" }
        
        if views >= 1_000_000 {
            return String(format: "%.1fM views", Double(views) / 1_000_000)
        } else if views >= 1_000 {
            return String(format: "%.1fK views", Double(views) / 1_000)
        }
        return "\(views) views"
    }
}

// MARK: - Playlist Info

/// Playlist information
struct PlaylistInfo: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let author: String?
    let videoCount: Int
    let thumbnailURL: URL?
    var videos: [PlaylistVideo]
    
    struct PlaylistVideo: Codable, Identifiable {
        let id: String
        let url: URL
        let title: String
        let duration: TimeInterval
        let thumbnailURL: URL?
        var position: Int
    }
    
    var totalDuration: TimeInterval {
        videos.reduce(0) { $0 + $1.duration }
    }
    
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Video Download Options

/// Configuration options for video downloads
public struct VideoDownloadOptions: Codable {
    public var quality: VideoQuality
    public var format: VideoFormat
    public var downloadAudio: Bool
    public var downloadSubtitles: Bool
    public var selectedSubtitleLanguages: [String]
    public var embedThumbnail: Bool
    public var convertToFormat: VideoFormat?
    public var extractAudioOnly: Bool
    public var preferredCodec: VideoCodec?
    public var fps: Int?
    public var maxFileSize: Int64?
    public var removeWatermark: Bool
    
    public enum VideoCodec: String, Codable {
        case h264 = "H.264"
        case h265 = "H.265/HEVC"
        case vp9 = "VP9"
        case av1 = "AV1"
    }
    
    public init(
        quality: VideoQuality = .quality1080p,
        format: VideoFormat = .mp4,
        downloadAudio: Bool = true,
        downloadSubtitles: Bool = false,
        selectedSubtitleLanguages: [String] = ["en"],
        embedThumbnail: Bool = true,
        convertToFormat: VideoFormat? = nil,
        extractAudioOnly: Bool = false,
        preferredCodec: VideoCodec? = .h264,
        fps: Int? = nil,
        maxFileSize: Int64? = nil,
        removeWatermark: Bool = false
    ) {
        self.quality = quality
        self.format = format
        self.downloadAudio = downloadAudio
        self.downloadSubtitles = downloadSubtitles
        self.selectedSubtitleLanguages = selectedSubtitleLanguages
        self.embedThumbnail = embedThumbnail
        self.convertToFormat = convertToFormat
        self.extractAudioOnly = extractAudioOnly
        self.preferredCodec = preferredCodec
        self.fps = fps
        self.maxFileSize = maxFileSize
        self.removeWatermark = removeWatermark
    }
    
    public static var `default`: VideoDownloadOptions {
        VideoDownloadOptions(
            quality: .quality1080p,
            format: .mp4,
            downloadAudio: true,
            downloadSubtitles: false,
            selectedSubtitleLanguages: ["en"],
            embedThumbnail: true,
            convertToFormat: nil,
            extractAudioOnly: false,
            preferredCodec: .h264,
            fps: nil,
            maxFileSize: nil,
            removeWatermark: false
        )
    }
    
    public static var audioOnly: VideoDownloadOptions {
        VideoDownloadOptions(
            quality: .best,
            format: .mp3,
            downloadAudio: true,
            downloadSubtitles: false,
            selectedSubtitleLanguages: [],
            embedThumbnail: true,
            convertToFormat: nil,
            extractAudioOnly: true,
            preferredCodec: nil,
            fps: nil,
            maxFileSize: nil,
            removeWatermark: false
        )
    }
    
    public static var highQuality: VideoDownloadOptions {
        VideoDownloadOptions(
            quality: .quality4K,
            format: .mp4,
            downloadAudio: true,
            downloadSubtitles: true,
            selectedSubtitleLanguages: ["en"],
            embedThumbnail: true,
            convertToFormat: nil,
            extractAudioOnly: false,
            preferredCodec: .h265,
            fps: 60,
            maxFileSize: nil,
            removeWatermark: false
        )
    }
}

// MARK: - Video Download Task

/// Represents a video download task
class VideoDownloadTask: Identifiable, ObservableObject, Codable {
    let id: UUID
    let url: URL
    let platform: VideoPlatform
    
    @Published var metadata: VideoMetadata?
    @Published var options: VideoDownloadOptions
    @Published var state: VideoDownloadState
    @Published var progress: Double
    @Published var speed: Int64
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var error: String?
    
    var downloadTask: DownloadTask?
    var playlist: PlaylistInfo?
    var outputURL: URL?
    var showsCompletionDialog: Bool = false
    var postDownloadAction: PostDownloadAction = .none
    /// Private Netscape cookie file supplied by the browser extension. Not
    /// persisted: it is deleted once the capture finishes.
    var cookieFile: URL?
    var destinationFolder: URL?
    /// Browser headers (Referer / User-Agent) for this capture. Manifests on
    /// protected CDNs reject requests that do not carry the page's Referer.
    var httpHeaders: [String: String]?
    /// Page title reported by the browser. Used when the extracted title is
    /// missing or just the stream's quality label ("720p").
    var preferredTitle: String?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    
    enum VideoDownloadState: String, Codable {
        case pending = "Pending"
        case fetchingMetadata = "Fetching Info"
        case ready = "Ready"
        case downloading = "Downloading"
        case paused = "Paused"
        case converting = "Converting"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, url, platform, metadata, options, state
        case progress, speed, error, playlist
        case createdAt, startedAt, completedAt
    }
    
    init(url: URL, options: VideoDownloadOptions = .default) {
        self.id = UUID()
        self.url = url
        self.platform = VideoPlatform.detect(from: url)
        self.options = options
        self.state = .pending
        self.progress = 0.0
        self.speed = 0
        self.createdAt = Date()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        platform = try container.decode(VideoPlatform.self, forKey: .platform)
        metadata = try container.decodeIfPresent(VideoMetadata.self, forKey: .metadata)
        options = try container.decode(VideoDownloadOptions.self, forKey: .options)
        state = try container.decode(VideoDownloadState.self, forKey: .state)
        progress = try container.decode(Double.self, forKey: .progress)
        speed = try container.decode(Int64.self, forKey: .speed)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        playlist = try container.decodeIfPresent(PlaylistInfo.self, forKey: .playlist)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encode(options, forKey: .options)
        try container.encode(state, forKey: .state)
        try container.encode(progress, forKey: .progress)
        try container.encode(speed, forKey: .speed)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(playlist, forKey: .playlist)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
    
    var estimatedTimeRemaining: TimeInterval? {
        // Real byte counts first (works without metadata and updates live).
        if state == .downloading, speed > 0, totalBytes > 0, downloadedBytes <= totalBytes {
            return Double(totalBytes - downloadedBytes) / Double(speed)
        }
        guard state == .downloading || state == .converting,
              progress > 0,
              speed > 0,
              let metadata = metadata else {
            return nil
        }
        
        let remainingProgress = 1.0 - progress
        let estimatedSize = Double(speed) * (metadata.duration / progress)
        let remainingBytes = estimatedSize * remainingProgress
        
        return remainingBytes / Double(speed)
    }
    
    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: speed, countStyle: .file) + "/s"
    }
    
    var formattedETA: String {
        guard let eta = estimatedTimeRemaining else { return "Calculating..." }
        
        let minutes = Int(eta) / 60
        let seconds = Int(eta) % 60
        
        if minutes > 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Video Download Statistics

/// Statistics for video downloads
struct VideoDownloadStatistics: Codable {
    var totalVideosDownloaded: Int
    var totalAudioExtracted: Int
    var totalPlaylistsDownloaded: Int
    var totalDataDownloaded: Int64
    var downloadsByPlatform: [VideoPlatform: Int]
    var downloadsByQuality: [VideoQuality: Int]
    var averageDownloadTime: TimeInterval
    var failureCount: Int
    
    init() {
        totalVideosDownloaded = 0
        totalAudioExtracted = 0
        totalPlaylistsDownloaded = 0
        totalDataDownloaded = 0
        downloadsByPlatform = [:]
        downloadsByQuality = [:]
        averageDownloadTime = 0
        failureCount = 0
    }
    
    mutating func recordSuccess(
        task: VideoDownloadTask,
        bytesDownloaded: Int64,
        duration: TimeInterval
    ) {
        if task.options.extractAudioOnly {
            totalAudioExtracted += 1
        } else {
            totalVideosDownloaded += 1
        }
        
        if task.playlist != nil {
            totalPlaylistsDownloaded += 1
        }
        
        totalDataDownloaded += bytesDownloaded
        
        downloadsByPlatform[task.platform, default: 0] += 1
        downloadsByQuality[task.options.quality, default: 0] += 1
        
        let totalDownloads = totalVideosDownloaded + totalAudioExtracted
        averageDownloadTime = ((averageDownloadTime * Double(totalDownloads - 1)) + duration) / Double(totalDownloads)
    }
    
    mutating func recordFailure() {
        failureCount += 1
    }
    
    var successRate: Double {
        let total = totalVideosDownloaded + totalAudioExtracted + failureCount
        guard total > 0 else { return 0 }
        return Double(totalVideosDownloaded + totalAudioExtracted) / Double(total) * 100
    }
    
    var formattedTotalData: String {
        ByteCountFormatter.string(fromByteCount: totalDataDownloaded, countStyle: .file)
    }
    
    var formattedAverageTime: String {
        let minutes = Int(averageDownloadTime) / 60
        let seconds = Int(averageDownloadTime) % 60
        return "\(minutes)m \(seconds)s"
    }
}
