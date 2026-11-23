//
//  MediaPreviewView.swift
//  Download Manager for Mac - Feature #11: Media Preview & Quick Look UI
//
//  Created on February 16, 2026
//

import SwiftUI
import QuickLook

struct MediaPreviewView: View {
    @StateObject private var previewManager = MediaPreviewManager.shared
    @State private var selectedPreview: MediaPreviewInfo?
    @State private var showingGallery = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Media Preview")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { showingGallery.toggle() }) {
                    Label("Gallery", systemImage: "square.grid.2x2")
                }
                
                Button(action: { previewManager.clearAllPreviews() }) {
                    Label("Clear All", systemImage: "trash")
                }
                .foregroundColor(.red)
            }
            .padding()
            
            Divider()
            
            // Content
            if previewManager.previews.isEmpty {
                EmptyPreviewsView()
            } else if showingGallery {
                PreviewGalleryView(selectedPreview: $selectedPreview)
            } else {
                PreviewListView(selectedPreview: $selectedPreview)
            }
        }
        .sheet(item: $selectedPreview) { preview in
            PreviewDetailView(previewInfo: preview)
        }
    }
}

// MARK: - Empty State

struct EmptyPreviewsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Previews Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Media previews will appear here after downloading")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview List

struct PreviewListView: View {
    @StateObject private var previewManager = MediaPreviewManager.shared
    @Binding var selectedPreview: MediaPreviewInfo?
    
    var body: some View {
        List {
            ForEach(previewManager.previews) { preview in
                PreviewListRow(preview: preview) {
                    selectedPreview = preview
                }
            }
        }
    }
}

struct PreviewListRow: View {
    let preview: MediaPreviewInfo
    let onTap: () -> Void
    @StateObject private var previewManager = MediaPreviewManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            if let thumbnail = preview.thumbnail, let image = thumbnail.loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: preview.mediaType.icon)
                    .font(.title)
                    .foregroundColor(.blue)
                    .frame(width: 60, height: 60)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.filePath.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label(preview.mediaType.rawValue.capitalized, systemImage: preview.mediaType.icon)
                        .font(.caption)
                    
                    if let metadata = preview.metadata {
                        if let duration = metadata.duration {
                            Text(metadata.formattedDuration())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let resolution = metadata.resolution {
                            Text(metadata.formattedResolution())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // State indicator
                PreviewStateIndicator(state: preview.previewState)
            }
            
            Spacer()
            
            // Quick Look button
            if preview.isQuickLookAvailable {
                Button(action: {
                    previewManager.showQuickLook(for: preview)
                }) {
                    Image(systemName: "eye.fill")
                }
                .buttonStyle(.borderless)
                .help("Quick Look")
            }
            
            // Details button
            Button(action: onTap) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Show Details")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview Gallery

struct PreviewGalleryView: View {
    @StateObject private var previewManager = MediaPreviewManager.shared
    @Binding var selectedPreview: MediaPreviewInfo?
    
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(previewManager.previews) { preview in
                    PreviewCardView(preview: preview) {
                        selectedPreview = preview
                    }
                }
            }
            .padding()
        }
    }
}

struct PreviewCardView: View {
    let preview: MediaPreviewInfo
    let onTap: () -> Void
    @StateObject private var previewManager = MediaPreviewManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail = preview.thumbnail, let image = thumbnail.loadImage() {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 150)
                        .overlay(
                            Image(systemName: preview.mediaType.icon)
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                        )
                }
                
                // Quick Look overlay
                if preview.isQuickLookAvailable {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                previewManager.showQuickLook(for: preview)
                            }) {
                                Image(systemName: "eye.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .shadow(radius: 4)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.filePath.lastPathComponent)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack {
                    Image(systemName: preview.mediaType.icon)
                        .font(.caption2)
                    
                    if let metadata = preview.metadata, let duration = metadata.duration {
                        Text(metadata.formattedDuration())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: {
                previewManager.showQuickLook(for: preview)
            }) {
                Label("Quick Look", systemImage: "eye")
            }
            .disabled(!preview.isQuickLookAvailable)
            
            Button(action: onTap) {
                Label("Show Details", systemImage: "info.circle")
            }
            
            Divider()
            
            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([preview.filePath])
            }) {
                Label("Show in Finder", systemImage: "folder")
            }
            
            Button(action: {
                previewManager.deletePreview(preview)
            }) {
                Label("Delete Preview", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview Detail

struct PreviewDetailView: View {
    let previewInfo: MediaPreviewInfo
    @StateObject private var previewManager = MediaPreviewManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preview Details")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Thumbnail/Preview
                    if let thumbnail = previewInfo.thumbnail, let image = thumbnail.loadImage() {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: previewInfo.mediaType.icon)
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    // Quick Look button
                    if previewInfo.isQuickLookAvailable {
                        Button(action: {
                            previewManager.showQuickLook(for: previewInfo)
                        }) {
                            Label("Open in Quick Look", systemImage: "eye.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    // File Info
                    GroupBox("File Information") {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(label: "Filename", value: previewInfo.filePath.lastPathComponent)
                            InfoRow(label: "Type", value: previewInfo.mediaType.rawValue.capitalized)
                            InfoRow(label: "Path", value: previewInfo.filePath.path)
                            
                            if let fileSize = previewInfo.metadata?.fileSize {
                                InfoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                            }
                            
                            InfoRow(label: "State", value: previewInfo.previewState.rawValue.capitalized)
                        }
                        .padding()
                    }
                    
                    // Metadata
                    if let metadata = previewInfo.metadata {
                        GroupBox("Media Metadata") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let duration = metadata.duration {
                                    InfoRow(label: "Duration", value: metadata.formattedDuration())
                                }
                                
                                if let resolution = metadata.resolution {
                                    InfoRow(label: "Resolution", value: metadata.formattedResolution())
                                }
                                
                                if let frameRate = metadata.frameRate {
                                    InfoRow(label: "Frame Rate", value: metadata.formattedFrameRate())
                                }
                                
                                if let bitrate = metadata.bitrate {
                                    InfoRow(label: "Bitrate", value: metadata.formattedBitrate())
                                }
                                
                                if let title = metadata.title {
                                    InfoRow(label: "Title", value: title)
                                }
                                
                                if let artist = metadata.artist {
                                    InfoRow(label: "Artist", value: artist)
                                }
                                
                                if let album = metadata.album {
                                    InfoRow(label: "Album", value: album)
                                }
                                
                                if let codec = metadata.codec {
                                    InfoRow(label: "Codec", value: codec)
                                }
                            }
                            .padding()
                        }
                    }
                    
                    // Actions
                    HStack(spacing: 12) {
                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting([previewInfo.filePath])
                        }) {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        
                        Button(action: {
                            NSWorkspace.shared.open(previewInfo.filePath)
                        }) {
                            Label("Open File", systemImage: "doc")
                        }
                        
                        Button(role: .destructive, action: {
                            previewManager.deletePreview(previewInfo)
                            dismiss()
                        }) {
                            Label("Delete Preview", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 700)
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
}

struct PreviewStateIndicator: View {
    let state: PreviewState
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(state.rawValue.capitalized)
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
    }
    
    private var iconName: String {
        switch state {
        case .idle: return "circle"
        case .generating: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .notSupported: return "exclamationmark.triangle.fill"
        }
    }
    
    private var color: Color {
        switch state {
        case .idle: return .gray
        case .generating: return .blue
        case .ready: return .green
        case .failed: return .red
        case .notSupported: return .orange
        }
    }
}

// MARK: - Settings View

struct MediaPreviewSettingsView: View {
    @StateObject private var previewManager = MediaPreviewManager.shared
    @State private var minimumBytes: Double
    @State private var minimumPercentage: Double
    @State private var enableWhileDownloading: Bool
    @State private var generateThumbnails: Bool
    @State private var extractMetadata: Bool
    @State private var thumbnailQuality: Double
    
    init() {
        let config = PartialPreviewConfig()
        _minimumBytes = State(initialValue: Double(config.minimumBytes) / 1_000_000) // MB
        _minimumPercentage = State(initialValue: config.minimumPercentage)
        _enableWhileDownloading = State(initialValue: config.enableWhileDownloading)
        
        let options = PreviewGenerationOptions()
        _generateThumbnails = State(initialValue: options.generateThumbnails)
        _extractMetadata = State(initialValue: options.extractMetadata)
        _thumbnailQuality = State(initialValue: options.thumbnailQuality)
    }
    
    var body: some View {
        Form {
            Section("Partial Preview (While Downloading)") {
                Toggle("Enable preview while downloading", isOn: $enableWhileDownloading)
                
                HStack {
                    Text("Minimum size:")
                    Slider(value: $minimumBytes, in: 0.5...10, step: 0.5)
                    Text("\(minimumBytes, specifier: "%.1f") MB")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Minimum progress:")
                    Slider(value: $minimumPercentage, in: 1...20, step: 1)
                    Text("\(Int(minimumPercentage))%")
                        .frame(width: 50, alignment: .trailing)
                }
            }
            
            Section("Preview Generation") {
                Toggle("Generate thumbnails", isOn: $generateThumbnails)
                Toggle("Extract metadata", isOn: $extractMetadata)
                
                HStack {
                    Text("Thumbnail quality:")
                    Slider(value: $thumbnailQuality, in: 0.1...1.0, step: 0.1)
                    Text("\(Int(thumbnailQuality * 100))%")
                        .frame(width: 50, alignment: .trailing)
                }
            }
            
            Section {
                Button("Apply Changes") {
                    applySettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func applySettings() {
        var config = PartialPreviewConfig()
        config.minimumBytes = Int64(minimumBytes * 1_000_000)
        config.minimumPercentage = minimumPercentage
        config.enableWhileDownloading = enableWhileDownloading
        previewManager.updatePartialPreviewConfig(config)
        
        var options = PreviewGenerationOptions()
        options.generateThumbnails = generateThumbnails
        options.extractMetadata = extractMetadata
        options.thumbnailQuality = thumbnailQuality
        previewManager.updateGenerationOptions(options)
    }
}

#if DEBUG
struct MediaPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        MediaPreviewView()
    }
}
#endif
