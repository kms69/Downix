import Foundation

/// Failed yt-dlp runs are appended to ~/Library/Logs/DownloadManager/ytdlp.log
/// so a site that stops working can be diagnosed from the real error text.
enum YtDlpLog {
    private static let queue = DispatchQueue(label: "ytdlp-log")

    static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        print("[yt-dlp] \(message)")
        queue.async {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DownloadManager", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("ytdlp.log")
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
