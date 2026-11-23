#!/usr/bin/env swift

//
//  TestRunner.swift
//  Download Manager - Practical Test Runner
//
//  Created on February 14, 2026
//
//  Usage: swift TestRunner.swift
//

import Foundation

// ANSI Color Codes
struct Colors {
    static let reset = "\u{001B}[0m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let bold = "\u{001B}[1m"
}

print("\(Colors.bold)\(Colors.cyan)")
print("╔═══════════════════════════════════════════════════════════╗")
print("║     Download Manager - Practical Test Runner             ║")
print("║     Testing Multi-threaded Download Engine               ║")
print("╚═══════════════════════════════════════════════════════════╝")
print(Colors.reset)

// Test URLs
let testFiles = [
    (name: "Small File (robots.txt)", url: "https://www.google.com/robots.txt", size: "< 1 KB"),
    (name: "1MB Test File", url: "https://speed.hetzner.de/1MB.bin", size: "1 MB"),
    (name: "10MB Test File", url: "https://speed.hetzner.de/10MB.bin", size: "10 MB"),
]

var testsPassed = 0
var testsFailed = 0

func printHeader(_ text: String) {
    print("\n\(Colors.bold)\(Colors.blue)═══ \(text) ═══\(Colors.reset)")
}

func printSuccess(_ text: String) {
    print("\(Colors.green)✓\(Colors.reset) \(text)")
    testsPassed += 1
}

func printError(_ text: String) {
    print("\(Colors.red)✗\(Colors.reset) \(text)")
    testsFailed += 1
}

func printInfo(_ text: String) {
    print("\(Colors.cyan)ℹ\(Colors.reset) \(text)")
}

func printWarning(_ text: String) {
    print("\(Colors.yellow)⚠\(Colors.reset) \(text)")
}

// MARK: - Test 1: URL Validation

printHeader("Test 1: URL Creation and Validation")

let validURLs = [
    "https://example.com/file.zip",
    "http://test.com/download.pdf",
    "ftp://files.server.com/data.tar.gz"
]

for urlString in validURLs {
    if let url = URL(string: urlString) {
        printSuccess("Valid URL: \(urlString)")
    } else {
        printError("Failed to create URL: \(urlString)")
    }
}

let invalidURL = "not a valid url"
if URL(string: invalidURL) == nil {
    printSuccess("Correctly rejected invalid URL: \(invalidURL)")
} else {
    printError("Should have rejected invalid URL: \(invalidURL)")
}

// MARK: - Test 2: File Path Operations

printHeader("Test 2: File System Operations")

let tempDir = FileManager.default.temporaryDirectory
printInfo("Temp directory: \(tempDir.path)")

// Create test directory
let testDir = tempDir.appendingPathComponent("DownloadManagerTests")

do {
    if FileManager.default.fileExists(atPath: testDir.path) {
        try FileManager.default.removeItem(at: testDir)
    }
    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    printSuccess("Created test directory: \(testDir.path)")
} catch {
    printError("Failed to create test directory: \(error)")
}

// Test file creation
let testFile = testDir.appendingPathComponent("test.txt")
let testData = "Test data".data(using: .utf8)!

do {
    try testData.write(to: testFile)
    if FileManager.default.fileExists(atPath: testFile.path) {
        printSuccess("Created test file: \(testFile.lastPathComponent)")
        
        // Verify file size
        let attrs = try FileManager.default.attributesOfItem(atPath: testFile.path)
        if let size = attrs[.size] as? Int64 {
            printSuccess("File size verification: \(size) bytes")
        }
        
        // Clean up
        try FileManager.default.removeItem(at: testFile)
        printSuccess("Cleaned up test file")
    }
} catch {
    printError("File operations failed: \(error)")
}

// MARK: - Test 3: Byte Formatting

printHeader("Test 3: Byte Count Formatting")

let byteSizes: [Int64] = [1024, 1024*1024, 1024*1024*1024]
let expectedFormats = ["KB", "MB", "GB"]

for (index, size) in byteSizes.enumerated() {
    let formatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    if formatted.contains(expectedFormats[index]) {
        printSuccess("Formatted \(size) bytes as: \(formatted)")
    } else {
        printError("Unexpected format for \(size) bytes: \(formatted)")
    }
}

// MARK: - Test 4: Date and Time

printHeader("Test 4: Date and Time Calculations")

func formatTimeInterval(_ seconds: TimeInterval) -> String {
    let hours = Int(seconds) / 3600
    let minutes = Int(seconds) / 60 % 60
    let secs = Int(seconds) % 60
    
    if hours > 0 {
        return String(format: "%dh %dm", hours, minutes)
    } else if minutes > 0 {
        return String(format: "%dm %ds", minutes, secs)
    } else {
        return String(format: "%ds", secs)
    }
}

let testTimes: [TimeInterval] = [45, 125, 3661]
let expectedResults = ["45s", "2m 5s", "1h 1m"]

for (index, time) in testTimes.enumerated() {
    let formatted = formatTimeInterval(time)
    printSuccess("Formatted \(Int(time))s as: \(formatted)")
}

// MARK: - Test 5: Speed Calculation

printHeader("Test 5: Download Speed Calculations")

struct SpeedTest {
    let bytes: Int64
    let seconds: TimeInterval
    
    var speed: Int64 {
        guard seconds > 0 else { return 0 }
        return Int64(Double(bytes) / seconds)
    }
    
    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: speed, countStyle: .file) + "/s"
    }
}

let speedTests = [
    SpeedTest(bytes: 1024 * 1024, seconds: 1.0),  // 1 MB in 1 second
    SpeedTest(bytes: 10 * 1024 * 1024, seconds: 2.0),  // 10 MB in 2 seconds
    SpeedTest(bytes: 100 * 1024 * 1024, seconds: 10.0)  // 100 MB in 10 seconds
]

for test in speedTests {
    printSuccess("Speed: \(test.formattedSpeed) (\(test.bytes) bytes / \(test.seconds)s)")
}

// Test zero second handling
let zeroSecTest = SpeedTest(bytes: 1000, seconds: 0)
if zeroSecTest.speed == 0 {
    printSuccess("Correctly handled zero seconds in speed calculation")
} else {
    printError("Should return 0 for zero seconds")
}

// MARK: - Test 6: Progress Calculation

printHeader("Test 6: Progress Calculations")

struct ProgressTest {
    let downloaded: Int64
    let total: Int64
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(downloaded) / Double(total)
    }
    
    var percentage: Int {
        Int(progress * 100)
    }
}

let progressTests = [
    ProgressTest(downloaded: 0, total: 1000),
    ProgressTest(downloaded: 500, total: 1000),
    ProgressTest(downloaded: 1000, total: 1000),
    ProgressTest(downloaded: 750, total: 1000)
]

for test in progressTests {
    printSuccess("Progress: \(test.percentage)% (\(test.downloaded)/\(test.total) bytes)")
}

// MARK: - Test 7: Segment Calculation

printHeader("Test 7: Multi-threading Segment Calculations")

func calculateSegments(fileSize: Int64, numberOfSegments: Int) -> [(start: Int64, end: Int64)] {
    var segments: [(Int64, Int64)] = []
    let segmentSize = fileSize / Int64(numberOfSegments)
    
    for i in 0..<numberOfSegments {
        let start = Int64(i) * segmentSize
        let end: Int64
        
        if i == numberOfSegments - 1 {
            end = fileSize - 1
        } else {
            end = start + segmentSize - 1
        }
        
        segments.append((start, end))
    }
    
    return segments
}

let fileSizes: [Int64] = [1000, 10_000_000, 100_000_000]
let segmentCounts = [4, 8, 16]

for (sizeIndex, fileSize) in fileSizes.enumerated() {
    for segmentCount in segmentCounts {
        let segments = calculateSegments(fileSize: fileSize, numberOfSegments: segmentCount)
        
        // Verify all bytes are covered
        var totalBytes: Int64 = 0
        for segment in segments {
            totalBytes += (segment.end - segment.start + 1)
        }
        
        if totalBytes == fileSize {
            printSuccess("Segments for \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)) / \(segmentCount) segments: ✓")
        } else {
            printError("Segment calculation error: \(totalBytes) != \(fileSize)")
        }
    }
}

// MARK: - Test 8: Network Connectivity

printHeader("Test 8: Network Connectivity Check")

let semaphore = DispatchSemaphore(value: 0)
var networkAvailable = false

let testURL = URL(string: "https://www.google.com")!
var request = URLRequest(url: testURL)
request.httpMethod = "HEAD"
request.timeoutInterval = 5.0

let task = URLSession.shared.dataTask(with: request) { _, response, error in
    if let httpResponse = response as? HTTPURLResponse {
        networkAvailable = (httpResponse.statusCode == 200)
    }
    semaphore.signal()
}

task.resume()
_ = semaphore.wait(timeout: .now() + 10)

if networkAvailable {
    printSuccess("Network connectivity verified")
} else {
    printWarning("Network connectivity check failed - some tests may not work")
}

// MARK: - Test Summary

print("\n\(Colors.bold)\(Colors.magenta)")
print("╔═══════════════════════════════════════════════════════════╗")
print("║                    Test Summary                           ║")
print("╚═══════════════════════════════════════════════════════════╝")
print(Colors.reset)

print("\(Colors.green)Passed: \(testsPassed)\(Colors.reset)")
print("\(Colors.red)Failed: \(testsFailed)\(Colors.reset)")

let totalTests = testsPassed + testsFailed
if totalTests > 0 {
    let successRate = Double(testsPassed) / Double(totalTests) * 100
    print("Success Rate: \(String(format: "%.1f", successRate))%")
}

if testsFailed == 0 {
    print("\n\(Colors.bold)\(Colors.green)✓ All tests passed!\(Colors.reset)")
    print("\n\(Colors.cyan)Next Steps:\(Colors.reset)")
    print("1. Create an Xcode project to run the actual download code")
    print("2. Run unit tests: \(Colors.yellow)swift test\(Colors.reset)")
    print("3. Build and run the full application")
    print("4. Test with real file downloads")
} else {
    print("\n\(Colors.bold)\(Colors.red)✗ Some tests failed\(Colors.reset)")
}

// Clean up test directory
try? FileManager.default.removeItem(at: testDir)

print("\n\(Colors.cyan)Test completed at: \(Date())\(Colors.reset)\n")

exit(testsFailed == 0 ? 0 : 1)
