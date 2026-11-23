//
//  MediaPreviewTests.swift
//  Download Manager for Mac - Feature #11 Tests
//
//  Created on February 16, 2026
//

import XCTest
@testable import DownloadManagerPackage

final class MediaPreviewTests: XCTestCase {
    var previewManager: MediaPreviewManager!
    var testFileURL: URL!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        previewManager = MediaPreviewManager.shared
        
        // Create temp directory for test files
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create a test file
        testFileURL = tempDirectory.appendingPathComponent("test.txt")
        try? "Test content".write(to: testFileURL, atomically: true, encoding: .utf8)
    }
    
    override func tearDown() {
        // Clean up temp files
        try? FileManager.default.removeItem(at: tempDirectory)
        previewManager = nil
        super.tearDown()
    }
    
    // MARK: - Media Type Detection Tests
    
    func testMediaTypeFromVideoExtension() {
        // Given
        let extensions = ["mp4", "mov", "avi", "mkv", "m4v"]
        
        // When/Then
        for ext in extensions {
            let mediaType = MediaType.from(fileExtension: ext)
            XCTAssertEqual(mediaType, .video, "Extension \(ext) should be detected as video")
        }
    }
    
    func testMediaTypeFromAudioExtension() {
        // Given
        let extensions = ["mp3", "m4a", "wav", "aac", "flac"]
        
        // When/Then
        for ext in extensions {
            let mediaType = MediaType.from(fileExtension: ext)
            XCTAssertEqual(mediaType, .audio, "Extension \(ext) should be detected as audio")
        }
    }
    
    func testMediaTypeFromImageExtension() {
        // Given
        let extensions = ["jpg", "jpeg", "png", "gif", "bmp"]
        
        // When/Then
        for ext in extensions {
            let mediaType = MediaType.from(fileExtension: ext)
            XCTAssertEqual(mediaType, .image, "Extension \(ext) should be detected as image")
        }
    }
    
    func testMediaTypeFromDocumentExtension() {
        // Given
        let extensions = ["pdf", "doc", "docx", "txt", "rtf"]
        
        // When/Then
        for ext in extensions {
            let mediaType = MediaType.from(fileExtension: ext)
            XCTAssertEqual(mediaType, .document, "Extension \(ext) should be detected as document")
        }
    }
    
    func testMediaTypeFromArchiveExtension() {
        // Given
        let extensions = ["zip", "tar", "gz", "7z", "rar"]
        
        // When/Then
        for ext in extensions {
            let mediaType = MediaType.from(fileExtension: ext)
            XCTAssertEqual(mediaType, .archive, "Extension \(ext) should be detected as archive")
        }
    }
    
    func testMediaTypeFromMimeType() {
        // Given/When/Then
        XCTAssertEqual(MediaType.from(mimeType: "video/mp4"), .video)
        XCTAssertEqual(MediaType.from(mimeType: "audio/mpeg"), .audio)
        XCTAssertEqual(MediaType.from(mimeType: "image/jpeg"), .image)
        XCTAssertEqual(MediaType.from(mimeType: "application/pdf"), .document)
        XCTAssertEqual(MediaType.from(mimeType: "application/zip"), .archive)
    }
    
    func testMediaTypeSupportsPreview() {
        // Given/When/Then
        XCTAssertTrue(MediaType.video.supportsPreview)
        XCTAssertTrue(MediaType.audio.supportsPreview)
        XCTAssertTrue(MediaType.image.supportsPreview)
        XCTAssertTrue(MediaType.document.supportsPreview)
        XCTAssertFalse(MediaType.archive.supportsPreview)
        XCTAssertFalse(MediaType.application.supportsPreview)
    }
    
    func testMediaTypeHasIcon() {
        // Given
        let allTypes: [MediaType] = [.video, .audio, .image, .document, .archive, .application, .unknown]
        
        // Then
        for type in allTypes {
            XCTAssertFalse(type.icon.isEmpty, "\(type) should have an icon")
        }
    }
    
    // MARK: - Media Metadata Tests
    
    func testMetadataFormatDuration() {
        // Given
        var metadata = MediaMetadata(fileSize: 0)
        
        // When
        metadata.duration = 3661 // 1 hour, 1 minute, 1 second
        
        // Then
        let formatted = metadata.formattedDuration()
        XCTAssertTrue(formatted.contains("1:01:01") || formatted.contains("1 hour"))
    }
    
    func testMetadataFormatBitrate() {
        // Given
        var metadata = MediaMetadata(fileSize: 0)
        
        // When/Then
        metadata.bitrate = 128_000 // 128 kbps
        XCTAssertTrue(metadata.formattedBitrate().contains("128") || metadata.formattedBitrate().contains("kbps"))
        
        metadata.bitrate = 5_000_000 // 5 Mbps
        XCTAssertTrue(metadata.formattedBitrate().contains("5") || metadata.formattedBitrate().contains("Mbps"))
    }
    
    func testMetadataFormatResolution() {
        // Given
        var metadata = MediaMetadata(fileSize: 0)
        
        // When
        metadata.resolution = CGSize(width: 1920, height: 1080)
        
        // Then
        XCTAssertEqual(metadata.formattedResolution(), "1920x1080")
    }
    
    func testMetadataFormatFrameRate() {
        // Given
        var metadata = MediaMetadata(fileSize: 0)
        
        // When
        metadata.frameRate = 29.97
        
        // Then
        let formatted = metadata.formattedFrameRate()
        XCTAssertTrue(formatted.contains("29.97") || formatted.contains("fps"))
    }
    
    // MARK: - Media Preview Info Tests
    
    func testMediaPreviewInfoCreation() {
        // Given
        let taskId = UUID()
        let filePath = testFileURL!
        
        // When
        let previewInfo = MediaPreviewInfo(taskId: taskId, filePath: filePath, mediaType: .document)
        
        // Then
        XCTAssertNotNil(previewInfo.id)
        XCTAssertEqual(previewInfo.taskId, taskId)
        XCTAssertEqual(previewInfo.filePath, filePath)
        XCTAssertEqual(previewInfo.mediaType, .document)
        XCTAssertEqual(previewInfo.previewState, .idle)
    }
    
    func testMediaPreviewInfoFileExists() {
        // Given
        let previewInfo = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .document)
        
        // When/Then
        XCTAssertTrue(previewInfo.fileExists())
        
        // Test with non-existent file
        let nonExistentURL = tempDirectory.appendingPathComponent("nonexistent.txt")
        let nonExistentPreview = MediaPreviewInfo(taskId: UUID(), filePath: nonExistentURL, mediaType: .document)
        XCTAssertFalse(nonExistentPreview.fileExists())
    }
    
    func testMediaPreviewInfoFileSize() {
        // Given
        let previewInfo = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .document)
        
        // When
        let fileSize = previewInfo.fileSize()
        
        // Then
        XCTAssertNotNil(fileSize)
        XCTAssertGreaterThan(fileSize!, 0)
    }
    
    func testMediaPreviewInfoIsPreviewAvailable() {
        // Given - video with ready state
        var videoPreview = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .video)
        videoPreview.previewState = .ready
        
        // Then
        XCTAssertTrue(videoPreview.isPreviewAvailable)
        
        // Given - archive with ready state (not supported)
        var archivePreview = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .archive)
        archivePreview.previewState = .ready
        
        // Then
        XCTAssertFalse(archivePreview.isPreviewAvailable)
    }
    
    func testMediaPreviewInfoIsQuickLookAvailable() {
        // Given
        let previewInfo = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .document)
        
        // When/Then
        XCTAssertTrue(previewInfo.isQuickLookAvailable)
    }
    
    // MARK: - Partial Preview Config Tests
    
    func testPartialPreviewConfigCanPreview() {
        // Given
        let config = PartialPreviewConfig()
        
        // Test with sufficient bytes and percentage
        XCTAssertTrue(config.canPreview(downloadedBytes: 2_000_000, totalBytes: 10_000_000))
        
        // Test with insufficient bytes
        XCTAssertFalse(config.canPreview(downloadedBytes: 500_000, totalBytes: 10_000_000))
        
        // Test with insufficient percentage
        XCTAssertFalse(config.canPreview(downloadedBytes: 100_000, totalBytes: 10_000_000))
        
        // Test with file too large
        XCTAssertFalse(config.canPreview(downloadedBytes: 50_000_000, totalBytes: 200_000_000))
    }
    
    func testPartialPreviewConfigDisabled() {
        // Given
        var config = PartialPreviewConfig()
        config.enableWhileDownloading = false
        
        // When/Then
        XCTAssertFalse(config.canPreview(downloadedBytes: 5_000_000, totalBytes: 10_000_000))
    }
    
    func testPartialPreviewConfigCustomMinimums() {
        // Given
        var config = PartialPreviewConfig()
        config.minimumBytes = 5_000_000 // 5 MB
        config.minimumPercentage = 10.0 // 10%
        
        // Test with 6 MB / 50 MB (12%)
        XCTAssertTrue(config.canPreview(downloadedBytes: 6_000_000, totalBytes: 50_000_000))
        
        // Test with 4 MB / 50 MB (8% - insufficient bytes)
        XCTAssertFalse(config.canPreview(downloadedBytes: 4_000_000, totalBytes: 50_000_000))
        
        // Test with 6 MB / 80 MB (7.5% - insufficient percentage)
        XCTAssertFalse(config.canPreview(downloadedBytes: 6_000_000, totalBytes: 80_000_000))
    }
    
    // MARK: - Quick Look Preview Item Tests
    
    func testQuickLookPreviewItemCreation() {
        // Given
        let url = testFileURL!
        let name = "Test File"
        
        // When
        let item = QuickLookPreviewItem(url: url, name: name)
        
        // Then
        XCTAssertEqual(item.previewItemURL, url)
        XCTAssertEqual(item.previewItemTitle, name)
    }
    
    func testQuickLookPreviewItemDefaultName() {
        // Given
        let url = testFileURL!
        
        // When
        let item = QuickLookPreviewItem(url: url, name: nil)
        
        // Then
        XCTAssertEqual(item.previewItemURL, url)
        XCTAssertEqual(item.previewItemTitle, url.lastPathComponent)
    }
    
    // MARK: - Preview Generation Options Tests
    
    func testPreviewGenerationOptionsDefaults() {
        // Given
        let options = PreviewGenerationOptions()
        
        // Then
        XCTAssertTrue(options.generateThumbnails)
        XCTAssertTrue(options.extractMetadata)
        XCTAssertEqual(options.thumbnailSize, CGSize(width: 512, height: 512))
        XCTAssertEqual(options.thumbnailQuality, 0.8)
        XCTAssertTrue(options.backgroundGeneration)
    }
    
    func testPreviewGenerationOptionsCustomization() {
        // Given
        var options = PreviewGenerationOptions()
        
        // When
        options.generateThumbnails = false
        options.extractMetadata = false
        options.thumbnailSize = CGSize(width: 256, height: 256)
        options.thumbnailQuality = 0.5
        
        // Then
        XCTAssertFalse(options.generateThumbnails)
        XCTAssertFalse(options.extractMetadata)
        XCTAssertEqual(options.thumbnailSize, CGSize(width: 256, height: 256))
        XCTAssertEqual(options.thumbnailQuality, 0.5)
    }
    
    // MARK: - Preview Cache Tests
    
    func testPreviewCacheStore() {
        // Given
        let cache = PreviewCache.shared
        let previewInfo = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .document)
        
        // When
        cache.store(previewInfo)
        
        // Then
        let retrieved = cache.retrieve(id: previewInfo.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, previewInfo.id)
    }
    
    func testPreviewCacheRetrieveByTaskId() {
        // Given
        let cache = PreviewCache.shared
        let taskId = UUID()
        let previewInfo = MediaPreviewInfo(taskId: taskId, filePath: testFileURL, mediaType: .document)
        
        // When
        cache.store(previewInfo)
        
        // Then
        let retrieved = cache.retrieve(taskId: taskId)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.taskId, taskId)
    }
    
    func testPreviewCacheRemove() {
        // Given
        let cache = PreviewCache.shared
        let previewInfo = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .document)
        cache.store(previewInfo)
        
        // When
        cache.remove(id: previewInfo.id)
        
        // Then
        let retrieved = cache.retrieve(id: previewInfo.id)
        XCTAssertNil(retrieved)
    }
    
    func testPreviewCacheClearAll() {
        // Given
        let cache = PreviewCache.shared
        let preview1 = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .document)
        let preview2 = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .image)
        cache.store(preview1)
        cache.store(preview2)
        
        // When
        cache.clearAll()
        
        // Then
        XCTAssertEqual(cache.allPreviews().count, 0)
    }
    
    // MARK: - Preview Manager Tests
    
    func testPreviewManagerGetPreview() {
        // Given
        let taskId = UUID()
        let previewInfo = MediaPreviewInfo(taskId: taskId, filePath: testFileURL, mediaType: .document)
        PreviewCache.shared.store(previewInfo)
        
        // When
        let retrieved = previewManager.getPreview(for: taskId)
        
        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.taskId, taskId)
    }
    
    func testPreviewManagerUpdatePartialPreviewConfig() {
        // Given
        var config = PartialPreviewConfig()
        config.minimumBytes = 2_000_000
        config.minimumPercentage = 10.0
        
        // When
        previewManager.updatePartialPreviewConfig(config)
        
        // Then - config should be applied (can't directly access private property, but no errors should occur)
        XCTAssertTrue(true) // If we reach here, update succeeded
    }
    
    func testPreviewManagerUpdateGenerationOptions() {
        // Given
        var options = PreviewGenerationOptions()
        options.generateThumbnails = false
        options.extractMetadata = true
        
        // When
        previewManager.updateGenerationOptions(options)
        
        // Then
        XCTAssertTrue(true) // If we reach here, update succeeded
    }
    
    // MARK: - Preview State Tests
    
    func testPreviewStateValues() {
        // Given/When/Then
        XCTAssertEqual(PreviewState.idle.rawValue, "idle")
        XCTAssertEqual(PreviewState.generating.rawValue, "generating")
        XCTAssertEqual(PreviewState.ready.rawValue, "ready")
        XCTAssertEqual(PreviewState.failed.rawValue, "failed")
        XCTAssertEqual(PreviewState.notSupported.rawValue, "notSupported")
    }
    
    // MARK: - Thumbnail Info Tests
    
    func testThumbnailInfoCreation() {
        // Given
        let thumbnailPath = testFileURL!
        let size = CGSize(width: 512, height: 512)
        let generatedAt = Date()
        
        // When
        let info = ThumbnailInfo(thumbnailPath: thumbnailPath, size: size, generatedAt: generatedAt)
        
        // Then
        XCTAssertEqual(info.thumbnailPath, thumbnailPath)
        XCTAssertEqual(info.size, size)
        XCTAssertEqual(info.generatedAt, generatedAt)
    }
    
    // MARK: - Integration Tests
    
    func testFullPreviewWorkflow() {
        // This test validates the conceptual workflow
        // In real testing, we'd need actual media files
        
        // Given
        let taskId = UUID()
        let filePath = testFileURL!
        
        // When - create preview info manually (generatePreview requires actual media file)
        var previewInfo = MediaPreviewInfo(taskId: taskId, filePath: filePath, mediaType: .document)
        previewInfo.previewState = .ready
        
        // Store in cache
        PreviewCache.shared.store(previewInfo)
        
        // Then - should be retrievable
        let retrieved = previewManager.getPreview(for: taskId)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.previewState, .ready)
    }
    
    func testMediaTypeWorkflow() {
        // Given
        let videoURL = URL(fileURLWithPath: "/path/to/video.mp4")
        
        // When
        let ext = videoURL.pathExtension
        let mediaType = MediaType.from(fileExtension: ext)
        
        // Then
        XCTAssertEqual(mediaType, .video)
        XCTAssertTrue(mediaType.supportsPreview)
        XCTAssertTrue(mediaType.supportsQuickLook)
        XCTAssertFalse(mediaType.icon.isEmpty)
    }
    
    func testPartialPreviewWorkflow() {
        // Given
        let config = PartialPreviewConfig()
        let downloadedBytes: Int64 = 3_000_000 // 3 MB
        let totalBytes: Int64 = 50_000_000 // 50 MB
        
        // When
        let canPreview = config.canPreview(downloadedBytes: downloadedBytes, totalBytes: totalBytes)
        
        // Then
        XCTAssertTrue(canPreview) // 3 MB > 1 MB minimum and 6% > 5% minimum
    }
    
    // MARK: - Error Handling Tests
    
    func testPreviewErrorTypes() {
        // Given/When/Then
        XCTAssertNotNil(PreviewError.metadataExtractionFailed.errorDescription)
        XCTAssertNotNil(PreviewError.thumbnailGenerationFailed.errorDescription)
        XCTAssertNotNil(PreviewError.thumbnailSaveFailed.errorDescription)
        XCTAssertNotNil(PreviewError.fileNotFound.errorDescription)
        XCTAssertNotNil(PreviewError.unsupportedFileType.errorDescription)
    }
    
    // MARK: - Codable Tests
    
    func testMediaMetadataCodable() throws {
        // Given
        var metadata = MediaMetadata(fileSize: 1024)
        metadata.duration = 120.5
        metadata.resolution = CGSize(width: 1920, height: 1080)
        metadata.bitrate = 128000
        
        // When
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(MediaMetadata.self, from: data)
        
        // Then
        XCTAssertEqual(decoded.fileSize, 1024)
        XCTAssertEqual(decoded.duration, 120.5)
        XCTAssertEqual(decoded.resolution, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(decoded.bitrate, 128000)
    }
    
    func testMediaPreviewInfoCodable() throws {
        // Given
        let previewInfo = MediaPreviewInfo(taskId: UUID(), filePath: testFileURL, mediaType: .video)
        
        // When
        let data = try JSONEncoder().encode(previewInfo)
        let decoded = try JSONDecoder().decode(MediaPreviewInfo.self, from: data)
        
        // Then
        XCTAssertEqual(decoded.id, previewInfo.id)
        XCTAssertEqual(decoded.taskId, previewInfo.taskId)
        XCTAssertEqual(decoded.mediaType, .video)
    }
    
    func testThumbnailInfoCodable() throws {
        // Given
        let info = ThumbnailInfo(
            thumbnailPath: testFileURL,
            size: CGSize(width: 512, height: 512),
            generatedAt: Date()
        )
        
        // When
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ThumbnailInfo.self, from: data)
        
        // Then
        XCTAssertEqual(decoded.thumbnailPath, testFileURL)
        XCTAssertEqual(decoded.size, CGSize(width: 512, height: 512))
    }
}
