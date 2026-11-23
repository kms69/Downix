//
//  UpdateAlert.swift
//  "Check for Updates..." as a dialog (menu-bar popup).
//

import AppKit

@MainActor
enum UpdateAlert {
    static func run() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            let outcome = await UpdateChecker.latest()
            let alert = NSAlert()
            switch outcome {
            case .latest(let remote, let page):
                if UpdateChecker.isNewer(remote, than: version) {
                    alert.messageText = "Downix \(remote) is available"
                    alert.informativeText = "You have version \(version)."
                    alert.addButton(withTitle: "Open Download Page")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
                    return
                }
                alert.messageText = "You're up to date"
                alert.informativeText = "Downix \(version) is the latest version."
            case .none:
                alert.messageText = "No updates found"
                alert.informativeText = "No published releases were found, so there is nothing newer to install."
            case .failed(let message):
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = message
            }
            alert.runModal()
        }
    }
}
