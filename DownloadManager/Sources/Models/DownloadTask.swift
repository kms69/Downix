//
//  DownloadTask.swift
//  Download Manager for Mac
//
//  Created on February 14, 2026
//

import Foundation

/// Represents the current state of a download
enum DownloadState: String, Codable {
    case waiting
    case downloading
    case paused
    case completed
    case failed
    case cancelled
}

/// Represents a single download task with all its metadata
class DownloadTask: Identifiable, ObservableObject {
    let id: UUID
    let url: URL
    var destinationPath: URL
    var filename: String
    
    @Published var state: DownloadState = .waiting
    @Published var progress: Double = 0.0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var speed: Int64 = 0 // bytes per second
    @Published var timeRemaining: TimeInterval = 0
    
    // Multi-threading configuration
    var numberOfSegments: Int = 8
    var segments: [DownloadSegment] = []
    
    // Resume capability
    var supportsResume: Bool = false
    var resumeData: Data?

    /// Extra HTTP headers sent with every request for this download
    /// (Referer, Cookie, User-Agent captured by the browser extension).
    /// "Cookie" is kept in memory only and is never written to disk.
    var requestHeaders: [String: String] = [:]

    /// True when the user (not the scheduler / network monitor) paused or
    /// stopped this download. Automatic resumers must leave such tasks alone.
    var manuallyHeld: Bool = false

    /// True while a scheduled download is waiting for its start time.
    /// The queue never starts a task that is held for its schedule.
    var isHeldForSchedule: Bool = false

    /// User-initiated downloads get the IDM-style "Download Complete" dialog.
    /// Not persisted: restored/scheduled tasks stay quiet.
    var showsCompletionDialog: Bool = false
    
    // Error handling
    var error: Error?
    var retryCount: Int = 0
    var maxRetries: Int = 3

    /// Last time the engine actually tried to transfer this download.
    var lastAttemptAt: Date?

    /// Set for rows that mirror a streaming video task driven by
    /// `VideoDownloadManager` (yt-dlp). Transient; never persisted.
    var videoTaskID: UUID?

    /// A streaming-video row restored after relaunch: its video task is gone, so
    /// Resume / Re-add start a fresh download of the same page instead.
    var isRestoredStreaming = false

    /// UI-only status label for transient engine phases (e.g. "Converting").
    var statusDetail: String?

    // Metadata
    var createdAt: Date
    var completedAt: Date?
    var fileType: String?
    var mimeType: String?
    
    init(id: UUID = UUID(), url: URL, destinationPath: URL, filename: String? = nil, numberOfSegments: Int = 8) {
        self.id = id
        self.url = url
        self.destinationPath = destinationPath
        self.filename = filename ?? url.lastPathComponent
        self.numberOfSegments = numberOfSegments
        self.createdAt = Date()
    }
    
    /// Full path of the output file (destination folder + filename).
    var fileURL: URL {
        destinationPath.appendingPathComponent(filename)
    }

    /// Calculate estimated time remaining
    func updateTimeRemaining() {
        guard speed > 0, totalBytes > 0 else {
            timeRemaining = 0
            return
        }
        let remainingBytes = totalBytes - downloadedBytes
        timeRemaining = TimeInterval(remainingBytes) / TimeInterval(speed)
    }
    
    /// Format speed for display
    var formattedSpeed: String {
        return ByteCountFormatter.string(fromByteCount: speed, countStyle: .file) + "/s"
    }
    
    /// Format time remaining for display
    var formattedTimeRemaining: String {
        if timeRemaining.isInfinite || timeRemaining.isNaN {
            return "Calculating..."
        }
        
        let hours = Int(timeRemaining) / 3600
        let minutes = Int(timeRemaining) / 60 % 60
        let seconds = Int(timeRemaining) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

/// Represents a segment of a file being downloaded in parallel
struct DownloadSegment: Identifiable {
    let id: UUID
    let segmentIndex: Int
    let startByte: Int64
    let endByte: Int64
    var downloadedBytes: Int64 = 0
    var isComplete: Bool = false
    var task: URLSessionDownloadTask?
    
    init(segmentIndex: Int, startByte: Int64, endByte: Int64) {
        self.id = UUID()
        self.segmentIndex = segmentIndex
        self.startByte = startByte
        self.endByte = endByte
    }
    
    var progress: Double {
        let totalBytes = endByte - startByte + 1
        return Double(downloadedBytes) / Double(totalBytes)
    }
}
