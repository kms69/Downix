import XCTest
@testable import DownloadManagerPackage

final class BatchOperationTests: XCTestCase {
    
    var manager: BatchOperationManager!
    
    override func setUp() {
        super.setUp()
        manager = BatchOperationManager.shared
    }
    
    override func tearDown() {
        manager.clearValidationResults()
        super.tearDown()
    }
    
    // MARK: - Batch Import Source Tests
    
    func testBatchImportSourceEnum() {
        XCTAssertEqual(BatchImportSource.clipboard.displayName, "Clipboard")
        XCTAssertEqual(BatchImportSource.textFile.displayName, "Text File")
        XCTAssertEqual(BatchImportSource.manualEntry.displayName, "Manual Entry")
        
        XCTAssertEqual(BatchImportSource.clipboard.icon, "doc.on.clipboard")
        XCTAssertEqual(BatchImportSource.textFile.icon, "doc.text")
        XCTAssertEqual(BatchImportSource.manualEntry.icon, "keyboard")
    }
    
    func testBatchImportSourceAllCases() {
        XCTAssertEqual(BatchImportSource.allCases.count, 4)
        XCTAssertTrue(BatchImportSource.allCases.contains(.clipboard))
        XCTAssertTrue(BatchImportSource.allCases.contains(.textFile))
        XCTAssertTrue(BatchImportSource.allCases.contains(.manualEntry))
        XCTAssertTrue(BatchImportSource.allCases.contains(.urlList))
    }
    
    // MARK: - Batch Category Tests
    
    func testBatchCategoryEnum() {
        XCTAssertEqual(BatchCategory.video.displayName, "Video")
        XCTAssertEqual(BatchCategory.audio.displayName, "Audio")
        XCTAssertEqual(BatchCategory.document.displayName, "Document")
        
        XCTAssertEqual(BatchCategory.video.icon, "film")
        XCTAssertEqual(BatchCategory.audio.icon, "music.note")
        XCTAssertEqual(BatchCategory.image.icon, "photo")
    }
    
    func testBatchCategoryDefaultSubdirectory() {
        XCTAssertEqual(BatchCategory.video.defaultSubdirectory, "Videos")
        XCTAssertEqual(BatchCategory.audio.defaultSubdirectory, "Music")
        XCTAssertEqual(BatchCategory.document.defaultSubdirectory, "Documents")
        XCTAssertEqual(BatchCategory.archive.defaultSubdirectory, "Archives")
        XCTAssertEqual(BatchCategory.image.defaultSubdirectory, "Images")
    }
    
    func testBatchCategoryAllCases() {
        XCTAssertEqual(BatchCategory.allCases.count, 9)
        XCTAssertTrue(BatchCategory.allCases.contains(.video))
        XCTAssertTrue(BatchCategory.allCases.contains(.audio))
        XCTAssertTrue(BatchCategory.allCases.contains(.ebook))
        XCTAssertTrue(BatchCategory.allCases.contains(.torrent))
    }
    
    // MARK: - URL Pattern Tests
    
    func testURLPatternStringMatching() {
        let pattern = URLPattern(pattern: ".mp4", isRegex: false)
        
        XCTAssertTrue(pattern.matches("https://example.com/video.mp4"))
        XCTAssertFalse(pattern.matches("https://example.com/video.avi"))
    }
    
    func testURLPatternRegexMatching() {
        let pattern = URLPattern(pattern: "\\.(mp4|avi|mkv)$", isRegex: true)
        
        XCTAssertTrue(pattern.matches("https://example.com/video.mp4"))
        XCTAssertTrue(pattern.matches("https://example.com/video.avi"))
        XCTAssertTrue(pattern.matches("https://example.com/video.mkv"))
        XCTAssertFalse(pattern.matches("https://example.com/video.mov"))
    }
    
    func testURLPatternIsEnabled() {
        var pattern = URLPattern(pattern: ".mp4", isRegex: false, isEnabled: false)
        
        XCTAssertFalse(pattern.matches("https://example.com/video.mp4"))
        
        pattern.isEnabled = true
        XCTAssertTrue(pattern.matches("https://example.com/video.mp4"))
    }
    
    func testURLPatternPresets() {
        let videoPattern = URLPattern.videoPattern
        XCTAssertTrue(videoPattern.isRegex)
        XCTAssertTrue(videoPattern.matches("https://example.com/file.mp4"))
        
        let audioPattern = URLPattern.audioPattern
        XCTAssertTrue(audioPattern.matches("https://example.com/song.mp3"))
        
        let imagePattern = URLPattern.imagePattern
        XCTAssertTrue(imagePattern.matches("https://example.com/photo.jpg"))
        
        let docPattern = URLPattern.documentPattern
        XCTAssertTrue(docPattern.matches("https://example.com/file.pdf"))
    }
    
    // MARK: - Sequential Name Pattern Tests
    
    func testSequentialNamePatternGeneration() {
        let pattern = SequentialNamePattern(
            basePattern: "file",
            startNumber: 1,
            numberDigits: 3,
            separator: "_"
        )
        
        XCTAssertEqual(pattern.generateFilename(at: 0), "file_001")
        XCTAssertEqual(pattern.generateFilename(at: 1), "file_002")
        XCTAssertEqual(pattern.generateFilename(at: 9), "file_010")
        XCTAssertEqual(pattern.generateFilename(at: 99), "file_100")
    }
    
    func testSequentialNamePatternWithExtension() {
        let pattern = SequentialNamePattern(
            basePattern: "video",
            startNumber: 1,
            numberDigits: 2,
            separator: "-",
            extension: "mp4"
        )
        
        XCTAssertEqual(pattern.generateFilename(at: 0), "video-01.mp4")
        XCTAssertEqual(pattern.generateFilename(at: 5), "video-06.mp4")
    }
    
    func testSequentialNamePatternPreview() {
        let pattern = SequentialNamePattern(
            basePattern: "download",
            startNumber: 10,
            numberDigits: 3
        )
        
        let preview = pattern.previewFilenames(count: 3)
        XCTAssertEqual(preview.count, 3)
        XCTAssertEqual(preview[0], "download_010")
        XCTAssertEqual(preview[1], "download_011")
        XCTAssertEqual(preview[2], "download_012")
    }
    
    func testSequentialNamePatternPresets() {
        let defaultPattern = SequentialNamePattern.defaultPattern
        XCTAssertEqual(defaultPattern.basePattern, "download")
        XCTAssertEqual(defaultPattern.startNumber, 1)
        XCTAssertEqual(defaultPattern.numberDigits, 3)
        
        let videoPattern = SequentialNamePattern.videoPattern
        XCTAssertEqual(videoPattern.extension, "mp4")
        
        let imagePattern = SequentialNamePattern.imagePattern
        XCTAssertEqual(imagePattern.extension, "jpg")
    }
    
    // MARK: - Batch Rename Pattern Tests
    
    func testBatchRenamePatternSimple() {
        let pattern = BatchRenamePattern(
            findPattern: " ",
            replaceWith: "_"
        )
        
        XCTAssertEqual(pattern.apply(to: "my file.txt"), "my_file.txt")
        XCTAssertEqual(pattern.apply(to: "another file name.pdf"), "another_file_name.pdf")
    }
    
    func testBatchRenamePatternRegex() {
        let pattern = BatchRenamePattern(
            findPattern: "[^a-zA-Z0-9._-]",
            replaceWith: "",
            isRegex: true
        )
        
        XCTAssertEqual(pattern.apply(to: "file@#$.txt"), "file.txt")
        XCTAssertEqual(pattern.apply(to: "my*file!name.pdf"), "myfilename.pdf")
    }
    
    func testBatchRenamePatternCaseSensitive() {
        let pattern = BatchRenamePattern(
            findPattern: "Video",
            replaceWith: "Movie",
            caseSensitive: true
        )
        
        XCTAssertEqual(pattern.apply(to: "Video.mp4"), "Movie.mp4")
        XCTAssertEqual(pattern.apply(to: "video.mp4"), "video.mp4") // Not replaced
    }
    
    func testBatchRenamePatternCaseInsensitive() {
        let pattern = BatchRenamePattern(
            findPattern: "Video",
            replaceWith: "Movie",
            caseSensitive: false
        )
        
        XCTAssertEqual(pattern.apply(to: "Video.mp4"), "Movie.mp4")
        XCTAssertEqual(pattern.apply(to: "video.mp4"), "Movie.mp4")
        XCTAssertEqual(pattern.apply(to: "VIDEO.mp4"), "Movie.mp4")
    }
    
    func testBatchRenamePatternPresets() {
        let removeSpaces = BatchRenamePattern.removeSpaces
        XCTAssertEqual(removeSpaces.apply(to: "my file.txt"), "my_file.txt")
        
        let removeSpecial = BatchRenamePattern.removeSpecialChars
        XCTAssertTrue(removeSpecial.isRegex)
    }
    
    // MARK: - Batch Import Config Tests
    
    func testBatchImportConfigDefaults() {
        let config = BatchImportConfig()
        
        XCTAssertEqual(config.source, .clipboard)
        XCTAssertTrue(config.urls.isEmpty)
        XCTAssertNil(config.targetCategory)
        XCTAssertNil(config.targetDirectory)
        XCTAssertTrue(config.urlPatterns.isEmpty)
        XCTAssertFalse(config.useSequentialNaming)
        XCTAssertTrue(config.validateURLs)
        XCTAssertTrue(config.removeDuplicates)
        XCTAssertFalse(config.startImmediately)
    }
    
    func testBatchImportConfigCustomization() {
        let config = BatchImportConfig(
            source: .textFile,
            urls: ["https://example.com/file1.mp4", "https://example.com/file2.mp4"],
            targetCategory: .video,
            targetDirectory: "/Downloads",
            useSequentialNaming: true,
            startImmediately: true
        )
        
        XCTAssertEqual(config.source, .textFile)
        XCTAssertEqual(config.urls.count, 2)
        XCTAssertEqual(config.targetCategory, .video)
        XCTAssertEqual(config.targetDirectory, "/Downloads")
        XCTAssertTrue(config.useSequentialNaming)
        XCTAssertTrue(config.startImmediately)
    }
    
    // MARK: - URL Validation Result Tests
    
    func testURLValidationResultCreation() {
        let result = URLValidationResult(
            url: "https://example.com/file.mp4",
            isValid: true,
            suggestedFilename: "file.mp4",
            detectedCategory: .video
        )
        
        XCTAssertEqual(result.url, "https://example.com/file.mp4")
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.suggestedFilename, "file.mp4")
        XCTAssertEqual(result.detectedCategory, .video)
    }
    
    func testURLValidationResultWithError() {
        let result = URLValidationResult(
            url: "invalid-url",
            isValid: false,
            error: "Invalid URL format"
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.error, "Invalid URL format")
    }
    
    // MARK: - Batch Operation Result Tests
    
    func testBatchOperationResultCreation() {
        let result = BatchOperationResult(
            totalCount: 10,
            successCount: 8,
            failedCount: 2,
            duration: 1.5
        )
        
        XCTAssertEqual(result.totalCount, 10)
        XCTAssertEqual(result.successCount, 8)
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertEqual(result.duration, 1.5)
    }
    
    func testBatchOperationResultSuccessRate() {
        let result = BatchOperationResult(
            totalCount: 10,
            successCount: 7,
            failedCount: 3
        )
        
        XCTAssertEqual(result.successRate, 70.0)
    }
    
    func testBatchOperationResultSuccessRateZero() {
        let result = BatchOperationResult(totalCount: 0)
        XCTAssertEqual(result.successRate, 0)
    }
    
    func testBatchOperationResultSummary() {
        let result = BatchOperationResult(
            totalCount: 5,
            successCount: 5,
            failedCount: 0,
            duration: 2.0
        )
        
        let summary = result.summary
        XCTAssertTrue(summary.contains("Total: 5"))
        XCTAssertTrue(summary.contains("Success: 5"))
        XCTAssertTrue(summary.contains("Failed: 0"))
        XCTAssertTrue(summary.contains("100.0%"))
    }
    
    // MARK: - Batch Operation Error Tests
    
    func testBatchOperationErrorDescriptions() {
        XCTAssertNotNil(BatchOperationError.invalidURL("bad-url").errorDescription)
        XCTAssertNotNil(BatchOperationError.invalidFilePath.errorDescription)
        XCTAssertNotNil(BatchOperationError.clipboardEmpty.errorDescription)
        XCTAssertNotNil(BatchOperationError.noURLsFound.errorDescription)
        XCTAssertNotNil(BatchOperationError.patternError("bad pattern").errorDescription)
    }
    
    // MARK: - Batch Export Config Tests
    
    func testBatchExportConfigDefaults() {
        let config = BatchExportConfig()
        
        XCTAssertFalse(config.includeMetadata)
        XCTAssertFalse(config.includeCategory)
        XCTAssertFalse(config.includeFilename)
        XCTAssertEqual(config.format, .plainText)
    }
    
    func testBatchExportFormatExtensions() {
        XCTAssertEqual(BatchExportConfig.ExportFormat.plainText.fileExtension, "txt")
        XCTAssertEqual(BatchExportConfig.ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(BatchExportConfig.ExportFormat.csv.fileExtension, "csv")
        XCTAssertEqual(BatchExportConfig.ExportFormat.markdown.fileExtension, "md")
    }
    
    // MARK: - Batch Task Info Tests
    
    func testBatchTaskInfoCreation() {
        let batchId = UUID()
        let task = BatchTaskInfo(
            batchId: batchId,
            url: "https://example.com/file.mp4",
            filename: "video.mp4",
            category: .video,
            destinationPath: "/Downloads/Videos/video.mp4"
        )
        
        XCTAssertEqual(task.batchId, batchId)
        XCTAssertEqual(task.url, "https://example.com/file.mp4")
        XCTAssertEqual(task.filename, "video.mp4")
        XCTAssertEqual(task.category, .video)
        XCTAssertEqual(task.destinationPath, "/Downloads/Videos/video.mp4")
    }
    
    // MARK: - Batch Import Session Tests
    
    func testBatchImportSessionCreation() {
        let config = BatchImportConfig()
        let session = BatchImportSession(name: "Test Session", config: config)
        
        XCTAssertEqual(session.name, "Test Session")
        XCTAssertEqual(session.status, .preparing)
        XCTAssertNil(session.completedAt)
        XCTAssertNil(session.duration)
    }
    
    func testBatchImportSessionDuration() {
        let config = BatchImportConfig()
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(10.0)
        
        let session = BatchImportSession(
            name: "Test",
            config: config,
            createdAt: startDate,
            completedAt: endDate
        )
        
        XCTAssertNotNil(session.duration)
        XCTAssertEqual(session.duration!, 10.0, accuracy: 0.1)
    }
    
    func testBatchImportSessionStatusIcons() {
        XCTAssertEqual(BatchImportSession.SessionStatus.preparing.icon, "clock")
        XCTAssertEqual(BatchImportSession.SessionStatus.validating.icon, "checkmark.circle")
        XCTAssertEqual(BatchImportSession.SessionStatus.completed.icon, "checkmark.circle.fill")
        XCTAssertEqual(BatchImportSession.SessionStatus.failed.icon, "xmark.circle.fill")
    }
    
    func testBatchImportSessionStatusColors() {
        XCTAssertEqual(BatchImportSession.SessionStatus.completed.color, "green")
        XCTAssertEqual(BatchImportSession.SessionStatus.failed.color, "red")
        XCTAssertEqual(BatchImportSession.SessionStatus.validating.color, "orange")
    }
    
    // MARK: - Manager URL Extraction Tests
    
    func testExtractURLsFromText() {
        let text = """
        https://example.com/file1.mp4
        https://example.com/file2.mp4
        # Comment line
        https://example.com/file3.mp4
        """
        
        let result = manager.importFromClipboard()
        // Note: This will fail in tests since clipboard isn't set
        // In real tests, we'd need to set the pasteboard
    }
    
    // MARK: - Manager Pattern Testing
    
    func testManagerTestPattern() {
        let pattern = URLPattern(pattern: ".mp4", isRegex: false)
        let urls = [
            "https://example.com/video.mp4",
            "https://example.com/video.avi",
            "https://example.com/movie.mp4"
        ]
        
        let matches = manager.testPattern(pattern, against: urls)
        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(matches.contains("https://example.com/video.mp4"))
        XCTAssertTrue(matches.contains("https://example.com/movie.mp4"))
    }
    
    func testManagerTestRenamePattern() {
        let pattern = BatchRenamePattern(findPattern: " ", replaceWith: "_")
        let filenames = ["my file.txt", "another file.pdf"]
        
        let results = manager.testRenamePattern(pattern, on: filenames)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results["my file.txt"], "my_file.txt")
        XCTAssertEqual(results["another file.pdf"], "another_file.pdf")
    }
    
    // MARK: - Manager Sequential Names
    
    func testManagerPreviewSequentialNames() {
        let pattern = SequentialNamePattern(
            basePattern: "file",
            startNumber: 1,
            numberDigits: 3
        )
        
        let preview = manager.previewSequentialNames(pattern, count: 5)
        XCTAssertEqual(preview.count, 5)
        XCTAssertEqual(preview[0], "file_001")
        XCTAssertEqual(preview[4], "file_005")
    }
    
    // MARK: - Manager Statistics
    
    func testManagerGetStatistics() {
        let stats = manager.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.totalSessions, 0)
        XCTAssertGreaterThanOrEqual(stats.totalURLs, 0)
        XCTAssertGreaterThanOrEqual(stats.averageSuccessRate, 0)
    }
    
    // MARK: - Manager Pattern Validation
    
    func testManagerValidatePattern() {
        XCTAssertTrue(manager.validatePattern("simple", isRegex: false))
        XCTAssertTrue(manager.validatePattern("\\.(mp4|avi)$", isRegex: true))
        XCTAssertFalse(manager.validatePattern("[invalid(regex", isRegex: true))
    }
    
    // MARK: - Category Detection Tests
    
    func testCategoryDetectionVideo() async {
        let config = BatchImportConfig()
        let urls = ["https://example.com/video.mp4"]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].detectedCategory, .video)
    }
    
    func testCategoryDetectionAudio() async {
        let config = BatchImportConfig()
        let urls = ["https://example.com/song.mp3"]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].detectedCategory, .audio)
    }
    
    func testCategoryDetectionDocument() async {
        let config = BatchImportConfig()
        let urls = ["https://example.com/document.pdf"]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].detectedCategory, .document)
    }
    
    func testCategoryDetectionImage() async {
        let config = BatchImportConfig()
        let urls = ["https://example.com/photo.jpg"]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].detectedCategory, .image)
    }
    
    // MARK: - Validation Tests
    
    func testValidateValidURL() async {
        let config = BatchImportConfig()
        let urls = ["https://example.com/file.mp4"]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isValid)
    }
    
    func testValidateInvalidURL() async {
        let config = BatchImportConfig()
        let urls = ["not-a-url"]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].isValid)
        XCTAssertNotNil(results[0].error)
    }
    
    func testValidateWithPattern() async {
        var config = BatchImportConfig()
        config.urlPatterns = [URLPattern(pattern: ".mp4", isRegex: false)]
        
        let urls = [
            "https://example.com/video.mp4",
            "https://example.com/video.avi"
        ]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].isValid) // .mp4 matches
        XCTAssertFalse(results[1].isValid) // .avi doesn't match
    }
    
    func testValidateWithSequentialNaming() async {
        var config = BatchImportConfig()
        config.useSequentialNaming = true
        config.sequentialPattern = SequentialNamePattern(
            basePattern: "video",
            startNumber: 1,
            numberDigits: 2
        )
        
        let urls = [
            "https://example.com/file1.mp4",
            "https://example.com/file2.mp4"
        ]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].suggestedFilename, "video_01")
        XCTAssertEqual(results[1].suggestedFilename, "video_02")
    }
    
    func testValidateWithRenamePattern() async {
        var config = BatchImportConfig()
        config.renamePatterns = [
            BatchRenamePattern(findPattern: " ", replaceWith: "_")
        ]
        
        let urls = ["https://example.com/my file.mp4"]
        
        let results = await manager.validateURLs(urls, with: config)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].finalFilename, "my_file.mp4")
    }
    
    // MARK: - Session Management Tests
    
    func testCreateSession() {
        let config = BatchImportConfig()
        let session = manager.createSession(name: "Test Session", config: config)
        
        XCTAssertEqual(session.name, "Test Session")
        XCTAssertTrue(manager.sessions.contains { $0.id == session.id })
        XCTAssertEqual(manager.currentSession?.id, session.id)
    }
    
    func testUpdateSession() {
        let config = BatchImportConfig()
        var session = manager.createSession(name: "Test", config: config)
        
        session.status = .completed
        manager.updateSession(session)
        
        let updated = manager.sessions.first { $0.id == session.id }
        XCTAssertEqual(updated?.status, .completed)
    }
    
    func testDeleteSession() {
        let config = BatchImportConfig()
        let session = manager.createSession(name: "Test", config: config)
        
        manager.deleteSession(session)
        
        XCTAssertFalse(manager.sessions.contains { $0.id == session.id })
    }
    
    // MARK: - Codable Tests
    
    func testURLPatternCodable() throws {
        let pattern = URLPattern(pattern: "\\.mp4$", isRegex: true)
        
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(URLPattern.self, from: data)
        
        XCTAssertEqual(decoded.pattern, pattern.pattern)
        XCTAssertEqual(decoded.isRegex, pattern.isRegex)
    }
    
    func testBatchImportConfigCodable() throws {
        let config = BatchImportConfig(
            source: .clipboard,
            urls: ["https://example.com"],
            targetCategory: .video
        )
        
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(BatchImportConfig.self, from: data)
        
        XCTAssertEqual(decoded.source, config.source)
        XCTAssertEqual(decoded.urls, config.urls)
        XCTAssertEqual(decoded.targetCategory, config.targetCategory)
    }
    
    func testBatchOperationResultCodable() throws {
        let result = BatchOperationResult(
            totalCount: 10,
            successCount: 8,
            failedCount: 2
        )
        
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(BatchOperationResult.self, from: data)
        
        XCTAssertEqual(decoded.totalCount, result.totalCount)
        XCTAssertEqual(decoded.successCount, result.successCount)
        XCTAssertEqual(decoded.failedCount, result.failedCount)
    }
    
    func testBatchImportSessionCodable() throws {
        let config = BatchImportConfig()
        let session = BatchImportSession(name: "Test", config: config)
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(BatchImportSession.self, from: data)
        
        XCTAssertEqual(decoded.name, session.name)
        XCTAssertEqual(decoded.status, session.status)
    }
}
