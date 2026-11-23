//
//  BatchLinksWindow.swift
//  "Download N links with Downix": the window shown when several links are
//  highlighted in the browser. Lists every link with its type and size, lets the
//  user tick what they want, then starts them all in one go.
//

import SwiftUI
import AppKit

// MARK: - Data

struct LinkBatch {
    var pageTitle = ""
    var pageURL = ""
    var referer = ""
    var cookie = ""
    var cookieHost = ""
    var userAgent = ""
    var links: [(url: String, text: String)] = []

    /// Folder the native host writes batch files to. Only files inside it are accepted.
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DownloadManager/Batches", isDirectory: true)
    }

    /// Reads (and deletes) a batch file written by the browser helper.
    static func load(from file: URL) -> LinkBatch? {
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(directory.standardizedFileURL.path + "/") else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var batch = LinkBatch()
        batch.pageTitle = root["pageTitle"] as? String ?? ""
        batch.pageURL = root["pageUrl"] as? String ?? ""
        batch.referer = root["referer"] as? String ?? ""
        batch.cookie = root["cookie"] as? String ?? ""
        batch.cookieHost = (root["cookieHost"] as? String ?? "").lowercased()
        batch.userAgent = root["userAgent"] as? String ?? ""
        for entry in root["links"] as? [[String: Any]] ?? [] {
            guard let url = entry["url"] as? String, !url.isEmpty else { continue }
            batch.links.append((url, entry["text"] as? String ?? ""))
        }
        return batch.links.isEmpty ? nil : batch
    }
}

enum LinkKind: String, CaseIterable {
    case video = "Video", audio = "Audio", archive = "Archives", document = "Documents"
    case image = "Images", program = "Programs", other = "Other", page = "Web pages"

    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .archive: return "archivebox"
        case .document: return "doc.text"
        case .image: return "photo"
        case .program: return "app.badge"
        case .other: return "doc"
        case .page: return "globe"
        }
    }

    private static let table: [LinkKind: Set<String>] = [
        .video: ["mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "ts", "3gp", "m3u8"],
        .audio: ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma", "aiff"],
        .archive: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "iso", "dmg", "pkg"],
        .document: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "epub", "mobi", "rtf", "odt", "ods", "pages", "numbers", "key", "md"],
        .image: ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "tif", "tiff", "heic", "avif", "psd"],
        .program: ["exe", "msi", "apk", "deb", "rpm", "app", "jar", "appimage", "bin"],
    ]
    private static let pageExt: Set<String> = ["html", "htm", "xhtml", "shtml", "php", "asp", "aspx", "jsp", "cgi", "cfm"]

    static func fromExtension(_ ext: String) -> LinkKind {
        let e = ext.lowercased()
        if e.isEmpty || e.count > 5 || pageExt.contains(e) { return .page }
        for (kind, set) in table where set.contains(e) { return kind }
        return .other
    }

    static func fromMime(_ mime: String) -> LinkKind? {
        let m = mime.lowercased()
        if m.hasPrefix("text/html") || m.contains("xhtml") { return .page }
        if m.hasPrefix("video/") { return .video }
        if m.hasPrefix("audio/") { return .audio }
        if m.hasPrefix("image/") { return .image }
        if m.contains("zip") || m.contains("rar") || m.contains("tar") || m.contains("compressed")
            || m.contains("7z") || m.contains("diskimage") { return .archive }
        if m.contains("pdf") || m.contains("msword") || m.contains("officedocument") || m.contains("excel")
            || m.contains("powerpoint") || m.hasPrefix("text/") || m.contains("epub") { return .document }
        if m.contains("octet-stream") || m.hasPrefix("application/") { return .other }
        return nil
    }
}

struct BatchLinkItem: Identifiable {
    let id = UUID()
    let url: URL
    var name: String
    var kind: LinkKind
    var size: Int64?
    var checked: Bool
    var isVideoSite: Bool
}

private struct ProbeResult: Sendable {
    let id: UUID
    let size: Int64?
    let mime: String?
    let fileName: String?
}

// MARK: - Model

@MainActor
final class BatchLinksModel: ObservableObject {
    @Published var items: [BatchLinkItem] = []
    @Published var search = ""
    @Published var filter: LinkKind?
    @Published var folder: URL = DownloadFolderStore.shared.resolvedDefault
    @Published var probing = false
    @Published var doneMessage: String?

    let batch: LinkBatch
    private var touched = Set<UUID>()
    private var probeTask: Task<Void, Never>?

    init(batch: LinkBatch) {
        self.batch = batch
        var used = Set<String>()
        var built: [BatchLinkItem] = []
        for entry in batch.links {
            guard let url = URL(string: entry.url) else { continue }
            let video = VideoPlatform.detect(from: url) != .generic
            let kind: LinkKind = video ? .video : LinkKind.fromExtension(url.pathExtension)
            var name = Self.fileName(for: url, text: entry.text)
            if used.contains(name.lowercased()) {
                let ext = (name as NSString).pathExtension
                let stem = (name as NSString).deletingPathExtension
                var n = 2
                var candidate = name
                repeat {
                    candidate = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
                    n += 1
                } while used.contains(candidate.lowercased())
                name = candidate
            }
            used.insert(name.lowercased())
            built.append(BatchLinkItem(url: url, name: name, kind: kind, size: nil, checked: kind != .page, isVideoSite: video))
        }
        // A selection made only of pages (no file links at all): tick everything.
        if !built.contains(where: { $0.checked }) {
            for i in built.indices { built[i].checked = true }
        }
        items = built
    }

    static func fileName(for url: URL, text: String) -> String {
        var name = url.lastPathComponent
        if name.isEmpty || name == "/" {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            name = t.isEmpty ? (url.host ?? "download") : t
        }
        let bad = CharacterSet(charactersIn: "/:\\\0")
        name = name.components(separatedBy: bad).joined(separator: "_")
        return String(name.prefix(180))
    }

    // MARK: Filtering and ticking

    var visible: [BatchLinkItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            (filter == nil || item.kind == filter)
                && (q.isEmpty || item.name.lowercased().contains(q) || item.url.absoluteString.lowercased().contains(q))
        }
    }

    var selectedCount: Int { items.filter { $0.checked }.count }

    var selectedBytes: Int64 { items.filter { $0.checked }.compactMap { $0.size }.reduce(0, +) }

    func count(of kind: LinkKind) -> Int { items.filter { $0.kind == kind }.count }

    func set(_ id: UUID, _ value: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].checked = value
        touched.insert(id)
    }

    func setVisible(_ value: Bool) {
        let ids = Set(visible.map { $0.id })
        for i in items.indices where ids.contains(items[i].id) {
            items[i].checked = value
            touched.insert(items[i].id)
        }
    }

    // MARK: Sizes

    func probe() {
        probeTask?.cancel()
        let todo = items.filter { !$0.isVideoSite }.map { ($0.id, $0.url, requestHeaders(for: $0.url)) }
        guard !todo.isEmpty else { return }
        let session = ProxySession.makeSession()
        probing = true
        probeTask = Task { [weak self] in
            await withTaskGroup(of: ProbeResult.self) { group in
                var next = 0
                let limit = 6
                while next < min(limit, todo.count) {
                    let t = todo[next]; next += 1
                    group.addTask { await Self.probeOne(id: t.0, url: t.1, headers: t.2, session: session) }
                }
                for await result in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    await self?.apply(result)
                    if next < todo.count {
                        let t = todo[next]; next += 1
                        group.addTask { await Self.probeOne(id: t.0, url: t.1, headers: t.2, session: session) }
                    }
                }
            }
            self?.probing = false
        }
    }

    func stopProbe() { probeTask?.cancel() }

    private func apply(_ r: ProbeResult) {
        guard let i = items.firstIndex(where: { $0.id == r.id }) else { return }
        if let size = r.size, size > 0 { items[i].size = size }
        if let name = r.fileName, !name.isEmpty, !touched.contains(r.id) {
            items[i].name = Self.fileName(for: URL(fileURLWithPath: name), text: "")
        }
        if items[i].kind == .page {
            var newKind: LinkKind?
            if let name = r.fileName, !(name as NSString).pathExtension.isEmpty {
                newKind = LinkKind.fromExtension((name as NSString).pathExtension)
            } else if let mime = r.mime {
                newKind = LinkKind.fromMime(mime)
            }
            if let k = newKind, k != .page {
                items[i].kind = k
                if !touched.contains(r.id) { items[i].checked = true }
            }
        }
    }

    nonisolated private static func probeOne(id: UUID, url: URL, headers: [String: String],
                                             session: URLSession) async -> ProbeResult {
        func request(_ method: String, range: Bool) async -> (HTTPURLResponse?, Int64?) {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 15
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            if range { req.setValue("bytes=0-0", forHTTPHeaderField: "Range") }
            do {
                let (_, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else { return (nil, nil) }
                var length: Int64?
                if let cr = http.value(forHTTPHeaderField: "Content-Range"), let slash = cr.lastIndex(of: "/") {
                    length = Int64(cr[cr.index(after: slash)...])
                } else if let cl = http.value(forHTTPHeaderField: "Content-Length") {
                    length = Int64(cl)
                }
                return (http, length)
            } catch {
                return (nil, nil)
            }
        }

        var (http, length) = await request("HEAD", range: false)
        if http == nil || (http?.statusCode ?? 0) >= 400 || length == nil {
            let second = await request("GET", range: true)
            if second.0 != nil, (second.0?.statusCode ?? 500) < 400 { (http, length) = second }
        }
        var fileName: String?
        if let cd = http?.value(forHTTPHeaderField: "Content-Disposition"),
           let re = try? NSRegularExpression(pattern: #"filename\*?=(?:UTF-8'')?"?([^";]+)"?"#, options: .caseInsensitive),
           let m = re.firstMatch(in: cd, range: NSRange(cd.startIndex..., in: cd)),
           let r = Range(m.range(at: 1), in: cd) {
            fileName = String(cd[r]).removingPercentEncoding ?? String(cd[r])
        }
        return ProbeResult(id: id, size: length, mime: http?.mimeType, fileName: fileName)
    }

    // MARK: Starting

    /// Headers for one link. The page's cookies only go to the site they belong to.
    func requestHeaders(for url: URL) -> [String: String] {
        var h: [String: String] = [:]
        if !batch.referer.isEmpty { h["Referer"] = batch.referer }
        if !batch.userAgent.isEmpty { h["User-Agent"] = batch.userAgent }
        if !batch.cookie.isEmpty, !batch.cookieHost.isEmpty {
            if let host = url.host?.lowercased(),
               host == batch.cookieHost || host.hasSuffix("." + batch.cookieHost) || batch.cookieHost.hasSuffix("." + host) {
                h["Cookie"] = batch.cookie
            }
        }
        return h
    }

    @discardableResult
    func start(now: Bool) -> Int {
        probeTask?.cancel()
        let chosen = items.filter { $0.checked }
        for item in chosen {
            if item.isVideoSite {
                _ = VideoDownloadManager.shared.addAndStartDownload(
                    url: item.url, options: .default, cookieFile: nil,
                    preferredTitle: nil, destinationFolder: folder)
            } else {
                let task = DownloadManager.shared.addDownload(
                    url: item.url,
                    destinationPath: folder,
                    filename: item.name,
                    headers: requestHeaders(for: item.url),
                    startImmediately: now
                )
                task.showsCompletionDialog = false
            }
        }
        return chosen.count
    }
}

// MARK: - Window controller

@MainActor
final class BatchLinksController: NSObject, NSWindowDelegate {
    static let shared = BatchLinksController()
    private var panels: [ObjectIdentifier: (panel: NSPanel, model: BatchLinksModel)] = [:]

    func present(_ batch: LinkBatch) {
        let model = BatchLinksModel(batch: batch)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.title = "Download \(model.items.count) links"
        panel.minSize = NSSize(width: 620, height: 420)
        panel.appearance = ThemeManager.appearance(for: ThemeManager.shared.currentColorScheme)
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.delegate = self

        let key = ObjectIdentifier(panel)
        panel.contentView = NSHostingView(rootView: BatchLinksView(model: model) { [weak self, weak panel] in
            guard let panel else { return }
            self?.close(panel)
        }.preferredColorScheme(ThemeManager.shared.currentColorScheme))
        panels[key] = (panel, model)

        let cascade = CGFloat(panels.count - 1) * 24
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.midX - 390 + cascade, y: v.midY - 300 - cascade))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.probe()
    }

    private func close(_ panel: NSPanel) { panel.close() }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSPanel else { return }
        panels[ObjectIdentifier(window)]?.model.stopProbe()
        panels.removeValue(forKey: ObjectIdentifier(window))
    }
}

// MARK: - View

private struct BatchLinksView: View {
    @ObservedObject var model: BatchLinksModel
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var folders = DownloadFolderStore.shared
    private var st: IdmStyle { IdmStyle(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(st.line)
            toolbar
            Divider().overlay(st.line)
            if let done = model.doneMessage {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundColor(st.emerald)
                    Text(done).font(.headline).foregroundColor(st.text)
                }
                Spacer()
            } else {
                list
                Divider().overlay(st.line)
                footer
            }
        }
        .background(st.window)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 28)).foregroundColor(st.emerald)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.items.count) links found").font(.headline).foregroundColor(st.text)
                Text(model.batch.pageTitle.isEmpty ? model.batch.pageURL : model.batch.pageTitle)
                    .font(.caption).foregroundColor(st.muted).lineLimit(1)
            }
            Spacer()
            if model.probing { ProgressView().controlSize(.small) }
        }
        .padding(14)
        .background(st.header)
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                chip("All", count: model.items.count, active: model.filter == nil) { model.filter = nil }
                ForEach(LinkKind.allCases, id: \.self) { kind in
                    let n = model.count(of: kind)
                    if n > 0 {
                        chip(kind.rawValue, count: n, active: model.filter == kind) {
                            model.filter = (model.filter == kind) ? nil : kind
                        }
                    }
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(st.muted)
                TextField("Filter by name or address", text: $model.search)
                    .textFieldStyle(.plain)
                Spacer()
                Button("Check all") { model.setVisible(true) }
                Button("Uncheck all") { model.setVisible(false) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(st.strip)
    }

    private func chip(_ title: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(title) \(count)")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(active ? st.emeraldBase.opacity(0.25) : st.chip)
                .foregroundColor(active ? st.emerald : st.text)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.visible) { item in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { item.checked }, set: { model.set(item.id, $0) }))
                            .labelsHidden()
                        Image(systemName: item.kind.icon).foregroundColor(st.sky).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).foregroundColor(st.text).lineLimit(1).truncationMode(.middle)
                            Text(item.url.absoluteString).font(.caption2).foregroundColor(st.muted)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(item.kind.rawValue).font(.caption).foregroundColor(st.muted).frame(width: 80, alignment: .leading)
                        Text(item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                            .font(.caption.monospacedDigit()).foregroundColor(st.muted).frame(width: 74, alignment: .trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { model.set(item.id, !item.checked) }
                    Divider().overlay(st.line)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Save to").foregroundColor(st.muted)
                Menu {
                    ForEach(folders.choices, id: \.path) { url in
                        Button(DownloadFolderStore.display(url)) { model.folder = url }
                    }
                    Divider()
                    Button("Choose…") { chooseFolder() }
                } label: {
                    Text(DownloadFolderStore.display(model.folder))
                }
                .frame(maxWidth: 320)
                Spacer()
                let bytes = model.selectedBytes
                Text("\(model.selectedCount) selected" + (bytes > 0 ? " • " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : ""))
                    .font(.callout).foregroundColor(st.muted)
            }
            HStack {
                Button("Cancel") { onClose() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add without starting") { finish(now: false) }
                    .disabled(model.selectedCount == 0)
                Button("Download now") { finish(now: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedCount == 0)
            }
        }
        .padding(14)
        .background(st.footer)
    }

    private func finish(now: Bool) {
        let n = model.start(now: now)
        model.doneMessage = now ? "Started \(n) download\(n == 1 ? "" : "s")" : "Added \(n) download\(n == 1 ? "" : "s")"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { onClose() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.folder
        if panel.runModal() == .OK, let url = panel.url { model.folder = url }
    }
}
