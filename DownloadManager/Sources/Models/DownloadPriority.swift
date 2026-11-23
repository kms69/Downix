//
//  DownloadPriority.swift
//  Download Manager for Mac - Feature #2: Smart Queue
//
//  Created on February 15, 2026
//

import Foundation

/// Download priority levels
enum DownloadPriority: Int, Codable, CaseIterable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "arrow.down.circle"
        case .normal: return "equal.circle"
        case .high: return "arrow.up.circle"
        case .urgent: return "exclamationmark.circle"
        }
    }
    
    static func < (lhs: DownloadPriority, rhs: DownloadPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Download categories for organization
enum DownloadCategory: String, Codable, CaseIterable {
    case all = "All Downloads"
    case documents = "Documents"
    case videos = "Videos"
    case audio = "Audio"
    case images = "Images"
    case archives = "Archives"
    case applications = "Applications"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .documents: return "doc.text"
        case .videos: return "video"
        case .audio: return "music.note"
        case .images: return "photo"
        case .archives: return "archivebox"
        case .applications: return "app"
        case .other: return "questionmark.folder"
        }
    }
    
    var color: String {
        switch self {
        case .all: return "blue"
        case .documents: return "orange"
        case .videos: return "purple"
        case .audio: return "pink"
        case .images: return "green"
        case .archives: return "brown"
        case .applications: return "cyan"
        case .other: return "gray"
        }
    }
    
    /// Auto-detect category from file extension
    static func detect(from filename: String) -> DownloadCategory {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        // Documents
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "xlsx", "xls", "ppt", "pptx", "key", "numbers":
            return .documents
            
        // Videos
        case "mp4", "mov", "avi", "mkv", "webm", "flv", "m4v", "mpg", "mpeg", "wmv":
            return .videos
            
        // Audio
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "wma", "aiff":
            return .audio
            
        // Images
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg", "webp", "heic":
            return .images
            
        // Archives
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso":
            return .archives
            
        // Applications
        case "app", "pkg", "dmg", "exe":
            return .applications
            
        default:
            return .other
        }
    }
}

/// Queue filter options
struct QueueFilter {
    var state: DownloadState?
    var category: DownloadCategory?
    var priority: DownloadPriority?
    var searchText: String?
    
    init(state: DownloadState? = nil, 
         category: DownloadCategory? = nil,
         priority: DownloadPriority? = nil,
         searchText: String? = nil) {
        self.state = state
        self.category = category
        self.priority = priority
        self.searchText = searchText
    }
    
    /// Check if a download task matches this filter
    func matches(_ task: DownloadTask) -> Bool {
        // State filter
        if let state = state, task.state != state {
            return false
        }
        
        // Category filter
        if let category = category, category != .all, task.category != category {
            return false
        }
        
        // Priority filter
        if let priority = priority, task.priority != priority {
            return false
        }
        
        // Search text filter
        if let searchText = searchText, !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            let filenameMatch = task.filename.lowercased().contains(lowercasedSearch)
            let urlMatch = task.url.absoluteString.lowercased().contains(lowercasedSearch)
            
            if !filenameMatch && !urlMatch {
                return false
            }
        }
        
        return true
    }
}

/// Queue sorting options
enum QueueSortOption: String, CaseIterable {
    case priority = "Priority"
    case dateAdded = "Date Added"
    case filename = "Filename"
    case size = "Size"
    case progress = "Progress"
    case speed = "Speed"
    
    var icon: String {
        switch self {
        case .priority: return "star"
        case .dateAdded: return "calendar"
        case .filename: return "textformat.abc"
        case .size: return "externaldrive"
        case .progress: return "chart.bar"
        case .speed: return "speedometer"
        }
    }
}

extension DownloadTask {
    /// Priority for queue management
    var priority: DownloadPriority {
        get { _priority }
        set { _priority = newValue }
    }
    
    private var _priority: DownloadPriority {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.priority) as? DownloadPriority ?? .normal
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.priority, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// Category for organization
    var category: DownloadCategory {
        get { _category }
        set { _category = newValue }
    }
    
    private var _category: DownloadCategory {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.category) as? DownloadCategory 
                ?? DownloadCategory.detect(from: filename)
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.category, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// Queue position for manual ordering
    var queuePosition: Int {
        get { _queuePosition }
        set { _queuePosition = newValue }
    }
    
    private var _queuePosition: Int {
        get {
            objc_getAssociatedObject(self, &AssociatedKeys.queuePosition) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.queuePosition, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private struct AssociatedKeys {
        static var priority = "priority"
        static var category = "category"
        static var queuePosition = "queuePosition"
    }
}
