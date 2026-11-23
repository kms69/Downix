//
//  MediaPreviewManager.swift
//  Download Manager for Mac - Feature #11: Media Preview & Quick Look Manager
//
//  Created on February 16, 2026
//

import Foundation
import AVFoundation
import QuickLook
import Quartz
import AppKit
import Combine

/// Manages media preview, Quick Look integration, and thumbnail generation
class MediaPreviewManager: NSObject, ObservableObject {
    
    static let shared = MediaPreviewManager()
    
    @Published var previews: [MediaPreviewInfo] = []
    @Published var currentPreview: MediaPreviewInfo?
    
    private var partialPreviewConfig = PartialPreviewConfig()
    private var generationOptions = PreviewGenerationOptions()
    private let cache = PreviewCache.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Quick Look panel
    private var quickLookPanel: QLPreviewPanel?
    private var previewItems: [QuickLookPreviewItem] = []
    private var currentPreviewIndex: Int = 0
    
    private override init() {
        super.init()
        loadPreviews()
    }
    
    // MARK: - Preview Generation
    
    /// Generate preview for a completed download
    func generatePreview(for taskId: UUID, filePath: URL) async throws -> MediaPreviewInfo {
        // Detect media type
        let fileExtension = filePath.pathExtension
        let mediaType = MediaType.from(fileExtension: fileExtension)
        
        // Create preview info
        var previewInfo = MediaPreviewInfo(taskId: taskId, filePath: filePath, mediaType: mediaType)
        
        // Check if file exists
        guard previewInfo.fileExists() else {
            previewInfo.previewState = .failed
            previewInfo.error = "File not found"
            return previewInfo
        }
        
        // Check if preview is supported
        guard mediaType.supportsPreview else {
            previewInfo.previewState = .notSupported
            return previewInfo
        }
        
        previewInfo.previewState = .generating
        
        // Extract metadata
        if generationOptions.extractMetadata {
            previewInfo.metadata = try await extractMetadata(from: filePath, mediaType: mediaType)
        }
        
        // Generate thumbnail
        if generationOptions.generateThumbnails {
            previewInfo.thumbnail = try await generateThumbnail(from: filePath, mediaType: mediaType, size: generationOptions.thumbnailSize)
        }
        
        previewInfo.previewState = .ready
        
        // Cache and store
        cache.store(previewInfo)
        await MainActor.run {
            if let index = previews.firstIndex(where: { $0.id == previewInfo.id }) {
                previews[index] = previewInfo
            } else {
                previews.append(previewInfo)
            }
        }
        
        savePreviews()
        
        return previewInfo
    }
    
    /// Generate preview for partial download (while downloading)
    func generatePartialPreview(for taskId: UUID, filePath: URL, downloadedBytes: Int64, totalBytes: Int64) async throws -> MediaPreviewInfo? {
        guard partialPreviewConfig.canPreview(downloadedBytes: downloadedBytes, totalBytes: totalBytes) else {
            return nil
        }
        
        return try await generatePreview(for: taskId, filePath: filePath)
    }
    
    // MARK: - Metadata Extraction
    
    /// Extract metadata from media file
    private func extractMetadata(from url: URL, mediaType: MediaType) async throws -> MediaMetadata {
        var metadata = MediaMetadata(fileSize: 0)
        
        // Get file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        metadata.fileSize = attributes[.size] as? Int64 ?? 0
        metadata.creationDate = attributes[.creationDate] as? Date
        metadata.modificationDate = attributes[.modificationDate] as? Date
        
        switch mediaType {
        case .video, .audio:
            return try await extractAVMetadata(from: url)
            
        case .image:
            return extractImageMetadata(from: url)
            
        case .document:
            return metadata // Basic file info only for documents
            
        default:
            return metadata
        }
    }
    
    /// Extract metadata using AVFoundation
    private func extractAVMetadata(from url: URL) async throws -> MediaMetadata {
        let asset = AVAsset(url: url)
        
        guard let metadata = await MediaMetadata.from(asset: asset) else {
            throw PreviewError.metadataExtractionFailed
        }
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        var finalMetadata = metadata
        finalMetadata.fileSize = attributes[.size] as? Int64 ?? 0
        finalMetadata.creationDate = attributes[.creationDate] as? Date
        finalMetadata.modificationDate = attributes[.modificationDate] as? Date
        
        return finalMetadata
    }
    
    /// Extract image metadata
    private func extractImageMetadata(from url: URL) -> MediaMetadata {
        var metadata = MediaMetadata(fileSize: 0)
        
        // Get file attributes
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            metadata.fileSize = attributes[.size] as? Int64 ?? 0
            metadata.creationDate = attributes[.creationDate] as? Date
            metadata.modificationDate = attributes[.modificationDate] as? Date
        }
        
        // Get image dimensions
        if let image = NSImage(contentsOf: url) {
            metadata.resolution = image.size
        }
        
        return metadata
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generate thumbnail for media file
    private func generateThumbnail(from url: URL, mediaType: MediaType, size: CGSize) async throws -> ThumbnailInfo {
        let thumbnailsDir = getThumbnailsDirectory()
        let thumbnailFilename = "\(UUID().uuidString).jpg"
        let thumbnailPath = thumbnailsDir.appendingPathComponent(thumbnailFilename)
        
        var thumbnail: NSImage?
        
        switch mediaType {
        case .video:
            thumbnail = try await generateVideoThumbnail(from: url, size: size)
            
        case .audio:
            thumbnail = generateDefaultThumbnail(for: mediaType, size: size)
            
        case .image:
            thumbnail = generateImageThumbnail(from: url, size: size)
            
        case .document:
            thumbnail = generateDocumentThumbnail(from: url, size: size)
            
        default:
            thumbnail = generateDefaultThumbnail(for: mediaType, size: size)
        }
        
        guard let thumbnail = thumbnail else {
            throw PreviewError.thumbnailGenerationFailed
        }
        
        // Save thumbnail
        try saveThumbnail(thumbnail, to: thumbnailPath)
        
        return ThumbnailInfo(
            thumbnailPath: thumbnailPath,
            size: size,
            generatedAt: Date()
        )
    }
    
    /// Generate video thumbnail
    private func generateVideoThumbnail(from url: URL, size: CGSize) async throws -> NSImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = size
        
        // Get thumbnail at 1 second or 10% of duration
        let duration = try await asset.load(.duration)
        let time = CMTime(seconds: min(1.0, duration.seconds * 0.1), preferredTimescale: 600)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            throw PreviewError.thumbnailGenerationFailed
        }
    }
    
    /// Generate image thumbnail
    private func generateImageThumbnail(from url: URL, size: CGSize) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        
        return image.resized(to: size)
    }
    
    /// Generate document thumbnail using Quick Look
    private func generateDocumentThumbnail(from url: URL, size: CGSize) -> NSImage? {
        // For documents, use a generic document icon
        // Note: QLThumbnailGenerator requires additional configuration
        // For now, return a symbolic icon
        return generateDefaultThumbnail(for: .document, size: size)
    }
    
    /// Generate default thumbnail for unsupported types
    private func generateDefaultThumbnail(for mediaType: MediaType, size: CGSize) -> NSImage? {
        let iconName = mediaType.icon
        let config = NSImage.SymbolConfiguration(pointSize: size.width * 0.5, weight: .regular)
        return NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }
    
    /// Save thumbnail to disk
    private func saveThumbnail(_ image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: generationOptions.thumbnailQuality]) else {
            throw PreviewError.thumbnailSaveFailed
        }
        
        try jpegData.write(to: url)
    }
    
    // MARK: - Quick Look Integration
    
    /// Show Quick Look preview for a file
    func showQuickLook(for previewInfo: MediaPreviewInfo) {
        guard previewInfo.isQuickLookAvailable else { return }
        
        let item = QuickLookPreviewItem(url: previewInfo.filePath, name: previewInfo.filePath.lastPathComponent)
        previewItems = [item]
        currentPreviewIndex = 0
        currentPreview = previewInfo
        
        // Show Quick Look panel
        DispatchQueue.main.async {
            if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() {
                panel.dataSource = self
                panel.delegate = self
                panel.currentPreviewItemIndex = 0
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    /// Show Quick Look for multiple files
    func showQuickLook(for previewInfos: [MediaPreviewInfo], startingAt index: Int = 0) {
        let items = previewInfos.filter { $0.isQuickLookAvailable }.map {
            QuickLookPreviewItem(url: $0.filePath, name: $0.filePath.lastPathComponent)
        }
        
        guard !items.isEmpty else { return }
        
        previewItems = items
        currentPreviewIndex = min(index, items.count - 1)
        
        if currentPreviewIndex < previewInfos.count {
            currentPreview = previewInfos[currentPreviewIndex]
        }
        
        // Show Quick Look panel
        DispatchQueue.main.async {
            if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() {
                panel.dataSource = self
                panel.delegate = self
                panel.currentPreviewItemIndex = self.currentPreviewIndex
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    /// Close Quick Look panel
    func closeQuickLook() {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() {
            panel.orderOut(nil as Any?)
        }
        currentPreview = nil
    }
    
    // MARK: - Preview Management
    
    /// Get preview info for a task
    func getPreview(for taskId: UUID) -> MediaPreviewInfo? {
        return previews.first { $0.taskId == taskId } ?? cache.retrieve(taskId: taskId)
    }
    
    /// Delete preview and associated files
    func deletePreview(_ previewInfo: MediaPreviewInfo) {
        // Delete thumbnail
        if let thumbnail = previewInfo.thumbnail {
            try? FileManager.default.removeItem(at: thumbnail.thumbnailPath)
        }
        
        // Remove from cache and array
        cache.remove(id: previewInfo.id)
        previews.removeAll { $0.id == previewInfo.id }
        
        savePreviews()
    }
    
    /// Clear all previews
    func clearAllPreviews() {
        // Delete all thumbnails
        let thumbnailsDir = getThumbnailsDirectory()
        try? FileManager.default.removeItem(at: thumbnailsDir)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        
        cache.clearAll()
        previews.removeAll()
        savePreviews()
    }
    
    // MARK: - Configuration
    
    /// Update partial preview configuration
    func updatePartialPreviewConfig(_ config: PartialPreviewConfig) {
        self.partialPreviewConfig = config
    }
    
    /// Update generation options
    func updateGenerationOptions(_ options: PreviewGenerationOptions) {
        self.generationOptions = options
    }
    
    // MARK: - Persistence
    
    private func getThumbnailsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let thumbnailsDir = appSupport.appendingPathComponent("RapidDownloadManager/Thumbnails")
        
        if !FileManager.default.fileExists(atPath: thumbnailsDir.path) {
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        }
        
        return thumbnailsDir
    }
    
    private func savePreviews() {
        if let data = try? JSONEncoder().encode(previews) {
            UserDefaults.standard.set(data, forKey: "mediaPreviewsList")
        }
    }
    
    private func loadPreviews() {
        if let data = UserDefaults.standard.data(forKey: "mediaPreviewsList"),
           let loaded = try? JSONDecoder().decode([MediaPreviewInfo].self, from: data) {
            previews = loaded
            
            // Populate cache
            loaded.forEach { cache.store($0) }
        }
    }
}

// MARK: - QLPreviewPanelDataSource

extension MediaPreviewManager: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        return previewItems.count
    }
    
    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        return previewItems[index]
    }
}

// MARK: - QLPreviewPanelDelegate

extension MediaPreviewManager: QLPreviewPanelDelegate {
    func previewPanel(_ panel: QLPreviewPanel, handle event: NSEvent) -> Bool {
        return false
    }
    
    func previewPanel(_ panel: QLPreviewPanel, sourceFrameOnScreenFor item: QLPreviewItem) -> CGRect {
        return .zero
    }
    
    func previewPanel(_ panel: QLPreviewPanel, transitionImageFor item: QLPreviewItem, contentRect: UnsafeMutablePointer<CGRect>) -> Any? {
        return nil
    }
}

// MARK: - Preview Error

enum PreviewError: LocalizedError {
    case metadataExtractionFailed
    case thumbnailGenerationFailed
    case thumbnailSaveFailed
    case fileNotFound
    case unsupportedFileType
    
    var errorDescription: String? {
        switch self {
        case .metadataExtractionFailed:
            return "Failed to extract media metadata"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        case .thumbnailSaveFailed:
            return "Failed to save thumbnail"
        case .fileNotFound:
            return "File not found"
        case .unsupportedFileType:
            return "File type not supported for preview"
        }
    }
}

// MARK: - NSImage Extension

extension NSImage {
    /// Resize image to fit within specified size while maintaining aspect ratio
    func resized(to targetSize: CGSize) -> NSImage {
        let size = self.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        let scaleFactor = min(widthRatio, heightRatio)
        let newWidth = size.width * scaleFactor
        let newHeight = size.height * scaleFactor
        let newSize = CGSize(width: newWidth, height: newHeight)
        
        let image = NSImage(size: newSize)
        image.lockFocus()
        self.draw(in: CGRect(origin: .zero, size: newSize),
                  from: CGRect(origin: .zero, size: size),
                  operation: .copy,
                  fraction: 1.0)
        image.unlockFocus()
        
        return image
    }
}
