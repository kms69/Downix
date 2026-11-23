//
//  MediaPreview.swift
//  Download Manager for Mac - Feature #11: Media Preview & Quick Look
//
//  Created on February 16, 2026
//

import Foundation
import AVFoundation
import QuickLook
import Quartz
import AppKit

// MARK: - Media Type

/// Represents the type of media for preview
enum MediaType: String, Codable {
    case video
    case audio
    case image
    case document
    case archive
    case application
    case unknown
    
    /// Icon for the media type
    var icon: String {
        switch self {
        case .video: return "video.fill"
        case .audio: return "music.note"
        case .image: return "photo.fill"
        case .document: return "doc.fill"
        case .archive: return "doc.zipper"
        case .application: return "app.fill"
        case .unknown: return "doc"
        }
    }
    
    /// Supports preview
    var supportsPreview: Bool {
        switch self {
        case .video, .audio, .image, .document:
            return true
        case .archive, .application, .unknown:
            return false
        }
    }
    
    /// Supports Quick Look
    var supportsQuickLook: Bool {
        return true // Quick Look supports most file types
    }
    
    /// Detect media type from file extension
    static func from(fileExtension: String) -> MediaType {
        let ext = fileExtension.lowercased()
        
        // Video formats
        if ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm", "mpeg", "mpg", "3gp", "m3u8"].contains(ext) {
            return .video
        }
        
        // Audio formats
        if ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma", "aiff", "alac", "opus"].contains(ext) {
            return .audio
        }
        
        // Image formats
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg", "ico"].contains(ext) {
            return .image
        }
        
        // Document formats
        if ["pdf", "doc", "docx", "txt", "rtf", "pages", "key", "numbers", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "md", "html", "htm"].contains(ext) {
            return .document
        }
        
        // Archive formats
        if ["zip", "tar", "gz", "bz2", "7z", "rar", "dmg", "iso", "pkg"].contains(ext) {
            return .archive
        }
        
        // Application formats
        if ["app", "exe", "dmg", "pkg"].contains(ext) {
            return .application
        }
        
        return .unknown
    }
    
    /// Detect from MIME type
    static func from(mimeType: String) -> MediaType {
        let mime = mimeType.lowercased()
        
        if mime.hasPrefix("video/") {
            return .video
        } else if mime.hasPrefix("audio/") {
            return .audio
        } else if mime.hasPrefix("image/") {
            return .image
        } else if mime.hasPrefix("text/") || mime.contains("pdf") || mime.contains("document") {
            return .document
        } else if mime.contains("zip") || mime.contains("compressed") || mime.contains("archive") {
            return .archive
        } else if mime.contains("application") {
            return .application
        }
        
        return .unknown
    }
}

// MARK: - Media Metadata

/// Metadata extracted from media files
struct MediaMetadata: Codable {
    var title: String?
    var artist: String?
    var album: String?
    var genre: String?
    var year: Int?
    var duration: TimeInterval?
    var bitrate: Int? // bits per second
    var sampleRate: Int? // Hz
    var resolution: CGSize?
    var frameRate: Double? // fps
    var codec: String?
    var fileSize: Int64
    var creationDate: Date?
    var modificationDate: Date?
    
    /// Format duration for display
    func formattedDuration() -> String {
        guard let duration = duration else { return "Unknown" }
        
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Format bitrate for display
    func formattedBitrate() -> String {
        guard let bitrate = bitrate else { return "Unknown" }
        
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        } else if bitrate >= 1_000 {
            return String(format: "%.0f kbps", Double(bitrate) / 1_000)
        } else {
            return "\(bitrate) bps"
        }
    }
    
    /// Format resolution for display
    func formattedResolution() -> String {
        guard let resolution = resolution else { return "Unknown" }
        return "\(Int(resolution.width))x\(Int(resolution.height))"
    }
    
    /// Format frame rate for display
    func formattedFrameRate() -> String {
        guard let frameRate = frameRate else { return "Unknown" }
        return String(format: "%.2f fps", frameRate)
    }
}

// MARK: - Thumbnail

/// Represents a generated thumbnail
struct ThumbnailInfo: Codable {
    let thumbnailPath: URL
    let size: CGSize
    let generatedAt: Date
    
    /// Load the thumbnail image
    func loadImage() -> NSImage? {
        return NSImage(contentsOf: thumbnailPath)
    }
}

// MARK: - Preview State

/// Current state of preview generation
enum PreviewState: String, Codable {
    case idle
    case generating
    case ready
    case failed
    case notSupported
}

// MARK: - Media Preview Info

/// Complete preview information for a downloaded file
struct MediaPreviewInfo: Identifiable, Codable {
    let id: UUID
    let taskId: UUID // Associated download task
    let filePath: URL
    let mediaType: MediaType
    var metadata: MediaMetadata?
    var thumbnail: ThumbnailInfo?
    var previewState: PreviewState = .idle
    var error: String?
    
    init(taskId: UUID, filePath: URL, mediaType: MediaType) {
        self.id = UUID()
        self.taskId = taskId
        self.filePath = filePath
        self.mediaType = mediaType
    }
    
    /// Check if file exists and is accessible
    func fileExists() -> Bool {
        return FileManager.default.fileExists(atPath: filePath.path)
    }
    
    /// Get file size
    func fileSize() -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath.path) else {
            return nil
        }
        return attributes[.size] as? Int64
    }
    
    /// Check if preview is available
    var isPreviewAvailable: Bool {
        return previewState == .ready && mediaType.supportsPreview
    }
    
    /// Check if Quick Look is available
    var isQuickLookAvailable: Bool {
        return fileExists() && mediaType.supportsQuickLook
    }
}

// MARK: - Partial Download Preview

/// Configuration for previewing partially downloaded files
struct PartialPreviewConfig {
    /// Minimum bytes required to attempt preview
    var minimumBytes: Int64 = 1_000_000 // 1 MB
    
    /// Percentage of file required for preview
    var minimumPercentage: Double = 5.0 // 5%
    
    /// Enable preview while downloading
    var enableWhileDownloading: Bool = true
    
    /// Maximum file size for partial preview (to avoid memory issues)
    var maxFileSizeForPartialPreview: Int64 = 100_000_000 // 100 MB
    
    /// Check if partial preview is possible
    func canPreview(downloadedBytes: Int64, totalBytes: Int64) -> Bool {
        guard enableWhileDownloading else { return false }
        guard totalBytes > 0 && totalBytes <= maxFileSizeForPartialPreview else { return false }
        
        let hasMinimumBytes = downloadedBytes >= minimumBytes
        let hasMinimumPercentage = (Double(downloadedBytes) / Double(totalBytes) * 100) >= minimumPercentage
        
        return hasMinimumBytes && hasMinimumPercentage
    }
}

// MARK: - Quick Look Preview Item

/// NSObject wrapper for Quick Look preview
class QuickLookPreviewItem: NSObject, QLPreviewItem {
    let fileURL: URL
    let displayName: String?
    
    init(url: URL, name: String? = nil) {
        self.fileURL = url
        self.displayName = name
        super.init()
    }
    
    var previewItemURL: URL? {
        return fileURL
    }
    
    var previewItemTitle: String? {
        return displayName ?? fileURL.lastPathComponent
    }
}

// MARK: - Preview Generation Options

/// Options for thumbnail and metadata generation
struct PreviewGenerationOptions {
    /// Generate thumbnails
    var generateThumbnails: Bool = true
    
    /// Thumbnail size
    var thumbnailSize: CGSize = CGSize(width: 512, height: 512)
    
    /// Extract metadata
    var extractMetadata: Bool = true
    
    /// Generate multiple thumbnail sizes
    var generateMultipleSizes: Bool = false
    
    /// Additional thumbnail sizes
    var additionalSizes: [CGSize] = [
        CGSize(width: 128, height: 128),
        CGSize(width: 256, height: 256)
    ]
    
    /// Quality for image thumbnails (0.0 - 1.0)
    var thumbnailQuality: Double = 0.8
    
    /// Background generation (async)
    var backgroundGeneration: Bool = true
}

// MARK: - Preview Cache

/// Cache for preview data
class PreviewCache {
    static let shared = PreviewCache()
    
    private var cache: [UUID: MediaPreviewInfo] = [:]
    private let queue = DispatchQueue(label: "com.rapiddownload.previewcache", attributes: .concurrent)
    
    private init() {}
    
    /// Store preview info in cache
    func store(_ previewInfo: MediaPreviewInfo) {
        queue.async(flags: .barrier) {
            self.cache[previewInfo.id] = previewInfo
        }
    }
    
    /// Retrieve preview info from cache
    func retrieve(id: UUID) -> MediaPreviewInfo? {
        return queue.sync {
            return cache[id]
        }
    }
    
    /// Retrieve by task ID
    func retrieve(taskId: UUID) -> MediaPreviewInfo? {
        return queue.sync {
            return cache.values.first { $0.taskId == taskId }
        }
    }
    
    /// Remove from cache
    func remove(id: UUID) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: id)
        }
    }
    
    /// Clear all cache
    func clearAll() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
    
    /// Get all cached previews
    func allPreviews() -> [MediaPreviewInfo] {
        return queue.sync {
            return Array(cache.values)
        }
    }
}

// MARK: - Extensions

extension MediaMetadata {
    /// Create from AVAsset
    static func from(asset: AVAsset) async -> MediaMetadata? {
        var metadata = MediaMetadata(fileSize: 0)
        
        // Duration
        let duration = try? await asset.load(.duration)
        metadata.duration = duration?.seconds
        
        // Tracks
        if let tracks = try? await asset.load(.tracks) {
            // Video track
            if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                if let size = try? await videoTrack.load(.naturalSize) {
                    metadata.resolution = size
                }
                if let frameRate = try? await videoTrack.load(.nominalFrameRate) {
                    metadata.frameRate = Double(frameRate)
                }
            }
            
            // Audio track
            if tracks.contains(where: { $0.mediaType == .audio }) {
                // Sample rate would require AudioStreamBasicDescription parsing
            }
        }
        
        // Common metadata
        if let commonMetadata = try? await asset.load(.commonMetadata) {
            for item in commonMetadata {
                if let key = item.commonKey?.rawValue {
                    switch key {
                    case "title":
                        metadata.title = try? await item.load(.stringValue)
                    case "artist":
                        metadata.artist = try? await item.load(.stringValue)
                    case "albumName":
                        metadata.album = try? await item.load(.stringValue)
                    default:
                        break
                    }
                }
            }
        }
        
        return metadata
    }
}
