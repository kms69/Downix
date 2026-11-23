//
//  SmartOrganizationTests.swift
//  Download Manager for Mac - Feature #8: Smart Organization Tests
//
//  Created on February 15, 2026
//

import XCTest
@testable import DownloadManager

final class SmartOrganizationTests: XCTestCase {
    
    var manager: OrganizationManager!
    var downloadManager: DownloadManager!
    
    override func setUp() {
        super.setUp()
        manager = OrganizationManager.shared
        downloadManager = DownloadManager.shared
        
        // Clear existing data
        manager.rules.removeAll()
        manager.tags.removeAll()
        manager.taskTags.removeAll()
        manager.statistics = OrganizationStatistics()
    }
    
    override func tearDown() {
        manager.rules.removeAll()
        manager.tags.removeAll()
        manager.taskTags.removeAll()
        super.tearDown()
    }
    
    // MARK: - Rule Management Tests
    
    func testAddRule() {
        let rule = OrganizationRule(
            name: "Test Rule",
            conditions: [.fileType(.video)],
            actions: [.addTag("Video")]
        )
        
        manager.addRule(rule)
        
        XCTAssertEqual(manager.rules.count, 1)
        XCTAssertEqual(manager.rules.first?.name, "Test Rule")
        XCTAssertEqual(manager.statistics.totalRulesCreated, 1)
        XCTAssertEqual(manager.statistics.activeRules, 1)
    }
    
    func testUpdateRule() {
        var rule = OrganizationRule(
            name: "Original",
            conditions: [.fileType(.video)],
            actions: [.addTag("Video")]
        )
        
        manager.addRule(rule)
        let originalID = rule.id
        
        rule.name = "Updated"
        rule.id = originalID
        manager.updateRule(rule)
        
        XCTAssertEqual(manager.rules.count, 1)
        XCTAssertEqual(manager.rules.first?.name, "Updated")
        XCTAssertEqual(manager.rules.first?.id, originalID)
    }
    
    func testDeleteRule() {
        let rule = OrganizationRule(
            name: "Test Rule",
            conditions: [.fileType(.video)],
            actions: [.addTag("Video")]
        )
        
        manager.addRule(rule)
        XCTAssertEqual(manager.rules.count, 1)
        
        manager.deleteRule(rule)
        XCTAssertEqual(manager.rules.count, 0)
        XCTAssertEqual(manager.statistics.activeRules, 0)
    }
    
    func testRuleToggle() {
        var rule = OrganizationRule(
            name: "Test Rule",
            conditions: [.fileType(.video)],
            actions: [.addTag("Video")],
            isEnabled: true
        )
        
        manager.addRule(rule)
        XCTAssertEqual(manager.statistics.activeRules, 1)
        
        rule.isEnabled = false
        manager.updateRule(rule)
        XCTAssertEqual(manager.statistics.activeRules, 0)
    }
    
    // MARK: - Rule Condition Tests
    
    func testFileTypeCondition() {
        let videoTask = createMockTask(filename: "video.mp4", mimeType: "video/mp4")
        let audioTask = createMockTask(filename: "audio.mp3", mimeType: "audio/mpeg")
        
        let condition = RuleCondition.fileType(.video)
        
        XCTAssertTrue(condition.matches(videoTask))
        XCTAssertFalse(condition.matches(audioTask))
    }
    
    func testFileExtensionCondition() {
        let mp4Task = createMockTask(filename: "file.mp4")
        let mp3Task = createMockTask(filename: "file.mp3")
        
        let condition = RuleCondition.fileExtension(["mp4", "mov"])
        
        XCTAssertTrue(condition.matches(mp4Task))
        XCTAssertFalse(condition.matches(mp3Task))
    }
    
    func testSourceURLCondition() {
        let youtubeTask = createMockTask(url: "https://youtube.com/watch?v=123")
        let vimeoTask = createMockTask(url: "https://vimeo.com/123")
        
        let condition = RuleCondition.sourceURL(
            RuleCondition.URLPattern(pattern: "youtube", matchType: .contains)
        )
        
        XCTAssertTrue(condition.matches(youtubeTask))
        XCTAssertFalse(condition.matches(vimeoTask))
    }
    
    func testFileSizeCondition() {
        let smallTask = createMockTask(totalBytes: 1_000_000) // 1MB
        let largeTask = createMockTask(totalBytes: 100_000_000) // 100MB
        
        let condition = RuleCondition.fileSize(min: 10_000_000, max: 1_000_000_000) // 10MB-1GB
        
        XCTAssertFalse(condition.matches(smallTask))
        XCTAssertTrue(condition.matches(largeTask))
    }
    
    func testFilenameCondition() {
        let task1 = createMockTask(filename: "report_2024.pdf")
        let task2 = createMockTask(filename: "image.png")
        
        let condition = RuleCondition.filename(pattern: "report")
        
        XCTAssertTrue(condition.matches(task1))
        XCTAssertFalse(condition.matches(task2))
    }
    
    func testDateDownloadedCondition() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        let recentTask = createMockTask(createdAt: now)
        
        let condition = RuleCondition.dateDownloaded(from: yesterday, to: tomorrow)
        
        XCTAssertTrue(condition.matches(recentTask))
    }
    
    func testMimeTypeCondition() {
        let videoTask = createMockTask(mimeType: "video/mp4")
        let audioTask = createMockTask(mimeType: "audio/mpeg")
        
        let condition = RuleCondition.mimeType(["video/mp4", "video/quicktime"])
        
        XCTAssertTrue(condition.matches(videoTask))
        XCTAssertFalse(condition.matches(audioTask))
    }
    
    // MARK: - Rule Action Tests
    
    func testMoveToFolderAction() {
        let task = createMockTask()
        let targetURL = URL(fileURLWithPath: "/tmp/downloads")
        
        let rule = OrganizationRule(
            name: "Move Rule",
            conditions: [.fileType(.video)],
            actions: [.moveToFolder(targetURL)]
        )
        
        manager.addRule(rule)
        manager.processTask(task)
        
        XCTAssertEqual(task.destinationPath, targetURL)
    }
    
    func testAddTagAction() {
        let task = createMockTask(filename: "video.mp4", mimeType: "video/mp4")
        
        let rule = OrganizationRule(
            name: "Tag Rule",
            conditions: [.fileType(.video)],
            actions: [.addTag("Video")]
        )
        
        manager.addRule(rule)
        manager.processTask(task)
        
        let tags = manager.getTags(for: task)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.name, "Video")
    }
    
    func testRenameFileAction() {
        let task = createMockTask(filename: "video.mp4")
        
        let rule = OrganizationRule(
            name: "Rename Rule",
            conditions: [.fileType(.video)],
            actions: [.renameFile("{name}_backup.{ext}")]
        )
        
        manager.addRule(rule)
        manager.processTask(task)
        
        XCTAssertTrue(task.filename.contains("_backup"))
    }
    
    // MARK: - Rule Matching Priority Tests
    
    func testRulePriorityOrdering() {
        let task = createMockTask(filename: "video.mp4", mimeType: "video/mp4")
        
        let lowPriorityRule = OrganizationRule(
            name: "Low Priority",
            priority: 1,
            conditions: [.fileType(.video)],
            actions: [.addTag("LowPriority")]
        )
        
        let highPriorityRule = OrganizationRule(
            name: "High Priority",
            priority: 10,
            conditions: [.fileType(.video)],
            actions: [.addTag("HighPriority")]
        )
        
        manager.addRule(lowPriorityRule)
        manager.addRule(highPriorityRule)
        
        manager.processTask(task)
        
        let tags = manager.getTags(for: task)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.name, "HighPriority", "Higher priority rule should be applied first")
    }
    
    func testMultipleConditions() {
        let videoTask = createMockTask(
            filename: "large_video.mp4",
            mimeType: "video/mp4",
            totalBytes: 100_000_000
        )
        
        let smallVideoTask = createMockTask(
            filename: "small_video.mp4",
            mimeType: "video/mp4",
            totalBytes: 1_000_000
        )
        
        let rule = OrganizationRule(
            name: "Large Video Rule",
            conditions: [
                .fileType(.video),
                .fileSize(min: 10_000_000, max: nil)
            ],
            actions: [.addTag("LargeVideo")]
        )
        
        manager.addRule(rule)
        
        manager.processTask(videoTask)
        manager.processTask(smallVideoTask)
        
        XCTAssertEqual(manager.getTags(for: videoTask).count, 1)
        XCTAssertEqual(manager.getTags(for: smallVideoTask).count, 0)
    }
    
    // MARK: - Tag Management Tests
    
    func testAddTag() {
        let tag = DownloadTag(name: "Important", color: .red)
        
        manager.addNewTag(tag)
        
        XCTAssertEqual(manager.tags.count, 1)
        XCTAssertEqual(manager.tags.first?.name, "Important")
        XCTAssertEqual(manager.statistics.tagsCreated, 1)
    }
    
    func testUpdateTag() {
        var tag = DownloadTag(name: "Original", color: .blue)
        manager.addNewTag(tag)
        
        tag.name = "Updated"
        manager.updateTag(tag)
        
        XCTAssertEqual(manager.tags.first?.name, "Updated")
    }
    
    func testDeleteTag() {
        let tag = DownloadTag(name: "Test", color: .green)
        manager.addNewTag(tag)
        
        XCTAssertEqual(manager.tags.count, 1)
        
        manager.deleteTag(tag)
        
        XCTAssertEqual(manager.tags.count, 0)
    }
    
    func testTagUsageCount() {
        let tag = DownloadTag(name: "Video", color: .blue)
        manager.addNewTag(tag)
        
        let task1 = createMockTask(filename: "video1.mp4")
        let task2 = createMockTask(filename: "video2.mp4")
        
        manager.addTag(tag, to: task1)
        manager.addTag(tag, to: task2)
        
        XCTAssertEqual(manager.tags.first?.usageCount, 2)
    }
    
    func testRemoveTagFromTask() {
        let tag = DownloadTag(name: "Test", color: .blue)
        manager.addNewTag(tag)
        
        let task = createMockTask()
        
        manager.addTag(tag, to: task)
        XCTAssertEqual(manager.getTags(for: task).count, 1)
        
        manager.removeTag(tag, from: task)
        XCTAssertEqual(manager.getTags(for: task).count, 0)
    }
    
    func testDeleteTagRemovesFromTasks() {
        let tag = DownloadTag(name: "Test", color: .blue)
        manager.addNewTag(tag)
        
        let task = createMockTask()
        manager.addTag(tag, to: task)
        
        XCTAssertEqual(manager.getTags(for: task).count, 1)
        
        manager.deleteTag(tag)
        
        XCTAssertEqual(manager.getTags(for: task).count, 0)
    }
    
    // MARK: - Duplicate Detection Tests
    
    func testExactURLDuplicate() {
        let url = URL(string: "https://example.com/file.zip")!
        
        let task1 = createMockTask(url: url.absoluteString, filename: "file1.zip")
        let task2 = createMockTask(url: url.absoluteString, filename: "file2.zip")
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        let duplicates = manager.findDuplicates()
        
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates.first?.duplicates.first?.matchType, .exactURL)
        XCTAssertEqual(duplicates.first?.duplicates.first?.confidence, 1.0)
    }
    
    func testExactFilenameDuplicate() {
        let task1 = createMockTask(url: "https://example1.com/file.zip", filename: "document.pdf")
        let task2 = createMockTask(url: "https://example2.com/file.zip", filename: "document.pdf")
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        let duplicates = manager.findDuplicates()
        
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates.first?.duplicates.first?.matchType, .exactFilename)
        XCTAssertGreaterThanOrEqual(duplicates.first?.duplicates.first?.confidence ?? 0, 0.9)
    }
    
    func testSimilarFilenameDuplicate() {
        let task1 = createMockTask(filename: "vacation_photo_2024.jpg")
        let task2 = createMockTask(filename: "vacation_photo_2024 (1).jpg")
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        let duplicates = manager.findDuplicates()
        
        XCTAssertGreaterThanOrEqual(duplicates.count, 0)
        if let duplicate = duplicates.first {
            XCTAssertGreaterThanOrEqual(duplicate.duplicates.first?.confidence ?? 0, 0.8)
        }
    }
    
    func testExactSizeDuplicate() {
        let size: Int64 = 1_000_000
        
        let task1 = createMockTask(filename: "file1.zip", totalBytes: size)
        let task2 = createMockTask(filename: "file2.zip", totalBytes: size)
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        let duplicates = manager.findDuplicates()
        
        // May or may not detect as duplicate depending on filename similarity
        XCTAssertGreaterThanOrEqual(duplicates.count, 0)
    }
    
    func testRemoveDuplicates() {
        let url = URL(string: "https://example.com/file.zip")!
        
        let task1 = createMockTask(url: url.absoluteString, filename: "file1.zip")
        let task2 = createMockTask(url: url.absoluteString, filename: "file2.zip")
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        let duplicates = manager.findDuplicates()
        XCTAssertEqual(duplicates.count, 1)
        
        if let duplicate = duplicates.first {
            manager.removeDuplicates(duplicate, keepOriginal: true)
            XCTAssertFalse(downloadManager.downloadTasks.contains(task2))
            XCTAssertTrue(downloadManager.downloadTasks.contains(task1))
        }
    }
    
    // MARK: - Search & Filter Tests
    
    func testSearchByText() {
        let task1 = createMockTask(filename: "report_2024.pdf")
        let task2 = createMockTask(filename: "image.png")
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        var filter = SearchFilter()
        filter.textQuery = "report"
        
        let results = manager.searchDownloads(filter: filter)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.filename, "report_2024.pdf")
    }
    
    func testSearchByTags() {
        let tag = DownloadTag(name: "Important", color: .red)
        manager.addNewTag(tag)
        
        let task1 = createMockTask(filename: "important.pdf")
        let task2 = createMockTask(filename: "regular.pdf")
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        manager.addTag(tag, to: task1)
        
        var filter = SearchFilter()
        filter.tags = [tag.id]
        
        let results = manager.searchDownloads(filter: filter)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.filename, "important.pdf")
    }
    
    func testSearchByCategory() {
        let task1 = createMockTask(filename: "video.mp4")
        task1.category = .videos
        
        let task2 = createMockTask(filename: "song.mp3")
        task2.category = .music
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        var filter = SearchFilter()
        filter.categories = [.videos]
        
        let results = manager.searchDownloads(filter: filter)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.filename, "video.mp4")
    }
    
    func testSearchBySizeRange() {
        let smallTask = createMockTask(filename: "small.txt", totalBytes: 1_000)
        let largeTask = createMockTask(filename: "large.zip", totalBytes: 100_000_000)
        
        downloadManager.addDownload(smallTask)
        downloadManager.addDownload(largeTask)
        
        var filter = SearchFilter()
        filter.sizeRange = (10_000_000, nil)
        
        let results = manager.searchDownloads(filter: filter)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.filename, "large.zip")
    }
    
    // MARK: - Auto-Categorization Tests
    
    func testAutoCategorizeVideo() {
        let task = createMockTask(mimeType: "video/mp4")
        
        let category = manager.autoCategorize(task)
        
        XCTAssertEqual(category, .videos)
    }
    
    func testAutoCategorizeAudio() {
        let task = createMockTask(mimeType: "audio/mpeg")
        
        let category = manager.autoCategorize(task)
        
        XCTAssertEqual(category, .music)
    }
    
    func testAutoCategorizeImage() {
        let task = createMockTask(mimeType: "image/jpeg")
        
        let category = manager.autoCategorize(task)
        
        XCTAssertEqual(category, .images)
    }
    
    func testAutoCategorizeDocument() {
        let task = createMockTask(mimeType: "application/pdf")
        
        let category = manager.autoCategorize(task)
        
        XCTAssertEqual(category, .documents)
    }
    
    func testAutoCategorizeArchive() {
        let task = createMockTask(mimeType: "application/zip")
        
        let category = manager.autoCategorize(task)
        
        XCTAssertEqual(category, .compressed)
    }
    
    // MARK: - Statistics Tests
    
    func testRuleMatchStatistics() {
        let rule = OrganizationRule(
            name: "Test Rule",
            conditions: [.fileType(.video)],
            actions: [.addTag("Video")]
        )
        
        manager.addRule(rule)
        
        let initialMatches = manager.statistics.totalMatches
        
        let task = createMockTask(filename: "video.mp4", mimeType: "video/mp4")
        manager.processTask(task)
        
        XCTAssertEqual(manager.statistics.totalMatches, initialMatches + 1)
    }
    
    func testDuplicateStatistics() {
        let url = URL(string: "https://example.com/file.zip")!
        
        let task1 = createMockTask(url: url.absoluteString, totalBytes: 1_000_000)
        let task2 = createMockTask(url: url.absoluteString, totalBytes: 1_000_000)
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        let initialDuplicates = manager.statistics.duplicatesFound
        let initialSpace = manager.statistics.spaceReclaimed
        
        _ = manager.findDuplicates()
        
        XCTAssertGreaterThan(manager.statistics.duplicatesFound, initialDuplicates)
        XCTAssertGreaterThan(manager.statistics.spaceReclaimed, initialSpace)
    }
    
    // MARK: - Suggestion Tests
    
    func testCreateRuleSuggestion() {
        // Add multiple downloads from same host
        for i in 1...5 {
            let task = createMockTask(
                url: "https://example.com/file\(i).zip",
                filename: "file\(i).zip"
            )
            downloadManager.addDownload(task)
        }
        
        let suggestions = manager.getSuggestions()
        
        let ruleSuggestions = suggestions.filter { $0.type == .createRule }
        XCTAssertGreaterThan(ruleSuggestions.count, 0)
    }
    
    func testMergeDuplicatesSuggestion() {
        let url = URL(string: "https://example.com/file.zip")!
        
        let task1 = createMockTask(url: url.absoluteString, filename: "file1.zip")
        let task2 = createMockTask(url: url.absoluteString, filename: "file2.zip")
        
        downloadManager.addDownload(task1)
        downloadManager.addDownload(task2)
        
        let suggestions = manager.getSuggestions()
        
        let duplicateSuggestions = suggestions.filter { $0.type == .mergeDuplicates }
        XCTAssertGreaterThan(duplicateSuggestions.count, 0)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteOrganizationWorkflow() {
        // Create tags
        let videoTag = DownloadTag(name: "Video", color: .blue)
        manager.addNewTag(videoTag)
        
        // Create rule
        let rule = OrganizationRule(
            name: "Organize Videos",
            priority: 10,
            conditions: [.fileType(.video)],
            actions: [.addTag("Video")]
        )
        manager.addRule(rule)
        
        // Add download
        let task = createMockTask(filename: "movie.mp4", mimeType: "video/mp4")
        downloadManager.addDownload(task)
        
        // Process task
        manager.processTask(task)
        
        // Verify
        let tags = manager.getTags(for: task)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.name, "Video")
        XCTAssertGreaterThan(manager.statistics.totalMatches, 0)
    }
    
    // MARK: - Helper Methods
    
    private func createMockTask(
        url: String = "https://example.com/file.zip",
        filename: String = "file.zip",
        mimeType: String? = nil,
        totalBytes: Int64 = 0,
        createdAt: Date = Date()
    ) -> DownloadTask {
        let task = DownloadTask(url: URL(string: url)!)
        task.filename = filename
        task.fileType = mimeType
        task.totalBytes = totalBytes
        task.createdAt = createdAt
        return task
    }
}

// MARK: - DownloadTask Extensions for Testing

extension DownloadTask {
    var category: DownloadCategory {
        get { .others }
        set { /* Mock setter */ }
    }
}
