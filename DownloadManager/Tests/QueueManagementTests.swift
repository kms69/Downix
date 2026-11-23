//
//  QueueManagementTests.swift
//  Download Manager Tests - Feature #2
//
//  Created on February 15, 2026
//

import XCTest
@testable import DownloadManager

class QueueManagementTests: XCTestCase {
    
    var manager: DownloadManager!
    
    override func setUp() {
        super.setUp()
        manager = DownloadManager.shared
        
        // Clear existing downloads
        for task in manager.downloadTasks {
            manager.removeDownload(task)
        }
    }
    
    override func tearDown() {
        for task in manager.downloadTasks {
            manager.removeDownload(task)
        }
        super.tearDown()
    }
    
    // MARK: - Priority Tests
    
    func testAddDownloadWithPriority() {
        let url = URL(string: "https://example.com/file.zip")!
        
        let task = manager.addDownload(
            url: url,
            priority: .high
        )
        
        XCTAssertEqual(task.priority, .high)
    }
    
    func testDefaultPriorityIsNormal() {
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.addDownload(url: url)
        
        XCTAssertEqual(task.priority, .normal)
    }
    
    func testChangePriority() {
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.addDownload(url: url, priority: .low)
        
        XCTAssertEqual(task.priority, .low)
        
        manager.setPriority(.urgent, for: task)
        
        XCTAssertEqual(task.priority, .urgent)
    }
    
    func testPriorityComparison() {
        XCTAssertTrue(DownloadPriority.urgent > DownloadPriority.high)
        XCTAssertTrue(DownloadPriority.high > DownloadPriority.normal)
        XCTAssertTrue(DownloadPriority.normal > DownloadPriority.low)
    }
    
    // MARK: - Category Tests
    
    func testCategoryDetection() {
        XCTAssertEqual(DownloadCategory.detect(from: "document.pdf"), .documents)
        XCTAssertEqual(DownloadCategory.detect(from: "video.mp4"), .videos)
        XCTAssertEqual(DownloadCategory.detect(from: "song.mp3"), .audio)
        XCTAssertEqual(DownloadCategory.detect(from: "image.jpg"), .images)
        XCTAssertEqual(DownloadCategory.detect(from: "archive.zip"), .archives)
        XCTAssertEqual(DownloadCategory.detect(from: "app.dmg"), .applications)
        XCTAssertEqual(DownloadCategory.detect(from: "unknown.xyz"), .other)
    }
    
    func testCategoryAutoAssignment() {
        let url = URL(string: "https://example.com/movie.mp4")!
        let task = manager.addDownload(url: url)
        
        XCTAssertEqual(task.category, .videos)
    }
    
    func testManualCategoryAssignment() {
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.addDownload(url: url, category: .documents)
        
        XCTAssertEqual(task.category, .documents)
    }
    
    func testChangeCate gory() {
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.addDownload(url: url)
        
        manager.setCategory(.videos, for: task)
        
        XCTAssertEqual(task.category, .videos)
    }
    
    // MARK: - Queue Sorting Tests
    
    func testSortByPriority() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        let url3 = URL(string: "https://example.com/file3.zip")!
        
        let task1 = manager.addDownload(url: url1, priority: .low)
        let task2 = manager.addDownload(url: url2, priority: .urgent)
        let task3 = manager.addDownload(url: url3, priority: .normal)
        
        manager.sortQueueByPriority()
        
        // Urgent should be first
        XCTAssertEqual(manager.downloadTasks[0].id, task2.id)
        XCTAssertEqual(manager.downloadTasks[0].priority, .urgent)
    }
    
    func testSortByFilename() {
        let url1 = URL(string: "https://example.com/zebra.zip")!
        let url2 = URL(string: "https://example.com/apple.zip")!
        let url3 = URL(string: "https://example.com/banana.zip")!
        
        manager.addDownload(url: url1)
        manager.addDownload(url: url2)
        manager.addDownload(url: url3)
        
        manager.sortQueue(by: .filename, ascending: true)
        
        XCTAssertEqual(manager.downloadTasks[0].filename, "apple.zip")
        XCTAssertEqual(manager.downloadTasks[1].filename, "banana.zip")
        XCTAssertEqual(manager.downloadTasks[2].filename, "zebra.zip")
    }
    
    func testSortByDate() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        
        let task1 = manager.addDownload(url: url1)
        
        // Wait a bit
        Thread.sleep(forTimeInterval: 0.1)
        
        let task2 = manager.addDownload(url: url2)
        
        manager.sortQueue(by: .dateAdded, ascending: true)
        
        // task1 should be first (older)
        XCTAssertEqual(manager.downloadTasks[0].id, task1.id)
    }
    
    // MARK: - Queue Reordering Tests
    
    func testMoveTaskToPosition() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        let url3 = URL(string: "https://example.com/file3.zip")!
        
        let task1 = manager.addDownload(url: url1)
        let task2 = manager.addDownload(url: url2)
        let task3 = manager.addDownload(url: url3)
        
        // Move task3 to position 0
        manager.moveTask(task3, to: 0)
        
        XCTAssertEqual(manager.downloadTasks[0].id, task3.id)
    }
    
    func testMoveTaskUp() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        
        let task1 = manager.addDownload(url: url1)
        let task2 = manager.addDownload(url: url2)
        
        // task2 is at index 1, move up to 0
        manager.moveTaskUp(task2)
        
        XCTAssertEqual(manager.downloadTasks[0].id, task2.id)
    }
    
    func testMoveTaskDown() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        
        let task1 = manager.addDownload(url: url1)
        let task2 = manager.addDownload(url: url2)
        
        // task1 is at index 0, move down to 1
        manager.moveTaskDown(task1)
        
        XCTAssertEqual(manager.downloadTasks[1].id, task1.id)
    }
    
    func testMoveTaskToTop() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        let url3 = URL(string: "https://example.com/file3.zip")!
        
        let task1 = manager.addDownload(url: url1)
        let task2 = manager.addDownload(url: url2)
        let task3 = manager.addDownload(url: url3)
        
        manager.moveTaskToTop(task3)
        
        XCTAssertEqual(manager.downloadTasks[0].id, task3.id)
    }
    
    func testMoveTaskToBottom() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        let url3 = URL(string: "https://example.com/file3.zip")!
        
        let task1 = manager.addDownload(url: url1)
        let task2 = manager.addDownload(url: url2)
        let task3 = manager.addDownload(url: url3)
        
        manager.moveTaskToBottom(task1)
        
        XCTAssertEqual(manager.downloadTasks[2].id, task1.id)
    }
    
    // MARK: - Filtering Tests
    
    func testFilterByCategory() {
        let url1 = URL(string: "https://example.com/video.mp4")!
        let url2 = URL(string: "https://example.com/document.pdf")!
        let url3 = URL(string: "https://example.com/song.mp3")!
        
        manager.addDownload(url: url1) // Videos
        manager.addDownload(url: url2) // Documents
        manager.addDownload(url: url3) // Audio
        
        let videos = manager.downloadsByCategory(.videos)
        let documents = manager.downloadsByCategory(.documents)
        let audio = manager.downloadsByCategory(.audio)
        
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(audio.count, 1)
    }
    
    func testFilterByPriority() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        let url3 = URL(string: "https://example.com/file3.zip")!
        
        manager.addDownload(url: url1, priority: .high)
        manager.addDownload(url: url2, priority: .high)
        manager.addDownload(url: url3, priority: .low)
        
        let highPriority = manager.downloadsByPriority(.high)
        let lowPriority = manager.downloadsByPriority(.low)
        
        XCTAssertEqual(highPriority.count, 2)
        XCTAssertEqual(lowPriority.count, 1)
    }
    
    func testFilterByState() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        
        let task1 = manager.addDownload(url: url1)
        let task2 = manager.addDownload(url: url2)
        
        task1.state = .completed
        task2.state = .waiting
        
        let completed = manager.downloadsByState(.completed)
        let waiting = manager.downloadsByState(.waiting)
        
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(waiting.count, 1)
    }
    
    func testQueueFilter() {
        let url1 = URL(string: "https://example.com/video.mp4")!
        let url2 = URL(string: "https://example.com/document.pdf")!
        
        let task1 = manager.addDownload(url: url1, priority: .high)
        let task2 = manager.addDownload(url: url2, priority: .low)
        
        task1.state = .downloading
        task2.state = .waiting
        
        let filter = QueueFilter(
            state: .downloading,
            category: .videos,
            priority: .high
        )
        
        let filtered = manager.filteredDownloads(filter: filter)
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, task1.id)
    }
    
    func testSearchFilter() {
        let url1 = URL(string: "https://example.com/important_document.pdf")!
        let url2 = URL(string: "https://example.com/random_video.mp4")!
        
        manager.addDownload(url: url1)
        manager.addDownload(url: url2)
        
        let filter = QueueFilter(searchText: "important")
        let filtered = manager.filteredDownloads(filter: filter)
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertTrue(filtered.first?.filename.contains("important") ?? false)
    }
    
    // MARK: - Batch Operations Tests
    
    func testPauseCategory() {
        let url1 = URL(string: "https://example.com/video1.mp4")!
        let url2 = URL(string: "https://example.com/video2.mp4")!
        let url3 = URL(string: "https://example.com/document.pdf")!
        
        let task1 = manager.addDownload(url: url1)
        let task2 = manager.addDownload(url: url2)
        let task3 = manager.addDownload(url: url3)
        
        task1.state = .downloading
        task2.state = .downloading
        task3.state = .downloading
        
        manager.pauseCategory(.videos)
        
        // Videos should be paused
        XCTAssertEqual(task1.state, .paused)
        XCTAssertEqual(task2.state, .paused)
        
        // Document should still be downloading
        XCTAssertEqual(task3.state, .downloading)
    }
    
    func testPausePriority() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        
        let task1 = manager.addDownload(url: url1, priority: .high)
        let task2 = manager.addDownload(url: url2, priority: .low)
        
        task1.state = .downloading
        task2.state = .downloading
        
        manager.pausePriority(.high)
        
        XCTAssertEqual(task1.state, .paused)
        XCTAssertEqual(task2.state, .downloading)
    }
    
    // MARK: - Statistics Tests
    
    func testQueueStatistics() {
        let url1 = URL(string: "https://example.com/file1.zip")!
        let url2 = URL(string: "https://example.com/file2.zip")!
        let url3 = URL(string: "https://example.com/file3.zip")!
        
        let task1 = manager.addDownload(url: url1, priority: .high)
        let task2 = manager.addDownload(url: url2, priority: .normal)
        let task3 = manager.addDownload(url: url3, priority: .urgent)
        
        task1.state = .downloading
        task2.state = .waiting
        task3.state = .completed
        
        let stats = manager.getQueueStatistics()
        
        XCTAssertEqual(stats.total, 3)
        XCTAssertEqual(stats.downloading, 1)
        XCTAssertEqual(stats.waiting, 1)
        XCTAssertEqual(stats.completed, 1)
        XCTAssertEqual(stats.high, 1)
        XCTAssertEqual(stats.normal, 1)
        XCTAssertEqual(stats.urgent, 1)
    }
}
