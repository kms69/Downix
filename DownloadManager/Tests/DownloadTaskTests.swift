//
//  DownloadTaskTests.swift
//  Download Manager Tests
//
//  Created on February 14, 2026
//

import XCTest
@testable import DownloadManager

class DownloadTaskTests: XCTestCase {
    
    var testURL: URL!
    var testDestination: URL!
    
    override func setUp() {
        super.setUp()
        testURL = URL(string: "https://example.com/testfile.zip")!
        testDestination = FileManager.default.temporaryDirectory
    }
    
    // MARK: - Initialization Tests
    
    func testDownloadTaskInitialization() {
        let task = DownloadTask(url: testURL, destinationPath: testDestination)
        
        XCTAssertNotNil(task.id)
        XCTAssertEqual(task.url, testURL)
        XCTAssertEqual(task.destinationPath, testDestination)
        XCTAssertEqual(task.filename, "testfile.zip")
        XCTAssertEqual(task.state, .waiting)
        XCTAssertEqual(task.progress, 0.0)
        XCTAssertEqual(task.numberOfSegments, 8)
    }
    
    func testDownloadTaskCustomFilename() {
        let task = DownloadTask(
            url: testURL,
            destinationPath: testDestination,
            filename: "custom_name.zip"
        )
        
        XCTAssertEqual(task.filename, "custom_name.zip")
    }
    
    func testDownloadTaskCustomSegments() {
        let task = DownloadTask(
            url: testURL,
            destinationPath: testDestination,
            numberOfSegments: 16
        )
        
        XCTAssertEqual(task.numberOfSegments, 16)
    }
    
    // MARK: - Progress Tests
    
    func testProgressCalculation() {
        let task = DownloadTask(url: testURL, destinationPath: testDestination)
        
        task.totalBytes = 1000
        task.downloadedBytes = 500
        
        // Progress should be calculated when accessed
        XCTAssertEqual(task.downloadedBytes, 500)
        XCTAssertEqual(task.totalBytes, 1000)
    }
    
    func testTimeRemainingCalculation() {
        let task = DownloadTask(url: testURL, destinationPath: testDestination)
        
        task.totalBytes = 1000
        task.downloadedBytes = 250
        task.speed = 100 // 100 bytes/sec
        
        task.updateTimeRemaining()
        
        // Remaining: 750 bytes / 100 bytes/sec = 7.5 seconds
        XCTAssertEqual(task.timeRemaining, 7.5, accuracy: 0.1)
    }
    
    func testTimeRemainingWithZeroSpeed() {
        let task = DownloadTask(url: testURL, destinationPath: testDestination)
        
        task.totalBytes = 1000
        task.downloadedBytes = 250
        task.speed = 0
        
        task.updateTimeRemaining()
        
        XCTAssertEqual(task.timeRemaining, 0)
    }
    
    // MARK: - Formatting Tests
    
    func testFormattedSpeed() {
        let task = DownloadTask(url: testURL, destinationPath: testDestination)
        
        task.speed = 1024 * 1024 // 1 MB/s
        
        let formatted = task.formattedSpeed
        XCTAssertTrue(formatted.contains("MB"))
        XCTAssertTrue(formatted.contains("/s"))
    }
    
    func testFormattedTimeRemaining() {
        let task = DownloadTask(url: testURL, destinationPath: testDestination)
        
        // Test hours
        task.timeRemaining = 3661 // 1h 1m 1s
        var formatted = task.formattedTimeRemaining
        XCTAssertTrue(formatted.contains("h"))
        XCTAssertTrue(formatted.contains("m"))
        
        // Test minutes
        task.timeRemaining = 65 // 1m 5s
        formatted = task.formattedTimeRemaining
        XCTAssertTrue(formatted.contains("m"))
        XCTAssertTrue(formatted.contains("s"))
        
        // Test seconds
        task.timeRemaining = 45 // 45s
        formatted = task.formattedTimeRemaining
        XCTAssertTrue(formatted.contains("s"))
    }
    
    // MARK: - State Tests
    
    func testStateTransitions() {
        let task = DownloadTask(url: testURL, destinationPath: testDestination)
        
        XCTAssertEqual(task.state, .waiting)
        
        task.state = .downloading
        XCTAssertEqual(task.state, .downloading)
        
        task.state = .paused
        XCTAssertEqual(task.state, .paused)
        
        task.state = .completed
        XCTAssertEqual(task.state, .completed)
    }
    
    // MARK: - Segment Tests
    
    func testSegmentCreation() {
        let segment = DownloadSegment(segmentIndex: 0, startByte: 0, endByte: 999)
        
        XCTAssertNotNil(segment.id)
        XCTAssertEqual(segment.segmentIndex, 0)
        XCTAssertEqual(segment.startByte, 0)
        XCTAssertEqual(segment.endByte, 999)
        XCTAssertEqual(segment.downloadedBytes, 0)
        XCTAssertFalse(segment.isComplete)
    }
    
    func testSegmentProgress() {
        var segment = DownloadSegment(segmentIndex: 0, startByte: 0, endByte: 999)
        
        segment.downloadedBytes = 500
        
        let expectedProgress = 500.0 / 1000.0
        XCTAssertEqual(segment.progress, expectedProgress, accuracy: 0.01)
    }
}
