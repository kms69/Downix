//
//  AutoShutdownManager.swift
//  Download Manager for Mac - Feature #4: Auto Shutdown Engine
//
//  Created on February 15, 2026
//

import Foundation
import Combine
import AppKit

/// Manages auto-shutdown actions after download completion
@MainActor
class AutoShutdownManager: ObservableObject {
    
    static let shared = AutoShutdownManager()
    
    @Published var actions: [AutoShutdownAction] = []
    @Published var activeWarning: PendingAction?
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let checkInterval: TimeInterval = 5.0 // Check every 5 seconds
    
    private var startTime: Date = Date()
    private var totalDownloadedMB: Int64 = 0
    
    // Cancellation tokens for pending actions
    private var pendingExecutions: [UUID: Timer] = [:]
    
    struct PendingAction {
        let action: AutoShutdownAction
        var remainingSeconds: Int
        let triggerTime: Date
    }
    
    private init() {
        startMonitoring()
    }
    
    // MARK: - Monitoring
    
    /// Start monitoring for trigger conditions
    func startMonitoring() {
        stopMonitoring()
        startTime = Date()
        
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkTriggerConditions()
        }
    }
    
    /// Stop monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Reset monitoring (restart timers and counters)
    func resetMonitoring() {
        startTime = Date()
        totalDownloadedMB = 0
        
        // Reset all actions to pending
        for i in 0..<actions.count {
            actions[i].executionStatus = .pending
            actions[i].executedAt = nil
            actions[i].executionNote = nil
        }
    }
    
    // MARK: - Action Management
    
    /// Add a new auto-shutdown action
    func addAction(_ action: AutoShutdownAction) -> Bool {
        let validation = action.validate()
        guard validation.isValid else {
            print("❌ Invalid action: \(validation.errors.joined(separator: ", "))")
            return false
        }
        
        DispatchQueue.main.async {
            if !self.actions.contains(where: { $0.id == action.id }) {
                self.actions.append(action)
            }
        }
        
        return true
    }
    
    /// Remove an action
    func removeAction(_ action: AutoShutdownAction) {
        // Cancel pending execution if any
        if let timer = pendingExecutions[action.id] {
            timer.invalidate()
            pendingExecutions.removeValue(forKey: action.id)
        }
        
        DispatchQueue.main.async {
            self.actions.removeAll { $0.id == action.id }
        }
    }
    
    /// Update an existing action
    func updateAction(_ action: AutoShutdownAction) -> Bool {
        let validation = action.validate()
        guard validation.isValid else {
            print("❌ Invalid action: \(validation.errors.joined(separator: ", "))")
            return false
        }
        
        DispatchQueue.main.async {
            if let index = self.actions.firstIndex(where: { $0.id == action.id }) {
                var updated = action
                updated.lastModified = Date()
                self.actions[index] = updated
            }
        }
        
        return true
    }
    
    /// Enable/disable an action
    func setActionEnabled(_ enabled: Bool, for actionID: UUID) {
        DispatchQueue.main.async {
            if let index = self.actions.firstIndex(where: { $0.id == actionID }) {
                self.actions[index].isEnabled = enabled
                self.actions[index].lastModified = Date()
                
                // If disabling, cancel any pending execution
                if !enabled, let timer = self.pendingExecutions[actionID] {
                    timer.invalidate()
                    self.pendingExecutions.removeValue(forKey: actionID)
                    self.actions[index].executionStatus = .cancelled
                }
            }
        }
    }
    
    /// Get all enabled actions
    func getEnabledActions() -> [AutoShutdownAction] {
        return actions.filter { $0.isEnabled && $0.executionStatus == .pending }
    }
    
    // MARK: - Trigger Checking
    
    /// Check if any actions should be triggered
    func checkTriggerConditions() {
        let elapsedMinutes = Int(Date().timeIntervalSince(startTime) / 60)
        
        // Get download state from DownloadManager (must be on main thread)
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.checkTriggerConditions() }
            return
        }
        let manager = DownloadManager.shared
        let allTasks = manager.downloadTasks
        let videoTasks = VideoDownloadManager.shared.videoTasks
        let hasWork = !allTasks.isEmpty || !videoTasks.isEmpty
        let allDownloadsComplete = hasWork
            && allTasks.allSatisfy { $0.state == .completed }
            && videoTasks.allSatisfy { $0.state == .completed }
        let queueComplete = allDownloadsComplete
        
        // Calculate total downloaded
        totalDownloadedMB = allTasks.reduce(0) { $0 + ($1.downloadedBytes / 1_048_576) }
        
        // Check each enabled action
        for action in getEnabledActions() {
            let shouldTrigger = action.shouldTrigger(
                allDownloadsComplete: allDownloadsComplete,
                queueDownloadsComplete: queueComplete,
                categoryComplete: nil, // TODO: Implement category tracking
                taskComplete: nil, // TODO: Implement task completion tracking
                elapsedMinutes: elapsedMinutes,
                downloadedMB: totalDownloadedMB
            )
            
            if shouldTrigger {
                triggerAction(action)
            }
        }
    }
    
    /// Manually check if a specific task completion should trigger actions
    func checkTaskCompletion(_ taskID: UUID, category: DownloadCategory?) {
        for action in getEnabledActions() {
            var shouldTrigger = false
            
            if action.condition == .specificTask && action.taskID == taskID {
                shouldTrigger = true
            } else if action.condition == .specificCategory,
                      let catID = action.categoryID,
                      let cat = category,
                      catID == cat.rawValue {
                // Check if all tasks in this category are complete
                guard Thread.isMainThread else { break }
                let manager = DownloadManager.shared
                let categoryTasks = manager.downloadTasks.filter { $0.category.rawValue == cat.rawValue }
                shouldTrigger = categoryTasks.allSatisfy { $0.state == .completed }
            }
            
            if shouldTrigger {
                triggerAction(action)
            }
        }
    }
    
    // MARK: - Action Execution
    
    /// Trigger an action (with optional delay and warning)
    private func triggerAction(_ action: AutoShutdownAction) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        
        DispatchQueue.main.async {
            self.actions[index].executionStatus = .triggered
            print("🔔 Action triggered: \(action.displayDescription)")
        }
        
        // Calculate total delay time
        let delaySeconds = action.delayMinutes * 60
        let totalDelay = action.showWarning ? delaySeconds + action.warningSeconds : delaySeconds
        
        // Show warning if configured
        if action.showWarning && action.actionType != .none {
            DispatchQueue.main.async {
                self.activeWarning = PendingAction(
                    action: action,
                    remainingSeconds: action.warningSeconds,
                    triggerTime: Date()
                )
            }
            
            // Start countdown
            startWarningCountdown(for: action)
        }
        
        // Schedule execution
        if totalDelay > 0 {
            let executionTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(totalDelay), repeats: false) { [weak self] _ in
                self?.executeAction(action)
                self?.pendingExecutions.removeValue(forKey: action.id)
            }
            pendingExecutions[action.id] = executionTimer
        } else {
            executeAction(action)
        }
    }
    
    /// Start warning countdown
    private func startWarningCountdown(for action: AutoShutdownAction) {
        var countdown = action.warningSeconds
        
        _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            countdown -= 1
            
            DispatchQueue.main.async {
                if var warning = self.activeWarning, warning.action.id == action.id {
                    warning.remainingSeconds = countdown
                    self.activeWarning = warning
                }
            }
            
            if countdown <= 0 {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.activeWarning = nil
                }
            }
        }
    }
    
    /// Execute the actual shutdown action
    private func executeAction(_ action: AutoShutdownAction) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        
        DispatchQueue.main.async {
            self.actions[index].executionStatus = .executing
            self.actions[index].executedAt = Date()
        }
        
        print("⚡ Executing action: \(action.actionType.rawValue)")
        
        var success = false
        var note: String?
        
        switch action.actionType {
        case .none:
            success = true
            note = "No action taken"
            
        case .shutdown:
            success = performShutdown()
            note = success ? "System shutdown initiated" : "Failed to shutdown"
            
        case .sleep:
            success = performSleep()
            note = success ? "System sleep initiated" : "Failed to sleep"
            
        case .hibernate:
            success = performHibernate()
            note = success ? "System hibernate initiated" : "Failed to hibernate"
            
        case .closeApp:
            success = performCloseApp()
            note = success ? "Application closing" : "Failed to close app"
            
        case .runScript:
            success = performRunScript(action)
            note = success ? "Script executed successfully" : "Script execution failed"
        }
        
        // Update execution status
        DispatchQueue.main.async {
            self.actions[index].executionStatus = success ? .completed : .failed
            self.actions[index].executionNote = note
            self.activeWarning = nil
        }
    }
    
    /// Cancel a pending action
    func cancelPendingAction(_ actionID: UUID) {
        if let timer = pendingExecutions[actionID] {
            timer.invalidate()
            pendingExecutions.removeValue(forKey: actionID)
        }
        
        DispatchQueue.main.async {
            if let index = self.actions.firstIndex(where: { $0.id == actionID }) {
                self.actions[index].executionStatus = .cancelled
                self.actions[index].executionNote = "Cancelled by user"
            }
            self.activeWarning = nil
        }
    }
    
    // MARK: - System Actions
    
    private func performShutdown() -> Bool {
        SystemPowerActions.shutdown()
    }

    private func performSleep() -> Bool {
        SystemPowerActions.sleep()
    }

    private func performHibernate() -> Bool {
        SystemPowerActions.sleep()
    }

    private func performCloseApp() -> Bool {
        #if DEBUG
        print("👋 [DEBUG] Would close application")
        return true
        #else
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
        return true
        #endif
    }
    
    private func performRunScript(_ action: AutoShutdownAction) -> Bool {
        #if DEBUG
        print("📜 [DEBUG] Would run script: \(action.scriptPath ?? action.scriptCommand ?? "unknown")")
        return true
        #else
        if let scriptPath = action.scriptPath {
            return executeScript(path: scriptPath, arguments: action.scriptArguments ?? [])
        } else if let command = action.scriptCommand {
            return executeCommand(command, arguments: action.scriptArguments ?? [])
        }
        return false
        #endif
    }
    
    /// Execute AppleScript
    private func executeAppleScript(_ script: String) -> Bool {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ AppleScript error: \(error)")
            return false
        }
        return true
    }
    
    /// Execute a shell script file
    private func executeScript(path: String, arguments: [String]) -> Bool {
        let task = Process()
        task.launchPath = path
        task.arguments = arguments
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("❌ Script execution failed: \(error)")
            return false
        }
    }
    
    /// Execute a shell command
    private func executeCommand(_ command: String, arguments: [String]) -> Bool {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command + " " + arguments.joined(separator: " ")]
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("❌ Command execution failed: \(error)")
            return false
        }
    }
    
    // MARK: - Statistics
    
    /// Get execution statistics
    func getStatistics() -> ActionStatistics {
        let total = actions.count
        let enabled = actions.filter { $0.isEnabled }.count
        let executed = actions.filter { $0.executionStatus == .completed }.count
        let failed = actions.filter { $0.executionStatus == .failed }.count
        let pending = actions.filter { $0.executionStatus == .pending }.count
        
        return ActionStatistics(
            totalActions: total,
            enabledActions: enabled,
            executedActions: executed,
            failedActions: failed,
            pendingActions: pending
        )
    }
    
    struct ActionStatistics {
        let totalActions: Int
        let enabledActions: Int
        let executedActions: Int
        let failedActions: Int
        let pendingActions: Int
    }
}

// MARK: - Integration with DownloadManager

extension DownloadManager {
    /// Notify auto-shutdown manager when a task completes
    func notifyTaskCompletion(_ task: DownloadTask) {
        AutoShutdownManager.shared.checkTaskCompletion(task.id, category: task.category)
    }
}
