//
//  URLClassifier.swift
//  Download Manager for Mac
//
//  Decides, for one URL, whether it is
//    .direct     – a real file: use the native multi-segment engine (DownloadManager)
//    .streaming  – a web page / manifest: use the yt-dlp video pipeline
//
//  Order of checks (cheap first, network last):
//    1. manifest extension (.m3u8 / .mpd)           -> streaming
//    2. known file extension (.zip .mp4 .dmg ...)   -> direct
//    3. known streaming site (YouTube, Vimeo ...)   -> streaming
//    4. ask the server (HEAD, then a 1-byte ranged GET) and read the headers
//    5. inconclusive -> the caller's hint, otherwise streaming (yt-dlp can still try)
//

import Foundation

enum DownloadKind: Equatable {
    case direct
    case streaming
}

enum URLClassifier {

    // MARK: - Static knowledge

    /// Extensions that are always a file the user wants as-is.
    static let fileExtensions: Set<String> = [
        // video / audio
        "mp4", "m4v", "mkv", "avi", "mov", "wmv", "flv", "webm", "mpg", "mpeg", "3gp",
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma",
        // archives / installers / images
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst",
        "dmg", "pkg", "iso", "img", "exe", "msi", "apk", "deb", "rpm", "appimage",
        // documents / data
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "epub", "mobi",
        "csv", "json", "xml", "txt", "torrent", "bin",
        // pictures
        "jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "tiff", "heic"
    ]

    /// Playlists/manifests describe a stream; they are not the media itself.
    static let manifestExtensions: Set<String> = ["m3u8", "mpd"]

    // MARK: - Public API

    /// Cheap, offline decision. `nil` = cannot tell without asking the server.
    static func quickClassify(_ url: URL) -> DownloadKind? {
        let ext = url.pathExtension.lowercased()
        if manifestExtensions.contains(ext) { return .streaming }
        if fileExtensions.contains(ext) { return .direct }
        if VideoPlatform.detect(from: url) != .generic { return .streaming }
        return nil
    }

    /// Full decision. `headers` (Referer / Cookie / User-Agent from the browser
    /// extension) are sent with the probe so protected links answer like they
    /// would to the browser. `hint` is only used when the server cannot be asked.
    static func classify(_ url: URL,
                         headers: [String: String] = [:],
                         hint: DownloadKind? = nil) async -> DownloadKind {
        if let quick = quickClassify(url) { return quick }
        if let probed = await probe(url, headers: headers) { return probed }
        return hint ?? .streaming
    }

    // MARK: - Server probe

    private static let probeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// HEAD first; many servers refuse it (403/405/501), so fall back to a
    /// 1-byte ranged GET. Returns nil when neither request gives an answer.
    private static func probe(_ url: URL, headers: [String: String]) async -> DownloadKind? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }

        let cfg = ProxySession.makeConfiguration(base: .ephemeral)   // honours the app's proxy setting
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        for method in ["HEAD", "GET"] {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue(probeUserAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            if method == "GET" { req.setValue("bytes=0-0", forHTTPHeaderField: "Range") }
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            do {
                // bytes(for:) returns once the headers are in; cancelling the
                // task stops the body, so a server that ignores Range costs nothing.
                let (stream, response) = try await session.bytes(for: req)
                stream.task.cancel()
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200 || http.statusCode == 206 else { continue }
                return kind(fromContentType: http.value(forHTTPHeaderField: "Content-Type"),
                            disposition: http.value(forHTTPHeaderField: "Content-Disposition"))
            } catch {
                if (error as NSError).code == NSURLErrorCancelled { return nil }
                continue
            }
        }
        return nil
    }

    /// Pure function (easy to unit-test): headers in, decision out.
    static func kind(fromContentType contentType: String?, disposition: String?) -> DownloadKind {
        let type = (contentType ?? "").lowercased()
        let disp = (disposition ?? "").lowercased()

        if disp.contains("attachment") { return .direct }                         // server says "save this"
        if type.contains("mpegurl") || type.contains("dash+xml") { return .streaming }
        if type.hasPrefix("text/html") || type.contains("xhtml") { return .streaming }   // a web page
        if type.hasPrefix("video/") || type.hasPrefix("audio/") || type.hasPrefix("image/")
            || type.hasPrefix("application/") { return .direct }                  // incl. octet-stream, zip, pdf
        return .streaming                                                         // missing/odd type: let yt-dlp try
    }
}
