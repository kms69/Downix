//
//  QueueManager.swift
//  Download Manager for Mac - Feature #2: Smart Queue
//
//  Created on February 15, 2026
//

import Foundation
import Combine

/// Enhanced queue manager with priority and category support
extension DownloadManager {

    // MARK: - Queue Management with Priorities

    /// Sorting helper used after adding a download (priority/category are now
    /// part of the main `addDownload` in DownloadManager.swift).
    
    /// Sort queue by priority (highest first)
    func sortQueueByPriority() {
        DispatchQueue.main.async {
            self.downloadTasks.sort { task1, task2 in
                // Downloading tasks stay in their position
                if task1.state == .downloading && task2.state != .downloading {
                    return true
                }
                if task2.state == .downloading && task1.state != .downloading {
                    return false
                }
                
                // Completed/failed tasks go to bottom
                let task1Finished = task1.state == .completed || task1.state == .failed || task1.state == .cancelled
                let task2Finished = task2.state == .completed || task2.state == .failed || task2.state == .cancelled
                
                if task1Finished && !task2Finished {
                    return false
                }
                if task2Finished && !task1Finished {
                    return true
                }
                
                // Sort by priority
                if task1.priority != task2.priority {
                    return task1.priority > task2.priority
                }
                
                // Then by queue position (manual ordering)
                return task1.queuePosition < task2.queuePosition
            }
        }
    }
    
    /// Sort queue by custom criteria
    func sortQueue(by option: QueueSortOption, ascending: Bool = true) {
        DispatchQueue.main.async {
            self.downloadTasks.sort { task1, task2 in
                let comparison: Bool
                
                switch option {
                case .priority:
                    comparison = task1.priority.rawValue > task2.priority.rawValue
                    
                case .dateAdded:
                    comparison = task1.createdAt < task2.createdAt
                    
                case .filename:
                    comparison = task1.filename.lowercased() < task2.filename.lowercased()
                    
                case .size:
                    comparison = task1.totalBytes < task2.totalBytes
                    
                case .progress:
                    comparison = task1.progress < task2.progress
                    
                case .speed:
                    comparison = task1.speed < task2.speed
                }
                
                return ascending ? comparison : !comparison
            }
        }
    }
    
    /// Move task to specific position in queue
    func moveTask(_ task: DownloadTask, to index: Int) {
        DispatchQueue.main.async {
            guard let currentIndex = self.downloadTasks.firstIndex(where: { $0.id == task.id }) else {
                return
            }
            
            let clampedIndex = min(max(0, index), self.downloadTasks.count - 1)
            
            self.downloadTasks.remove(at: currentIndex)
            self.downloadTasks.insert(task, at: clampedIndex)
            
            // Update queue positions
            for (idx, task) in self.downloadTasks.enumerated() {
                task.queuePosition = idx
            }
        }
    }
    
    /// Move task up in queue
    func moveTaskUp(_ task: DownloadTask) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == task.id }),
              index > 0 else {
            return
        }
        moveTask(task, to: index - 1)
    }
    
    /// Move task down in queue
    func moveTaskDown(_ task: DownloadTask) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == task.id }),
              index < downloadTasks.count - 1 else {
            return
        }
        moveTask(task, to: index + 1)
    }
    
    /// Move task to top of queue
    func moveTaskToTop(_ task: DownloadTask) {
        moveTask(task, to: 0)
    }
    
    /// Move task to bottom of queue
    func moveTaskToBottom(_ task: DownloadTask) {
        moveTask(task, to: downloadTasks.count - 1)
    }
    
    /// Change task priority
    func setPriority(_ priority: DownloadPriority, for task: DownloadTask) {
        task.priority = priority
        sortQueueByPriority()
        processQueue()
    }
    
    /// Change task category
    func setCategory(_ category: DownloadCategory, for task: DownloadTask) {
        task.category = category
    }
    
    // MARK: - Filtering
    
    /// Get filtered downloads
    func filteredDownloads(filter: QueueFilter) -> [DownloadTask] {
        return downloadTasks.filter { filter.matches($0) }
    }
    
    /// Get downloads by state
    func downloadsByState(_ state: DownloadState) -> [DownloadTask] {
        return downloadTasks.filter { $0.state == state }
    }
    
    /// Get downloads by category
    func downloadsByCategory(_ category: DownloadCategory) -> [DownloadTask] {
        if category == .all {
            return downloadTasks
        }
        return downloadTasks.filter { $0.category == category }
    }
    
    /// Get downloads by priority
    func downloadsByPriority(_ priority: DownloadPriority) -> [DownloadTask] {
        return downloadTasks.filter { $0.priority == priority }
    }
    
    // MARK: - Batch Operations
    
    /// Pause downloads by category
    func pauseCategory(_ category: DownloadCategory) {
        let tasks = downloadsByCategory(category).filter { $0.state == .downloading }
        Task { @MainActor in
            for task in tasks { await self.pauseDownload(task) }
        }
    }
    
    /// Resume downloads by category
    func resumeCategory(_ category: DownloadCategory) {
        let tasks = downloadsByCategory(category).filter { $0.state == .paused }
        Task { @MainActor in
            for task in tasks {
                if self.activeDownloads < self.maxConcurrentDownloads {
                    await self.resumeDownload(task)
                }
            }
        }
    }
    
    /// Pause downloads by priority
    func pausePriority(_ priority: DownloadPriority) {
        let tasks = downloadsByPriority(priority).filter { $0.state == .downloading }
        Task { @MainActor in
            for task in tasks { await self.pauseDownload(task) }
        }
    }
    
    /// Resume downloads by priority
    func resumePriority(_ priority: DownloadPriority) {
        let tasks = downloadsByPriority(priority).filter { $0.state == .paused }
        Task { @MainActor in
            for task in tasks {
                if self.activeDownloads < self.maxConcurrentDownloads {
                    await self.resumeDownload(task)
                }
            }
        }
    }
    
    // MARK: - Queue Statistics
    
    /// Get queue statistics
    func getQueueStatistics() -> QueueStatistics {
        let byState = Dictionary(grouping: downloadTasks, by: { $0.state })
        let byPriority = Dictionary(grouping: downloadTasks, by: { $0.priority })
        let byCategory = Dictionary(grouping: downloadTasks, by: { $0.category })
        
        return QueueStatistics(
            total: downloadTasks.count,
            waiting: byState[.waiting]?.count ?? 0,
            downloading: byState[.downloading]?.count ?? 0,
            paused: byState[.paused]?.count ?? 0,
            completed: byState[.completed]?.count ?? 0,
            failed: byState[.failed]?.count ?? 0,
            urgent: byPriority[.urgent]?.count ?? 0,
            high: byPriority[.high]?.count ?? 0,
            normal: byPriority[.normal]?.count ?? 0,
            low: byPriority[.low]?.count ?? 0,
            categoryCounts: byCategory.mapValues { $0.count }
        )
    }
    
    /// Enhanced queue processing with priority support
    private func processQueueWithPriority() {
        // Get waiting tasks sorted by priority
        let waitingTasks = downloadTasks
            .filter { $0.state == .waiting }
            .sorted { $0.priority > $1.priority }
        
        for task in waitingTasks {
            if activeDownloads < maxConcurrentDownloads {
                startDownload(task)
            } else {
                break
            }
        }
    }
}

// MARK: - Supporting Types

struct QueueStatistics {
    let total: Int
    let waiting: Int
    let downloading: Int
    let paused: Int
    let completed: Int
    let failed: Int
    
    let urgent: Int
    let high: Int
    let normal: Int
    let low: Int
    
    let categoryCounts: [DownloadCategory: Int]
    
    var activeCount: Int {
        downloading + waiting
    }
    
    var finishedCount: Int {
        completed + failed
    }
}
