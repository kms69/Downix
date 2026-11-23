//
//  Example.swift
//  Download Manager for Mac - Usage Examples
//
//  Created on February 14, 2026
//

import Foundation

/// Example usage of the Download Manager
class DownloadManagerExamples {
    
    // MARK: - Example 1: Basic Download
    
    func basicDownload() {
        let manager = DownloadManager.shared
        
        // Download a file
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.addDownload(url: url)
        
        print("Download started: \(task.filename)")
    }
    
    // MARK: - Example 2: Download with Custom Settings
    
    func customDownload() {
        let manager = DownloadManager.shared
        
        let url = URL(string: "https://example.com/largefile.zip")!
        let destination = URL(fileURLWithPath: "/Users/user/Downloads")
        
        let task = manager.addDownload(
            url: url,
            destinationPath: destination,
            filename: "my_custom_name.zip",
            numberOfSegments: 16  // Use 16 parallel connections for faster download
        )
        
        print("Custom download started with 16 segments")
    }
    
    // MARK: - Example 3: Monitor Download Progress
    
    func monitorProgress() {
        let manager = DownloadManager.shared
        let url = URL(string: "https://speed.hetzner.de/100MB.bin")!
        let task = manager.addDownload(url: url)
        
        // Create a timer to check progress
        var timer: Timer?
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            switch task.state {
            case .downloading:
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📥 \(task.filename)")
                print("Progress: \(Int(task.progress * 100))%")
                print("Speed: \(task.formattedSpeed)")
                print("Downloaded: \(ByteCountFormatter.string(fromByteCount: task.downloadedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file))")
                print("Time remaining: \(task.formattedTimeRemaining)")
                print("Active segments: \(task.segments.filter { !$0.isComplete }.count)/\(task.segments.count)")
                
            case .completed:
                print("✅ Download completed!")
                t.invalidate()
                timer = nil
                
            case .failed:
                print("❌ Download failed: \(task.error?.localizedDescription ?? "Unknown error")")
                t.invalidate()
                timer = nil
                
            case .paused:
                print("⏸ Download paused")
                
            case .waiting:
                print("⏳ Waiting in queue...")
                
            case .cancelled:
                print("🚫 Download cancelled")
                t.invalidate()
                timer = nil
            }
        }
    }
    
    // MARK: - Example 4: Pause and Resume
    
    func pauseResumeExample() {
        let manager = DownloadManager.shared
        let url = URL(string: "https://example.com/file.zip")!
        let task = manager.addDownload(url: url)
        
        // Pause after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            manager.pauseDownload(task)
            print("⏸ Download paused")
            
            // Resume after another 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                manager.resumeDownload(task)
                print("▶️ Download resumed")
            }
        }
    }
    
    // MARK: - Example 5: Multiple Downloads
    
    func multipleDownloads() {
        let manager = DownloadManager.shared
        
        // Configure max concurrent downloads
        manager.maxConcurrentDownloads = 3
        
        let urls = [
            "https://example.com/file1.zip",
            "https://example.com/file2.pdf",
            "https://example.com/file3.mp4",
            "https://example.com/file4.iso",
            "https://example.com/file5.dmg"
        ]
        
        // Add all downloads
        for urlString in urls {
            if let url = URL(string: urlString) {
                let task = manager.addDownload(url: url)
                print("Added: \(task.filename)")
            }
        }
        
        // Monitor queue status
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("Queue Status:")
            print("Active downloads: \(manager.activeDownloads)/\(manager.maxConcurrentDownloads)")
            print("Total speed: \(manager.formattedTotalSpeed)")
            print("Waiting: \(manager.downloadTasks.filter { $0.state == .waiting }.count)")
            print("Downloading: \(manager.downloadTasks.filter { $0.state == .downloading }.count)")
            print("Completed: \(manager.downloadTasks.filter { $0.state == .completed }.count)")
        }
    }
    
    // MARK: - Example 6: Batch Operations
    
    func batchOperations() {
        let manager = DownloadManager.shared
        
        // Pause all downloads
        manager.pauseAll()
        print("⏸ All downloads paused")
        
        // Resume all downloads
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            manager.resumeAll()
            print("▶️ All downloads resumed")
        }
        
        // Clear completed downloads
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            manager.clearCompleted()
            print("🧹 Cleared completed downloads")
        }
    }
    
    // MARK: - Example 7: Download Statistics
    
    func showStatistics() {
        let manager = DownloadManager.shared
        let stats = manager.getStatistics()
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 Download Statistics")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Total downloads completed: \(stats.totalDownloads)")
        print("Total data downloaded: \(stats.formattedTotalBytes)")
        print("Active downloads: \(stats.activeDownloads)")
        print("Current download speed: \(stats.formattedSpeed)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    // MARK: - Example 8: Real-World Usage
    
    func realWorldExample() {
        let manager = DownloadManager.shared
        
        // Configure for optimal performance
        manager.maxConcurrentDownloads = 5
        manager.defaultNumberOfSegments = 8
        manager.defaultSaveLocation = URL(fileURLWithPath: "/Users/user/Downloads")
        
        // Download a large file with monitoring
        let url = URL(string: "https://releases.ubuntu.com/22.04/ubuntu-22.04.3-desktop-amd64.iso")!
        
        let task = manager.addDownload(
            url: url,
            filename: "Ubuntu-22.04-Desktop.iso",
            numberOfSegments: 16
        )
        
        print("Starting download of Ubuntu ISO...")
        print("File will be saved to: \(manager.defaultSaveLocation.path)")
        
        // Monitor with detailed progress
        var lastProgress = 0
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if task.state == .downloading {
                let currentProgress = Int(task.progress * 100)
                
                // Only print if progress changed
                if currentProgress != lastProgress {
                    let progressBar = String(repeating: "█", count: currentProgress / 2) + 
                                    String(repeating: "░", count: 50 - currentProgress / 2)
                    
                    print("\n[\(progressBar)] \(currentProgress)%")
                    print("Speed: \(task.formattedSpeed) | Remaining: \(task.formattedTimeRemaining)")
                    print("Downloaded: \(ByteCountFormatter.string(fromByteCount: task.downloadedBytes, countStyle: .file))")
                    
                    // Show segment progress
                    let completedSegments = task.segments.filter { $0.isComplete }.count
                    print("Segments: \(completedSegments)/\(task.segments.count) complete")
                    
                    lastProgress = currentProgress
                }
            } else if task.state == .completed {
                print("\n✅ Download completed successfully!")
                print("File saved to: \(task.destinationPath.path)/\(task.filename)")
                print("Total time: \(Int(task.completedAt?.timeIntervalSince(task.createdAt) ?? 0)) seconds")
                timer.invalidate()
            } else if task.state == .failed {
                print("\n❌ Download failed!")
                if let error = task.error {
                    print("Error: \(error.localizedDescription)")
                }
                print("Retry count: \(task.retryCount)/\(task.maxRetries)")
                timer.invalidate()
            }
        }
    }
}

// MARK: - Run Examples

/// Uncomment to run specific examples
func runExamples() {
    let examples = DownloadManagerExamples()
    
    // Choose which example to run:
    // examples.basicDownload()
    // examples.customDownload()
    // examples.monitorProgress()
    // examples.pauseResumeExample()
    // examples.multipleDownloads()
    // examples.batchOperations()
    // examples.showStatistics()
    examples.realWorldExample()
}

// Run the examples (uncomment to execute)
// runExamples()
