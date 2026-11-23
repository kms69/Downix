//
//  SmartOrganization.swift
//  Download Manager for Mac - Feature #8: Smart Organization
//
//  Created on February 15, 2026
//

import Foundation

// MARK: - Organization Rule

/// Rule for automatic file organization
struct OrganizationRule: Identifiable, Codable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var priority: Int
    var conditions: [RuleCondition]
    var actions: [RuleAction]
    var createdAt: Date
    var lastMatchedAt: Date?
    var matchCount: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        priority: Int = 0,
        conditions: [RuleCondition] = [],
        actions: [RuleAction] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.priority = priority
        self.conditions = conditions
        self.actions = actions
        self.createdAt = Date()
        self.matchCount = 0
    }
    
    /// Check if this rule matches a download task
    func matches(_ task: DownloadTask) -> Bool {
        guard isEnabled else { return false }
        
        // All conditions must match (AND logic)
        return conditions.allSatisfy { $0.matches(task) }
    }
    
    mutating func recordMatch() {
        lastMatchedAt = Date()
        matchCount += 1
    }
}

// MARK: - Rule Condition

/// Condition for organization rules
enum RuleCondition: Codable, Equatable {
    case fileType(FileTypePattern)
    case fileExtension(String)
    case sourceURL(URLPattern)
    case fileSize(FileSizeRange)
    case filename(StringPattern)
    case dateDownloaded(DateRange)
    case mimeType(String)
    
    enum FileTypePattern: String, Codable {
        case video = "Video"
        case audio = "Audio"
        case image = "Image"
        case document = "Document"
        case archive = "Archive"
        case executable = "Executable"
        case any = "Any"
        
        func matches(_ type: String?) -> Bool {
            guard let type = type else { return false }
            
            let videoExtensions = ["mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v"]
            let audioExtensions = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "wma"]
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "heic"]
            let documentExtensions = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt"]
            let archiveExtensions = ["zip", "rar", "7z", "tar", "gz", "bz2", "dmg"]
            let executableExtensions = ["app", "exe", "dmg", "pkg"]
            
            let ext = type.lowercased()
            
            switch self {
            case .video: return videoExtensions.contains(ext)
            case .audio: return audioExtensions.contains(ext)
            case .image: return imageExtensions.contains(ext)
            case .document: return documentExtensions.contains(ext)
            case .archive: return archiveExtensions.contains(ext)
            case .executable: return executableExtensions.contains(ext)
            case .any: return true
            }
        }
    }
    
    struct URLPattern: Codable, Equatable {
        let pattern: String
        let matchType: MatchType
        
        enum MatchType: String, Codable {
            case contains = "Contains"
            case startsWith = "Starts With"
            case endsWith = "Ends With"
            case regex = "Regex"
            case exact = "Exact Match"
        }
        
        func matches(_ url: URL) -> Bool {
            let urlString = url.absoluteString
            
            switch matchType {
            case .contains:
                return urlString.localizedCaseInsensitiveContains(pattern)
            case .startsWith:
                return urlString.lowercased().hasPrefix(pattern.lowercased())
            case .endsWith:
                return urlString.lowercased().hasSuffix(pattern.lowercased())
            case .regex:
                return urlString.range(of: pattern, options: .regularExpression) != nil
            case .exact:
                return urlString.lowercased() == pattern.lowercased()
            }
        }
    }
    
    struct FileSizeRange: Codable, Equatable {
        let min: Int64?     // bytes
        let max: Int64?     // bytes
        
        func matches(_ size: Int64) -> Bool {
            if let min = min, size < min { return false }
            if let max = max, size > max { return false }
            return true
        }
        
        var description: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            
            if let min = min, let max = max {
                return "\(formatter.string(fromByteCount: min)) - \(formatter.string(fromByteCount: max))"
            } else if let min = min {
                return "≥ \(formatter.string(fromByteCount: min))"
            } else if let max = max {
                return "≤ \(formatter.string(fromByteCount: max))"
            }
            return "Any size"
        }
    }
    
    struct StringPattern: Codable, Equatable {
        let pattern: String
        let matchType: URLPattern.MatchType
        
        func matches(_ string: String) -> Bool {
            switch matchType {
            case .contains:
                return string.localizedCaseInsensitiveContains(pattern)
            case .startsWith:
                return string.lowercased().hasPrefix(pattern.lowercased())
            case .endsWith:
                return string.lowercased().hasSuffix(pattern.lowercased())
            case .regex:
                return string.range(of: pattern, options: .regularExpression) != nil
            case .exact:
                return string.lowercased() == pattern.lowercased()
            }
        }
    }
    
    struct DateRange: Codable, Equatable {
        let start: Date?
        let end: Date?
        
        func matches(_ date: Date) -> Bool {
            if let start = start, date < start { return false }
            if let end = end, date > end { return false }
            return true
        }
    }
    
    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .fileType(let pattern):
            return pattern.matches(task.fileType)
        case .fileExtension(let ext):
            return task.filename.lowercased().hasSuffix(".\(ext.lowercased())")
        case .sourceURL(let pattern):
            return pattern.matches(task.url)
        case .fileSize(let range):
            return range.matches(task.totalBytes)
        case .filename(let pattern):
            return pattern.matches(task.filename)
        case .dateDownloaded(let range):
            return range.matches(task.createdAt)
        case .mimeType(let mime):
            return task.mimeType?.lowercased() == mime.lowercased()
        }
    }
    
    var description: String {
        switch self {
        case .fileType(let pattern):
            return "File type is \(pattern.rawValue)"
        case .fileExtension(let ext):
            return "Extension is .\(ext)"
        case .sourceURL(let pattern):
            return "URL \(pattern.matchType.rawValue.lowercased()) '\(pattern.pattern)'"
        case .fileSize(let range):
            return "File size \(range.description)"
        case .filename(let pattern):
            return "Filename \(pattern.matchType.rawValue.lowercased()) '\(pattern.pattern)'"
        case .dateDownloaded:
            return "Downloaded within date range"
        case .mimeType(let mime):
            return "MIME type is \(mime)"
        }
    }
}

// MARK: - Rule Action

/// Action to perform when rule matches
enum RuleAction: Codable, Equatable {
    case moveToFolder(URL)
    case addTag(String)
    case setCategory(DownloadCategory)
    case setPriority(DownloadPriority)
    case renameFile(String)  // Pattern with {name}, {ext}, {date}, {index}
    
    var description: String {
        switch self {
        case .moveToFolder(let url):
            return "Move to \(url.lastPathComponent)"
        case .addTag(let tag):
            return "Add tag '\(tag)'"
        case .setCategory(let category):
            return "Set category to \(category.rawValue)"
        case .setPriority(let priority):
            return "Set priority to \(priority.rawValue)"
        case .renameFile(let pattern):
            return "Rename to '\(pattern)'"
        }
    }
}

// MARK: - Download Tag

/// Tag for organizing downloads
struct DownloadTag: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: TagColor
    var createdAt: Date
    var usageCount: Int
    
    enum TagColor: String, Codable, CaseIterable {
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case gray = "Gray"
    }
    
    init(id: UUID = UUID(), name: String, color: TagColor = .blue) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
        self.usageCount = 0
    }
    
    mutating func incrementUsage() {
        usageCount += 1
    }
}

// MARK: - Search Filter

/// Filter for searching downloads
struct SearchFilter: Codable {
    var text: String?
    var tags: [UUID]
    var categories: [DownloadCategory]
    var fileTypes: [RuleCondition.FileTypePattern]
    var sizeRange: RuleCondition.FileSizeRange?
    var dateRange: RuleCondition.DateRange?
    var states: [DownloadState]
    var sourceURLPattern: String?
    
    init() {
        self.tags = []
        self.categories = []
        self.fileTypes = []
        self.states = []
    }
    
    func matches(_ task: DownloadTask, tags: [UUID]) -> Bool {
        // Text search
        if let text = text, !text.isEmpty {
            let searchable = [
                task.filename,
                task.url.absoluteString,
                task.mimeType ?? "",
                task.fileType ?? ""
            ].joined(separator: " ").lowercased()
            
            if !searchable.contains(text.lowercased()) {
                return false
            }
        }
        
        // Tags filter
        if !self.tags.isEmpty {
            let hasMatchingTag = self.tags.contains(where: { tags.contains($0) })
            if !hasMatchingTag {
                return false
            }
        }
        
        // Categories filter
        if !categories.isEmpty, let category = getCategoryForTask(task) {
            if !categories.contains(category) {
                return false
            }
        }
        
        // File types filter
        if !fileTypes.isEmpty {
            let hasMatchingType = fileTypes.contains(where: { $0.matches(task.fileType) })
            if !hasMatchingType {
                return false
            }
        }
        
        // Size range filter
        if let sizeRange = sizeRange {
            if !sizeRange.matches(task.totalBytes) {
                return false
            }
        }
        
        // Date range filter
        if let dateRange = dateRange {
            if !dateRange.matches(task.createdAt) {
                return false
            }
        }
        
        // States filter
        if !states.isEmpty {
            if !states.contains(task.state) {
                return false
            }
        }
        
        // Source URL pattern
        if let pattern = sourceURLPattern, !pattern.isEmpty {
            if !task.url.absoluteString.localizedCaseInsensitiveContains(pattern) {
                return false
            }
        }
        
        return true
    }
    
    private func getCategoryForTask(_ task: DownloadTask) -> DownloadCategory? {
        // This would normally check the task's actual category
        // For now, infer from file type
        guard let fileType = task.fileType else { return nil }
        
        if RuleCondition.FileTypePattern.video.matches(fileType) { return .videos }
        if RuleCondition.FileTypePattern.audio.matches(fileType) { return .audio }
        if RuleCondition.FileTypePattern.image.matches(fileType) { return .images }
        if RuleCondition.FileTypePattern.document.matches(fileType) { return .documents }
        if RuleCondition.FileTypePattern.archive.matches(fileType) { return .archives }
        
        return .other
    }
    
    var isActive: Bool {
        text != nil && !text!.isEmpty ||
        !tags.isEmpty ||
        !categories.isEmpty ||
        !fileTypes.isEmpty ||
        sizeRange != nil ||
        dateRange != nil ||
        !states.isEmpty ||
        (sourceURLPattern != nil && !sourceURLPattern!.isEmpty)
    }
}

// MARK: - Duplicate Detection

/// Result of duplicate detection
struct DuplicateDetectionResult: Identifiable {
    let id = UUID()
    let original: DownloadTask
    let duplicates: [DuplicateMatch]
    
    struct DuplicateMatch {
        let task: DownloadTask
        let matchType: MatchType
        let confidence: Double  // 0.0 - 1.0
        
        enum MatchType: String {
            case exactURL = "Exact URL"
            case exactFilename = "Exact Filename"
            case similarFilename = "Similar Filename"
            case exactSize = "Exact Size"
            case exactChecksum = "Exact Checksum"
        }
    }
    
    var totalDuplicates: Int {
        duplicates.count
    }
    
    var totalWastedSpace: Int64 {
        duplicates.reduce(0) { $0 + $1.task.totalBytes }
    }
}

// MARK: - Organization Statistics

/// Statistics for smart organization
struct OrganizationStatistics: Codable {
    var totalRulesCreated: Int
    var activeRules: Int
    var totalMatches: Int
    var filesOrganized: Int
    var tagsCreated: Int
    var duplicatesFound: Int
    var spaceReclaimed: Int64
    var lastOrganizationDate: Date?
    
    init() {
        totalRulesCreated = 0
        activeRules = 0
        totalMatches = 0
        filesOrganized = 0
        tagsCreated = 0
        duplicatesFound = 0
        spaceReclaimed = 0
    }
    
    mutating func recordRuleMatch() {
        totalMatches += 1
        filesOrganized += 1
        lastOrganizationDate = Date()
    }
    
    mutating func recordDuplicate(size: Int64) {
        duplicatesFound += 1
        spaceReclaimed += size
    }
    
    var formattedSpaceReclaimed: String {
        ByteCountFormatter.string(fromByteCount: spaceReclaimed, countStyle: .file)
    }
}

// MARK: - Smart Suggestions

/// AI-powered organization suggestions
struct OrganizationSuggestion: Identifiable {
    let id = UUID()
    let type: SuggestionType
    let description: String
    let confidence: Double  // 0.0 - 1.0
    let affectedTasks: [DownloadTask]
    let suggestedRule: OrganizationRule?
    
    enum SuggestionType {
        case createRule
        case mergeDuplicates
        case addTag
        case reorganizeFolder
        case cleanupOldFiles
    }
}
