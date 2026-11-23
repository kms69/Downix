import Foundation

/// Append-only debug log for "after completion" power actions (Sleep / Shutdown).
/// `~/Library/Logs/DownloadManager/power.log` — also mirrored to Console.app.
enum PowerActionLog {
    static let fileURL: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let directory = library.appendingPathComponent("Logs/DownloadManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("power.log")
    }()

    private static let lock = NSLock()

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        NSLog("[PowerAction] %@", message)

        lock.lock()
        defer { lock.unlock() }

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
