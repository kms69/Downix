import SwiftUI

/// Dialog for adding new downloads
struct AddDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var videoManager = VideoDownloadManager.shared
    @ObservedObject private var queueManager = SchedulerQueueManager.shared

    @State private var urlString = ""
    @State private var destinationPath = ""
    @State private var filename = ""
    @State private var selectedQueue: QueuePriority = .normal
    @State private var selectedCategory: FileType = .other
    @State private var startImmediately = true
    @State private var scheduleForLater = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var isVideoURL = false
    @State private var selectedQuality: DownloadVideoQuality = .best
    @State private var isValidating = false
    @State private var validationError: String?

    // Post-download behaviour
    @State private var postDownloadAction: PostDownloadAction = .none
    /// nil = no queue assignment (uses "Main Queue" default if one exists)
    @State private var assignedQueueID: UUID? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Download")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form content
            Form {
                Section {
                    TextField("URL", text: $urlString, prompt: Text("https://example.com/file.zip"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: urlString) { newValue in
                            validateURL(newValue)
                        }
                    
                    if isValidating {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Validating URL...")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    HStack {
                        Button {
                            pasteFromClipboard()
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        
                        Button {
                            clearURL()
                        } label: {
                            Label("Clear", systemImage: "xmark")
                        }
                        .disabled(urlString.isEmpty)
                    }
                }
                
                if isVideoURL {
                    Section("Video Options") {
                        Picker("Quality:", selection: $selectedQuality) {
                            ForEach(DownloadVideoQuality.allCases, id: \.self) { quality in
                                Text(quality.displayName).tag(quality)
                            }
                        }
                    }
                }
                
                Section("Save Location") {
                    HStack {
                        TextField("Destination", text: $destinationPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        
                        Button("Choose...") {
                            selectDestination()
                        }
                    }
                    
                    TextField("Filename", text: $filename, prompt: Text("Leave empty for auto"))
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Options") {
                    Picker("Queue Priority:", selection: $selectedQueue) {
                        Text("High").tag(QueuePriority.high)
                        Text("Normal").tag(QueuePriority.normal)
                        Text("Low").tag(QueuePriority.low)
                    }

                    Picker("Category:", selection: $selectedCategory) {
                        ForEach(FileType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }

                    Toggle("Start download immediately", isOn: $startImmediately)
                        .disabled(scheduleForLater)

                    Toggle("Start at a specific time", isOn: $scheduleForLater)
                    if scheduleForLater {
                        DatePicker("Start", selection: $scheduledDate,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                }

                // ── Scheduler Queue ──────────────────────────────────
                Section("Scheduler Queue") {
                    Picker("Add to Queue", selection: $assignedQueueID) {
                        Text("None").tag(UUID?.none)
                        ForEach(queueManager.queues) { queue in
                            HStack {
                                Circle()
                                    .fill(Color(hexString: queue.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(queue.name)
                            }
                            .tag(Optional(queue.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let qid = assignedQueueID,
                       let q = queueManager.queues.first(where: { $0.id == qid }),
                       q.isScheduleEnabled {
                        Label(
                            "Queue runs \(q.scheduleTimeRange) — downloads may be held until that window.",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                // ── After this download completes ─────────────────────
                Section("After This Download Completes") {
                    Picker("Action", selection: $postDownloadAction) {
                        ForEach(PostDownloadAction.macCases, id: \.self) { action in
                            Label(action.rawValue, systemImage: action.icon).tag(action)
                        }
                    }
                    .pickerStyle(.menu)

                    if postDownloadAction != .none {
                        Label(
                            postDownloadAction == .sleep || postDownloadAction == .shutdown
                                ? "\(postDownloadAction.rawValue) will run after all active downloads in the queue finish."
                                : "\(postDownloadAction.rawValue) will execute when this specific download finishes.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add Download") {
                    addDownload()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(urlString.isEmpty || validationError != nil)
            }
            .padding()
        }
        .frame(width: 550, height: 500)
        .onAppear {
            loadDefaults()
        }
    }
    
    private func validateURL(_ urlString: String) {
        guard !urlString.isEmpty else {
            validationError = nil
            isVideoURL = false
            return
        }
        
        isValidating = true
        validationError = nil
        
        Task {
            // Simulate validation delay
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                if let url = URL(string: urlString), url.scheme != nil {
                    validationError = nil
                    // Check if this is a video URL
                    let videoHosts = ["youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv"]
                    isVideoURL = videoHosts.contains(where: { url.host?.contains($0) ?? false })
                    
                    // Auto-fill filename from URL
                    if filename.isEmpty {
                        filename = url.lastPathComponent
                    }
                } else {
                    validationError = "Invalid URL format"
                    isVideoURL = false
                }
                
                isValidating = false
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            urlString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    private func clearURL() {
        urlString = ""
        filename = ""
        validationError = nil
        isVideoURL = false
    }
    
    private func selectDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Select download destination"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                destinationPath = url.path
            }
        }
    }
    
    private func loadDefaults() {
        // Load default download location
        if let defaultLocation = UserDefaults.standard.string(forKey: "defaultDownloadLocation"), !defaultLocation.isEmpty {
            destinationPath = defaultLocation
        } else {
            destinationPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
        }
        
        // Check clipboard for URL
        if let clipboardString = NSPasteboard.general.string(forType: .string),
           let url = URL(string: clipboardString),
           url.scheme != nil {
            urlString = clipboardString
        }
    }
    
    private func addDownload() {
        guard let url = URL(string: urlString) else { return }

        let destination = destinationPath.isEmpty ? nil : URL(fileURLWithPath: destinationPath)

        // Streaming sites (YouTube, Vimeo, …) are handled by yt-dlp. Sending a page
        // URL to the plain file engine would only download the web page itself.
        if isVideoURL || VideoPlatform.detect(from: urlString) != .generic {
            var options = VideoDownloadOptions()
            switch selectedQuality {
            case .best:      options.quality = .best
            case .uhd4k:     options.quality = .quality4K
            case .fullHD:    options.quality = .quality1080p
            case .hd:        options.quality = .quality720p
            case .sd:        options.quality = .quality480p
            case .audioOnly:
                options.extractAudioOnly = true
                options.format = .mp3
            }
            Task { @MainActor in
                let task = VideoDownloadManager.shared.addAndStartDownload(url: url, options: options)
                DownloadProgressWindowController.open(for: task)
                dismiss()
            }
            return
        }

        Task { @MainActor in
            // Create the task WITHOUT starting it: queue / schedule / hold settings
            // must be applied first, otherwise it would already be running.
            let task = downloadManager.addDownload(
                url: url,
                destinationPath: destination,
                filename: filename.isEmpty ? nil : filename,
                startImmediately: false
            )

            switch selectedQueue {
            case .high:   task.priority = .high
            case .normal: task.priority = .normal
            case .low:    task.priority = .low
            }

            // Apply per-download completion action
            if postDownloadAction != .none {
                task.postDownloadAction = postDownloadAction
            }

            // Assign to scheduler queue
            if let qid = assignedQueueID {
                SchedulerQueueManager.shared.assignTask(task.id, to: qid)
                task.schedulerQueueID = qid
            } else if let defaultQueue = SchedulerQueueManager.shared.queues.first {
                // Silently assign to the first (Main) queue
                SchedulerQueueManager.shared.assignTask(task.id, to: defaultQueue.id)
                task.schedulerQueueID = defaultQueue.id
            }

            if scheduleForLater {
                // Wait for the chosen time, then the scheduler starts it.
                var schedule = DownloadSchedule(type: .once)
                schedule.scheduledDate = scheduledDate
                schedule.calculateNextRun()
                DownloadScheduler.shared.addScheduledDownload(task, schedule: schedule)
            } else if startImmediately {
                downloadManager.processQueue()
            } else {
                // "Start download immediately" is off: leave it paused for the user.
                task.state = .paused
                task.manuallyHeld = true
                downloadManager.saveTaskList()
            }

            // Open floating progress window for this download
            task.showsCompletionDialog = true
            DownloadProgressWindowController.open(for: task)

            dismiss()
        }
    }
}

// MARK: - Download Video Quality
enum DownloadVideoQuality: String, CaseIterable {
    case best = "Best Available"
    case uhd4k = "4K (2160p)"
    case fullHD = "Full HD (1080p)"
    case hd = "HD (720p)"
    case sd = "SD (480p)"
    case audioOnly = "Audio Only"
    
    var displayName: String { rawValue }
}

// MARK: - Queue Priority
enum QueuePriority: String {
    case high = "High"
    case normal = "Normal"
    case low = "Low"
}

// MARK: - File Type Extensions
extension FileType {
    var displayName: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .archive: return "Archive"
        case .image: return "Image"
        case .application: return "Application"
        case .other: return "Other"
        }
    }
}
