import Foundation

/// Locates and invokes external binaries (yt-dlp, ffmpeg) via Process.
/// Falls back gracefully when binaries are missing so the app still builds/runs.
enum ExternalToolRunner {
    static var ytDlpPath: String? { findBinary(names: ["yt-dlp", "yt-dlp_macos"]) }
    static var ffmpegPath: String? { findBinary(names: ["ffmpeg"]) }

    static var isYTDLPAvailable: Bool { ytDlpPath != nil }
    static var isFFmpegAvailable: Bool { ffmpegPath != nil }

    /// Where the app keeps tools it downloaded itself (no admin rights needed).
    static var managedToolsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DownloadManager/bin", isDirectory: true)
    }

    /// Search common install locations + PATH.
    static func findBinary(names: [String]) -> String? {
        let fm = FileManager.default
        // 1. Our own managed directory, then bundled alongside the app
        let bundleDirs = [
            managedToolsDirectory.path,
            Bundle.main.bundlePath + "/Contents/MacOS",
            Bundle.main.bundlePath + "/Contents/Resources",
            Bundle.main.resourcePath ?? ""
        ]
        // 2. Common system locations
        let sysDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        // 3. PATH entries
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")

        for name in names {
            for dir in bundleDirs + sysDirs + pathDirs where !dir.isEmpty {
                let p = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }

    /// A GUI app (launched from Finder/Dock) has a tiny PATH, so yt-dlp could not
    /// find ffmpeg and silently skipped merging video+audio. Give child processes a full one.
    static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var dirs = [managedToolsDirectory.path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        if let ff = ffmpegPath { dirs.insert((ff as NSString).deletingLastPathComponent, at: 0) }
        if let existing = env["PATH"], !existing.isEmpty { dirs.append(existing) }
        env["PATH"] = dirs.joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    /// Cookie args so YouTube bot-check passes: tries installed browsers' cookies.
    /// Override with prefs key `ytDlpCookiesFromBrowser` (e.g. "chrome", "brave", "safari", "firefox", "edge", or "none").
    /// Cookie arg sets to try, in order. YouTube's bot-check sometimes rejects one
    /// browser's cookies, so callers fall back to the next available browser.
    static var ytDlpCookieArgSets: [[String]] {
        let pref = UserDefaults.standard.string(forKey: "ytDlpCookiesFromBrowser") ?? "auto"
        if pref == "none" { return [[]] }
        // Explicit choice: honoured (Chrome/Brave/Edge/Safari make macOS ask for the
        // login password or Full Disk Access), with a cookie-less fallback.
        if pref != "auto" { return [["--cookies-from-browser", pref], []] }

        // Automatic mode never reads Chromium or Safari cookie stores: that is what
        // popped up the Keychain password dialog. Try without cookies first, then
        // Firefox if it is installed (its cookies are not Keychain-protected).
        var sets: [[String]] = [[]]
        let firefox = FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Application Support/Firefox"
        if FileManager.default.fileExists(atPath: firefox) {
            sets.append(["--cookies-from-browser", "firefox"])
        }
        return sets
    }

    static var ytDlpCookieArgs: [String] { ytDlpCookieArgSets.first ?? [] }

    struct RunResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var succeeded: Bool { exitCode == 0 }
    }

    // MARK: - Simple blocking run (metadata, small jobs)

    /// Collects output on background threads WHILE the process runs.
    /// (Waiting for exit first deadlocks as soon as output exceeds the 64 KB pipe
    /// buffer — which yt-dlp's `-J` metadata always does.)
    @discardableResult
    static func run(binary: String, args: [String], timeout: TimeInterval = 60) throws -> RunResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ProxySession.arguments(for: binary, args)
        proc.environment = childEnvironment()
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outBox.set(out.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.set(err.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        do {
            try proc.run()
        } catch {
            // Launch failed: close our pipe ends so the two reader threads see EOF and exit.
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
            group.wait()
            throw error
        }
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning { proc.terminate() }
        proc.waitUntilExit()
        group.wait()

        return RunResult(
            exitCode: proc.terminationStatus,
            stdout: String(data: outBox.data, encoding: .utf8) ?? "",
            stderr: String(data: errBox.data, encoding: .utf8) ?? ""
        )
    }

    // MARK: - Streaming run (long downloads: live progress + cancel)

    /// Lets the owner stop a running process (pause / stop / cancel).
    final class ProcessHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

        /// SIGTERM: yt-dlp exits cleanly and keeps its `.part` files for a later resume.
        func cancel() {
            lock.lock()
            cancelled = true
            let p = process
            lock.unlock()
            if let p, p.isRunning { p.terminate() }
        }

        fileprivate func attach(_ p: Process) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if cancelled { return false }
            process = p
            return true
        }
    }

    /// Runs a process and reports every stdout line as it arrives.
    /// Returns the exit code and the last stderr lines (for error messages).
    static func runStreaming(binary: String,
                             args: [String],
                             handle: ProcessHandle,
                             onLine: @escaping @Sendable (String) -> Void) async throws -> (exitCode: Int32, stderrTail: String) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(exitCode: Int32, stderrTail: String), Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binary)
            proc.arguments = ProxySession.arguments(for: binary, args)
            proc.environment = childEnvironment()
            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err

            let tail = LineTail(limit: 30)
            let outReader = LineReader { onLine($0) }
            // yt-dlp writes progress to stderr, so forward those lines to onLine
            // (keeping them out of the error tail). Everything else is error text.
            let errReader = LineReader { line in
                if line.hasPrefix(progressPrefix) { onLine(line) } else { tail.add(line) }
            }

            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { outReader.feed(d) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { errReader.feed(d) }
            }

            proc.terminationHandler = { p in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                outReader.feed(out.fileHandleForReading.readDataToEndOfFile())
                errReader.feed(err.fileHandleForReading.readDataToEndOfFile())
                outReader.finish()
                errReader.finish()
                cont.resume(returning: (p.terminationStatus, tail.text))
            }

            guard handle.attach(proc) else {
                cont.resume(throwing: CancellationError())
                return
            }
            do {
                try proc.run()
            } catch {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Tool installation

    enum ToolError: LocalizedError {
        case downloadFailed(String)
        var errorDescription: String? {
            switch self {
            case .downloadFailed(let m): return m
            }
        }
    }

    /// Downloads the standalone yt-dlp binary into the managed tools directory.
    /// Needs no Homebrew, Python or admin rights.
    @discardableResult
    static func installYtDlp() async throws -> String {
        let dir = managedToolsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("yt-dlp")

        guard let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos") else {
            throw ToolError.downloadFailed("Invalid yt-dlp download URL")
        }
        let (tmp, response) = try await ProxySession.makeSession().download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ToolError.downloadFailed("Could not download yt-dlp (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        // Make sure it really starts here; otherwise a blocked copy would stall every download.
        let probe = try? run(binary: target.path, args: ["--version"], timeout: 25)
        if probe?.succeeded != true {
            try? FileManager.default.removeItem(at: target)
            throw ToolError.downloadFailed("the downloaded yt-dlp does not start on this Mac (macOS blocked it)")
        }
        return target.path
    }

    /// Updates yt-dlp when it is the copy we manage (sites change often; old copies break).
    /// Returns true if an update was attempted.
    private static let ytDlpHealthLock = NSLock()
    private static var ytDlpHealthChecked = false

    /// The standalone yt-dlp unpacks a Python bundle on every launch. If macOS rejects that
    /// bundle ("Python.framework is damaged") the process blocks behind a dialog and every
    /// download stalls at 0%. Test the managed copy once per session (call off the main
    /// thread) and set it aside if it does not run cleanly, so another copy is used.
    static func ensureManagedYtDlpRuns() {
        ytDlpHealthLock.lock(); defer { ytDlpHealthLock.unlock() }
        guard !ytDlpHealthChecked else { return }
        ytDlpHealthChecked = true
        let path = managedToolsDirectory.appendingPathComponent("yt-dlp").path
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        let result = try? run(binary: path, args: ["--version"], timeout: 20)
        if result?.succeeded != true {
            let broken = path + ".broken"
            try? FileManager.default.removeItem(atPath: broken)
            try? FileManager.default.moveItem(atPath: path, toPath: broken)
            YtDlpLog.log("managed yt-dlp did not run cleanly (exit \(result?.exitCode ?? -1)); moved aside")
        }
    }

    /// Blocking re-download of the standalone yt-dlp for the updater (runs off the main thread).
    /// The new file must run before it replaces the old one.
    private static func downloadYtDlpBlocking() -> Bool {
        guard let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos") else { return false }
        let dir = managedToolsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fresh = dir.appendingPathComponent("yt-dlp.new")
        let sem = DispatchSemaphore(value: 0)
        var downloaded = false
        let job = ProxySession.makeSession().downloadTask(with: url) { tmp, resp, _ in
            defer { sem.signal() }
            guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            try? FileManager.default.removeItem(at: fresh)
            guard (try? FileManager.default.moveItem(at: tmp, to: fresh)) != nil else { return }
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fresh.path)
            downloaded = true
        }
        job.resume()
        sem.wait()
        guard downloaded else { return false }
        let check = try? run(binary: fresh.path, args: ["--version"], timeout: 25)
        guard check?.succeeded == true else {
            try? FileManager.default.removeItem(at: fresh)
            YtDlpLog.log("yt-dlp update: the new copy does not run on this Mac; keeping the old one")
            return false
        }
        let target = dir.appendingPathComponent("yt-dlp")
        try? FileManager.default.removeItem(at: target)
        return (try? FileManager.default.moveItem(at: fresh, to: target)) != nil
    }

    /// Refreshes yt-dlp when it is the copy we manage (sites change often; old copies break).
    /// A fresh download replaces the file; `yt-dlp -U` rewrote it in place, which could leave
    /// a copy macOS refuses to run. Returns true if the copy was replaced.
    @discardableResult
    static func updateManagedYtDlp() -> Bool {
        guard let path = ytDlpPath, path.hasPrefix(managedToolsDirectory.path) else { return false }
        YtDlpLog.log("yt-dlp: refreshing the managed copy")
        return downloadYtDlpBlocking()
    }

    // MARK: - yt-dlp helpers

    /// yt-dlp format selector for a given quality choice.
    /// Without ffmpeg yt-dlp cannot merge separate video+audio streams, so we ask for a
    /// single pre-merged file instead of producing two unusable halves.
    /// yt-dlp format selector. With "H.264" selected, avc1 video is preferred at
    /// the requested height (any height, not just 720) and the usual selector
    /// remains as the fallback.
    static func formatSelector(quality: VideoQuality,
                               extractAudioOnly: Bool,
                               hasFFmpeg: Bool = ExternalToolRunner.isFFmpegAvailable) -> String {
        let base = baseFormatSelector(quality: quality, extractAudioOnly: extractAudioOnly, hasFFmpeg: hasFFmpeg)
        guard let prefix = VideoCodecPreference.vcodecPrefix, hasFFmpeg, !extractAudioOnly else { return base }
        let cap = quality.height.map { "[height<=\($0)]" } ?? ""
        let v = "bestvideo[vcodec^=\(prefix)]\(cap)"
        return "\(v)+bestaudio[ext=m4a]/\(v)+bestaudio/" + base
    }

    static func baseFormatSelector(quality: VideoQuality,
                               extractAudioOnly: Bool,
                               hasFFmpeg: Bool = ExternalToolRunner.isFFmpegAvailable) -> String {
        if extractAudioOnly { return "bestaudio/best" }
        if !hasFFmpeg {
            if let h = quality.height { return "best[height<=\(h)]/best" }
            return "best"
        }
        switch quality {
        case .best: return "bestvideo+bestaudio/best"
        case .quality4K: return "bestvideo[height<=2160]+bestaudio/best[height<=2160]/best"
        case .quality2K: return "bestvideo[height<=1440]+bestaudio/best[height<=1440]/best"
        case .quality1080p: return "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best"
        case .quality720p: return "bestvideo[height<=720]+bestaudio/best[height<=720]/best"
        case .quality480p: return "bestvideo[height<=480]+bestaudio/best[height<=480]/best"
        case .quality360p: return "bestvideo[height<=360]+bestaudio/best[height<=360]/best"
        case .quality240p: return "bestvideo[height<=240]+bestaudio/best[height<=240]/best"
        case .quality144p: return "bestvideo[height<=144]+bestaudio/best[height<=144]/best"
        case .auto: return "bestvideo+bestaudio/best"
        }
    }

    // MARK: - Progress line parsing

    /// Marker used in `--progress-template` so our lines are easy to recognise.
    static let progressPrefix = "RDMPROGRESS"

    /// Args that make yt-dlp print one machine-readable progress line per update.
    static var progressArgs: [String] {
        ["--newline",
         "--progress-template",
         "download:\(progressPrefix) %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s"]
    }

    struct Progress {
        let fraction: Double      // 0...1
        let speed: Int64          // bytes/second
        let downloadedBytes: Int64
        let totalBytes: Int64
    }

    /// Parses "RDMPROGRESS <downloaded> <total> <estimate> <speed>" (values may be "NA").
    static func parseProgress(_ line: String) -> Progress? {
        guard line.hasPrefix(progressPrefix) else { return nil }
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 5 else { return nil }
        let downloaded = Double(parts[1]) ?? 0
        let total = Double(parts[2]) ?? Double(parts[3]) ?? 0
        let speed = Double(parts[4]) ?? 0
        let downloadedBytes = Int64(max(0, downloaded))
        let totalBytes = Int64(max(0, total))
        guard total > 0 else {
            return Progress(fraction: 0, speed: Int64(max(0, speed)),
                            downloadedBytes: downloadedBytes, totalBytes: 0)
        }
        return Progress(fraction: min(1, max(0, downloaded / total)),
                        speed: Int64(max(0, speed)),
                        downloadedBytes: downloadedBytes, totalBytes: totalBytes)
    }
}

// MARK: - Small thread-safe helpers

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return _data }
    func set(_ d: Data) { lock.lock(); _data = d; lock.unlock() }
}

/// Splits a byte stream into lines (handles \n and \r).
private final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        var lines: [String] = []
        lock.lock()
        buffer.append(data)
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            if let s = String(data: lineData, encoding: .utf8), !s.isEmpty { lines.append(s) }
        }
        lock.unlock()
        for l in lines { onLine(l) }
    }

    func finish() {
        lock.lock()
        let rest = buffer
        buffer = Data()
        lock.unlock()
        if let s = String(data: rest, encoding: .utf8), !s.isEmpty { onLine(s) }
    }
}

/// Keeps only the last few lines (for error messages).
private final class LineTail: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func add(_ line: String) {
        lock.lock()
        lines.append(line)
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        lock.unlock()
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
