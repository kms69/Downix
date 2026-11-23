//
//  DownixBranding.swift
//  Menu-bar arrow that fills with progress + live speed, and a Dock tile with a big
//  progress bar, big speed number and a breathing emerald glow.
//

import SwiftUI
import AppKit

enum DownixFormat {
    /// "12.3 MB/s"
    static func speed(_ bytesPerSecond: Int64) -> String {
        let p = speedParts(bytesPerSecond)
        return p.value + " " + p.unit
    }

    /// ("12.3", "MB/s") so the Dock can draw the number large and the unit small.
    static func speedParts(_ bytesPerSecond: Int64) -> (value: String, unit: String) {
        guard bytesPerSecond >= 1024 else { return ("0", "KB/s") }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        let s = f.string(fromByteCount: bytesPerSecond)          // e.g. "12.3 MB"
        let pieces = s.split(separator: " ")
        if pieces.count == 2 { return (String(pieces[0]), String(pieces[1]) + "/s") }
        return (s, "/s")
    }
}

/// One place that adds up every running download (normal + video).
@MainActor
final class DownixActivity: ObservableObject {
    static let shared = DownixActivity()

    @Published private(set) var activeCount = 0
    @Published private(set) var progress: Double = 0      // 0...1
    @Published private(set) var speed: Int64 = 0          // smoothed bytes/s
    @Published private(set) var phase: Double = 0         // 0..<1, drives the breathing glow
    @Published private(set) var attention = false         // a download failed while the app was in the background

    private var timer: Timer?
    private var baseIcon: NSImage?
    private var dockView: DownixDockTileView?
    private var lastFailed = 0
    private var primed = false

    private init() {}

    func start() {
        guard timer == nil else { return }
        baseIcon = NSApp.applicationIconImage?.copy() as? NSImage
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.attention { self.attention = false }
                self.refreshDock()
            }
        }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        var count = 0, failed = 0
        var done: Int64 = 0, total: Int64 = 0, rate: Int64 = 0
        var fractionSum = 0.0, fractionCount = 0

        for t in DownloadManager.shared.downloadTasks {
            if t.videoTaskID != nil { continue }        // streaming rows: counted once, via their video task
            switch t.state {
            case .downloading:
                count += 1
                rate += t.speed
                if t.totalBytes > 0 { done += t.downloadedBytes; total += t.totalBytes }
                else { fractionSum += t.progress; fractionCount += 1 }
            case .failed:
                failed += 1
            default: break
            }
        }
        for v in VideoDownloadManager.shared.videoTasks {
            if v.downloadTask != nil { continue }       // direct files: counted once, via their own row
            switch v.state {
            case .downloading, .converting:
                count += 1
                rate += v.speed
                fractionSum += v.progress; fractionCount += 1
            case .failed:
                failed += 1
            default: break
            }
        }

        var p = 0.0
        if total > 0 && fractionCount == 0 { p = Double(done) / Double(total) }
        else if total > 0 { p = (Double(done) / Double(total) + fractionSum / Double(fractionCount)) / 2 }
        else if fractionCount > 0 { p = fractionSum / Double(fractionCount) }
        p = min(max(p, 0), 1)

        if primed, failed > lastFailed, !NSApp.isActive { attention = true }
        lastFailed = failed
        primed = true

        if activeCount != count { activeCount = count }
        if abs(progress - p) > 0.0005 { progress = p }
        let smoothed = count == 0 ? 0 : rate                 // same value the download windows show
        if speed != smoothed { speed = smoothed }
        let newPhase = count > 0 ? (phase + 0.25 / 2.6).truncatingRemainder(dividingBy: 1) : 0
        if phase != newPhase { phase = newPhase }

        refreshDock()
    }

    private func refreshDock() {
        let tile = NSApp.dockTile
        guard activeCount > 0 || attention else {
            if tile.contentView != nil { tile.contentView = nil; tile.display() }
            return
        }
        if dockView == nil, let icon = baseIcon {
            let size = tile.size.width > 0 ? tile.size : NSSize(width: 128, height: 128)
            let v = DownixDockTileView(frame: NSRect(origin: .zero, size: size))
            v.icon = icon
            dockView = v
        }
        guard let v = dockView else { return }
        if tile.contentView !== v { tile.contentView = v }
        v.update(active: activeCount > 0, progress: progress,
                 speed: DownixFormat.speedParts(speed), phase: phase, attention: attention)
        tile.display()
    }
}

// MARK: - Dock tile

final class DownixDockTileView: NSView {
    var icon = NSImage()
    private var active = false
    private var progress = 0.0
    private var speed: (value: String, unit: String) = ("0", "KB/s")
    private var phase = 0.0
    private var attention = false

    func update(active: Bool, progress: Double, speed: (value: String, unit: String),
                phase: Double, attention: Bool) {
        self.active = active; self.progress = progress; self.speed = speed
        self.phase = phase; self.attention = attention
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        icon.draw(in: bounds)

        let amber = NSColor(calibratedRed: 0.98, green: 0.65, blue: 0.14, alpha: 1)
        let emerald = NSColor(calibratedRed: 0.18, green: 0.95, blue: 0.70, alpha: 1)
        let accent = (attention && !active) ? amber : emerald
        let breathe = active ? 0.5 + 0.5 * sin(phase * 2 * .pi) : 1.0

        // Glow hugging the icon's rounded square (it covers ~80 % of the tile).
        let body = bounds.insetBy(dx: w * 0.098, dy: w * 0.098)
        let radius = body.width * 0.25
        let outline = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = accent.withAlphaComponent(0.25 + 0.55 * breathe)
        glow.shadowBlurRadius = w * (0.03 + 0.05 * breathe)
        glow.shadowOffset = .zero
        glow.set()
        accent.withAlphaComponent(0.35 + 0.5 * breathe).setStroke()
        outline.lineWidth = w * 0.014
        outline.stroke()
        NSGraphicsContext.restoreGraphicsState()

        guard active else { return }

        // Big progress bar near the bottom edge.
        let barW = body.width * 0.86, barH = w * 0.115
        let bar = NSRect(x: bounds.midX - barW / 2, y: body.minY + w * 0.07, width: barW, height: barH)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barH / 2, yRadius: barH / 2).fill()
        let inner = bar.insetBy(dx: barH * 0.14, dy: barH * 0.14)
        let fillW = max(inner.height, inner.width * CGFloat(min(max(progress, 0), 1)))
        let fill = NSRect(x: inner.minX, y: inner.minY, width: fillW, height: inner.height)
        let gradient = NSGradient(starting: emerald,
                                  ending: NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.51, alpha: 1))
        gradient?.draw(in: NSBezierPath(roundedRect: fill, xRadius: inner.height / 2, yRadius: inner.height / 2), angle: 0)

        // Big speed number (small unit next to it) above the bar.
        var numberSize = w * 0.20
        func build(_ n: CGFloat) -> NSAttributedString {
            let s = NSMutableAttributedString(
                string: speed.value,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: n, weight: .heavy),
                             .foregroundColor: NSColor.white])
            s.append(NSAttributedString(
                string: " " + speed.unit,
                attributes: [.font: NSFont.systemFont(ofSize: n * 0.52, weight: .bold),
                             .foregroundColor: emerald]))
            return s
        }
        var text = build(numberSize)
        let padX = w * 0.05, padY = w * 0.016
        let maxWidth = body.width * 0.9 - padX * 2
        if text.size().width > maxWidth {
            numberSize *= maxWidth / text.size().width
            text = build(numberSize)
        }
        let size = text.size()
        let pill = NSRect(x: bounds.midX - (size.width + padX * 2) / 2, y: bar.maxY + w * 0.03,
                          width: size.width + padX * 2, height: size.height + padY * 2)
        NSColor.black.withAlphaComponent(0.74).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height * 0.4, yRadius: pill.height * 0.4).fill()
        text.draw(at: NSPoint(x: pill.minX + padX, y: pill.minY + padY))
    }
}

// MARK: - Menu bar

/// Loads the logo images that bundle_app.sh copies into the app's Resources.
enum DownixLogo {
    /// Colour butterfly without the icon frame (main window, in-app badges).
    static let mark: NSImage = load("DownixMark") ?? NSApp.applicationIconImage ?? NSImage()
    /// White-logo mask for the menu bar (black + alpha, drawn as a template image).
    static let menuMask: NSImage? = load("DownixMenu")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// Menu-bar image: the white Downix logo (a template image, so macOS draws it white or
/// black to match the bar). While downloading it dims and fills from the bottom up with the
/// total progress and breathes; a failure turns it amber.
enum DownixTray {
    static func image(progress: Double, active: Bool, phase: Double, attention: Bool) -> NSImage {
        let mask = DownixLogo.menuMask
        let warn = attention && !active
        let img = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            guard let mask else { return true }
            let breathe = active ? 0.5 + 0.5 * sin(phase * 2 * .pi) : 1.0
            let ms = mask.size
            let scale = min(rect.width / ms.width, rect.height / ms.height)
            let r = NSRect(x: rect.midX - ms.width * scale / 2, y: rect.midY - ms.height * scale / 2,
                           width: ms.width * scale, height: ms.height * scale)
            if active {
                mask.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.32)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: r.minX, y: r.minY, width: r.width,
                                          height: r.height * CGFloat(min(max(progress, 0.05), 1)))).addClip()
                mask.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.8 + 0.2 * breathe)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                mask.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            }
            if warn {
                NSColor(calibratedRed: 0.98, green: 0.65, blue: 0.14, alpha: 1).setFill()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        img.isTemplate = !warn
        return img
    }
}

/// Label of the menu-bar item: the arrow, plus the live speed while downloading.
struct DownixMenuBarContent: View {
    @ObservedObject private var activity = DownixActivity.shared

    var body: some View {
        let _ = DownixActivity.shared.start()
        HStack(spacing: 4) {
            Image(nsImage: DownixTray.image(progress: activity.progress,
                                            active: activity.activeCount > 0,
                                            phase: activity.phase,
                                            attention: activity.attention))
            if activity.activeCount > 0 {
                Text(DownixFormat.speed(activity.speed))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
        }
    }
}
