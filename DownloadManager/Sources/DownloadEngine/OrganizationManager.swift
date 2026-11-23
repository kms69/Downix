//
//  OrganizationManager.swift
//  Download Manager for Mac - Feature #8: Smart Organization
//
//  Created on February 15, 2026
//

import Foundation
import Combine

/// Manages smart organization of downloads
@MainActor
class OrganizationManager: ObservableObject {
    
    static let shared = OrganizationManager()
    
    @Published var rules: [OrganizationRule] = []
    @Published var tags: [DownloadTag] = []
    @Published var statistics: OrganizationStatistics = OrganizationStatistics()
    @Published var taskTags: [UUID: [UUID]] = [:]  // TaskID -> TagIDs
    
    private var cancellables = Set<AnyCancellable>()
    private let downloadManager = DownloadManager.shared
    
    private init() {
        loadRules()
        loadTags()
        loadStatistics()
        loadTaskTags()
        createDefaultRules()
    }
    
    // MARK: - Rule Management
    
    /// Add a new organization rule
    func addRule(_ rule: OrganizationRule) {
        rules.append(rule)
        statistics.totalRulesCreated += 1
        if rule.isEnabled {
            statistics.activeRules += 1
        }
        saveRules()
        saveStatistics()
    }
    
    /// Update an existing rule
    func updateRule(_ rule: OrganizationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            let wasEnabled = rules[index].isEnabled
            rules[index] = rule
            
            if wasEnabled != rule.isEnabled {
                statistics.activeRules += rule.isEnabled ? 1 : -1
            }
            
            saveRules()
            saveStatistics()
        }
    }
    
    /// Delete a rule
    func deleteRule(_ rule: OrganizationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            if rules[index].isEnabled {
                statistics.activeRules -= 1
            }
            rules.remove(at: index)
            saveRules()
            saveStatistics()
        }
    }
    
    /// Process a task through all rules
    func processTask(_ task: DownloadTask) {
        let sortedRules = rules.sorted { $0.priority > $1.priority }
        
        for var rule in sortedRules where rule.matches(task) {
            // Apply actions
            for action in rule.actions {
                applyAction(action, to: task)
            }
            
            // Record match
            rule.recordMatch()
            updateRule(rule)
            statistics.recordRuleMatch()
            
            // Only apply first matching rule
            break
        }
    }
    
    /// Apply an action to a task
    private func applyAction(_ action: RuleAction, to task: DownloadTask) {
        switch action {
        case .moveToFolder(let url):
            task.destinationPath = url
            
        case .addTag(let tagName):
            if let tag = tags.first(where: { $0.name == tagName }) {
                addTag(tag, to: task)
            } else {
                // Create tag if it doesn't exist
                let newTag = DownloadTag(name: tagName)
                addNewTag(newTag)
                addTag(newTag, to: task)
            }
            
        case .setCategory:
            // Category setting would be handled by QueueManager
            break
            
        case .setPriority:
            // Priority setting would be handled by QueueManager
            break
            
        case .renameFile(let pattern):
            let newName = expandPattern(pattern, for: task)
            task.filename = newName
        }
    }
    
    /// Expand pattern variables in filename
    private func expandPattern(_ pattern: String, for task: DownloadTask) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var result = pattern
        result = result.replacingOccurrences(of: "{name}", with: task.filename)
        result = result.replacingOccurrences(of: "{ext}", with: URL(fileURLWithPath: task.filename).pathExtension)
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: Date()))
        result = result.replacingOccurrences(of: "{url}", with: task.url.host ?? "unknown")
        
        return result
    }
    
    // MARK: - Tag Management
    
    /// Add a new tag
    func addNewTag(_ tag: DownloadTag) {
        tags.append(tag)
        statistics.tagsCreated += 1
        saveTags()
        saveStatistics()
    }
    
    /// Update a tag
    func updateTag(_ tag: DownloadTag) {
        if let index = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[index] = tag
            saveTags()
        }
    }
    
    /// Delete a tag
    func deleteTag(_ tag: DownloadTag) {
        // Remove from all tasks
        for (taskID, tagIDs) in taskTags {
            if tagIDs.contains(tag.id) {
                taskTags[taskID] = tagIDs.filter { $0 != tag.id }
            }
        }
        
        if let index = tags.firstIndex(where: { $0.id == tag.id }) {
            tags.remove(at: index)
            saveTags()
            saveTaskTags()
        }
    }
    
    /// Add a tag to a task
    func addTag(_ tag: DownloadTag, to task: DownloadTask) {
        var currentTags = taskTags[task.id] ?? []
        if !currentTags.contains(tag.id) {
            currentTags.append(tag.id)
            taskTags[task.id] = currentTags
            
            // Increment usage count
            if let index = tags.firstIndex(where: { $0.id == tag.id }) {
                tags[index].incrementUsage()
            }
            
            saveTaskTags()
            saveTags()
        }
    }
    
    /// Remove a tag from a task
    func removeTag(_ tag: DownloadTag, from task: DownloadTask) {
        if var currentTags = taskTags[task.id] {
            currentTags.removeAll { $0 == tag.id }
            taskTags[task.id] = currentTags
            saveTaskTags()
        }
    }
    
    /// Get tags for a task
    func getTags(for task: DownloadTask) -> [DownloadTag] {
        guard let tagIDs = taskTags[task.id] else { return [] }
        return tags.filter { tagIDs.contains($0.id) }
    }
    
    // MARK: - Duplicate Detection
    
    /// Find duplicates across all downloads
    func findDuplicates() -> [DuplicateDetectionResult] {
        var results: [DuplicateDetectionResult] = []
        guard Thread.isMainThread else { return [] }
        let tasks = downloadManager.downloadTasks
        var processed = Set<UUID>()
        
        for task in tasks {
            guard !processed.contains(task.id) else { continue }
            
            var duplicates: [DuplicateDetectionResult.DuplicateMatch] = []
            
            for other in tasks where other.id != task.id && !processed.contains(other.id) {
                if let match = checkDuplicate(task, other) {
                    duplicates.append(match)
                    processed.insert(other.id)
                }
            }
            
            if !duplicates.isEmpty {
                let result = DuplicateDetectionResult(original: task, duplicates: duplicates)
                results.append(result)
                processed.insert(task.id)
                
                // Update statistics
                statistics.recordDuplicate(size: result.totalWastedSpace)
            }
        }
        
        saveStatistics()
        return results
    }
    
    /// Check if two tasks are duplicates
    private func checkDuplicate(_ task1: DownloadTask, _ task2: DownloadTask) -> DuplicateDetectionResult.DuplicateMatch? {
        // Exact URL match
        if task1.url == task2.url {
            return DuplicateDetectionResult.DuplicateMatch(
                task: task2,
                matchType: .exactURL,
                confidence: 1.0
            )
        }
        
        // Exact filename match
        if task1.filename == task2.filename {
            return DuplicateDetectionResult.DuplicateMatch(
                task: task2,
                matchType: .exactFilename,
                confidence: 0.95
            )
        }
        
        // Exact size match (same size and similar name)
        if task1.totalBytes == task2.totalBytes && task1.totalBytes > 0 {
            let similarity = calculateSimilarity(task1.filename, task2.filename)
            if similarity > 0.8 {
                return DuplicateDetectionResult.DuplicateMatch(
                    task: task2,
                    matchType: .exactSize,
                    confidence: similarity * 0.9
                )
            }
        }
        
        // Similar filename
        let similarity = calculateSimilarity(task1.filename, task2.filename)
        if similarity > 0.9 {
            return DuplicateDetectionResult.DuplicateMatch(
                task: task2,
                matchType: .similarFilename,
                confidence: similarity * 0.85
            )
        }
        
        return nil
    }
    
    /// Calculate similarity between two strings (Levenshtein distance based)
    private func calculateSimilarity(_ str1: String, _ str2: String) -> Double {
        let longer = str1.count >= str2.count ? str1 : str2
        
        if longer.isEmpty { return 1.0 }
        
        let longerLength = Double(longer.count)
        let distance = Double(levenshteinDistance(str1, str2))
        
        return (longerLength - distance) / longerLength
    }
    
    /// Calculate Levenshtein distance
    private func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let a = Array(str1)
        let b = Array(str2)
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count {
            matrix[i][0] = i
        }
        for j in 0...b.count {
            matrix[0][j] = j
        }
        
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }
        
        return matrix[a.count][b.count]
    }
    
    /// Remove duplicate tasks
    func removeDuplicates(_ result: DuplicateDetectionResult, keepOriginal: Bool = true) {
        Task { @MainActor in
            for match in result.duplicates {
                await self.downloadManager.removeDownload(match.task)
            }
            if !keepOriginal {
                await self.downloadManager.removeDownload(result.original)
            }
        }
    }
    
    // MARK: - Search & Filter
    
    /// Search downloads with filter
    func searchDownloads(filter: SearchFilter) -> [DownloadTask] {
        guard Thread.isMainThread else { return [] }
        return downloadManager.downloadTasks.filter { task in
            let tags = taskTags[task.id] ?? []
            return filter.matches(task, tags: tags)
        }
    }
    
    // MARK: - Auto-Categorization
    
    /// Automatically categorize a download based on file type
    func autoCategorize(_ task: DownloadTask) -> DownloadCategory {
        guard let fileType = task.fileType else { return .other }
        
        if RuleCondition.FileTypePattern.video.matches(fileType) { return .videos }
        if RuleCondition.FileTypePattern.audio.matches(fileType) { return .audio }
        if RuleCondition.FileTypePattern.image.matches(fileType) { return .images }
        if RuleCondition.FileTypePattern.document.matches(fileType) { return .documents }
        if RuleCondition.FileTypePattern.archive.matches(fileType) { return .archives }
        
        return .other
    }
    
    /// Get smart suggestions for organization
    func getSuggestions() -> [OrganizationSuggestion] {
        var suggestions: [OrganizationSuggestion] = []
        
        // Suggest rules based on patterns
        guard Thread.isMainThread else { return suggestions }
        let tasks = downloadManager.downloadTasks
        let urlGroups = Dictionary(grouping: tasks) { $0.url.host ?? "unknown" }
        
        for (host, group) in urlGroups where group.count >= 3 {
            let suggestion = OrganizationSuggestion(
                type: .createRule,
                description: "Create a rule for downloads from \(host) (\(group.count) files)",
                confidence: min(Double(group.count) / 10.0, 1.0),
                affectedTasks: group,
                suggestedRule: OrganizationRule(
                    name: "Downloads from \(host)",
                    conditions: [
                        .sourceURL(RuleCondition.URLPattern(
                            pattern: host,
                            matchType: .contains
                        ))
                    ],
                    actions: [
                        .moveToFolder(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent(host))
                    ]
                )
            )
            suggestions.append(suggestion)
        }
        
        // Suggest duplicate cleanup
        let duplicates = findDuplicates()
        if duplicates.count > 0 {
            let totalWasted = duplicates.reduce(0) { $0 + $1.totalWastedSpace }
            let suggestion = OrganizationSuggestion(
                type: .mergeDuplicates,
                description: "Remove \(duplicates.flatMap { $0.duplicates }.count) duplicate files to reclaim \(ByteCountFormatter.string(fromByteCount: totalWasted, countStyle: .file))",
                confidence: 0.95,
                affectedTasks: duplicates.flatMap { [$0.original] + $0.duplicates.map { $0.task } },
                suggestedRule: nil
            )
            suggestions.append(suggestion)
        }
        
        return suggestions.sorted { $0.confidence > $1.confidence }
    }
    
    // MARK: - Default Rules
    
    private func createDefaultRules() {
        guard rules.isEmpty else { return }
        
        // Video files rule
        addRule(OrganizationRule(
            name: "Organize Videos",
            priority: 10,
            conditions: [.fileType(.video)],
            actions: [
                .addTag("Video"),
                .setCategory(.videos)
            ]
        ))
        
        // Audio files rule
        addRule(OrganizationRule(
            name: "Organize Music",
            priority: 9,
            conditions: [.fileType(.audio)],
            actions: [
                .addTag("Music"),
                .setCategory(.audio)
            ]
        ))
        
        // Document files rule
        addRule(OrganizationRule(
            name: "Organize Documents",
            priority: 8,
            conditions: [.fileType(.document)],
            actions: [
                .addTag("Document"),
                .setCategory(.documents)
            ]
        ))
        
        // Image files rule
        addRule(OrganizationRule(
            name: "Organize Images",
            priority: 7,
            conditions: [.fileType(.image)],
            actions: [
                .addTag("Image"),
                .setCategory(.images)
            ]
        ))
        
        // Archive files rule
        addRule(OrganizationRule(
            name: "Organize Archives",
            priority: 6,
            conditions: [.fileType(.archive)],
            actions: [
                .addTag("Archive"),
                .setCategory(.archives)
            ]
        ))
    }
    
    // MARK: - Persistence
    
    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: "OrganizationRules"),
           let loaded = try? JSONDecoder().decode([OrganizationRule].self, from: data) {
            rules = loaded
            statistics.activeRules = rules.filter { $0.isEnabled }.count
        }
    }
    
    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: "OrganizationRules")
        }
    }
    
    private func loadTags() {
        if let data = UserDefaults.standard.data(forKey: "OrganizationTags"),
           let loaded = try? JSONDecoder().decode([DownloadTag].self, from: data) {
            tags = loaded
        }
    }
    
    private func saveTags() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: "OrganizationTags")
        }
    }
    
    private func loadStatistics() {
        if let data = UserDefaults.standard.data(forKey: "OrganizationStatistics"),
           let loaded = try? JSONDecoder().decode(OrganizationStatistics.self, from: data) {
            statistics = loaded
        }
    }
    
    private func saveStatistics() {
        if let data = try? JSONEncoder().encode(statistics) {
            UserDefaults.standard.set(data, forKey: "OrganizationStatistics")
        }
    }
    
    private func loadTaskTags() {
        if let data = UserDefaults.standard.data(forKey: "TaskTags"),
           let loaded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            // Convert String keys to UUIDs
            taskTags = loaded.reduce(into: [:]) { result, pair in
                if let taskID = UUID(uuidString: pair.key) {
                    result[taskID] = pair.value.compactMap { UUID(uuidString: $0) }
                }
            }
        }
    }
    
    private func saveTaskTags() {
        // Convert UUID keys to Strings for persistence
        let stringDict = taskTags.reduce(into: [String: [String]]()) { result, pair in
            result[pair.key.uuidString] = pair.value.map { $0.uuidString }
        }
        
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: "TaskTags")
        }
    }
}
