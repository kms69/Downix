import AppKit
import Foundation

/// Sleep / shutdown used by the "after all downloads" power actions.
/// Sleep uses the native `pmset sleepnow`; shutdown asks System Events (no root
/// needed for a logged-in user) and falls back to `/sbin/shutdown -h now`.
@MainActor
enum SystemPowerActions {
    /// `RDM_DISABLE_POWER_ACTIONS=1` exercises the whole pipeline (logging included)
    /// without actually sleeping or shutting the Mac down. Never set in normal use.
    private static var isSuppressed: Bool {
        ProcessInfo.processInfo.environment["RDM_DISABLE_POWER_ACTIONS"] == "1"
    }

    @discardableResult
    static func sleep() -> Bool {
        PowerActionLog.log("SLEEP requested — primary command: /usr/bin/pmset sleepnow")
        logEnvironmentSnapshot(reason: "before sleep")
        didRetrySleep = false

        if isSuppressed {
            PowerActionLog.log("SLEEP suppressed by RDM_DISABLE_POWER_ACTIONS")
            return true
        }

        let primary = run("/usr/bin/pmset", ["sleepnow"])
        if primary.succeeded {
            watchForSleep()
            return true
        }

        PowerActionLog.log("pmset sleepnow did not succeed — falling back to System Events")
        let fallback = run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to sleep"])
        if fallback.succeeded {
            watchForSleep()
            return true
        }

        presentFailure(
            title: "Could Not Sleep the Mac",
            message: "pmset: \(primary.message)\nSystem Events: \(fallback.message)\n\n"
                + "If macOS asked for permission, allow Download Manager to control System Events in "
                + "System Settings → Privacy & Security → Automation.\n\nLog: \(PowerActionLog.fileURL.path)"
        )
        return false
    }

    @discardableResult
    static func shutdown() -> Bool {
        PowerActionLog.log("SHUTDOWN requested — primary command: osascript System Events shut down")
        logEnvironmentSnapshot(reason: "before shutdown")

        if isSuppressed {
            PowerActionLog.log("SHUTDOWN suppressed by RDM_DISABLE_POWER_ACTIONS")
            return true
        }

        let primary = run(
            "/usr/bin/osascript",
            ["-e", "tell application \"System Events\" to shut down"]
        )
        if primary.succeeded {
            PowerActionLog.log("shutdown accepted by System Events")
            return true
        }

        PowerActionLog.log("System Events shutdown failed — falling back to /sbin/shutdown -h now")
        let fallback = run("/sbin/shutdown", ["-h", "now"])
        if fallback.succeeded {
            return true
        }

        presentFailure(
            title: "Could Not Shut Down the Mac",
            message: "System Events: \(primary.message)\nshutdown: \(fallback.message)\n\n"
                + "If macOS asked for permission, allow Download Manager to control System Events in "
                + "System Settings → Privacy & Security → Automation.\n\nLog: \(PowerActionLog.fileURL.path)"
        )
        return false
    }

    // MARK: - Command execution

    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
        let launchError: String?

        var succeeded: Bool { launchError == nil && status == 0 }

        var message: String {
            if let launchError { return launchError }
            let detail = stderr.isEmpty ? stdout : stderr
            return detail.isEmpty ? "exit status \(status)" : detail
        }
    }

    private static func run(
        _ executable: String,
        _ arguments: [String],
        logOutput: Bool = true
    ) -> CommandResult {
        let command = ([executable] + arguments).joined(separator: " ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if logOutput { PowerActionLog.log("exec: \(command)") }

        do {
            try process.run()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let result = CommandResult(
                status: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                stderr: String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                launchError: nil
            )
            if logOutput {
                PowerActionLog.log(
                    "exit: \(command) status=\(result.status) "
                        + "stdout=\"\(result.stdout)\" stderr=\"\(result.stderr)\""
                )
            }
            return result
        } catch {
            PowerActionLog.log("launch failed: \(command) error=\(error.localizedDescription)")
            return CommandResult(
                status: -1,
                stdout: "",
                stderr: "",
                launchError: error.localizedDescription
            )
        }
    }

    // MARK: - Diagnostics

    /// Snapshot of everything macOS uses to refuse a sleep request. This is the
    /// native equivalent of Electron's `powerSaveBlocker`: the app itself never
    /// takes a `ProcessInfo.beginActivity` / `IOPMAssertion`, and any assertion
    /// held by another process shows up here.
    private static func logEnvironmentSnapshot(reason: String) {
        PowerActionLog.log("diagnostics (\(reason)): app-held sleep assertions = none")
        PowerActionLog.log("diagnostics (\(reason)): pmset sleepnow does not force sleep past another process's assertion")

        let settings = run("/usr/bin/pmset", ["-g"], logOutput: false)
        for line in settings.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SleepDisabled") || trimmed.contains("prevented") {
                PowerActionLog.log("pmset -g: \(trimmed)")
            }
        }

        let assertions = run("/usr/bin/pmset", ["-g", "assertions"], logOutput: false)
        for line in assertions.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("PreventUserIdleSystemSleep")
                || trimmed.contains("PreventSystemSleep")
                || trimmed.contains("PreventUserIdleDisplaySleep")
                || trimmed == "Assertion status system-wide:" else { continue }
            PowerActionLog.log("assertion: \(trimmed)")
        }

        let caffeinate = run("/usr/bin/pgrep", ["-x", "caffeinate"], logOutput: false)
        PowerActionLog.log("caffeinate running: \(caffeinate.succeeded ? caffeinate.stdout : "no")")
    }

    private final class WakeFlag {
        var didWake = false
    }

    private static let wakeFlag = WakeFlag()
    private static var didRetrySleep = false

    /// If control comes back after asking for sleep, either the Mac slept and
    /// woke up (the request worked) or it is still awake (something blocked it).
    private static func watchForSleep() {
        let requestedAt = Date()
        wakeFlag.didWake = false
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            wakeFlag.didWake = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            if wakeFlag.didWake {
                PowerActionLog.log("SLEEP confirmed: the Mac slept and has woken up again")
                return
            }

            PowerActionLog.log(String(
                format: "WARNING: the Mac is still awake %.1fs after the sleep request — it was blocked",
                Date().timeIntervalSince(requestedAt)
            ))

            // `pmset sleepnow` is an idle-sleep request; a stubborn assertion can
            // swallow it. A System Events sleep goes through loginwindow, so give
            // it one try before reporting the blocker.
            guard !didRetrySleep else {
                logEnvironmentSnapshot(reason: "still awake after retry")
                return
            }
            didRetrySleep = true
            let retry = run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to sleep"])
            if retry.succeeded {
                PowerActionLog.log("retried sleep through System Events (loginwindow)")
                watchForSleep()
            } else {
                PowerActionLog.log("System Events sleep retry failed: \(retry.message)")
                logEnvironmentSnapshot(reason: "still awake after retry failed")
            }
        }
    }

    private static func presentFailure(title: String, message: String) {
        PowerActionLog.log("power action FAILED: \(title) — \(message)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
