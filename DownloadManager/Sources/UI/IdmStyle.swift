//
//  IdmStyle.swift
//  Shared look for the floating download window and the confirmation window
//  (emerald / teal / sky, deep navy in dark mode, candy-stripe progress bar).
//

import SwiftUI

struct IdmStyle {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    // Surfaces
    var window: Color { dark ? Color(hexString: "#090d18") : Color(hexString: "#ffffff") }
    var header: Color { dark ? Color(hexString: "#060912") : Color(hexString: "#f1f5f9") }
    var strip: Color { dark ? Color(hexString: "#070b15") : Color(hexString: "#f8fafc") }
    var tabTrack: Color { dark ? Color(hexString: "#040710") : Color(hexString: "#e2e8f0") }
    var tabSelected: Color { dark ? Color(hexString: "#121a2d") : Color.white }
    var card: Color { dark ? Color(hexString: "#060912") : Color(hexString: "#f1f5f9") }
    var footer: Color { dark ? Color(hexString: "#070b15") : Color(hexString: "#f1f5f9") }
    var drawer: Color { dark ? Color(hexString: "#050812") : Color(hexString: "#f8fafc") }
    var track: Color { dark ? Color(hexString: "#0f172a") : Color(hexString: "#e2e8f0") }
    var line: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.09) }
    var chip: Color { dark ? Color(hexString: "#1e293b") : Color(hexString: "#e2e8f0") }

    // Text
    var text: Color { dark ? Color(hexString: "#e2e8f0") : Color(hexString: "#1e293b") }
    var muted: Color { dark ? Color(hexString: "#94a3b8") : Color(hexString: "#64748b") }

    // Accents
    var emerald: Color { DownixAccent.isDefault ? (dark ? Color(hexString: "#34d399") : Color(hexString: "#059669")) : DownixAccent.primary }
    var emeraldBase: Color { DownixAccent.isDefault ? Color(hexString: "#10b981") : DownixAccent.primary }
    var teal: Color { DownixAccent.isDefault ? Color(hexString: "#2dd4bf") : DownixAccent.secondary }
    var sky: Color { dark ? Color(hexString: "#38bdf8") : Color(hexString: "#0284c7") }
    var amber: Color { dark ? Color(hexString: "#fbbf24") : Color(hexString: "#d97706") }
    var indigo: Color { dark ? Color(hexString: "#818cf8") : Color(hexString: "#6366f1") }
    var rose: Color { dark ? Color(hexString: "#fb7185") : Color(hexString: "#e11d48") }

    var barColors: [Color] { [Color(hexString: "#059669"), Color(hexString: "#10b981"), Color(hexString: "#34d399")] }
    var pausedColors: [Color] { [Color(hexString: "#f59e0b"), Color(hexString: "#fbbf24")] }
    var failedColors: [Color] { [Color(hexString: "#e11d48"), Color(hexString: "#fb7185")] }
    var logoGradient: LinearGradient {
        LinearGradient(colors: [Color(hexString: "#34d399"), Color(hexString: "#14b8a6"), Color(hexString: "#047857")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Small green globe-with-arrow badge used in headers.
struct IdmLogoBadge: View {
    var size: CGFloat = 20
    var body: some View {
        Image(nsImage: DownixLogo.mark)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size * 1.25, height: size * 1.25)
            .frame(width: size, height: size)
    }
}

/// Rounded progress bar with a gradient fill and moving candy stripes.
struct IdmProgressBar: View {
    let fraction: Double
    let colors: [Color]
    var height: CGFloat = 16
    var animated: Bool = true
    var track: Color = Color.primary.opacity(0.10)

    var body: some View {
        GeometryReader { geo in
            let w = max(0, geo.size.width * CGFloat(min(1, max(0, fraction))))
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated || w < 2)) { ctx in
                    let phase = CGFloat((ctx.date.timeIntervalSinceReferenceDate * 40)
                        .truncatingRemainder(dividingBy: 24))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay(
                            Canvas { context, size in
                                guard animated else { return }
                                var x = -size.height * 2 + phase
                                while x < size.width + size.height {
                                    var p = Path()
                                    p.move(to: CGPoint(x: x + size.height, y: 0))
                                    p.addLine(to: CGPoint(x: x + size.height + 12, y: 0))
                                    p.addLine(to: CGPoint(x: x + 12, y: size.height))
                                    p.addLine(to: CGPoint(x: x, y: size.height))
                                    p.closeSubpath()
                                    context.fill(p, with: .color(.white.opacity(0.22)))
                                    x += 24
                                }
                            }
                            .clipShape(Capsule())
                        )
                }
                .frame(width: w)
                .shadow(color: (colors.first ?? .green).opacity(0.45), radius: 5)
            }
        }
        .frame(height: height)
    }
}
