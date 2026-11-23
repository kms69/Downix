import SwiftUI

/// HyperFetch-inspired palette used by the main window. It is intentionally
/// derived from the effective SwiftUI colour scheme so the quick Day/Night
/// toggle (and the System setting in Appearance preferences) repaints the
/// whole window without restarting.
struct HyperTheme {
    let scheme: ColorScheme

    var isDark: Bool { scheme == .dark }

    // Window / surfaces
    var background: Color { isDark ? Color(hexString: "#090d16") : Color(hexString: "#eef3f9") }
    var backgroundTop: Color { isDark ? Color(hexString: "#0c1220") : Color(hexString: "#f8fafc") }
    var sidebar: Color { isDark ? Color(hexString: "#0d1320").opacity(0.96) : Color.white.opacity(0.72) }
    var header: Color { isDark ? Color(hexString: "#0f1523").opacity(0.92) : Color.white.opacity(0.82) }
    var toolbar: Color { isDark ? Color(hexString: "#111827").opacity(0.82) : Color.white.opacity(0.70) }
    var surface: Color { isDark ? Color(hexString: "#101827") : Color.white }
    var surfaceRaised: Color { isDark ? Color(hexString: "#151f31") : Color(hexString: "#f8fafc") }
    var surfaceMuted: Color { isDark ? Color(hexString: "#0a0f1a") : Color(hexString: "#eef2f7") }
    var footer: Color { isDark ? Color(hexString: "#0f1625").opacity(0.95) : Color.white.opacity(0.86) }

    // Text
    var textPrimary: Color { isDark ? Color(hexString: "#f1f5f9") : Color(hexString: "#0f172a") }
    var textSecondary: Color { isDark ? Color(hexString: "#94a3b8") : Color(hexString: "#64748b") }
    var textTertiary: Color { isDark ? Color(hexString: "#64748b") : Color(hexString: "#94a3b8") }

    // Lines
    var border: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    var borderStrong: Color { isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12) }

    // Brand
    var accent: Color { DownixAccent.isDefault ? (isDark ? Color(hexString: "#38bdf8") : Color(hexString: "#0284c7")) : DownixAccent.primary }
    var accentDeep: Color { DownixAccent.isDefault ? Color(hexString: "#0ea5e9") : DownixAccent.primary }
    var indigo: Color { DownixAccent.isDefault ? (isDark ? Color(hexString: "#818cf8") : Color(hexString: "#6366f1")) : DownixAccent.secondary }
    var success: Color { isDark ? Color(hexString: "#34d399") : Color(hexString: "#059669") }
    var warning: Color { isDark ? Color(hexString: "#fbbf24") : Color(hexString: "#d97706") }
    var danger: Color { isDark ? Color(hexString: "#fb7185") : Color(hexString: "#e11d48") }
    var purple: Color { isDark ? Color(hexString: "#a78bfa") : Color(hexString: "#7c3aed") }
    var teal: Color { isDark ? Color(hexString: "#2dd4bf") : Color(hexString: "#0d9488") }
    var amber: Color { isDark ? Color(hexString: "#f59e0b") : Color(hexString: "#b45309") }
    var pink: Color { isDark ? Color(hexString: "#f472b6") : Color(hexString: "#db2777") }

    var accentGradient: LinearGradient {
        LinearGradient(colors: DownixAccent.isDefault ? [Color(hexString: "#0ea5e9"), Color(hexString: "#6366f1")] : [DownixAccent.primary, DownixAccent.secondary],
                       startPoint: .leading, endPoint: .trailing)
    }

    var logoGradient: LinearGradient {
        LinearGradient(colors: [Color(hexString: "#38bdf8"),
                                Color(hexString: "#0ea5e9"),
                                Color(hexString: "#4f46e5")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var progressGradient: LinearGradient {
        LinearGradient(colors: DownixAccent.isDefault ? [Color(hexString: "#0ea5e9"), Color(hexString: "#6366f1")] : [DownixAccent.primary, DownixAccent.secondary],
                       startPoint: .leading, endPoint: .trailing)
    }

    var selectedRow: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(isDark ? 0.16 : 0.14), accent.opacity(0.03)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    var windowBackground: some View {
        ZStack {
            LinearGradient(colors: [backgroundTop, background], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [(DownixAccent.isDefault ? Color(hexString: "#0ea5e9") : DownixAccent.primary).opacity(isDark ? 0.14 : 0.10), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [(DownixAccent.isDefault ? Color(hexString: "#6366f1") : DownixAccent.secondary).opacity(isDark ? 0.10 : 0.07), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

extension FileType {
    var tint: Color {
        switch self {
        case .video: return .pink
        case .audio: return .purple
        case .document: return .green
        case .archive: return .orange
        case .application: return .cyan
        case .image: return .teal
        case .other: return .indigo
        }
    }
}
