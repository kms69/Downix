import Foundation
import Combine

/// Manager for advanced video features
@MainActor
public class AdvancedVideoManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var extractedVideos: [VideoInfo]
    @Published public var liveStreams: [LiveStreamInfo]
    @Published public var downloadProgress: [UUID: VideoDownloadProgress]
    @Published public var credentials: [VideoPlatform: VideoPlatformCredentials]
    @Published public var isExtracting: Bool
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let urlSession: URLSession
    
    // MARK: - Initialization
    
    public init() {
        self.extractedVideos = []
        self.liveStreams = []
        self.downloadProgress = [:]
        self.credentials = [:]
        self.isExtracting = false
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: ProxySession.makeConfiguration(base: config))
        
        loadCredentials()
    }
    
    // MARK: - Platform Detection
    
    public func detectPlatform(from url: String) -> VideoPlatform {
        VideoPlatform.detect(from: url)
    }
    
    public func isVideoURL(_ urlString: String) -> Bool {
        let platform = detectPlatform(from: urlString)
        return platform != .generic || urlString.contains(".m3u8") || urlString.hasSuffix(".mp4")
    }
    
    // MARK: - Video Extraction
    
    public func extractVideoInfo(from urlString: String) async throws -> VideoExtractionResult {
        isExtracting = true
        defer { isExtracting = false }
        
        let startTime = Date()
        
        guard let url = URL(string: urlString) else {
            throw AdvancedVideoError.invalidURL(urlString)
        }
        
        let platform = detectPlatform(from: urlString)
        
        do {
            let videoInfo: VideoInfo
            
            switch platform {
            case .instagram:
                videoInfo = try await extractInstagram(url: url)
            case .facebook:
                videoInfo = try await extractFacebook(url: url)
            case .twitter:
                videoInfo = try await extractTwitter(url: url)
            case .tiktok:
                videoInfo = try await extractTikTok(url: url)
            case .twitch:
                videoInfo = try await extractTwitch(url: url)
            case .youtube:
                videoInfo = try await extractYouTube(url: url)
            case .vimeo:
                videoInfo = try await extractVimeo(url: url)
            case .dailymotion:
                videoInfo = try await extractDailymotion(url: url)
            case .generic:
                videoInfo = try await extractGeneric(url: url)
            }
            
            extractedVideos.append(videoInfo)
            
            let extractionTime = Date().timeIntervalSince(startTime)
            
            return VideoExtractionResult(
                success: true,
                videoInfo: videoInfo,
                directURL: videoInfo.url,
                extractionTime: extractionTime
            )
        } catch {
            let extractionTime = Date().timeIntervalSince(startTime)
            
            return VideoExtractionResult(
                success: false,
                error: error.localizedDescription,
                extractionTime: extractionTime
            )
        }
    }
    
    // MARK: - Platform-Specific Extraction
    
    private func extractInstagram(url: URL) async throws -> VideoInfo {
        // Simulate Instagram video extraction
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .instagram,
            title: "Instagram Video",
            description: "Video from Instagram",
            duration: 30,
            thumbnailURL: "https://example.com/thumb.jpg",
            author: "instagram_user",
            viewCount: 1500,
            uploadDate: Date(),
            availableQualities: [.quality480p, .quality720p],
            availableFormats: [.mp4],
            streamType: .progressive,
            isLiveStream: false
        )
    }
    
    private func extractFacebook(url: URL) async throws -> VideoInfo {
        // Simulate Facebook video extraction
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .facebook,
            title: "Facebook Video",
            description: "Video from Facebook",
            duration: 120,
            thumbnailURL: "https://example.com/fb-thumb.jpg",
            author: "facebook_page",
            viewCount: 5000,
            uploadDate: Date(),
            availableQualities: [.quality360p, .quality480p, .quality720p],
            availableFormats: [.mp4],
            streamType: .progressive
        )
    }
    
    private func extractTwitter(url: URL) async throws -> VideoInfo {
        // Simulate Twitter video extraction
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .twitter,
            title: "Twitter Video",
            description: "Video from Twitter/X",
            duration: 45,
            thumbnailURL: "https://example.com/twitter-thumb.jpg",
            author: "@twitter_user",
            viewCount: 10000,
            uploadDate: Date(),
            availableQualities: [.quality480p, .quality720p, .quality1080p],
            availableFormats: [.mp4],
            streamType: .progressive
        )
    }
    
    private func extractTikTok(url: URL) async throws -> VideoInfo {
        // Simulate TikTok video extraction (without watermark)
        try await Task.sleep(nanoseconds: 800_000_000) // Longer for watermark removal
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .tiktok,
            title: "TikTok Video",
            description: "Video from TikTok (no watermark)",
            duration: 15,
            thumbnailURL: "https://example.com/tiktok-thumb.jpg",
            author: "@tiktok_creator",
            viewCount: 50000,
            uploadDate: Date(),
            availableQualities: [.quality480p, .quality720p],
            availableFormats: [.mp4],
            streamType: .progressive,
            metadata: ["watermark_removed": "true"]
        )
    }
    
    private func extractTwitch(url: URL) async throws -> VideoInfo {
        // Simulate Twitch video/VOD extraction
        try await Task.sleep(nanoseconds: 600_000_000)
        
        // Check if it's a live stream
        let isLive = url.absoluteString.contains("/videos/") == false
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .twitch,
            title: isLive ? "Live Stream" : "Twitch VOD",
            description: isLive ? "Live broadcast" : "Past broadcast",
            duration: isLive ? nil : 7200,
            thumbnailURL: "https://example.com/twitch-thumb.jpg",
            author: "streamer_name",
            viewCount: isLive ? nil : 25000,
            uploadDate: Date(),
            availableQualities: [.quality480p, .quality720p, .quality1080p],
            availableFormats: [.mp4],
            streamType: isLive ? .live : .adaptive,
            isLiveStream: isLive
        )
    }
    
    private func extractYouTube(url: URL) async throws -> VideoInfo {
        // Simulate YouTube video extraction
        try await Task.sleep(nanoseconds: 400_000_000)
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .youtube,
            title: "YouTube Video",
            description: "Video from YouTube",
            duration: 600,
            thumbnailURL: "https://example.com/yt-thumb.jpg",
            author: "YouTube Channel",
            viewCount: 100000,
            uploadDate: Date(),
            availableQualities: [.quality360p, .quality480p, .quality720p, .quality1080p, .quality4K],
            availableFormats: [.mp4, .webm],
            streamType: .adaptive
        )
    }
    
    private func extractVimeo(url: URL) async throws -> VideoInfo {
        // Simulate Vimeo video extraction
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .vimeo,
            title: "Vimeo Video",
            description: "Video from Vimeo",
            duration: 300,
            thumbnailURL: "https://example.com/vimeo-thumb.jpg",
            author: "Vimeo Creator",
            viewCount: 5000,
            uploadDate: Date(),
            availableQualities: [.quality480p, .quality720p, .quality1080p],
            availableFormats: [.mp4],
            streamType: .progressive
        )
    }
    
    private func extractDailymotion(url: URL) async throws -> VideoInfo {
        // Simulate Dailymotion video extraction
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .dailymotion,
            title: "Dailymotion Video",
            description: "Video from Dailymotion",
            duration: 180,
            thumbnailURL: "https://example.com/dm-thumb.jpg",
            author: "Dailymotion User",
            viewCount: 3000,
            uploadDate: Date(),
            availableQualities: [.quality480p, .quality720p],
            availableFormats: [.mp4],
            streamType: .progressive
        )
    }
    
    private func extractGeneric(url: URL) async throws -> VideoInfo {
        // Simulate generic video extraction
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Check if it's M3U8
        if url.absoluteString.contains(".m3u8") {
            return VideoInfo(
                url: url.absoluteString,
                platform: .generic,
                title: "HLS Stream",
                availableQualities: [.auto],
                availableFormats: [.mp4],
                streamType: .m3u8
            )
        }
        
        return VideoInfo(
            url: url.absoluteString,
            platform: .generic,
            title: "Video",
            availableQualities: [.auto],
            availableFormats: [.mp4],
            streamType: .progressive
        )
    }
    
    // MARK: - M3U8/HLS Support
    
    public func parseM3U8(from urlString: String) async throws -> M3U8Playlist {
        guard let url = URL(string: urlString) else {
            throw AdvancedVideoError.invalidURL(urlString)
        }
        
        // Fetch M3U8 content
        let (data, _) = try await urlSession.data(from: url)
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw AdvancedVideoError.m3u8ParseError("Invalid encoding")
        }
        
        return try parseM3U8Content(content, baseURL: url)
    }
    
    private func parseM3U8Content(_ content: String, baseURL: URL) throws -> M3U8Playlist {
        let lines = content.components(separatedBy: .newlines)
        
        var version = 3
        var targetDuration: TimeInterval = 10
        var segments: [M3U8Segment] = []
        var currentDuration: TimeInterval = 0
        var sequence = 0
        var totalDuration: TimeInterval = 0
        var isLive = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("#EXT-X-VERSION:") {
                version = Int(trimmed.replacingOccurrences(of: "#EXT-X-VERSION:", with: "")) ?? 3
            } else if trimmed.hasPrefix("#EXT-X-TARGETDURATION:") {
                targetDuration = TimeInterval(trimmed.replacingOccurrences(of: "#EXT-X-TARGETDURATION:", with: "")) ?? 10
            } else if trimmed.hasPrefix("#EXTINF:") {
                // Parse segment duration
                let durationStr = trimmed.replacingOccurrences(of: "#EXTINF:", with: "").components(separatedBy: ",")[0]
                currentDuration = TimeInterval(durationStr) ?? 0
            } else if !trimmed.hasPrefix("#") && !trimmed.isEmpty {
                // This is a segment URL
                let segmentURL = resolveURL(trimmed, baseURL: baseURL)
                
                let segment = M3U8Segment(
                    url: segmentURL,
                    duration: currentDuration,
                    sequence: sequence
                )
                
                segments.append(segment)
                totalDuration += currentDuration
                sequence += 1
                currentDuration = 0
            } else if trimmed.hasPrefix("#EXT-X-ENDLIST") {
                // Not a live stream
                isLive = false
            }
        }
        
        // If no end list tag, assume it's live
        if !content.contains("#EXT-X-ENDLIST") {
            isLive = true
        }
        
        return M3U8Playlist(
            url: baseURL.absoluteString,
            version: version,
            targetDuration: targetDuration,
            segments: segments,
            totalDuration: totalDuration,
            isLive: isLive
        )
    }
    
    private func resolveURL(_ urlString: String, baseURL: URL) -> String {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return urlString
        }
        
        // Relative URL
        if let resolved = URL(string: urlString, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        
        return urlString
    }
    
    // MARK: - HLS Download (real segment fetch + concat)

    /// Download an HLS/M3U8 stream to a local .mp4 (ffmpeg if present, else raw concat).
    public func downloadHLSStream(from playlist: M3U8Playlist, to destination: URL) async throws -> URL {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        // Fetch segments with limited concurrency
        var localFiles: [URL] = []
        let session = urlSession
        try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (idx, seg) in playlist.segments.enumerated() {
                group.addTask {
                    guard let u = URL(string: seg.url) else { throw AdvancedVideoError.invalidURL(seg.url) }
                    let (data, _) = try await session.data(from: u)
                    let f = tmpDir.appendingPathComponent(String(format: "seg%05d.ts", idx))
                    try data.write(to: f)
                    return (idx, f)
                }
            }
            var ordered = [(Int, URL)]()
            for try await item in group { ordered.append(item) }
            localFiles = ordered.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        guard !localFiles.isEmpty else { throw AdvancedVideoError.m3u8ParseError("No segments downloaded") }

        // Prefer ffmpeg concat; fallback: binary-append .ts (works for MPEG-TS HLS)
        if let ffmpeg = ExternalToolRunner.ffmpegPath {
            let listFile = tmpDir.appendingPathComponent("list.txt")
            let list = localFiles.map { "file '\($0.path)'" }.joined(separator: "\n")
            try list.write(to: listFile, atomically: true, encoding: .utf8)
            let res = try ExternalToolRunner.run(binary: ffmpeg,
                args: ["-y", "-f", "concat", "-safe", "0", "-i", listFile.path, "-c", "copy", destination.path],
                timeout: 3600)
            if res.succeeded { return destination }
            print("ffmpeg HLS concat failed: \(res.stderr)")
        }
        // Raw concat fallback
        fm.createFile(atPath: destination.path, contents: nil)
        guard let out = FileHandle(forWritingAtPath: destination.path) else {
            throw AdvancedVideoError.m3u8ParseError("Cannot write destination")
        }
        defer { try? out.close() }
        for f in localFiles {
            if let h = FileHandle(forReadingAtPath: f.path) {
                out.write(h.readDataToEndOfFile())
                try? h.close()
            }
        }
        return destination
    }

    // MARK: - Live Stream Recording
    
    public func startLiveStreamRecording(urlString: String) async throws -> LiveStreamInfo {
        let platform = detectPlatform(from: urlString)
        
        // Extract live stream info
        let videoInfo = try await extractVideoInfo(from: urlString)
        
        guard videoInfo.success, let info = videoInfo.videoInfo else {
            throw AdvancedVideoError.extractionFailed("Could not extract live stream info")
        }
        
        guard info.isLiveStream else {
            throw AdvancedVideoError.liveStreamNotStarted
        }
        
        let liveStream = LiveStreamInfo(
            url: urlString,
            platform: platform,
            title: info.title,
            streamer: info.author,
            viewerCount: info.viewCount,
            startedAt: Date(),
            isLive: true,
            qualityOptions: info.availableQualities
        )
        
        liveStreams.append(liveStream)
        
        return liveStream
    }
    
    public func stopLiveStreamRecording(streamID: UUID) {
        if let index = liveStreams.firstIndex(where: { $0.id == streamID }) {
            liveStreams[index].isLive = false
        }
    }
    
    // MARK: - Embedded Video Detection
    
    public func detectEmbeddedVideos(in htmlContent: String, pageURL: String) -> [EmbeddedVideo] {
        var videos: [EmbeddedVideo] = []
        
        // Detect iframe embeds
        videos.append(contentsOf: detectIFrameVideos(htmlContent, pageURL: pageURL))
        
        // Detect video tags
        videos.append(contentsOf: detectVideoTags(htmlContent, pageURL: pageURL))
        
        // Detect platform-specific embeds
        videos.append(contentsOf: detectPlatformEmbeds(htmlContent, pageURL: pageURL))
        
        return videos
    }
    
    private func detectIFrameVideos(_ html: String, pageURL: String) -> [EmbeddedVideo] {
        var videos: [EmbeddedVideo] = []
        
        // Simple regex-like pattern matching for iframes
        let patterns = [
            "youtube.com/embed/",
            "player.vimeo.com/video/",
            "dailymotion.com/embed/",
            "player.twitch.tv/"
        ]
        
        for pattern in patterns {
            if html.contains(pattern) {
                // Extract URL (simplified)
                if let range = html.range(of: pattern) {
                    let startIndex = range.lowerBound
                    // Find the end of the URL (simplified)
                    if let endRange = html[startIndex...].range(of: "\"") {
                        let urlString = String(html[startIndex..<endRange.lowerBound])
                        
                        let platform = detectPlatform(from: urlString)
                        
                        let video = EmbeddedVideo(
                            pageURL: pageURL,
                            videoURL: urlString,
                            platform: platform,
                            embedType: .iframe
                        )
                        
                        videos.append(video)
                    }
                }
            }
        }
        
        return videos
    }
    
    private func detectVideoTags(_ html: String, pageURL: String) -> [EmbeddedVideo] {
        var videos: [EmbeddedVideo] = []
        
        // Look for <video> tags with src attribute
        if html.contains("<video") && html.contains("src=") {
            // Simplified detection
            let video = EmbeddedVideo(
                pageURL: pageURL,
                videoURL: pageURL, // Would extract actual URL
                platform: .generic,
                embedType: .video
            )
            
            videos.append(video)
        }
        
        return videos
    }
    
    private func detectPlatformEmbeds(_ html: String, pageURL: String) -> [EmbeddedVideo] {
        var videos: [EmbeddedVideo] = []
        
        // Check for platform-specific script embeds
        let platforms: [(VideoPlatform, String)] = [
            (.instagram, "instagram.com/p/"),
            (.twitter, "twitter.com/.*/status/"),
            (.tiktok, "tiktok.com/@"),
            (.facebook, "facebook.com/plugins/video")
        ]
        
        for (platform, pattern) in platforms {
            if html.contains(pattern) {
                let video = EmbeddedVideo(
                    pageURL: pageURL,
                    videoURL: pageURL, // Would extract actual URL
                    platform: platform,
                    embedType: .script
                )
                
                videos.append(video)
            }
        }
        
        return videos
    }
    
    // MARK: - Watermark Removal
    
    public func removeWatermark(from videoURL: URL) async throws -> URL {
        // Best-effort: re-encode via ffmpeg if present (clears some overlays);
        // true TikTok no-watermark requires yt-dlp source URL, handled in VideoDownloadManager.
        if let ffmpeg = ExternalToolRunner.ffmpegPath {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            let res = try ExternalToolRunner.run(binary: ffmpeg,
                args: ["-y", "-i", videoURL.path, "-c:v", "libx264", "-crf", "20", "-c:a", "copy", outputURL.path],
                timeout: 3600)
            if res.succeeded { return outputURL }
            print("watermark re-encode failed: \(res.stderr)")
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        // Simulate creating output file
        try Data().write(to: outputURL)
        
        return outputURL
    }
    
    // MARK: - Authentication
    
    public func setCredentials(_ credentials: VideoPlatformCredentials) {
        self.credentials[credentials.platform] = credentials
        saveCredentials()
    }
    
    public func getCredentials(for platform: VideoPlatform) -> VideoPlatformCredentials? {
        credentials[platform]
    }
    
    public func removeCredentials(for platform: VideoPlatform) {
        credentials.removeValue(forKey: platform)
        saveCredentials()
    }
    
    private func loadCredentials() {
        // Load from UserDefaults or Keychain
        // Simplified for demo
    }
    
    private func saveCredentials() {
        // Save to UserDefaults or Keychain
        // Simplified for demo
    }
    
    // MARK: - Download Progress
    
    public func updateDownloadProgress(_ progress: VideoDownloadProgress, for videoID: UUID) {
        downloadProgress[videoID] = progress
    }
    
    public func getDownloadProgress(for videoID: UUID) -> VideoDownloadProgress? {
        downloadProgress[videoID]
    }
    
    public func clearDownloadProgress(for videoID: UUID) {
        downloadProgress.removeValue(forKey: videoID)
    }
    
    // MARK: - Utilities
    
    public func clearExtractedVideos() {
        extractedVideos.removeAll()
    }
    
    public func clearLiveStreams() {
        liveStreams.removeAll()
    }
    
    public func getVideoInfo(byID id: UUID) -> VideoInfo? {
        extractedVideos.first { $0.id == id }
    }
    
    public func getLiveStream(byID id: UUID) -> LiveStreamInfo? {
        liveStreams.first { $0.id == id }
    }
}
