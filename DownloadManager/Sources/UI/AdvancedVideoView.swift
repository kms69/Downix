import SwiftUI

/// View for advanced video features
public struct AdvancedVideoView: View {
    @StateObject private var manager = AdvancedVideoManager()
    @State private var selectedTab = 0
    @State private var urlInput = ""
    @State private var showExtractionSheet = false
    @State private var showLiveStreamSheet = false
    @State private var extractionResult: VideoExtractionResult?
    @State private var selectedQuality: VideoQuality = .auto
    @State private var selectedFormat: VideoFormat = .mp4
    @State private var removeWatermark = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Extract").tag(0)
                Text("Live Streams").tag(1)
                Text("M3U8").tag(2)
                Text("History").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                extractTab.tag(0)
                liveStreamsTab.tag(1)
                m3u8Tab.tag(2)
                historyTab.tag(3)
            }
            .tabViewStyle(.automatic)
        }
        .sheet(isPresented: $showExtractionSheet) {
            extractionSheetView
        }
        .sheet(isPresented: $showLiveStreamSheet) {
            liveStreamSheetView
        }
        .alert("Video Extraction", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "play.rectangle.fill")
                .font(.largeTitle)
                .foregroundColor(.purple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Advanced Video Features")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Extract and download from any platform")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Quick stats
            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(manager.extractedVideos.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Extracted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(manager.liveStreams.filter { $0.isLive }.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("Live")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Extract Tab
    
    private var extractTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // URL input section
                urlInputSection
                
                // Supported platforms
                supportedPlatformsSection
                
                // Quick extract actions
                quickActionsSection
                
                // Recent extractions
                if !manager.extractedVideos.isEmpty {
                    recentExtractionsSection
                }
            }
            .padding()
        }
    }
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extract Video")
                .font(.headline)
            
            HStack {
                TextField("Enter video URL", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: {
                    extractVideo()
                }) {
                    Label("Extract", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlInput.isEmpty || manager.isExtracting)
            }
            
            if manager.isExtracting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Extracting video info...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
    }
    
    private var supportedPlatformsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Platforms")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(VideoPlatform.allCases.filter { $0 != .generic }, id: \.self) { platform in
                    PlatformCard(platform: platform)
                }
            }
        }
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            VStack(spacing: 8) {
                Button(action: {
                    // Detect from clipboard
                    if let clipboardString = NSPasteboard.general.string(forType: .string) {
                        urlInput = clipboardString
                        extractVideo()
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Extract from Clipboard")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    showLiveStreamSheet = true
                }) {
                    HStack {
                        Image(systemName: "record.circle")
                        Text("Record Live Stream")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var recentExtractionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Extractions")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear") {
                    manager.clearExtractedVideos()
                }
                .font(.caption)
            }
            
            ForEach(manager.extractedVideos.prefix(5)) { video in
                VideoInfoCard(video: video)
            }
        }
    }
    
    // MARK: - Live Streams Tab
    
    private var liveStreamsTab: some View {
        VStack(spacing: 20) {
            if manager.liveStreams.isEmpty {
                emptyLiveStreamsView
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(manager.liveStreams) { stream in
                            LiveStreamCard(stream: stream) {
                                manager.stopLiveStreamRecording(streamID: stream.id)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var emptyLiveStreamsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "record.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Live Streams")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Start recording a live stream from supported platforms")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showLiveStreamSheet = true
            }) {
                Label("Record Live Stream", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - M3U8 Tab
    
    private var m3u8Tab: some View {
        VStack(spacing: 20) {
            Text("M3U8/HLS Stream Support")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Parse and download M3U8 playlists (HLS streams)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Features")
                    .font(.headline)
                
                FeatureRow(icon: "list.bullet", title: "Playlist Parsing", description: "Parse M3U8 playlists and segments")
                FeatureRow(icon: "arrow.down.circle", title: "Segment Download", description: "Download all segments sequentially")
                FeatureRow(icon: "waveform.path", title: "Adaptive Streaming", description: "Support for adaptive bitrate streaming")
                FeatureRow(icon: "record.circle", title: "Live Streams", description: "Record ongoing live HLS streams")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.05))
            )
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - History Tab
    
    private var historyTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Statistics
                statsSection
                
                // Platform breakdown
                platformBreakdownSection
                
                // Recent activity
                recentActivitySection
            }
            .padding()
        }
    }
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                AdvancedVideoStatCard(
                    title: "Total Extracted",
                    value: "\(manager.extractedVideos.count)",
                    icon: "arrow.down.circle",
                    color: .blue
                )
                
                AdvancedVideoStatCard(
                    title: "Live Streams",
                    value: "\(manager.liveStreams.count)",
                    icon: "record.circle",
                    color: .red
                )
                
                AdvancedVideoStatCard(
                    title: "Platforms",
                    value: "\(Set(manager.extractedVideos.map { $0.platform }).count)",
                    icon: "globe",
                    color: .green
                )
            }
        }
    }
    
    private var platformBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Platform Breakdown")
                .font(.headline)
            
            ForEach(VideoPlatform.allCases.filter { $0 != .generic }, id: \.self) { platform in
                let count = manager.extractedVideos.filter { $0.platform == platform }.count
                
                if count > 0 {
                    HStack {
                        Image(systemName: platform.icon)
                            .frame(width: 30)
                        
                        Text(platform.displayName)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text("\(count)")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.05))
                    )
                }
            }
        }
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
            
            if manager.extractedVideos.isEmpty {
                Text("No activity yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(manager.extractedVideos.suffix(10).reversed()) { video in
                    HStack {
                        Image(systemName: video.platform.icon)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title ?? "Untitled")
                                .font(.subheadline)
                                .lineLimit(1)
                            
                            Text(video.platform.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let duration = video.formattedDuration {
                            Text(duration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.05))
                    )
                }
            }
        }
    }
    
    // MARK: - Extraction Sheet
    
    private var extractionSheetView: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let result = extractionResult {
                    if result.success, let video = result.videoInfo {
                        // Success view
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            
                            Text("Video Extracted Successfully")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            VideoInfoCard(video: video)
                            
                            // Download options
                            VStack(spacing: 12) {
                                Picker("Quality", selection: $selectedQuality) {
                                    Text("Best Available").tag(VideoQuality.best)
                                    Text("4K (2160p)").tag(VideoQuality.quality4K)
                                    Text("1080p").tag(VideoQuality.quality1080p)
                                    Text("720p").tag(VideoQuality.quality720p)
                                    Text("480p").tag(VideoQuality.quality480p)
                                }
                                
                                Picker("Format", selection: $selectedFormat) {
                                    Text("MP4").tag(VideoFormat.mp4)
                                    Text("WebM").tag(VideoFormat.webm)
                                    Text("MKV").tag(VideoFormat.mkv)
                                }
                                
                                if video.platform == .tiktok {
                                    Toggle("Remove Watermark", isOn: $removeWatermark)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.05))
                            )
                            
                            Button(action: {
                                // Start download
                                showExtractionSheet = false
                            }) {
                                Label("Download Video", systemImage: "arrow.down.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding()
                    } else {
                        // Error view
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 60))
                                .foregroundColor(.red)
                            
                            Text("Extraction Failed")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Text(result.error ?? "Unknown error")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Video Extraction")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showExtractionSheet = false
                        extractionResult = nil
                    }
                }
            })
        }
    }
    
    // MARK: - Live Stream Sheet
    
    private var liveStreamSheetView: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Live Stream URL", text: $urlInput)
                    
                    Picker("Quality", selection: $selectedQuality) {
                        ForEach([VideoQuality.auto, .quality480p, .quality720p, .quality1080p], id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                } header: {
                    Text("Stream Details")
                }
                
                Section {
                    Button("Start Recording") {
                        startLiveStreamRecording()
                    }
                    .disabled(urlInput.isEmpty)
                } footer: {
                    Text("Recording will continue until you stop it or the stream ends")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Record Live Stream")
            .toolbar(content: {
                SwiftUI.ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showLiveStreamSheet = false
                    }
                }
            })
        }
    }
    
    // MARK: - Actions
    
    private func extractVideo() {
        guard !urlInput.isEmpty else { return }
        
        Task {
            do {
                let result = try await manager.extractVideoInfo(from: urlInput)
                
                await MainActor.run {
                    extractionResult = result
                    showExtractionSheet = true
                    
                    if !result.success {
                        alertMessage = result.error ?? "Extraction failed"
                        showAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
    
    private func startLiveStreamRecording() {
        guard !urlInput.isEmpty else { return }
        
        Task {
            do {
                _ = try await manager.startLiveStreamRecording(urlString: urlInput)
                
                await MainActor.run {
                    showLiveStreamSheet = false
                    urlInput = ""
                    selectedTab = 1 // Switch to live streams tab
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct PlatformCard: View {
    let platform: VideoPlatform
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: platform.icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(platform.displayName)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

struct VideoInfoCard: View {
    let video: VideoInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: video.platform.icon)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(2)
                    
                    if let author = video.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            HStack {
                if let duration = video.formattedDuration {
                    Label(duration, systemImage: "clock")
                        .font(.caption)
                }
                
                if let views = video.formattedViewCount {
                    Label(views, systemImage: "eye")
                        .font(.caption)
                }
                
                Spacer()
                
                Label(video.platform.displayName, systemImage: "globe")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

struct LiveStreamCard: View {
    let stream: LiveStreamInfo
    let onStop: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundColor(stream.isLive ? .red : .gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(stream.title ?? "Untitled Stream")
                        .font(.headline)
                    
                    if let streamer = stream.streamer {
                        Text(streamer)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if stream.isLive {
                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            
            HStack {
                if let viewers = stream.formattedViewerCount {
                    Label(viewers, systemImage: "person.2")
                        .font(.caption)
                }
                
                if let duration = stream.streamDuration {
                    let formatted = String(format: "%.0f:%.0f", duration / 60, duration.truncatingRemainder(dividingBy: 60))
                    Label(formatted, systemImage: "clock")
                        .font(.caption)
                }
                
                Spacer()
                
                Text(stream.isLive ? "LIVE" : "ENDED")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(stream.isLive ? .red : .gray)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AdvancedVideoStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

// MARK: - Preview

struct AdvancedVideoView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedVideoView()
            .frame(width: 900, height: 700)
    }
}
