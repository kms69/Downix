//
//  IdmDownloadWindow.swift
//  Download Manager for Mac
//
//  The floating download window in the style of Internet Download Manager:
//    • tabs: Download Status · Speed Limiter · Options on Completion
//    • telemetry list + live transfer-rate graph
//    • always-visible progress bar with Pause / Stop buttons
//    • "<< Hide Details" drawer with the per-connection (segment) table
//  Used for regular downloads and yt-dlp video downloads.
//

import SwiftUI
import AppKit

// MARK: - Optional extra details a task can provide

struct CompactSegment: Identifiable {
    let id: Int
    let downloadedBytes: Int64
    let totalBytes: Int64
    let isComplete: Bool
    var fraction: Double { totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : 0 }
}

protocol CompactDownloadDetails {
    var compactSegments: [CompactSegment] { get }
    var compactSourceURL: String { get }
    var compactResumeText: String { get }
}

extension DownloadTask: CompactDownloadDetails {
    var compactSegments: [CompactSegment] {
        segments.map {
            CompactSegment(id: $0.segmentIndex,
                           downloadedBytes: $0.downloadedBytes,
                           totalBytes: max(0, $0.endByte - $0.startByte + 1),
                           isComplete: $0.isComplete)
        }
    }
    var compactSourceURL: String { url.absoluteString }
    var compactResumeText: String { supportsResume ? "Yes" : "Not confirmed" }
}

extension VideoDownloadTask: CompactDownloadDetails {
    var compactSegments: [CompactSegment] { [] }
    var compactSourceURL: String { url.absoluteString }
    var compactResumeText: String { "Managed by yt-dlp" }
}

// MARK: - View

struct IdmDownloadProgressView<Model: CompactDownloadTaskModel>: View {
    @ObservedObject var task: Model
    let actions: CompactDownloadActions

    private enum Tab: String, CaseIterable {
        case status = "Download Status"
        case limiter = "Speed Limiter"
        case completion = "Options on Completion"
        var icon: String {
            switch self {
            case .status: return "waveform.path.ecg"
            case .limiter: return "gauge.with.dots.needle.67percent"
            case .completion: return "checkmark.square"
            }
        }
    }

    @StateObject private var bandwidthManager = BandwidthManager.shared
    @Environment(\.colorScheme) private var colorScheme
    private var st: IdmStyle { IdmStyle(colorScheme) }
    @State private var tab: Tab = .status
    @State private var showDetails = false
    @State private var speedHistory: [Double] = Array(repeating: 0, count: 45)
    @State private var peakSpeed: Double = 0

    // per-download speed limiter
    @State private var limiterOn = false
    @State private var limiterText = "1"
    @State private var limiterUnitMB = true

    // completion options
    @State private var revealWhenDone = false
    @State private var closeWhenDone = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let width: CGFloat = 560

    private var details: CompactDownloadDetails? { task as? CompactDownloadDetails }
    private var height: CGFloat { showDetails ? 640 : 460 }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            Group {
                switch tab {
                case .status: statusTab
                case .limiter: limiterTab
                case .completion: completionTab
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 238, maxHeight: 238, alignment: .top)

            Rectangle().fill(st.line).frame(height: 1)
            progressBar
            if showDetails {
                Rectangle().fill(st.line).frame(height: 1)
                detailsDrawer
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .background(st.window)
        .background(WindowSizer(width: width, height: height, title: windowTitle))
        .onAppear(perform: loadLimiter)
        .onReceive(tick) { _ in sampleSpeed() }
        .onChange(of: task.compactStatus) { status in
            guard status == .completed else { return }
            if revealWhenDone { actions.showInFinder?() }
            if closeWhenDone { actions.close() }
        }
    }

    // MARK: Title / tabs

    private var windowTitle: String {
        let pct = String(format: "[%.1f%%]", task.compactProgress * 100)
        return "\(pct) \(task.compactTitle) — \(task.compactStatusText)"
    }

    /// Title strip that sits next to the window's traffic-light buttons.
    private var headerBar: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 62)                         // room for the window buttons
            IdmLogoBadge(size: 20)
            HStack(spacing: 5) {
                Text(String(format: "[%.1f%%]", task.compactProgress * 100))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(st.emerald)
                Text(task.compactTitle)
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(st.text)
                    .lineLimit(1).truncationMode(.middle)
                Text("—").foregroundStyle(st.muted)
                Text(task.compactStatusText)
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.trailing, 12)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(st.header)
        .overlay(Rectangle().fill(st.line).frame(height: 1), alignment: .bottom)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button { tab = t } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.icon).font(.system(size: 11))
                                .foregroundStyle(tab == t ? tabColor(t) : tabColor(t).opacity(0.75))
                            Text(t.rawValue).font(.system(size: 11.5, weight: tab == t ? .semibold : .medium))
                            if t == .limiter {
                                badge(limiterOn ? "ON" : "OFF", color: limiterOn ? .orange : st.muted)
                            }
                            if t == .completion, task.compactPostDownloadAction != .none {
                                badge(task.compactPostDownloadAction.rawValue, color: st.indigo)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(tab == t ? st.tabSelected : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(tab == t ? 0.12 : 0), radius: 2, y: 1)
                        .foregroundStyle(tab == t ? st.emerald : st.muted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(st.tabTrack, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(st.line, lineWidth: 1))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(st.strip)
        .overlay(Rectangle().fill(st.line).frame(height: 1), alignment: .bottom)
    }

    private func tabColor(_ t: Tab) -> Color {
        switch t {
        case .status: return st.emerald
        case .limiter: return st.amber
        case .completion: return st.indigo
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: Tab 1 – status

    private var statusTab: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(st.emerald)
                    .frame(width: 34, height: 34)
                    .background(st.emeraldBase.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(st.emeraldBase.opacity(0.28), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.compactTitle).font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(st.text).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 5) {
                        Text("GET").font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(st.emeraldBase.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(st.emerald)
                        Text(details?.compactSourceURL ?? task.compactSubtitle)
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(st.muted)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 6)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(details?.compactSourceURL ?? task.compactSubtitle, forType: .string)
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(st.text)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(st.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(9)
            .background(st.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(st.line, lineWidth: 1))

            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    row("Status") {
                        Text(task.compactStatusText).foregroundStyle(statusColor).fontWeight(.semibold)
                    }
                    row("File size") { Text(task.compactTotalBytes > 0 ? size(task.compactTotalBytes) : "Unknown") }
                    row("Downloaded") { Text(size(task.compactDownloadedBytes)).foregroundStyle(st.emerald) }
                    row("Transfer rate") {
                        Text(task.compactStatus == .downloading ? rate(Double(task.compactSpeed)) : "—")
                            .foregroundStyle(st.emerald)
                    }
                    row("Time left") { Text(eta).foregroundStyle(st.amber) }
                    row("Resume capability", last: true) { Text(details?.compactResumeText ?? "—") }
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(st.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(st.line, lineWidth: 1))
                .frame(maxWidth: .infinity)

                rateGraph
            }

            if let error = task.compactError, !error.isEmpty {
                Text(error).font(.system(size: 10.5)).foregroundStyle(.red)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row<V: View>(_ label: String, last: Bool = false, @ViewBuilder value: () -> V) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).foregroundStyle(st.muted)
                Spacer()
                value().font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            }
            .padding(.vertical, 5)
            if !last { Rectangle().fill(st.line).frame(height: 1) }
        }
    }

    private var rateGraph: some View {
        let green = Color(hexString: "#34d399")
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TRANSFER RATE").font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color(hexString: "#94a3b8"))
                    Text(task.compactStatus == .downloading ? rate(Double(task.compactSpeed)) : "0 KB/s")
                        .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Peak \(rate(peakSpeed))").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(hexString: "#94a3b8"))
                    Text(limiterOn ? "Cap: limited" : "Cap: Unlimited").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(hexString: "#64748b"))
                }
            }
            GeometryReader { geo in
                let maxV = max(speedHistory.max() ?? 1, 1)
                let pts: [CGPoint] = speedHistory.enumerated().map { i, v in
                    CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(speedHistory.count - 1, 1)),
                            y: geo.size.height * (1 - CGFloat(v / maxV)))
                }
                ZStack {
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        p.closeSubpath()
                    }.fill(LinearGradient(colors: [green.opacity(0.35), green.opacity(0.02)],
                                          startPoint: .top, endPoint: .bottom))
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: first)
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }.stroke(green, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .padding(9)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(Color(hexString: "#0b1220"), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: Tab 2 – speed limiter

    private var limiterTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 18)).foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Use speed limiter for this download").font(.system(size: 12.5, weight: .semibold))
                    Text("Changes apply immediately, without dropping connections.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $limiterOn).labelsHidden().toggleStyle(.switch)
                    .onChange(of: limiterOn) { _ in applyLimiter() }
            }
            Divider()
            HStack(spacing: 8) {
                Text("Maximum transfer rate:").font(.system(size: 11.5))
                TextField("1", text: $limiterText)
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                    .multilineTextAlignment(.center)
                    .onSubmit { applyLimiter() }
                Picker("", selection: $limiterUnitMB) {
                    Text("KB/s").tag(false)
                    Text("MB/s").tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 110)
                .onChange(of: limiterUnitMB) { _ in applyLimiter() }
                Button("Apply") { limiterOn = true; applyLimiter() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
            }
            HStack(spacing: 6) {
                Text("Quick presets:").font(.system(size: 11)).foregroundStyle(.secondary)
                preset("500 KB/s", 500, false)
                preset("2 MB/s", 2, true)
                preset("10 MB/s", 10, true)
                preset("50 MB/s", 50, true)
                Button("Unlimited") { limiterOn = false; applyLimiter() }
                    .buttonStyle(.bordered).controlSize(.small).tint(.green)
                Spacer()
            }
            Spacer(minLength: 0)
        }
    }

    private func preset(_ title: String, _ value: Double, _ mb: Bool) -> some View {
        Button(title) {
            limiterText = value == value.rounded() ? String(Int(value)) : String(value)
            limiterUnitMB = mb
            limiterOn = true
            applyLimiter()
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    // MARK: Tab 3 – completion

    private var completionTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WHEN THIS DOWNLOAD FINISHES")
                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            Toggle("Reveal the file in Finder", isOn: $revealWhenDone).font(.system(size: 12))
            Toggle("Close this window automatically", isOn: $closeWhenDone).font(.system(size: 12))
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "power").foregroundStyle(.red)
                Text("After all downloads finish:").font(.system(size: 12, weight: .semibold))
                Picker("", selection: Binding(
                    get: { task.compactPostDownloadAction },
                    set: { task.compactPostDownloadAction = $0 })) {
                    ForEach(PostDownloadAction.compactCases, id: \.self) { a in
                        Label(a.rawValue, systemImage: a.icon).tag(a)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 190)
                Spacer()
            }
            .padding(10)
            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Sleep and Shut Down run only after the last active download has finished.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Persistent progress + buttons

    private var progressBar: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                HStack {
                    Text(String(format: "%.1f%%", task.compactProgress * 100))
                        .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(barColor)
                    Text("|").foregroundStyle(st.line)
                    Text(bytesLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(st.muted)
                    if task.compactStatus == .downloading {
                        Text(rate(Double(task.compactSpeed)))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(st.emeraldBase.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(st.emerald)
                    }
                    Spacer()
                    Text(eta.isEmpty || eta == "—" ? "" : "ETA: \(eta)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(st.amber)
                }
                IdmProgressBar(fraction: task.compactProgress, colors: barGradient, height: 16,
                               animated: task.compactStatus == .downloading, track: st.track)
                    .overlay(Capsule().stroke(st.line, lineWidth: 1))
            }

            HStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() } } label: {
                    Text(showDetails ? "<< Hide details" : "Show details >>")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(st.text)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(st.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()
                buttons
                Button(action: actions.close) {
                    Text("Close").font(.system(size: 12, weight: .semibold)).foregroundStyle(st.text)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(st.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(st.footer)
    }

    @ViewBuilder
    private var buttons: some View {
        switch task.compactStatus {
        case .downloading:
            if let pause = actions.pause { colored("Pause", "pause.fill", .orange, pause) }
            if let stop = actions.stop { colored("Stop", "stop.fill", .red, stop) }
        case .paused:
            if let resume = actions.resume { colored("Resume", "play.fill", .green, resume) }
            if let cancel = actions.cancel { colored("Cancel", "xmark.circle.fill", .red, cancel) }
        case .waiting:
            if let cancel = actions.cancel { colored("Cancel", "xmark.circle.fill", .red, cancel) }
        case .converting:
            if let stop = actions.stop { colored("Stop", "stop.fill", .red, stop) }
        case .completed:
            if let open = actions.openFile { colored("Open File", "arrow.up.right.square.fill", .accentColor, open) }
            if let show = actions.showInFinder { colored("Show in Finder", "folder.fill", .gray, show) }
        case .failed, .cancelled:
            if let retry = actions.retry { colored("Retry", "arrow.clockwise", .orange, retry) }
            if let remove = actions.remove { colored("Remove", "trash", .red, remove) }
        }
    }

    private func colored(_ title: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(LinearGradient(colors: [color, color.opacity(0.78)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: color.opacity(0.28), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Details drawer (connections)

    private var detailsDrawer: some View {
        let segs = details?.compactSegments ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Start positions and download progress by connections", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if !segs.isEmpty {
                    Text("\(segs.filter { !$0.isComplete }.count) / \(segs.count) active")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(st.emerald)
                }
            }
            if segs.isEmpty {
                Text("Per-connection details are not available for this download type.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                HStack(spacing: 2) {
                    ForEach(segs) { s in
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(st.track)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(s.isComplete ? st.teal : st.emeraldBase)
                                    .frame(width: g.size.width * s.fraction)
                            }
                        }
                    }
                }
                .frame(height: 16)

                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text("#").frame(width: 28, alignment: .leading)
                            Text("Downloaded").frame(width: 100, alignment: .leading)
                            Text("Progress").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Info").frame(width: 120, alignment: .leading)
                        }
                        .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                        Divider()
                        ForEach(segs) { s in
                            HStack {
                                Text("\(s.id + 1)").frame(width: 28, alignment: .leading)
                                Text(size(s.downloadedBytes)).frame(width: 100, alignment: .leading)
                                ProgressView(value: s.fraction).frame(maxWidth: .infinity)
                                Text(s.isComplete ? "Complete" : (task.compactStatus == .downloading ? "Receiving data…" : "Idle"))
                                    .foregroundStyle(s.isComplete ? Color.green : Color.secondary)
                                    .frame(width: 120, alignment: .leading)
                            }
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(.vertical, 3)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 96)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(st.drawer)
    }

    // MARK: Helpers

    private var barColor: Color {
        switch task.compactStatus {
        case .completed: return st.emerald
        case .failed, .cancelled: return st.rose
        case .paused: return st.amber
        default: return st.emerald
        }
    }

    private var barGradient: [Color] {
        switch task.compactStatus {
        case .failed, .cancelled: return st.failedColors
        case .paused: return st.pausedColors
        default: return st.barColors
        }
    }

    private var statusColor: Color {
        switch task.compactStatus {
        case .downloading: return st.emerald
        case .completed: return st.emerald
        case .failed, .cancelled: return st.rose
        case .paused: return st.amber
        default: return st.muted
        }
    }

    private var bytesLabel: String {
        let d = size(task.compactDownloadedBytes)
        return task.compactTotalBytes > 0 ? "\(d) of \(size(task.compactTotalBytes))" : d
    }

    private var eta: String {
        guard task.compactStatus == .downloading, task.compactTimeRemaining > 0 else { return "—" }
        let s = Int(task.compactTimeRemaining)
        if s < 60 { return String(format: "%02d sec", s) }
        if s < 3600 { return String(format: "%02d min %02d sec", s / 60, s % 60) }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond <= 0 { return "0 KB/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    private func sampleSpeed() {
        let v = task.compactStatus == .downloading ? Double(task.compactSpeed) : 0
        speedHistory.append(v)
        if speedHistory.count > 45 { speedHistory.removeFirst(speedHistory.count - 45) }
        peakSpeed = max(peakSpeed, v)
    }

    // per-download limiter persistence (same store the old window used)
    private func loadLimiter() {
        guard let limit = bandwidthManager.getDownloadLimit(task.compactID) else { return }
        limiterOn = limit.isEnabled
        guard limit.downloadSpeed > 0 else { return }
        if limit.downloadSpeed >= 1_000_000 {
            limiterUnitMB = true
            limiterText = trimmed(Double(limit.downloadSpeed) / 1_000_000)
        } else {
            limiterUnitMB = false
            limiterText = trimmed(Double(limit.downloadSpeed) / 1_000)
        }
    }

    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func applyLimiter() {
        let value = Double(limiterText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let bytes = Int64(value * (limiterUnitMB ? 1_000_000 : 1_000))
        let enabled = limiterOn && bytes > 0
        bandwidthManager.setDownloadLimit(task.compactID,
                                          limit: BandwidthLimit(isEnabled: enabled, downloadSpeed: bytes))
    }
}

// MARK: - Keeps the hosting window sized to the SwiftUI content and titled live

private struct WindowSizer: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if window.title != title { window.title = title }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            let current = window.contentRect(forFrameRect: window.frame).size
            guard abs(current.width - width) > 0.5 || abs(current.height - height) > 0.5 else { return }
            let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height))
            var frame = window.frame
            frame.origin.y += frame.size.height - target.size.height    // keep the top edge in place
            frame.size = target.size
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
