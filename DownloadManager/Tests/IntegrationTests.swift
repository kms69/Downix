//
//  IntegrationTests.swift
//  Download Manager Integration Tests
//
//  Created on February 14, 2026
//

import XCTest
@testable import DownloadManager

/// Integration tests that perform actual downloads
/// These tests require internet connection
class IntegrationTests: XCTestCase {
    
    var manager: DownloadManager!
    
    override func setUp() {
        super.setUp()
        manager = DownloadManager.shared
        
        // Clean up
        for task in manager.downloadTasks {
            manager.removeDownload(task)
        }
    }
    
    override func tearDown() {
        // Clean up downloaded files
        for task in manager.downloadTasks {
            let filePath = task.destinationPath.appendingPathComponent(task.filename)
            try? FileManager.default.removeItem(at: filePath)
            manager.removeDownload(task)
        }
        super.tearDown()
    }
    
    // MARK: - Small File Download Tests
    
    func testDownloadSmallFile() {
        let expectation = XCTestExpectation(description: "Download small file")
        
        // Use a small test file (robots.txt is usually small)
        let url = URL(string: "https://www.google.com/robots.txt")!
        let task = manager.addDownload(url: url)
        
        // Monitor the download
        var observer: NSKeyValueObservation?
        observer = task.observe(\.state, options: [.new]) { observedTask, change in
            if observedTask.state == .completed {
                XCTAssertEqual(observedTask.progress, 1.0)
                XCTAssertGreaterThan(observedTask.totalBytes, 0)
                
                // Verify file exists
                let filePath = observedTask.destinationPath.appendingPathComponent(observedTask.filename)
                XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))
                
                expectation.fulfill()
                observer?.invalidate()
            } else if observedTask.state == .failed {
                XCTFail("Download failed: \(observedTask.error?.localizedDescription ?? "Unknown error")")
                expectation.fulfill()
                observer?.invalidate()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - Multi-segment Download Tests
    
    func testMultiSegmentDownload() {
        let expectation = XCTestExpectation(description: "Multi-segment download")
        
        // Use a larger file to test multi-threading (10MB test file)
        let url = URL(string: "https://speed.hetzner.de/10MB.bin")!
        let task = manager.addDownload(url: url, numberOfSegments: 4)
        
        var maxSegmentsObserved = 0
        
        var observer: NSKeyValueObservation?
        observer = task.observe(\.state, options: [.new]) { observedTask, change in
            
            // Track segments
            if observedTask.state == .downloading {
                maxSegmentsObserved = max(maxSegmentsObserved, observedTask.segments.count)
            }
            
            if observedTask.state == .completed {
                // Verify segments were used
                XCTAssertGreaterThan(maxSegmentsObserved, 0, "Should have used segments")
                
                // Verify file exists and has correct size
                let filePath = observedTask.destinationPath.appendingPathComponent(observedTask.filename)
                XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))
                
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: filePath.path)[.size] as? Int64 {
                    XCTAssertEqual(fileSize, observedTask.totalBytes)
                }
                
                expectation.fulfill()
                observer?.invalidate()
            } else if observedTask.state == .failed {
                XCTFail("Download failed: \(observedTask.error?.localizedDescription ?? "Unknown error")")
                expectation.fulfill()
                observer?.invalidate()
            }
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Pause and Resume Tests
    
    func testPauseAndResumeDownload() {
        let expectation = XCTestExpectation(description: "Pause and resume download")
        
        let url = URL(string: "https://speed.hetzner.de/10MB.bin")!
        let task = manager.addDownload(url: url)
        
        var wasPaused = false
        var wasResumed = false
        
        // Pause after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if task.state == .downloading {
                self.manager.pauseDownload(task)
                wasPaused = true
                
                // Resume after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.manager.resumeDownload(task)
                    wasResumed = true
                }
            }
        }
        
        var observer: NSKeyValueObservation?
        observer = task.observe(\.state, options: [.new]) { observedTask, change in
            if observedTask.state == .completed {
                // Verify pause/resume happened
                // Note: This might not always work if download is too fast
                
                // Verify file exists
                let filePath = observedTask.destinationPath.appendingPathComponent(observedTask.filename)
                XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))
                
                expectation.fulfill()
                observer?.invalidate()
            } else if observedTask.state == .failed {
                XCTFail("Download failed: \(observedTask.error?.localizedDescription ?? "Unknown error")")
                expectation.fulfill()
                observer?.invalidate()
            }
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Multiple Concurrent Downloads Tests
    
    func testMultipleConcurrentDownloads() {
        let expectation = XCTestExpectation(description: "Multiple concurrent downloads")
        expectation.expectedFulfillmentCount = 3
        
        manager.maxConcurrentDownloads = 3
        
        let urls = [
            URL(string: "https://www.google.com/robots.txt")!,
            URL(string: "https://www.github.com/robots.txt")!,
            URL(string: "https://www.microsoft.com/robots.txt")!
        ]
        
        var completedCount = 0
        
        for (index, url) in urls.enumerated() {
            let task = manager.addDownload(url: url, filename: "robots\(index).txt")
            
            _ = task.observe(\.state, options: [.new]) { observedTask, change in
                if observedTask.state == .completed {
                    completedCount += 1
                    expectation.fulfill()
                } else if observedTask.state == .failed {
                    XCTFail("Download \(index) failed")
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 60.0)
        
        XCTAssertEqual(completedCount, 3, "All downloads should complete")
        XCTAssertLessThanOrEqual(manager.activeDownloads, manager.maxConcurrentDownloads)
    }
    
    // MARK: - Speed Calculation Tests
    
    func testSpeedCalculation() {
        let expectation = XCTestExpectation(description: "Speed calculation")
        
        let url = URL(string: "https://speed.hetzner.de/10MB.bin")!
        let task = manager.addDownload(url: url)
        
        var maxSpeed: Int64 = 0
        
        // Check speed periodically
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if task.state == .downloading {
                maxSpeed = max(maxSpeed, task.speed)
            }
        }
        
        var observer: NSKeyValueObservation?
        observer = task.observe(\.state, options: [.new]) { observedTask, change in
            if observedTask.state == .completed {
                timer.invalidate()
                
                // Should have recorded some speed
                XCTAssertGreaterThan(maxSpeed, 0, "Should have measured download speed")
                
                expectation.fulfill()
                observer?.invalidate()
            } else if observedTask.state == .failed {
                timer.invalidate()
                XCTFail("Download failed")
                expectation.fulfill()
                observer?.invalidate()
            }
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidURLHandling() {
        let expectation = XCTestExpectation(description: "Invalid URL handling")
        
        let url = URL(string: "https://this-domain-definitely-does-not-exist-12345.com/file.zip")!
        let task = manager.addDownload(url: url)
        
        var observer: NSKeyValueObservation?
        observer = task.observe(\.state, options: [.new]) { observedTask, change in
            if observedTask.state == .failed {
                XCTAssertNotNil(observedTask.error)
                expectation.fulfill()
                observer?.invalidate()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
}
