import XCTest
@testable import DownloadManager

@MainActor
final class AdvancedVideoTests: XCTestCase {
    
    var manager: AdvancedVideoManager!
    
    override func setUp() async throws {
        manager = AdvancedVideoManager()
    }
    
    override func tearDown() async throws {
        manager = nil
    }
    
    // MARK: - Video Platform Tests
    
    func testVideoPlatformDetection() {
        XCTAssertEqual(VideoPlatform.detect(from: "https://youtube.com/watch?v=123"), .youtube)
        XCTAssertEqual(VideoPlatform.detect(from: "https://youtu.be/abc"), .youtube)
        XCTAssertEqual(VideoPlatform.detect(from: "https://instagram.com/p/abc"), .instagram)
        XCTAssertEqual(VideoPlatform.detect(from: "https://facebook.com/video"), .facebook)
        XCTAssertEqual(VideoPlatform.detect(from: "https://twitter.com/user/status/123"), .twitter)
        XCTAssertEqual(VideoPlatform.detect(from: "https://x.com/user/status/123"), .twitter)
        XCTAssertEqual(VideoPlatform.detect(from: "https://tiktok.com/@user/video/123"), .tiktok)
        XCTAssertEqual(VideoPlatform.detect(from: "https://twitch.tv/streamer"), .twitch)
        XCTAssertEqual(VideoPlatform.detect(from: "https://vimeo.com/123456"), .vimeo)
        XCTAssertEqual(VideoPlatform.detect(from: "https://dailymotion.com/video/x123"), .dailymotion)
        XCTAssertEqual(VideoPlatform.detect(from: "https://example.com/video.mp4"), .generic)
    }
    
    func testVideoPlatformDisplayNames() {
        XCTAssertEqual(VideoPlatform.youtube.displayName, "YouTube")
        XCTAssertEqual(VideoPlatform.instagram.displayName, "Instagram")
        XCTAssertEqual(VideoPlatform.facebook.displayName, "Facebook")
        XCTAssertEqual(VideoPlatform.twitter.displayName, "Twitter")
        XCTAssertEqual(VideoPlatform.tiktok.displayName, "TikTok")
        XCTAssertEqual(VideoPlatform.twitch.displayName, "Twitch")
        XCTAssertEqual(VideoPlatform.vimeo.displayName, "Vimeo")
        XCTAssertEqual(VideoPlatform.dailymotion.displayName, "Dailymotion")
        XCTAssertEqual(VideoPlatform.generic.displayName, "Generic")
    }
    
    func testVideoPlatformIcons() {
        XCTAssertEqual(VideoPlatform.youtube.icon, "play.rectangle.fill")
        XCTAssertEqual(VideoPlatform.instagram.icon, "camera.fill")
        XCTAssertEqual(VideoPlatform.facebook.icon, "f.circle.fill")
        XCTAssertEqual(VideoPlatform.twitter.icon, "bird.fill")
        XCTAssertEqual(VideoPlatform.tiktok.icon, "music.note")
        XCTAssertEqual(VideoPlatform.twitch.icon, "tv.fill")
    }
    
    func testVideoPlatformURLPatterns() {
        XCTAssertTrue(VideoPlatform.youtube.urlPatterns.contains("youtube.com"))
        XCTAssertTrue(VideoPlatform.youtube.urlPatterns.contains("youtu.be"))
        XCTAssertTrue(VideoPlatform.instagram.urlPatterns.contains("instagram.com"))
        XCTAssertTrue(VideoPlatform.facebook.urlPatterns.contains("facebook.com"))
        XCTAssertTrue(VideoPlatform.twitter.urlPatterns.contains("twitter.com"))
    }
    
    // MARK: - Video Quality Tests
    
    func testVideoQualityDisplayNames() {
        XCTAssertEqual(VideoQuality.auto.displayName, "Auto")
        XCTAssertEqual(VideoQuality.quality360p.displayName, "360p")
        XCTAssertEqual(VideoQuality.quality480p.displayName, "480p")
        XCTAssertEqual(VideoQuality.quality720p.displayName, "720p")
        XCTAssertEqual(VideoQuality.quality1080p.displayName, "1080p")
        XCTAssertEqual(VideoQuality.quality2K.displayName, "1440p")
        XCTAssertEqual(VideoQuality.quality4K.displayName, "4K")
        XCTAssertEqual(VideoQuality.uhd8k.displayName, "8K")
    }
    
    func testVideoQualityHeight() {
        XCTAssertNil(VideoQuality.auto.height)
        XCTAssertEqual(VideoQuality.quality360p.height, 360)
        XCTAssertEqual(VideoQuality.quality480p.height, 480)
        XCTAssertEqual(VideoQuality.quality720p.height, 720)
        XCTAssertEqual(VideoQuality.quality1080p.height, 1080)
        XCTAssertEqual(VideoQuality.quality2K.height, 1440)
        XCTAssertEqual(VideoQuality.quality4K.height, 2160)
        XCTAssertEqual(VideoQuality.uhd8k.height, 4320)
    }
    
    // MARK: - Video Format Tests
    
    func testVideoFormatDisplayNames() {
        XCTAssertEqual(VideoFormat.mp4.displayName, "MP4")
        XCTAssertEqual(VideoFormat.webm.displayName, "WebM")
        XCTAssertEqual(VideoFormat.mov.displayName, "MOV")
        XCTAssertEqual(VideoFormat.avi.displayName, "AVI")
        XCTAssertEqual(VideoFormat.mkv.displayName, "MKV")
    }
    
    func testVideoFormatExtensions() {
        XCTAssertEqual(VideoFormat.mp4.fileExtension, "mp4")
        XCTAssertEqual(VideoFormat.webm.fileExtension, "webm")
        XCTAssertEqual(VideoFormat.mov.fileExtension, "mov")
        XCTAssertEqual(VideoFormat.avi.fileExtension, "avi")
        XCTAssertEqual(VideoFormat.mkv.fileExtension, "mkv")
    }
    
    func testVideoFormatMimeTypes() {
        XCTAssertTrue(VideoFormat.mp4.mimeTypes.contains("video/mp4"))
        XCTAssertTrue(VideoFormat.webm.mimeTypes.contains("video/webm"))
        XCTAssertTrue(VideoFormat.mov.mimeTypes.contains("video/quicktime"))
        XCTAssertTrue(VideoFormat.avi.mimeTypes.contains("video/x-msvideo"))
        XCTAssertTrue(VideoFormat.mkv.mimeTypes.contains("video/x-matroska"))
    }
    
    // MARK: - Stream Type Tests
    
    func testStreamTypeDisplayNames() {
        XCTAssertEqual(StreamType.progressive.displayName, "Progressive")
        XCTAssertEqual(StreamType.adaptive.displayName, "Adaptive (HLS/DASH)")
        XCTAssertEqual(StreamType.live.displayName, "Live Stream")
        XCTAssertEqual(StreamType.m3u8.displayName, "M3U8 Playlist")
    }
    
    func testStreamTypeIcons() {
        XCTAssertEqual(StreamType.progressive.icon, "arrow.down.circle")
        XCTAssertEqual(StreamType.adaptive.icon, "waveform.path")
        XCTAssertEqual(StreamType.live.icon, "record.circle")
        XCTAssertEqual(StreamType.m3u8.icon, "list.bullet")
    }
    
    // MARK: - Video Info Tests
    
    func testVideoInfoCreation() {
        let video = VideoInfo(
            url: "https://example.com/video",
            platform: .youtube,
            title: "Test Video",
            description: "Test Description",
            duration: 600,
            author: "Test Author",
            viewCount: 10000,
            availableQualities: [.quality720p, .quality1080p],
            availableFormats: [.mp4]
        )
        
        XCTAssertEqual(video.url, "https://example.com/video")
        XCTAssertEqual(video.platform, .youtube)
        XCTAssertEqual(video.title, "Test Video")
        XCTAssertEqual(video.description, "Test Description")
        XCTAssertEqual(video.duration, 600)
        XCTAssertEqual(video.author, "Test Author")
        XCTAssertEqual(video.viewCount, 10000)
        XCTAssertEqual(video.availableQualities.count, 2)
        XCTAssertEqual(video.availableFormats.count, 1)
    }
    
    func testVideoInfoFormattedDuration() {
        let video1 = VideoInfo(url: "test", platform: .youtube, duration: 125)
        XCTAssertEqual(video1.formattedDuration, "2:05")
        
        let video2 = VideoInfo(url: "test", platform: .youtube, duration: 3665)
        XCTAssertEqual(video2.formattedDuration, "1:01:05")
        
        let video3 = VideoInfo(url: "test", platform: .youtube, duration: 45)
        XCTAssertEqual(video3.formattedDuration, "0:45")
        
        let video4 = VideoInfo(url: "test", platform: .youtube)
        XCTAssertNil(video4.formattedDuration)
    }
    
    func testVideoInfoFormattedViewCount() {
        let video1 = VideoInfo(url: "test", platform: .youtube, viewCount: 500)
        XCTAssertEqual(video1.formattedViewCount, "500 views")
        
        let video2 = VideoInfo(url: "test", platform: .youtube, viewCount: 5000)
        XCTAssertEqual(video2.formattedViewCount, "5.0K views")
        
        let video3 = VideoInfo(url: "test", platform: .youtube, viewCount: 1500000)
        XCTAssertEqual(video3.formattedViewCount, "1.5M views")
        
        let video4 = VideoInfo(url: "test", platform: .youtube)
        XCTAssertNil(video4.formattedViewCount)
    }
    
    func testVideoInfoCodable() throws {
        let video = VideoInfo(
            url: "https://example.com/video",
            platform: .youtube,
            title: "Test Video",
            duration: 600
        )
        
        let data = try JSONEncoder().encode(video)
        let decoded = try JSONDecoder().decode(VideoInfo.self, from: data)
        
        XCTAssertEqual(decoded.url, video.url)
        XCTAssertEqual(decoded.platform, video.platform)
        XCTAssertEqual(decoded.title, video.title)
        XCTAssertEqual(decoded.duration, video.duration)
    }
    
    // MARK: - Video Download Options Tests
    
    func testVideoDownloadOptionsDefault() {
        let options = VideoDownloadOptions()
        
        XCTAssertEqual(options.quality, .auto)
        XCTAssertEqual(options.format, .mp4)
        XCTAssertTrue(options.downloadAudio)
        XCTAssertFalse(options.downloadSubtitles)
        XCTAssertFalse(options.removeWatermark)
        XCTAssertNil(options.convertToFormat)
        XCTAssertNil(options.maxFileSize)
    }
    
    func testVideoDownloadOptionsCodable() throws {
        let options = VideoDownloadOptions(
            quality: .quality1080p,
            format: .mp4,
            downloadAudio: true,
            downloadSubtitles: true,
            removeWatermark: true,
            convertToFormat: .mov,
            maxFileSize: 1_000_000_000
        )
        
        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(VideoDownloadOptions.self, from: data)
        
        XCTAssertEqual(decoded.quality, options.quality)
        XCTAssertEqual(decoded.format, options.format)
        XCTAssertEqual(decoded.downloadAudio, options.downloadAudio)
        XCTAssertEqual(decoded.downloadSubtitles, options.downloadSubtitles)
        XCTAssertEqual(decoded.removeWatermark, options.removeWatermark)
        XCTAssertEqual(decoded.convertToFormat, options.convertToFormat)
        XCTAssertEqual(decoded.maxFileSize, options.maxFileSize)
    }
    
    // MARK: - M3U8 Tests
    
    func testM3U8SegmentCreation() {
        let segment = M3U8Segment(
            url: "https://example.com/segment.ts",
            duration: 10.0,
            sequence: 0
        )
        
        XCTAssertEqual(segment.url, "https://example.com/segment.ts")
        XCTAssertEqual(segment.duration, 10.0)
        XCTAssertEqual(segment.sequence, 0)
        XCTAssertNil(segment.byteRange)
    }
    
    func testM3U8PlaylistCreation() {
        let segments = [
            M3U8Segment(url: "seg1.ts", duration: 10, sequence: 0),
            M3U8Segment(url: "seg2.ts", duration: 10, sequence: 1),
            M3U8Segment(url: "seg3.ts", duration: 10, sequence: 2)
        ]
        
        let playlist = M3U8Playlist(
            url: "https://example.com/playlist.m3u8",
            version: 3,
            targetDuration: 10,
            segments: segments,
            totalDuration: 30,
            isLive: false
        )
        
        XCTAssertEqual(playlist.url, "https://example.com/playlist.m3u8")
        XCTAssertEqual(playlist.version, 3)
        XCTAssertEqual(playlist.targetDuration, 10)
        XCTAssertEqual(playlist.segments.count, 3)
        XCTAssertEqual(playlist.totalDuration, 30)
        XCTAssertEqual(playlist.segmentCount, 3)
        XCTAssertFalse(playlist.isLive)
    }
    
    func testM3U8PlaylistCodable() throws {
        let playlist = M3U8Playlist(
            url: "https://example.com/playlist.m3u8",
            segments: [],
            totalDuration: 100
        )
        
        let data = try JSONEncoder().encode(playlist)
        let decoded = try JSONDecoder().decode(M3U8Playlist.self, from: data)
        
        XCTAssertEqual(decoded.url, playlist.url)
        XCTAssertEqual(decoded.totalDuration, playlist.totalDuration)
    }
    
    // MARK: - Live Stream Info Tests
    
    func testLiveStreamInfoCreation() {
        let stream = LiveStreamInfo(
            url: "https://twitch.tv/streamer",
            platform: .twitch,
            title: "Live Stream",
            streamer: "Streamer Name",
            viewerCount: 1000,
            startedAt: Date(),
            isLive: true
        )
        
        XCTAssertEqual(stream.url, "https://twitch.tv/streamer")
        XCTAssertEqual(stream.platform, .twitch)
        XCTAssertEqual(stream.title, "Live Stream")
        XCTAssertEqual(stream.streamer, "Streamer Name")
        XCTAssertEqual(stream.viewerCount, 1000)
        XCTAssertTrue(stream.isLive)
    }
    
    func testLiveStreamFormattedViewerCount() {
        let stream1 = LiveStreamInfo(url: "test", platform: .twitch, viewerCount: 500)
        XCTAssertEqual(stream1.formattedViewerCount, "500 watching")
        
        let stream2 = LiveStreamInfo(url: "test", platform: .twitch, viewerCount: 5000)
        XCTAssertEqual(stream2.formattedViewerCount, "5.0K watching")
        
        let stream3 = LiveStreamInfo(url: "test", platform: .twitch, viewerCount: 1500000)
        XCTAssertEqual(stream3.formattedViewerCount, "1.5M watching")
        
        let stream4 = LiveStreamInfo(url: "test", platform: .twitch)
        XCTAssertNil(stream4.formattedViewerCount)
    }
    
    func testLiveStreamDuration() {
        let startTime = Date().addingTimeInterval(-300) // 5 minutes ago
        let stream = LiveStreamInfo(url: "test", platform: .twitch, startedAt: startTime)
        
        guard let duration = stream.streamDuration else {
            XCTFail("Stream duration should not be nil")
            return
        }
        
        XCTAssertGreaterThan(duration, 0)
        XCTAssertLessThanOrEqual(duration, 301) // Allow 1 second tolerance
    }
    
    func testLiveStreamInfoCodable() throws {
        let stream = LiveStreamInfo(
            url: "https://twitch.tv/streamer",
            platform: .twitch,
            title: "Test Stream"
        )
        
        let data = try JSONEncoder().encode(stream)
        let decoded = try JSONDecoder().decode(LiveStreamInfo.self, from: data)
        
        XCTAssertEqual(decoded.url, stream.url)
        XCTAssertEqual(decoded.platform, stream.platform)
        XCTAssertEqual(decoded.title, stream.title)
    }
    
    // MARK: - Embedded Video Tests
    
    func testEmbeddedVideoCreation() {
        let embedded = EmbeddedVideo(
            pageURL: "https://example.com/page",
            videoURL: "https://youtube.com/embed/abc123",
            platform: .youtube,
            title: "Embedded Video",
            embedType: .iframe
        )
        
        XCTAssertEqual(embedded.pageURL, "https://example.com/page")
        XCTAssertEqual(embedded.videoURL, "https://youtube.com/embed/abc123")
        XCTAssertEqual(embedded.platform, .youtube)
        XCTAssertEqual(embedded.title, "Embedded Video")
        XCTAssertEqual(embedded.embedType, .iframe)
    }
    
    func testEmbedTypeDisplayNames() {
        XCTAssertEqual(EmbeddedVideo.EmbedType.iframe.displayName, "iFrame")
        XCTAssertEqual(EmbeddedVideo.EmbedType.video.displayName, "Video Tag")
        XCTAssertEqual(EmbeddedVideo.EmbedType.object.displayName, "Object/Embed")
        XCTAssertEqual(EmbeddedVideo.EmbedType.script.displayName, "Script")
    }
    
    // MARK: - Video Extraction Result Tests
    
    func testVideoExtractionResultSuccess() {
        let video = VideoInfo(url: "test", platform: .youtube)
        let result = VideoExtractionResult(
            success: true,
            videoInfo: video,
            directURL: "https://example.com/video.mp4",
            extractionTime: 0.5
        )
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.directURL, "https://example.com/video.mp4")
        XCTAssertNil(result.error)
        XCTAssertEqual(result.extractionTime, 0.5)
    }
    
    func testVideoExtractionResultFailure() {
        let result = VideoExtractionResult(
            success: false,
            error: "Extraction failed",
            extractionTime: 0.2
        )
        
        XCTAssertFalse(result.success)
        XCTAssertNil(result.videoInfo)
        XCTAssertEqual(result.error, "Extraction failed")
        XCTAssertEqual(result.extractionTime, 0.2)
    }
    
    // MARK: - Video Download Progress Tests
    
    func testVideoDownloadProgressCreation() {
        let progress = VideoDownloadProgress(
            videoPlatform: .youtube,
            currentSegment: 5,
            totalSegments: 10,
            bytesDownloaded: 5_000_000,
            totalBytes: 10_000_000,
            speed: 1_000_000,
            timeRemaining: 5
        )
        
        XCTAssertEqual(progress.videoPlatform, .youtube)
        XCTAssertEqual(progress.currentSegment, 5)
        XCTAssertEqual(progress.totalSegments, 10)
        XCTAssertEqual(progress.bytesDownloaded, 5_000_000)
        XCTAssertEqual(progress.totalBytes, 10_000_000)
        XCTAssertEqual(progress.speed, 1_000_000)
        XCTAssertEqual(progress.timeRemaining, 5)
    }
    
    func testVideoDownloadProgressCalculations() {
        let progress = VideoDownloadProgress(
            videoPlatform: .youtube,
            currentSegment: 5,
            totalSegments: 10,
            bytesDownloaded: 5_000_000,
            totalBytes: 10_000_000
        )
        
        XCTAssertEqual(progress.segmentProgress, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.byteProgress, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.overallProgress, 0.5, accuracy: 0.01)
    }
    
    // MARK: - Video Platform Credentials Tests
    
    func testVideoPlatformCredentialsCreation() {
        let expiry = Date().addingTimeInterval(3600)
        let credentials = VideoPlatformCredentials(
            platform: .youtube,
            username: "testuser",
            accessToken: "token123",
            refreshToken: "refresh456",
            expiresAt: expiry,
            cookies: ["session": "abc123"]
        )
        
        XCTAssertEqual(credentials.platform, .youtube)
        XCTAssertEqual(credentials.username, "testuser")
        XCTAssertEqual(credentials.accessToken, "token123")
        XCTAssertEqual(credentials.refreshToken, "refresh456")
        XCTAssertEqual(credentials.expiresAt, expiry)
        XCTAssertEqual(credentials.cookies["session"], "abc123")
        XCTAssertFalse(credentials.isExpired)
    }
    
    func testVideoPlatformCredentialsExpiry() {
        let expiredDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let credentials = VideoPlatformCredentials(
            platform: .youtube,
            expiresAt: expiredDate
        )
        
        XCTAssertTrue(credentials.isExpired)
    }
    
    // MARK: - Advanced Video Error Tests
    
    func testAdvancedVideoErrorDescriptions() {
        XCTAssertNotNil(AdvancedVideoError.unsupportedPlatform("Test").errorDescription)
        XCTAssertNotNil(AdvancedVideoError.extractionFailed("reason").errorDescription)
        XCTAssertNotNil(AdvancedVideoError.invalidURL("url").errorDescription)
        XCTAssertNotNil(AdvancedVideoError.videoNotFound.errorDescription)
        XCTAssertNotNil(AdvancedVideoError.authenticationRequired(.youtube).errorDescription)
        XCTAssertNotNil(AdvancedVideoError.geoRestricted("US").errorDescription)
        XCTAssertNotNil(AdvancedVideoError.ageRestricted.errorDescription)
        XCTAssertNotNil(AdvancedVideoError.privateVideo.errorDescription)
        XCTAssertNotNil(AdvancedVideoError.liveStreamNotStarted.errorDescription)
        XCTAssertNotNil(AdvancedVideoError.liveStreamEnded.errorDescription)
        XCTAssertNotNil(AdvancedVideoError.m3u8ParseError("reason").errorDescription)
        XCTAssertNotNil(AdvancedVideoError.watermarkRemovalFailed.errorDescription)
        XCTAssertNotNil(AdvancedVideoError.conversionFailed("reason").errorDescription)
    }
    
    // MARK: - Manager Tests
    
    func testManagerInitialization() {
        XCTAssertNotNil(manager)
        XCTAssertEqual(manager.extractedVideos.count, 0)
        XCTAssertEqual(manager.liveStreams.count, 0)
        XCTAssertEqual(manager.downloadProgress.count, 0)
        XCTAssertFalse(manager.isExtracting)
    }
    
    func testManagerDetectPlatform() {
        XCTAssertEqual(manager.detectPlatform(from: "https://youtube.com/watch"), .youtube)
        XCTAssertEqual(manager.detectPlatform(from: "https://instagram.com/p/123"), .instagram)
        XCTAssertEqual(manager.detectPlatform(from: "https://example.com/video.mp4"), .generic)
    }
    
    func testManagerIsVideoURL() {
        XCTAssertTrue(manager.isVideoURL("https://youtube.com/watch?v=123"))
        XCTAssertTrue(manager.isVideoURL("https://instagram.com/p/abc"))
        XCTAssertTrue(manager.isVideoURL("https://example.com/video.m3u8"))
        XCTAssertTrue(manager.isVideoURL("https://example.com/video.mp4"))
    }
    
    func testManagerExtractInstagram() async throws {
        let result = try await manager.extractVideoInfo(from: "https://instagram.com/p/test123")
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.videoInfo?.platform, .instagram)
        XCTAssertGreaterThan(result.extractionTime, 0)
    }
    
    func testManagerExtractFacebook() async throws {
        let result = try await manager.extractVideoInfo(from: "https://facebook.com/video/123")
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.videoInfo?.platform, .facebook)
    }
    
    func testManagerExtractTwitter() async throws {
        let result = try await manager.extractVideoInfo(from: "https://twitter.com/user/status/123")
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.videoInfo?.platform, .twitter)
    }
    
    func testManagerExtractTikTok() async throws {
        let result = try await manager.extractVideoInfo(from: "https://tiktok.com/@user/video/123")
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.videoInfo?.platform, .tiktok)
        
        // Check watermark removal metadata
        XCTAssertEqual(result.videoInfo?.metadata["watermark_removed"], "true")
    }
    
    func testManagerExtractYouTube() async throws {
        let result = try await manager.extractVideoInfo(from: "https://youtube.com/watch?v=abc123")
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.videoInfo?.platform, .youtube)
    }
    
    func testManagerExtractTwitch() async throws {
        let result = try await manager.extractVideoInfo(from: "https://twitch.tv/streamer")
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.videoInfo?.platform, .twitch)
    }
    
    func testManagerExtractVimeo() async throws {
        let result = try await manager.extractVideoInfo(from: "https://vimeo.com/123456")
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.videoInfo?.platform, .vimeo)
    }
    
    func testManagerExtractDailymotion() async throws {
        let result = try await manager.extractVideoInfo(from: "https://dailymotion.com/video/x123")
        
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.videoInfo)
        XCTAssertEqual(result.videoInfo?.platform, .dailymotion)
    }
    
    func testManagerInvalidURL() async {
        do {
            _ = try await manager.extractVideoInfo(from: "not a valid url")
            XCTFail("Should throw error for invalid URL")
        } catch {
            XCTAssertTrue(error is AdvancedVideoError)
        }
    }
    
    func testManagerExtractedVideosStorage() async throws {
        let initialCount = manager.extractedVideos.count
        
        _ = try await manager.extractVideoInfo(from: "https://youtube.com/watch?v=123")
        
        XCTAssertEqual(manager.extractedVideos.count, initialCount + 1)
    }
    
    func testManagerClearExtractedVideos() async throws {
        _ = try await manager.extractVideoInfo(from: "https://youtube.com/watch?v=123")
        
        XCTAssertGreaterThan(manager.extractedVideos.count, 0)
        
        manager.clearExtractedVideos()
        
        XCTAssertEqual(manager.extractedVideos.count, 0)
    }
    
    func testManagerCredentials() {
        let credentials = VideoPlatformCredentials(
            platform: .youtube,
            username: "testuser",
            accessToken: "token123"
        )
        
        manager.setCredentials(credentials)
        
        let retrieved = manager.getCredentials(for: .youtube)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.username, "testuser")
        
        manager.removeCredentials(for: .youtube)
        
        let removed = manager.getCredentials(for: .youtube)
        XCTAssertNil(removed)
    }
    
    func testManagerDownloadProgress() {
        let videoID = UUID()
        let progress = VideoDownloadProgress(
            videoPlatform: .youtube,
            currentSegment: 1,
            totalSegments: 10
        )
        
        manager.updateDownloadProgress(progress, for: videoID)
        
        let retrieved = manager.getDownloadProgress(for: videoID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.currentSegment, 1)
        
        manager.clearDownloadProgress(for: videoID)
        
        let cleared = manager.getDownloadProgress(for: videoID)
        XCTAssertNil(cleared)
    }
    
    func testManagerEmbeddedVideoDetection() {
        let html = """
        <html>
        <iframe src="https://youtube.com/embed/abc123"></iframe>
        <iframe src="https://player.vimeo.com/video/456789"></iframe>
        </html>
        """
        
        let videos = manager.detectEmbeddedVideos(in: html, pageURL: "https://example.com")
        
        XCTAssertGreaterThan(videos.count, 0)
    }
    
    func testManagerGetVideoInfoByID() async throws {
        let result = try await manager.extractVideoInfo(from: "https://youtube.com/watch?v=123")
        
        guard let videoID = result.videoInfo?.id else {
            XCTFail("Video info should have an ID")
            return
        }
        
        let retrieved = manager.getVideoInfo(byID: videoID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, videoID)
    }
}
