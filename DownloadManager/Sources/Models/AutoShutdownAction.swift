//
//  AutoShutdownAction.swift
//  Download Manager for Mac - Feature #4: Auto Shutdown
//
//  Created on February 15, 2026
//

import Foundation

/// Types of actions that can be performed after downloads complete
enum ShutdownActionType: String, Codable, CaseIterable {
    case none = "Do Nothing"
    case shutdown = "Shut Down Mac"
    case sleep = "Sleep Mac"
    case hibernate = "Hibernate Mac"
    case closeApp = "Close Application"
    case runScript = "Run Custom Script"
    
    var icon: String {
        switch self {
        case .none: return "circle"
        case .shutdown: return "power"
        case .sleep: return "moon.fill"
        case .hibernate: return "snow"
        case .closeApp: return "xmark.app.fill"
        case .runScript: return "terminal.fill"
        }
    }
    
    var description: String {
        switch self {
        case .none: return "No action will be taken"
        case .shutdown: return "Mac will shut down"
        case .sleep: return "Mac will sleep"
        case .hibernate: return "Mac will hibernate (deep sleep)"
        case .closeApp: return "Download Manager will close"
        case .runScript: return "Custom script/command will execute"
        }
    }
    
    var requiresAdminPrivileges: Bool {
        switch self {
        case .shutdown, .hibernate:
            return true
        case .sleep, .closeApp, .runScript, .none:
            return false
        }
    }

    static var macCases: [ShutdownActionType] {
        [.none, .shutdown, .sleep, .closeApp, .runScript]
    }
}

/// Conditions that trigger the auto-shutdown action
enum ShutdownCondition: String, Codable, CaseIterable {
    case allDownloads = "All Downloads Complete"
    case currentQueue = "Current Queue Complete"
    case specificCategory = "Specific Category Complete"
    case specificTask = "Specific Task Complete"
    case timeElapsed = "Time Elapsed"
    case dataDownloaded = "Data Amount Downloaded"
    
    var icon: String {
        switch self {
        case .allDownloads: return "checkmark.circle.fill"
        case .currentQueue: return "list.bullet.circle.fill"
        case .specificCategory: return "folder.fill"
        case .specificTask: return "doc.fill"
        case .timeElapsed: return "clock.fill"
        case .dataDownloaded: return "arrow.down.circle.fill"
        }
    }
}

/// A scheduled auto-shutdown action
struct AutoShutdownAction: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var isEnabled: Bool
    var actionType: ShutdownActionType
    var condition: ShutdownCondition
    var delayMinutes: Int // Delay before executing action (0 = immediate)
    var showWarning: Bool // Show warning dialog before executing
    var warningSeconds: Int // Countdown time for warning (default: 30)
    
    // Condition-specific parameters
    var categoryID: String? // For specificCategory condition
    var taskID: UUID? // For specificTask condition
    var timeMinutes: Int? // For timeElapsed condition
    var dataMB: Int64? // For dataDownloaded condition (in MB)
    
    // Script/command for runScript action
    var scriptPath: String?
    var scriptCommand: String?
    var scriptArguments: [String]?
    
    // Metadata
    var createdAt: Date
    var lastModified: Date
    var executedAt: Date?
    var executionStatus: ExecutionStatus
    var executionNote: String?
    
    enum ExecutionStatus: String, Codable {
        case pending = "Pending"
        case triggered = "Triggered"
        case executing = "Executing"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }
    
    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        actionType: ShutdownActionType = .none,
        condition: ShutdownCondition = .allDownloads,
        delayMinutes: Int = 0,
        showWarning: Bool = true,
        warningSeconds: Int = 30,
        categoryID: String? = nil,
        taskID: UUID? = nil,
        timeMinutes: Int? = nil,
        dataMB: Int64? = nil,
        scriptPath: String? = nil,
        scriptCommand: String? = nil,
        scriptArguments: [String]? = nil,
        createdAt: Date = Date(),
        lastModified: Date = Date(),
        executedAt: Date? = nil,
        executionStatus: ExecutionStatus = .pending,
        executionNote: String? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.actionType = actionType
        self.condition = condition
        self.delayMinutes = delayMinutes
        self.showWarning = showWarning
        self.warningSeconds = warningSeconds
        self.categoryID = categoryID
        self.taskID = taskID
        self.timeMinutes = timeMinutes
        self.dataMB = dataMB
        self.scriptPath = scriptPath
        self.scriptCommand = scriptCommand
        self.scriptArguments = scriptArguments
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.executedAt = executedAt
        self.executionStatus = executionStatus
        self.executionNote = executionNote
    }
    
    /// Check if this action is ready to be triggered based on its condition
    func shouldTrigger(
        allDownloadsComplete: Bool,
        queueDownloadsComplete: Bool,
        categoryComplete: String?,
        taskComplete: UUID?,
        elapsedMinutes: Int,
        downloadedMB: Int64
    ) -> Bool {
        guard isEnabled && executionStatus == .pending else { return false }
        
        switch condition {
        case .allDownloads:
            return allDownloadsComplete
        case .currentQueue:
            return queueDownloadsComplete
        case .specificCategory:
            guard let catID = categoryID else { return false }
            return categoryComplete == catID
        case .specificTask:
            guard let tID = taskID else { return false }
            return taskComplete == tID
        case .timeElapsed:
            guard let requiredMinutes = timeMinutes else { return false }
            return elapsedMinutes >= requiredMinutes
        case .dataDownloaded:
            guard let requiredMB = dataMB else { return false }
            return downloadedMB >= requiredMB
        }
    }
    
    /// Get a human-readable description of this action
    var displayDescription: String {
        var parts: [String] = []
        
        // Condition
        parts.append("When: \(condition.rawValue)")
        
        // Condition details
        switch condition {
        case .specificCategory:
            if let catID = categoryID {
                parts.append("  Category: \(catID)")
            }
        case .specificTask:
            if let tID = taskID {
                parts.append("  Task: \(tID.uuidString.prefix(8))...")
            }
        case .timeElapsed:
            if let minutes = timeMinutes {
                parts.append("  Duration: \(minutes) minutes")
            }
        case .dataDownloaded:
            if let mb = dataMB {
                parts.append("  Amount: \(mb) MB")
            }
        default:
            break
        }
        
        // Delay
        if delayMinutes > 0 {
            parts.append("Delay: \(delayMinutes) minutes")
        }
        
        // Action
        parts.append("Action: \(actionType.rawValue)")
        
        // Warning
        if showWarning && actionType != .none {
            parts.append("Warning: \(warningSeconds)s countdown")
        }
        
        return parts.joined(separator: " | ")
    }
    
    /// Validate the action configuration
    func validate() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Check condition-specific parameters
        switch condition {
        case .specificCategory:
            if categoryID == nil || categoryID?.isEmpty == true {
                errors.append("Category ID required for 'Specific Category' condition")
            }
        case .specificTask:
            if taskID == nil {
                errors.append("Task ID required for 'Specific Task' condition")
            }
        case .timeElapsed:
            if timeMinutes == nil || timeMinutes! <= 0 {
                errors.append("Time in minutes required for 'Time Elapsed' condition")
            }
        case .dataDownloaded:
            if dataMB == nil || dataMB! <= 0 {
                errors.append("Data amount (MB) required for 'Data Downloaded' condition")
            }
        default:
            break
        }
        
        // Check action-specific parameters
        if actionType == .runScript {
            if (scriptPath == nil || scriptPath?.isEmpty == true) &&
               (scriptCommand == nil || scriptCommand?.isEmpty == true) {
                errors.append("Script path or command required for 'Run Script' action")
            }
        }
        
        // Check delay
        if delayMinutes < 0 {
            errors.append("Delay cannot be negative")
        }
        
        // Check warning
        if showWarning && warningSeconds <= 0 {
            errors.append("Warning time must be positive when warnings are enabled")
        }
        
        return (errors.isEmpty, errors)
    }
}

// MARK: - Preset Actions

extension AutoShutdownAction {
    /// Shut down Mac when all downloads complete
    static var shutDownWhenAllComplete: AutoShutdownAction {
        AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            delayMinutes: 1,
            showWarning: true,
            warningSeconds: 60
        )
    }
    
    /// Sleep Mac when current queue completes
    static var sleepWhenQueueComplete: AutoShutdownAction {
        AutoShutdownAction(
            actionType: .sleep,
            condition: .currentQueue,
            delayMinutes: 0,
            showWarning: true,
            warningSeconds: 30
        )
    }
    
    /// Close app when all downloads complete
    static var closeWhenAllComplete: AutoShutdownAction {
        AutoShutdownAction(
            actionType: .closeApp,
            condition: .allDownloads,
            delayMinutes: 0,
            showWarning: false
        )
    }
    
    /// Run custom script when specific task completes
    static func runScriptWhenTaskComplete(taskID: UUID, scriptPath: String) -> AutoShutdownAction {
        AutoShutdownAction(
            actionType: .runScript,
            condition: .specificTask,
            delayMinutes: 0,
            showWarning: false,
            taskID: taskID,
            scriptPath: scriptPath
        )
    }
}
