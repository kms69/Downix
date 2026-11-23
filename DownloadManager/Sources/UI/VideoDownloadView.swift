//
//  VideoDownloadView.swift
//  Download Manager for Mac - Feature #7: YouTube & Video Downloading
//
//  Created on February 15, 2026
//

import SwiftUI

struct VideoDownloadView: View {
    @ObservedObject var manager = VideoDownloadManager.shared
    
    @State private var urlText: String = ""
    @State private var selectedQuality: VideoQuality = .quality1080p
    @State private var selectedFormat: VideoFormat = .mp4
    @State private var extractAudioOnly: Bool = false
    @State private var downloadSubtitles: Bool = false
    @State private var selectedPlatform: VideoPlatform?
    @State private var detectedMetadata: VideoMetadata?
    @State private var detectedPlaylist: PlaylistInfo?
    @State private var isFetchingInfo: Bool = false
    @State private var showOptions: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Main content
            ScrollView {
                VStack(spacing: 20) {
                    // URL input section
                    urlInputSection
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(12)
                    
                    // Metadata preview (if fetched)
                    if let metadata = detectedMetadata {
                        metadataPreviewSection(metadata: metadata)
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(12)
                    }
                    
                    // Playlist preview (if detected)
                    if let playlist = detectedPlaylist {
                        playlistPreviewSection(playlist: playlist)
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(12)
                    }
                    
                    // Download options
                    if detectedMetadata != nil {
                        downloadOptionsSection
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(12)
                    }
                    
                    // Active downloads
                    if !manager.videoTasks.isEmpty {
                        activeDownloadsSection
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(12)
                    }
                    
                    // Statistics
                    statisticsSection
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(12)
                }
                .padding()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundColor(.purple)
            
            Text("Video Downloader")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: { showOptions.toggle() }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - URL Input Section
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video URL")
                .font(.headline)
            
            HStack {
                TextField("Paste video URL (YouTube, Vimeo, etc.)", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        fetchVideoInfo()
                    }
                
                if isFetchingInfo {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Fetch Info") {
                        fetchVideoInfo()
                    }
                    .disabled(urlText.isEmpty)
                }
            }
            
            if let platform = selectedPlatform {
                HStack {
                    Image(systemName: platform.icon)
                        .foregroundColor(.blue)
                    Text("Platform: \(platform.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Metadata Preview
    
    private func metadataPreviewSection(metadata: VideoMetadata) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video Information")
                .font(.headline)
            
            HStack(alignment: .top, spacing: 16) {
                // Thumbnail
                if let thumbnailURL = metadata.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 120, height: 90)
                    .cornerRadius(8)
                }
                
                // Metadata
                VStack(alignment: .leading, spacing: 6) {
                    Text(metadata.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    if let author = metadata.author {
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.caption)
                            Text(author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        Label(metadata.formattedDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label(metadata.formattedViews, systemImage: "eye")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if metadata.isLiveStream {
                        Label("Live Stream", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Playlist Preview
    
    private func playlistPreviewSection(playlist: PlaylistInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playlist")
                    .font(.headline)
                
                Spacer()
                
                Text("\(playlist.videoCount) videos • \(playlist.formattedTotalDuration)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(playlist.title)
                .font(.title3)
                .fontWeight(.semibold)
            
            if let author = playlist.author {
                HStack {
                    Image(systemName: "person.fill")
                        .font(.caption)
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Video list (first 5)
            VStack(spacing: 8) {
                ForEach(Array(playlist.videos.prefix(5))) { video in
                    HStack {
                        Text("\(video.position).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)
                        
                        Text(video.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(formatDuration(video.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if playlist.videoCount > 5 {
                    Text("+ \(playlist.videoCount - 5) more videos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Download Entire Playlist") {
                downloadPlaylist()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Download Options
    
    private var downloadOptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download Options")
                .font(.headline)
            
            // Quality selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Quality")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Quality", selection: $selectedQuality) {
                    ForEach(detectedMetadata?.availableQualities ?? VideoQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Format selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(VideoFormat.allCases, id: \.self) { format in
                            Text(format.description).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    
                    Spacer()
                }
            }
            
            Divider()
            
            // Additional options
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Extract audio only", isOn: $extractAudioOnly)
                
                Toggle("Download subtitles", isOn: $downloadSubtitles)
                
                if extractAudioOnly {
                    HStack {
                        Text("Audio will be saved as:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Audio Format", selection: $selectedFormat) {
                            Text("MP3").tag(VideoFormat.mp3)
                            Text("M4A").tag(VideoFormat.m4a)
                            Text("AAC").tag(VideoFormat.aac)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                }
            }
            
            // Download button
            Button(action: startDownload) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Start Download")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    // MARK: - Active Downloads
    
    private var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Downloads (\(manager.videoTasks.count))")
                .font(.headline)
            
            ForEach(manager.videoTasks) { task in
                VideoDownloadRow(task: task, manager: manager)
            }
        }
    }
    
    // MARK: - Statistics
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                VideoStatCard(
                    title: "Videos Downloaded",
                    value: "\(manager.statistics.totalVideosDownloaded)",
                    color: .blue
                )
                
                VideoStatCard(
                    title: "Audio Extracted",
                    value: "\(manager.statistics.totalAudioExtracted)",
                    color: .green
                )
                
                VideoStatCard(
                    title: "Playlists",
                    value: "\(manager.statistics.totalPlaylistsDownloaded)",
                    color: .purple
                )
                
                VideoStatCard(
                    title: "Total Data",
                    value: manager.statistics.formattedTotalData,
                    color: .orange
                )
                
                VideoStatCard(
                    title: "Success Rate",
                    value: "\(manager.statistics.successRate.formatted(.number.precision(.fractionLength(1))))%",
                    color: .cyan
                )
                
                VideoStatCard(
                    title: "Avg Time",
                    value: manager.statistics.formattedAverageTime,
                    color: .pink
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func fetchVideoInfo() {
        guard !urlText.isEmpty,
              let url = URL(string: urlText) else { return }
        
        selectedPlatform = VideoPlatform.detect(from: url)
        isFetchingInfo = true
        detectedMetadata = nil
        detectedPlaylist = nil
        
        Task {
            do {
                let task = VideoDownloadTask(url: url)
                await manager.fetchMetadata(for: task)
                
                await MainActor.run {
                    detectedMetadata = task.metadata
                    
                    if task.metadata?.isPlaylist == true {
                        Task {
                            await manager.fetchPlaylistInfo(for: task)
                            await MainActor.run {
                                detectedPlaylist = task.playlist
                            }
                        }
                    }
                    
                    isFetchingInfo = false
                    
                    // Remove temporary task
                    manager.removeTask(task)
                }
            }
        }
    }
    
    private func startDownload() {
        guard !urlText.isEmpty,
              let url = URL(string: urlText) else { return }
        
        var options = VideoDownloadOptions.default
        options.quality = selectedQuality
        options.format = selectedFormat
        options.extractAudioOnly = extractAudioOnly
        options.downloadSubtitles = downloadSubtitles
        
        let task = manager.addVideoDownload(url: url, options: options)
        
        Task {
            await manager.startDownload(task)
        }
        
        // Clear input
        urlText = ""
        detectedMetadata = nil
        detectedPlaylist = nil
        selectedPlatform = nil
    }
    
    private func downloadPlaylist() {
        guard !urlText.isEmpty,
              let url = URL(string: urlText) else { return }
        
        var options = VideoDownloadOptions.default
        options.quality = selectedQuality
        options.format = selectedFormat
        options.extractAudioOnly = extractAudioOnly
        options.downloadSubtitles = downloadSubtitles
        
        let task = manager.addVideoDownload(url: url, options: options)
        
        Task {
            await manager.downloadPlaylist(task)
        }
        
        // Clear input
        urlText = ""
        detectedMetadata = nil
        detectedPlaylist = nil
        selectedPlatform = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video Download Row

struct VideoDownloadRow: View {
    @ObservedObject var task: VideoDownloadTask
    let manager: VideoDownloadManager
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HyperTheme { HyperTheme(scheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: task.platform.icon)
                    .foregroundColor(theme.accent)
                    .frame(width: 22, height: 22)
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.metadata?.title ?? task.url.absoluteString)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    
                    HStack {
                        Text(task.state.rawValue)
                            .font(.caption)
                            .foregroundColor(stateColor)
                        
                        if task.state == .downloading || task.state == .paused || task.state == .converting {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.textTertiary)
                            
                            Text("\(Int(task.progress * 100))%")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                            
                            if task.speed > 0 {
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.textTertiary)
                                
                                Text(task.formattedSpeed)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    if task.state == .downloading {
                        controlButton("Pause", icon: "pause.fill", color: .orange) {
                            manager.pauseDownload(task)
                        }
                    } else if task.state == .paused {
                        controlButton("Resume", icon: "play.fill", color: .green) {
                            manager.resumeDownload(task)
                        }
                    }
                    if task.state == .downloading || task.state == .paused || task.state == .converting {
                        controlButton("Stop", icon: "stop.fill", color: .red) {
                            manager.cancelDownload(task)
                        }
                    }
                    if task.state == .failed || task.state == .cancelled {
                        controlButton("Retry", icon: "arrow.clockwise", color: .orange) {
                            manager.retryDownload(task)
                        }
                    }
                    if task.state == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if task.state == .failed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            
            if task.state == .downloading || task.state == .paused || task.state == .converting {
                ProgressView(value: task.progress)
                    .tint(task.state == .paused ? theme.warning : theme.accent)
            }
            
            if let error = task.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(theme.danger)
            }
        }
        .padding(10)
        .background(theme.surface.opacity(colorScheme == .dark ? 0.82 : 0.72),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            DownloadProgressWindowController.open(for: task)
        })
        .help("Double-click to show the progress window")
    }
    
    private func controlButton(_ title: String, icon: String, color: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var stateColor: Color {
        switch task.state {
        case .completed: return .green
        case .failed, .cancelled: return .red
        case .downloading, .converting: return .blue
        case .paused: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Video Stat Card

struct VideoStatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Preview

struct VideoDownloadView_Previews: PreviewProvider {
    static var previews: some View {
        VideoDownloadView()
            .frame(width: 800, height: 600)
    }
}
