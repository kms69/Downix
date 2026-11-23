//
//  VideoCodecPreference.swift
//  "Video codec" choice for YouTube-style downloads.
//

import SwiftUI

enum VideoCodecPreference {
    static let key = "videoCodecPreference"          // "auto" | "av1" | "h264"
    static var choice: String { UserDefaults.standard.string(forKey: key) ?? "auto" }
    static var preferH264: Bool { choice == "h264" }

    /// Value of yt-dlp's `vcodec` prefix for the chosen codec (nil = no preference).
    static var vcodecPrefix: String? {
        switch choice {
        case "h264": return "avc1"
        case "av1": return "av01"
        default: return nil
        }
    }
}

struct VideoCodecSettingRow: View {
    @AppStorage(VideoCodecPreference.key) private var codec = "auto"

    var body: some View {
        Picker("Video codec:", selection: $codec) {
            Text("AV1 (smallest files)").tag("av1")
            Text("H.264 (larger files, plays on any device)").tag("h264")
            Text("Auto (highest bitrate offered)").tag("auto")
        }
        Text(note).font(.caption).foregroundStyle(.secondary)
    }

    private var note: String {
        switch codec {
        case "av1": return "Downloads the AV1 stream at your chosen quality. Smallest size; some TVs and Android boxes play it with lag."
        case "h264": return "Downloads the H.264 stream at your chosen quality (YouTube offers it up to 1080p). Bigger files, smooth on older devices."
        default: return "Lets the app pick the stream with the highest bitrate."
        }
    }
}
