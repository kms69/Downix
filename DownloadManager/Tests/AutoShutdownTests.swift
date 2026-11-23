//
//  AutoShutdownTests.swift
//  Download Manager for Mac - Feature #4: Auto Shutdown Tests
//
//  Created on February 15, 2026
//

import XCTest
@testable import DownloadManager

class AutoShutdownTests: XCTestCase {
    
    var manager: AutoShutdownManager!
    
    override func setUp() {
        super.setUp()
        manager = AutoShutdownManager.shared
        manager.actions.removeAll()
        manager.resetMonitoring()
    }
    
    override func tearDown() {
        manager.stopMonitoring()
        manager.actions.removeAll()
        super.tearDown()
    }
    
    // MARK: - Model Tests
    
    func testActionCreation() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads
        )
        
        XCTAssertNotNil(action.id)
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.actionType, .shutdown)
        XCTAssertEqual(action.condition, .allDownloads)
        XCTAssertEqual(action.executionStatus, .pending)
    }
    
    func testActionValidation_Valid() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            delayMinutes: 1,
            showWarning: true,
            warningSeconds: 30
        )
        
        let validation = action.validate()
        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.errors.isEmpty)
    }
    
    func testActionValidation_MissingCategoryID() {
        let action = AutoShutdownAction(
            actionType: .sleep,
            condition: .specificCategory,
            categoryID: nil
        )
        
        let validation = action.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains { $0.contains("Category ID") })
    }
    
    func testActionValidation_MissingTaskID() {
        let action = AutoShutdownAction(
            actionType: .closeApp,
            condition: .specificTask,
            taskID: nil
        )
        
        let validation = action.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains { $0.contains("Task ID") })
    }
    
    func testActionValidation_MissingTimeMinutes() {
        let action = AutoShutdownAction(
            actionType: .sleep,
            condition: .timeElapsed,
            timeMinutes: nil
        )
        
        let validation = action.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains { $0.contains("Time in minutes") })
    }
    
    func testActionValidation_InvalidTimeMinutes() {
        let action = AutoShutdownAction(
            actionType: .sleep,
            condition: .timeElapsed,
            timeMinutes: 0
        )
        
        let validation = action.validate()
        XCTAssertFalse(validation.isValid)
    }
    
    func testActionValidation_MissingDataMB() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .dataDownloaded,
            dataMB: nil
        )
        
        let validation = action.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains { $0.contains("Data amount") })
    }
    
    func testActionValidation_MissingScript() {
        let action = AutoShutdownAction(
            actionType: .runScript,
            condition: .allDownloads,
            scriptPath: nil,
            scriptCommand: nil
        )
        
        let validation = action.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains { $0.contains("Script") })
    }
    
    func testActionValidation_NegativeDelay() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            delayMinutes: -5
        )
        
        let validation = action.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains { $0.contains("Delay cannot be negative") })
    }
    
    func testActionValidation_InvalidWarningTime() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            showWarning: true,
            warningSeconds: 0
        )
        
        let validation = action.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains { $0.contains("Warning time") })
    }
    
    func testPresetActions() {
        let shutdownAction = AutoShutdownAction.shutDownWhenAllComplete
        XCTAssertEqual(shutdownAction.actionType, .shutdown)
        XCTAssertEqual(shutdownAction.condition, .allDownloads)
        XCTAssertTrue(shutdownAction.validate().isValid)
        
        let sleepAction = AutoShutdownAction.sleepWhenQueueComplete
        XCTAssertEqual(sleepAction.actionType, .sleep)
        XCTAssertEqual(sleepAction.condition, .currentQueue)
        XCTAssertTrue(sleepAction.validate().isValid)
        
        let closeAction = AutoShutdownAction.closeWhenAllComplete
        XCTAssertEqual(closeAction.actionType, .closeApp)
        XCTAssertEqual(closeAction.condition, .allDownloads)
        XCTAssertTrue(closeAction.validate().isValid)
    }
    
    func testActionDisplayDescription() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            delayMinutes: 5,
            showWarning: true,
            warningSeconds: 30
        )
        
        let description = action.displayDescription
        XCTAssertTrue(description.contains("All Downloads Complete"))
        XCTAssertTrue(description.contains("Shut Down Mac"))
        XCTAssertTrue(description.contains("5 minutes"))
        XCTAssertTrue(description.contains("30s countdown"))
    }
    
    // MARK: - Manager Tests
    
    func testAddAction() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads
        )
        
        let success = manager.addAction(action)
        XCTAssertTrue(success)
        XCTAssertEqual(manager.actions.count, 1)
        XCTAssertEqual(manager.actions[0].id, action.id)
    }
    
    func testAddAction_Invalid() {
        let action = AutoShutdownAction(
            actionType: .runScript,
            condition: .allDownloads,
            scriptPath: nil,
            scriptCommand: nil
        )
        
        let success = manager.addAction(action)
        XCTAssertFalse(success)
        XCTAssertEqual(manager.actions.count, 0)
    }
    
    func testRemoveAction() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads
        )
        
        _ = manager.addAction(action)
        XCTAssertEqual(manager.actions.count, 1)
        
        manager.removeAction(action)
        XCTAssertEqual(manager.actions.count, 0)
    }
    
    func testUpdateAction() {
        var action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            delayMinutes: 1
        )
        
        _ = manager.addAction(action)
        
        action.delayMinutes = 5
        let success = manager.updateAction(action)
        
        XCTAssertTrue(success)
        XCTAssertEqual(manager.actions[0].delayMinutes, 5)
    }
    
    func testSetActionEnabled() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads
        )
        
        _ = manager.addAction(action)
        XCTAssertTrue(manager.actions[0].isEnabled)
        
        manager.setActionEnabled(false, for: action.id)
        XCTAssertFalse(manager.actions[0].isEnabled)
        
        manager.setActionEnabled(true, for: action.id)
        XCTAssertTrue(manager.actions[0].isEnabled)
    }
    
    func testGetEnabledActions() {
        let action1 = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            isEnabled: true
        )
        
        let action2 = AutoShutdownAction(
            actionType: .sleep,
            condition: .currentQueue,
            isEnabled: false
        )
        
        _ = manager.addAction(action1)
        _ = manager.addAction(action2)
        
        let enabledActions = manager.getEnabledActions()
        XCTAssertEqual(enabledActions.count, 1)
        XCTAssertEqual(enabledActions[0].id, action1.id)
    }
    
    func testStatistics() {
        _ = manager.addAction(AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            isEnabled: true
        ))
        
        _ = manager.addAction(AutoShutdownAction(
            actionType: .sleep,
            condition: .currentQueue,
            isEnabled: false
        ))
        
        let stats = manager.getStatistics()
        XCTAssertEqual(stats.totalActions, 2)
        XCTAssertEqual(stats.enabledActions, 1)
        XCTAssertEqual(stats.pendingActions, 2)
        XCTAssertEqual(stats.executedActions, 0)
        XCTAssertEqual(stats.failedActions, 0)
    }
    
    // MARK: - Trigger Condition Tests
    
    func testShouldTrigger_AllDownloads() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads
        )
        
        // Should trigger when all downloads complete
        var shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: true,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertTrue(shouldTrigger)
        
        // Should not trigger when downloads incomplete
        shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertFalse(shouldTrigger)
    }
    
    func testShouldTrigger_CurrentQueue() {
        let action = AutoShutdownAction(
            actionType: .sleep,
            condition: .currentQueue
        )
        
        var shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: true,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertTrue(shouldTrigger)
        
        shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertFalse(shouldTrigger)
    }
    
    func testShouldTrigger_SpecificCategory() {
        let action = AutoShutdownAction(
            actionType: .closeApp,
            condition: .specificCategory,
            categoryID: "Videos"
        )
        
        var shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: "Videos",
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertTrue(shouldTrigger)
        
        shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: "Documents",
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertFalse(shouldTrigger)
    }
    
    func testShouldTrigger_SpecificTask() {
        let taskID = UUID()
        let action = AutoShutdownAction(
            actionType: .runScript,
            condition: .specificTask,
            taskID: taskID,
            scriptPath: "/tmp/test.sh"
        )
        
        var shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: taskID,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertTrue(shouldTrigger)
        
        shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: UUID(),
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertFalse(shouldTrigger)
    }
    
    func testShouldTrigger_TimeElapsed() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .timeElapsed,
            timeMinutes: 30
        )
        
        var shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 35,
            downloadedMB: 0
        )
        XCTAssertTrue(shouldTrigger)
        
        shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 25,
            downloadedMB: 0
        )
        XCTAssertFalse(shouldTrigger)
    }
    
    func testShouldTrigger_DataDownloaded() {
        let action = AutoShutdownAction(
            actionType: .sleep,
            condition: .dataDownloaded,
            dataMB: 100
        )
        
        var shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 150
        )
        XCTAssertTrue(shouldTrigger)
        
        shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: false,
            queueDownloadsComplete: false,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 50
        )
        XCTAssertFalse(shouldTrigger)
    }
    
    func testShouldNotTrigger_WhenDisabled() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            isEnabled: false
        )
        
        let shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: true,
            queueDownloadsComplete: true,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertFalse(shouldTrigger)
    }
    
    func testShouldNotTrigger_WhenAlreadyExecuted() {
        var action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads
        )
        action.executionStatus = .completed
        
        let shouldTrigger = action.shouldTrigger(
            allDownloadsComplete: true,
            queueDownloadsComplete: true,
            categoryComplete: nil,
            taskComplete: nil,
            elapsedMinutes: 0,
            downloadedMB: 0
        )
        XCTAssertFalse(shouldTrigger)
    }
    
    // MARK: - Action Type Tests
    
    func testActionTypes() {
        XCTAssertEqual(ShutdownActionType.allCases.count, 6)
        
        XCTAssertFalse(ShutdownActionType.none.requiresAdminPrivileges)
        XCTAssertTrue(ShutdownActionType.shutdown.requiresAdminPrivileges)
        XCTAssertFalse(ShutdownActionType.sleep.requiresAdminPrivileges)
        XCTAssertTrue(ShutdownActionType.hibernate.requiresAdminPrivileges)
        XCTAssertFalse(ShutdownActionType.closeApp.requiresAdminPrivileges)
        XCTAssertFalse(ShutdownActionType.runScript.requiresAdminPrivileges)
    }
    
    func testShutdownConditions() {
        XCTAssertEqual(ShutdownCondition.allCases.count, 6)
        
        for condition in ShutdownCondition.allCases {
            XCTAssertFalse(condition.icon.isEmpty)
            XCTAssertFalse(condition.rawValue.isEmpty)
        }
    }
    
    // MARK: - Codable Tests
    
    func testActionCodable() throws {
        let original = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads,
            delayMinutes: 5,
            showWarning: true,
            warningSeconds: 60
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AutoShutdownAction.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.actionType, original.actionType)
        XCTAssertEqual(decoded.condition, original.condition)
        XCTAssertEqual(decoded.delayMinutes, original.delayMinutes)
        XCTAssertEqual(decoded.showWarning, original.showWarning)
        XCTAssertEqual(decoded.warningSeconds, original.warningSeconds)
    }
    
    // MARK: - Edge Cases
    
    func testMultipleActions() {
        for i in 0..<10 {
            let action = AutoShutdownAction(
                actionType: .shutdown,
                condition: .allDownloads,
                delayMinutes: i
            )
            _ = manager.addAction(action)
        }
        
        XCTAssertEqual(manager.actions.count, 10)
        
        let stats = manager.getStatistics()
        XCTAssertEqual(stats.totalActions, 10)
        XCTAssertEqual(stats.enabledActions, 10)
    }
    
    func testActionEquality() {
        let id = UUID()
        let action1 = AutoShutdownAction(
            id: id,
            actionType: .shutdown,
            condition: .allDownloads
        )
        
        let action2 = AutoShutdownAction(
            id: id,
            actionType: .shutdown,
            condition: .allDownloads
        )
        
        XCTAssertEqual(action1, action2)
    }
    
    func testResetMonitoring() {
        var action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads
        )
        action.executionStatus = .completed
        action.executedAt = Date()
        action.executionNote = "Test"
        
        _ = manager.addAction(action)
        
        manager.resetMonitoring()
        
        XCTAssertEqual(manager.actions[0].executionStatus, .pending)
        XCTAssertNil(manager.actions[0].executedAt)
        XCTAssertNil(manager.actions[0].executionNote)
    }
    
    func testCancelPendingAction() {
        let action = AutoShutdownAction(
            actionType: .shutdown,
            condition: .allDownloads
        )
        
        _ = manager.addAction(action)
        manager.cancelPendingAction(action.id)
        
        // Action should be marked as cancelled
        let cancelledAction = manager.actions.first { $0.id == action.id }
        XCTAssertNotNil(cancelledAction)
        XCTAssertEqual(cancelledAction?.executionStatus, .cancelled)
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_AddMultipleActions() {
        measure {
            for _ in 0..<100 {
                let action = AutoShutdownAction(
                    actionType: .shutdown,
                    condition: .allDownloads
                )
                _ = manager.addAction(action)
            }
            manager.actions.removeAll()
        }
    }
    
    func testPerformance_TriggerCheck() {
        // Add 50 actions
        for _ in 0..<50 {
            let action = AutoShutdownAction(
                actionType: .shutdown,
                condition: .allDownloads
            )
            _ = manager.addAction(action)
        }
        
        measure {
            for action in manager.actions {
                _ = action.shouldTrigger(
                    allDownloadsComplete: true,
                    queueDownloadsComplete: true,
                    categoryComplete: nil,
                    taskComplete: nil,
                    elapsedMinutes: 100,
                    downloadedMB: 1000
                )
            }
        }
    }
}
