//
//  FloatingPanel.swift
//  Download Manager for Mac
//

import AppKit
import SwiftUI

/// Panel behind every floating download window. These panels are shown without
/// activating the app (a browser grab must not steal focus), but once the user
/// clicks inside — especially a menu picker — the panel has to become key and
/// the app active. Otherwise the first click is only spent focusing the panel:
/// a menu picker does not open and the window can fall behind again.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            if !isKeyWindow { makeKeyAndOrderFront(nil) }
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// A hosting view whose controls react to the click that focuses the panel
/// instead of swallowing it.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
