//
//  DownloadManagerTests.swift
//  Download Manager Tests
//
//  Created on February 14, 2026
//

import XCTest
@testable import DownloadManager

class DownloadManagerTests: XCTestCase {
    
    var manager: DownloadManager!
    var testURL: URL!
    
    override func setUp() {
        super.setUp()
        manager = DownloadManager.shared
        testURL = URL(string: "https://example.com/testfile.zip")!
        
        // Clear any existing downloads
        for task in manager.downloadTasks {
            manager.removeDownload(task)
        }
    }
    
    override func tearDown() {
        // Clean up after tests
        for task in manager.downloadTasks {
            manager.removeDownload(task)
        }
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testManagerInitialization() {
        XCTAssertNotNil(manager)
        XCTAssertEqual(manager.maxConcurrentDownloads, 5)
        XCTAssertEqual(manager.defaultNumberOfSegments, 8)
        XCTAssertNotNil(manager.defaultSaveLocation)
    }
    
    func testManagerIsSingleton() {
        let manager1 = DownloadManager.shared
        let manager2 = DownloadManager.shared
        
        XCTAssertTrue(manager1 === manager2)
    }
    
    // MARK: - Add Download Tests
    
    func testAddDownload() {
        let initialCount = manager.downloadTasks.count
        
        let task = manager.addDownload(url: testURL)
        
        XCTAssertEqual(manager.downloadTasks.count, initialCount + 1)
        XCTAssertEqual(task.url, testURL)
        XCTAssertNotNil(task.id)
    }
    
    func testAddDownloadWithCustomSettings() {
        let destination = FileManager.default.temporaryDirectory
        let filename = "custom.zip"
        let segments = 16
        
        let task = manager.addDownload(
            url: testURL,
            destinationPath: destination,
            filename: filename,
            numberOfSegments: segments
        )
        
        XCTAssertEqual(task.destinationPath, destination)
        XCTAssertEqual(task.filename, filename)
        XCTAssertEqual(task.numberOfSegments, segments)
    }
    
    func testAddMultipleDownloads() {
        let urls = [
            URL(string: "https://example.com/file1.zip")!,
            URL(string: "https://example.com/file2.pdf")!,
            URL(string: "https://example.com/file3.mp4")!
        ]
        
        let initialCount = manager.downloadTasks.count
        
        for url in urls {
            manager.addDownload(url: url)
        }
        
        XCTAssertEqual(manager.downloadTasks.count, initialCount + 3)
    }
    
    // MARK: - Remove Download Tests
    
    func testRemoveDownload() {
        let task = manager.addDownload(url: testURL)
        let initialCount = manager.downloadTasks.count
        
        manager.removeDownload(task)
        
        XCTAssertEqual(manager.downloadTasks.count, initialCount - 1)
    }
    
    // MARK: - Queue Management Tests
    
    func testMaxConcurrentDownloads() {
        manager.maxConcurrentDownloads = 2
        
        // Add 5 downloads
        for i in 1...5 {
            let url = URL(string: "https://example.com/file\(i).zip")!
            manager.addDownload(url: url)
        }
        
        // Active downloads should not exceed max
        XCTAssertLessThanOrEqual(manager.activeDownloads, manager.maxConcurrentDownloads)
    }
    
    // MARK: - Statistics Tests
    
    func testGetStatistics() {
        // Add some downloads
        let task1 = manager.addDownload(url: testURL)
        let task2 = manager.addDownload(url: URL(string: "https://example.com/file2.zip")!)
        
        // Simulate completed downloads
        task1.state = .completed
        task1.totalBytes = 1024 * 1024 // 1 MB
        
        task2.state = .completed
        task2.totalBytes = 2 * 1024 * 1024 // 2 MB
        
        let stats = manager.getStatistics()
        
        XCTAssertEqual(stats.totalDownloads, 2)
        XCTAssertEqual(stats.totalBytesDownloaded, 3 * 1024 * 1024)
    }
    
    func testFormattedTotalSpeed() {
        manager.totalDownloadSpeed = 1024 * 1024 // 1 MB/s
        
        let formatted = manager.formattedTotalSpeed
        
        XCTAssertTrue(formatted.contains("MB"))
        XCTAssertTrue(formatted.contains("/s"))
    }
    
    // MARK: - Clear Operations Tests
    
    func testClearCompleted() {
        // Add downloads with different states
        let task1 = manager.addDownload(url: URL(string: "https://example.com/file1.zip")!)
        let task2 = manager.addDownload(url: URL(string: "https://example.com/file2.zip")!)
        let task3 = manager.addDownload(url: URL(string: "https://example.com/file3.zip")!)
        
        task1.state = .completed
        task2.state = .downloading
        task3.state = .completed
        
        let initialCount = manager.downloadTasks.count
        
        manager.clearCompleted()
        
        // Should have removed 2 completed downloads
        XCTAssertEqual(manager.downloadTasks.count, initialCount - 2)
        XCTAssertFalse(manager.downloadTasks.contains(where: { $0.id == task1.id }))
        XCTAssertTrue(manager.downloadTasks.contains(where: { $0.id == task2.id }))
        XCTAssertFalse(manager.downloadTasks.contains(where: { $0.id == task3.id }))
    }
    
    // MARK: - Configuration Tests
    
    func testConfigurationChanges() {
        manager.maxConcurrentDownloads = 10
        XCTAssertEqual(manager.maxConcurrentDownloads, 10)
        
        manager.defaultNumberOfSegments = 16
        XCTAssertEqual(manager.defaultNumberOfSegments, 16)
        
        let newLocation = FileManager.default.temporaryDirectory
        manager.defaultSaveLocation = newLocation
        XCTAssertEqual(manager.defaultSaveLocation, newLocation)
    }
}
