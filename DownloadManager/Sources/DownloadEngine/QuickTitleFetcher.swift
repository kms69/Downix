//
//  QuickTitleFetcher.swift
//  Download Manager for Mac
//
//  Gets a video's title in well under a second so the download can start
//  without waiting for a full yt-dlp metadata extraction (which, on YouTube,
//  takes several seconds and then runs AGAIN inside the download command).
//

import Foundation

enum QuickTitleFetcher {

    static func fetch(_ url: URL) async -> String? {
        guard let host = url.host?.lowercased(), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }

        if host.contains("youtube.com") || host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return await youtubeOEmbed(url)
        }
        return await pageTitle(url, host: host)
    }

    // MARK: - YouTube (oEmbed, tiny JSON)

    private static func youtubeOEmbed(_ url: URL) async -> String? {
        var comps = URLComponents(string: "https://www.youtube.com/oembed")
        comps?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString),
                             URLQueryItem(name: "format", value: "json")]
        guard let endpoint = comps?.url else { return nil }
        guard let data = await get(endpoint, maxBytes: 64 * 1024, timeout: 4) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else { return nil }
        return clean(title, host: "youtube.com")
    }

    // MARK: - Any other site: og:title / <title> from the first bytes of the page

    private static func pageTitle(_ url: URL, host: String) async -> String? {
        guard let data = await get(url, maxBytes: 150 * 1024, timeout: 5) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let patterns = [
            #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#,
            #"<title[^>]*>([^<]+)</title>"#
        ]
        for p in patterns {
            if let r = html.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                let match = String(html[r])
                if let g = match.range(of: p.contains("<title") ? #">([^<]+)<"# : #"content=["']([^"']+)["']"#,
                                       options: [.regularExpression, .caseInsensitive]) {
                    var raw = String(match[g])
                    raw = raw.replacingOccurrences(of: #"^(>|content=["'])|(<|["'])$"#, with: "",
                                                   options: [.regularExpression, .caseInsensitive])
                    let title = clean(raw, host: host)
                    if !title.isEmpty { return title }
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func get(_ url: URL, maxBytes: Int, timeout: TimeInterval) async -> Data? {
        let cfg = ProxySession.makeConfiguration(base: .ephemeral)   // honours the app's proxy setting
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 2
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            let (stream, response) = try await session.bytes(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { stream.task.cancel(); return nil }
            var data = Data()
            for try await byte in stream {
                data.append(byte)
                if data.count >= maxBytes { break }
            }
            stream.task.cancel()
            return data
        } catch {
            return nil
        }
    }

    /// Decode entities and drop a trailing " - SiteName" / " | SiteName".
    private static func clean(_ raw: String, host: String) -> String {
        var t = raw
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
                       ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let site = host.replacingOccurrences(of: "www.", with: "")
            .split(separator: ".").first.map(String.init)?.lowercased() ?? ""
        if !site.isEmpty,
           let r = t.range(of: #"\s[-|–—]\s[^-|–—]{2,40}$"#, options: .regularExpression),
           t[r].lowercased().contains(site) {
            t.removeSubrange(r)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
