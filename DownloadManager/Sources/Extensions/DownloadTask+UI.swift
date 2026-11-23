import Foundation

/// Extension to provide UI-compatible properties
extension DownloadTask {
    /// Alias for filename (UI compatibility)
    var name: String {
        get { filename }
        set { filename = newValue }
    }
    
    /// Alias for state (UI compatibility)
    var status: DownloadState {
        get { state }
        set { state = newValue }
    }
    
    /// Destination URL (UI compatibility)
    var destination: URL? {
        get { destinationPath }
        set { if let url = newValue { destinationPath = url } }
    }
    
    /// Checksum for verification (optional)
    var checksum: String? {
        get { nil } // TODO: Implement checksum storage
        set { } // TODO: Implement checksum storage
    }
    
    /// Estimated time remaining
    var estimatedTimeRemaining: TimeInterval {
        timeRemaining
    }

    /// Sortable value for the Last Try column.
    var lastAttemptSortValue: Date {
        lastAttemptAt ?? .distantPast
    }

    /// Sortable rank for the Status column: active work first, then terminal
    /// states, instead of alphabetical order of the case names.
    var statusSortRank: Int {
        switch state {
        case .downloading: return 0
        case .paused: return 1
        case .waiting: return 2
        case .completed: return 3
        case .failed: return 4
        case .cancelled: return 5
        }
    }
    
    /// File type category
    var fileCategory: FileType {
        // Determine from file extension
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        case "mp4", "mov", "avi", "mkv", "webm", "flv", "m4v":
            return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg":
            return .audio
        case "pdf", "doc", "docx", "txt", "rtf", "pages":
            return .document
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return .archive
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "svg":
            return .image
        case "app", "dmg", "pkg":
            return .application
        default:
            return .other
        }
    }
}

/// Date ordering for the Last Try column: the first header click lists the
/// most recently tried downloads first, like IDM. Later clicks toggle.
struct NewestFirstDateComparator: SortComparator {
    var order: SortOrder = .reverse

    func compare(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        let result: ComparisonResult = lhs < rhs ? .orderedAscending
            : (lhs > rhs ? .orderedDescending : .orderedSame)
        switch (order, result) {
        case (.forward, _): return result
        case (.reverse, .orderedAscending): return .orderedDescending
        case (.reverse, .orderedDescending): return .orderedAscending
        case (.reverse, .orderedSame): return .orderedSame
        }
    }
}

/// File type categories for organization
enum FileType: String, Codable, CaseIterable {
    case video
    case audio
    case document
    case archive
    case image
    case application
    case other
}

/// Type alias for UI compatibility
typealias DownloadStatus = DownloadState
