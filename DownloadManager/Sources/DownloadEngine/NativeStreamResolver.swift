//
//  NativeStreamResolver.swift
//  Finds the direct video / audio stream URLs of a YouTube page so the
//  multi-threaded native engine can download them. yt-dlp is used only as the
//  extractor (`-J`, no download), which is much faster than letting it
//  download the single-connection way. Any failure returns nil and the
//  caller falls back to the normal yt-dlp download.
//

import Foundation

struct NativeStream {
    let url: URL
    let ext: String
    let height: Int
    let size: Int64
    let headers: [String: String]
}

struct NativeStreamPlan {
    let video: NativeStream
    let audio: NativeStream?       // nil when the video stream already carries sound
}

enum NativeStreamResolver {

    /// True when the last yt-dlp -J was stopped for taking too long (YouTube unreachable).
    static var lastResolveTimedOut = false

    /// Sites handled by the native engine. Everything else keeps using yt-dlp.
    static func isEligibleHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    /// Blocking: runs yt-dlp -J. Call from a background task.
    static func resolve(pageURL: URL, outputExtension: String, maxHeight: Int?,
                        authArgs: [String]) -> NativeStreamPlan? {
        guard let ytDlp = ExternalToolRunner.ytDlpPath else { return nil }
        lastResolveTimedOut = false
        let args = authArgs + ["-J", "--no-playlist", "--no-warnings", pageURL.absoluteString]
        let started = Date()
        guard let result = try? ExternalToolRunner.run(binary: ytDlp, args: args, timeout: 90) else {
            YtDlpLog.log("native: yt-dlp -J did not run")
            return nil
        }
        guard result.succeeded else {
            if result.exitCode == 15 || Date().timeIntervalSince(started) >= 85 { lastResolveTimedOut = true }
            YtDlpLog.log("native: yt-dlp -J failed (exit \(result.exitCode)): \(result.stderr.suffix(400))")
            return nil
        }
        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["is_live"] as? Bool) != true,
              let formats = json["formats"] as? [[String: Any]] else {
            YtDlpLog.log("native: no usable format list")
            return nil
        }
        let plan = plan(formats: formats, outputExtension: outputExtension, maxHeight: maxHeight)
        let summary = formats.map { f in
            "\(f["format_id"] ?? "?"):\(f["ext"] ?? "?"):\(f["protocol"] ?? "?"):\(f["height"] ?? 0)"
        }.joined(separator: " ")
        YtDlpLog.log("native: extracted \(formats.count) formats in \(String(format: "%.1f", Date().timeIntervalSince(started)))s, plan \(plan == nil ? "NONE" : "ok"); \(summary)")
        return plan
    }

    // MARK: Format choice (pure, testable)

    static func plan(formats: [[String: Any]], outputExtension: String, maxHeight: Int?) -> NativeStreamPlan? {
        let candidates: [NativeStream?] = formats.map { f in
            // Plain HTTPS files only (no DASH/HLS manifests or fragmented streams).
            guard (f["protocol"] as? String) == "https",
                  f["fragments"] == nil,
                  let s = f["url"] as? String, let url = URL(string: s) else { return nil }
            let size = (f["filesize"] as? NSNumber)?.int64Value
                ?? (f["filesize_approx"] as? NSNumber)?.int64Value ?? 0
            var headers = (f["http_headers"] as? [String: String]) ?? [:]
            headers.removeValue(forKey: "Accept-Encoding")      // ranges need the raw bytes
            return NativeStream(url: url, ext: (f["ext"] as? String) ?? "",
                                height: (f["height"] as? Int) ?? 0, size: size, headers: headers)
        }
        func codecs(_ f: [String: Any]) -> (v: Bool, a: Bool) {
            ((f["vcodec"] as? String ?? "none") != "none", (f["acodec"] as? String ?? "none") != "none")
        }
        func tbr(_ f: [String: Any]) -> Double { (f["tbr"] as? NSNumber)?.doubleValue ?? 0 }

        let pairs = Array(zip(formats, candidates)).compactMap { f, c in c.map { (f, $0) } }
        let videoOnly = pairs.filter { codecs($0.0) == (true, false) }
        let audioOnly = pairs.filter { codecs($0.0) == (false, true) }

        let wantsMP4 = outputExtension == "mp4"
        let videoExts: Set<String> = wantsMP4 ? ["mp4"] : (outputExtension == "webm" ? ["webm"] : ["mp4", "webm"])
        let audioExts: Set<String> = wantsMP4 ? ["m4a"] : (outputExtension == "webm" ? ["webm"] : ["m4a", "webm"])

        func within(_ c: NativeStream) -> Bool { maxHeight == nil || c.height <= maxHeight! }

        let videos = videoOnly.filter { videoExts.contains($0.1.ext) && within($0.1) }
            .sorted { ($0.1.height, tbr($0.0)) > ($1.1.height, tbr($1.0)) }
        let audios = audioOnly.filter { audioExts.contains($0.1.ext) }
            .sorted { tbr($0.0) > tbr($1.0) }

        // "H.264" setting: avc1 streams first (plays smoothly on boxes that lag with AV1).
        var pool = videos
        if let prefix = VideoCodecPreference.vcodecPrefix {
            let matching = videos.filter { ($0.0["vcodec"] as? String ?? "").hasPrefix(prefix) }
            if !matching.isEmpty { pool = matching }
        }
        guard let v = pool.first, let a = audios.first else { return nil }
        // A much lower resolution than asked means the good formats were not
        // plain files (e.g. manifest-only); let yt-dlp deal with it.
        if let limit = maxHeight, v.1.height > 0, v.1.height < min(limit, 720) / 2 { return nil }
        YtDlpLog.log("native pick: choice=\(VideoCodecPreference.choice) video \(v.0["format_id"] ?? "?") \(v.0["vcodec"] ?? "?") \(v.1.height)p, audio \(a.0["format_id"] ?? "?")")
        return NativeStreamPlan(video: v.1, audio: a.1)
    }
}
