//
//  ScheduledSelection.swift
//  Download Manager for Mac
//
//  What the sidebar's "Scheduled" view shows: every download that belongs to a
//  queue that is running or waiting for its start time, plus individually
//  scheduled downloads. (It used to be hard-wired to an empty list.)
//

import Foundation

@MainActor
extension QueueRunController {
    func scheduledTasks() -> [DownloadTask] {
        let all = DownloadManager.shared.downloadTasks
        var ids = Set<UUID>()
        for queue in SchedulerQueueManager.shared.queues where isRunning(queue) || isWaitingForStart(queue) {
            ids.formUnion(queue.taskIDs)
        }
        for task in DownloadScheduler.shared.scheduledTasks { ids.insert(task.id) }
        for task in all where task.isHeldForSchedule { ids.insert(task.id) }
        return all.filter { ids.contains($0.id) }
    }
}
