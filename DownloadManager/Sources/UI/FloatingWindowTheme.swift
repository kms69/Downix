//
//  FloatingWindowTheme.swift
//  Keeps the floating windows (confirm / progress / complete) in the same
//  Day / Night / System mode as the main window.
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class FloatingWindowTheme {
    static let shared = FloatingWindowTheme()

    private var windows: [WeakWindow] = []
    private var cancellable: AnyCancellable?

    private struct WeakWindow { weak var window: NSWindow? }

    private init() {
        cancellable = ThemeManager.shared.$currentColorScheme
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    private static func appearance() -> NSAppearance? {
        switch ThemeManager.shared.currentColorScheme {
        case .some(.dark): return NSAppearance(named: .darkAqua)
        case .some(.light): return NSAppearance(named: .aqua)
        default: return nil                       // follow the system
        }
    }

    static func apply(to window: NSWindow) {
        window.appearance = appearance()
        shared.windows.removeAll { $0.window == nil }
        if !shared.windows.contains(where: { $0.window === window }) {
            shared.windows.append(WeakWindow(window: window))
        }
    }

    private func refresh() {
        windows.removeAll { $0.window == nil }
        for entry in windows { entry.window?.appearance = Self.appearance() }
    }
}
