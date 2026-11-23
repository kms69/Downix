import Foundation

// MARK: - Batch Import Source

/// Source for batch URL import
public enum BatchImportSource: String, Codable, CaseIterable {
    case clipboard
    case textFile
    case manualEntry
    case urlList
    
    var icon: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .textFile: return "doc.text"
        case .manualEntry: return "keyboard"
        case .urlList: return "list.bullet"
        }
    }
    
    var displayName: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .textFile: return "Text File"
        case .manualEntry: return "Manual Entry"
        case .urlList: return "URL List"
        }
    }
}

// MARK: - Batch Category

/// Categories for organizing batch downloads
public enum BatchCategory: String, Codable, CaseIterable {
    case video
    case audio
    case document
    case archive
    case image
    case software
    case ebook
    case torrent
    case other
    
    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .image: return "photo"
        case .software: return "app"
        case .ebook: return "book"
        case .torrent: return "arrow.down.circle"
        case .other: return "questionmark.circle"
        }
    }
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var defaultSubdirectory: String {
        switch self {
        case .video: return "Videos"
        case .audio: return "Music"
        case .document: return "Documents"
        case .archive: return "Archives"
        case .image: return "Images"
        case .software: return "Software"
        case .ebook: return "Books"
        case .torrent: return "Torrents"
        case .other: return "Others"
        }
    }
}

// MARK: - URL Pattern

/// Pattern for matching and filtering URLs
public struct URLPattern: Codable, Identifiable {
    public let id: UUID
    public var pattern: String
    public var isRegex: Bool
    public var isEnabled: Bool
    public var description: String?
    
    public init(
        id: UUID = UUID(),
        pattern: String,
        isRegex: Bool = false,
        isEnabled: Bool = true,
        description: String? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.isRegex = isRegex
        self.isEnabled = isEnabled
        self.description = description
    }
    
    /// Check if URL matches this pattern
    public func matches(_ url: String) -> Bool {
        guard isEnabled else { return false }
        
        if isRegex {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(url.startIndex..., in: url)
            return regex.firstMatch(in: url, options: [], range: range) != nil
        } else {
            return url.lowercased().contains(pattern.lowercased())
        }
    }
    
    /// Common patterns
    public static var videoPattern: URLPattern {
        URLPattern(
            pattern: "\\.(mp4|avi|mkv|mov|wmv|flv|webm)$",
            isRegex: true,
            description: "Video files"
        )
    }
    
    public static var audioPattern: URLPattern {
        URLPattern(
            pattern: "\\.(mp3|m4a|wav|aac|flac|ogg)$",
            isRegex: true,
            description: "Audio files"
        )
    }
    
    public static var imagePattern: URLPattern {
        URLPattern(
            pattern: "\\.(jpg|jpeg|png|gif|bmp|webp)$",
            isRegex: true,
            description: "Image files"
        )
    }
    
    public static var documentPattern: URLPattern {
        URLPattern(
            pattern: "\\.(pdf|doc|docx|txt|rtf)$",
            isRegex: true,
            description: "Document files"
        )
    }
}

// MARK: - Sequential Name Pattern

/// Pattern for generating sequential filenames
public struct SequentialNamePattern: Codable {
    public var basePattern: String
    public var startNumber: Int
    public var numberDigits: Int
    public var separator: String
    public var fileExtension: String?
    
    public init(
        basePattern: String = "file",
        startNumber: Int = 1,
        numberDigits: Int = 3,
        separator: String = "_",
        fileExtension: String? = nil
    ) {
        self.basePattern = basePattern
        self.startNumber = startNumber
        self.numberDigits = numberDigits
        self.separator = separator
        self.fileExtension = fileExtension
    }
    
    /// Generate filename for given index
    public func generateFilename(at index: Int) -> String {
        let number = startNumber + index
        let paddedNumber = String(format: "%0\(numberDigits)d", number)
        var filename = "\(basePattern)\(separator)\(paddedNumber)"
        
        if let ext = fileExtension, !ext.isEmpty {
            filename += ".\(ext)"
        }
        
        return filename
    }
    
    /// Generate preview of first N filenames
    public func previewFilenames(count: Int = 3) -> [String] {
        (0..<count).map { generateFilename(at: $0) }
    }
    
    /// Common patterns
    public static var defaultPattern: SequentialNamePattern {
        SequentialNamePattern(basePattern: "download", startNumber: 1, numberDigits: 3)
    }
    
    public static var videoPattern: SequentialNamePattern {
        SequentialNamePattern(basePattern: "video", startNumber: 1, numberDigits: 3, fileExtension: "mp4")
    }
    
    public static var imagePattern: SequentialNamePattern {
        SequentialNamePattern(basePattern: "image", startNumber: 1, numberDigits: 4, fileExtension: "jpg")
    }
}

// MARK: - Batch Rename Pattern

/// Pattern for bulk renaming files
public struct BatchRenamePattern: Codable, Identifiable {
    public let id: UUID
    public var findPattern: String
    public var replaceWith: String
    public var isRegex: Bool
    public var caseSensitive: Bool
    public var description: String?
    
    public init(
        id: UUID = UUID(),
        findPattern: String,
        replaceWith: String,
        isRegex: Bool = false,
        caseSensitive: Bool = false,
        description: String? = nil
    ) {
        self.id = id
        self.findPattern = findPattern
        self.replaceWith = replaceWith
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
        self.description = description
    }
    
    /// Apply rename pattern to filename
    public func apply(to filename: String) -> String {
        if isRegex {
            guard let regex = try? NSRegularExpression(
                pattern: findPattern,
                options: caseSensitive ? [] : [.caseInsensitive]
            ) else {
                return filename
            }
            
            let range = NSRange(filename.startIndex..., in: filename)
            return regex.stringByReplacingMatches(
                in: filename,
                options: [],
                range: range,
                withTemplate: replaceWith
            )
        } else {
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            return filename.replacingOccurrences(
                of: findPattern,
                with: replaceWith,
                options: options
            )
        }
    }
    
    /// Common patterns
    public static var removeSpaces: BatchRenamePattern {
        BatchRenamePattern(
            findPattern: " ",
            replaceWith: "_",
            description: "Replace spaces with underscores"
        )
    }
    
    public static var removeSpecialChars: BatchRenamePattern {
        BatchRenamePattern(
            findPattern: "[^a-zA-Z0-9._-]",
            replaceWith: "",
            isRegex: true,
            description: "Remove special characters"
        )
    }
    
    public static var lowercase: BatchRenamePattern {
        BatchRenamePattern(
            findPattern: "[A-Z]",
            replaceWith: "",
            isRegex: true,
            description: "Convert to lowercase"
        )
    }
}

// MARK: - Batch Import Config

/// Configuration for batch URL import
public struct BatchImportConfig: Codable {
    public var source: BatchImportSource
    public var urls: [String]
    public var sourceFilePath: String?
    public var targetCategory: BatchCategory?
    public var targetDirectory: String?
    public var urlPatterns: [URLPattern]
    public var useSequentialNaming: Bool
    public var sequentialPattern: SequentialNamePattern?
    public var renamePatterns: [BatchRenamePattern]
    public var validateURLs: Bool
    public var removeDuplicates: Bool
    public var startImmediately: Bool
    
    public init(
        source: BatchImportSource = .clipboard,
        urls: [String] = [],
        sourceFilePath: String? = nil,
        targetCategory: BatchCategory? = nil,
        targetDirectory: String? = nil,
        urlPatterns: [URLPattern] = [],
        useSequentialNaming: Bool = false,
        sequentialPattern: SequentialNamePattern? = nil,
        renamePatterns: [BatchRenamePattern] = [],
        validateURLs: Bool = true,
        removeDuplicates: Bool = true,
        startImmediately: Bool = false
    ) {
        self.source = source
        self.urls = urls
        self.sourceFilePath = sourceFilePath
        self.targetCategory = targetCategory
        self.targetDirectory = targetDirectory
        self.urlPatterns = urlPatterns
        self.useSequentialNaming = useSequentialNaming
        self.sequentialPattern = sequentialPattern
        self.renamePatterns = renamePatterns
        self.validateURLs = validateURLs
        self.removeDuplicates = removeDuplicates
        self.startImmediately = startImmediately
    }
}

// MARK: - URL Validation Result

/// Result of URL validation
public struct URLValidationResult: Codable, Identifiable {
    public let id: UUID
    public let url: String
    public var isValid: Bool
    public var error: String?
    public var suggestedFilename: String?
    public var detectedCategory: BatchCategory?
    public var finalFilename: String?
    
    public init(
        id: UUID = UUID(),
        url: String,
        isValid: Bool = false,
        error: String? = nil,
        suggestedFilename: String? = nil,
        detectedCategory: BatchCategory? = nil,
        finalFilename: String? = nil
    ) {
        self.id = id
        self.url = url
        self.isValid = isValid
        self.error = error
        self.suggestedFilename = suggestedFilename
        self.detectedCategory = detectedCategory
        self.finalFilename = finalFilename
    }
}

// MARK: - Batch Operation Result

/// Result of a batch operation
public struct BatchOperationResult: Codable {
    public var totalCount: Int
    public var successCount: Int
    public var failedCount: Int
    public var validationResults: [URLValidationResult]
    public var errors: [String]
    public var duration: TimeInterval
    public var createdTaskIds: [UUID]
    
    public init(
        totalCount: Int = 0,
        successCount: Int = 0,
        failedCount: Int = 0,
        validationResults: [URLValidationResult] = [],
        errors: [String] = [],
        duration: TimeInterval = 0,
        createdTaskIds: [UUID] = []
    ) {
        self.totalCount = totalCount
        self.successCount = successCount
        self.failedCount = failedCount
        self.validationResults = validationResults
        self.errors = errors
        self.duration = duration
        self.createdTaskIds = createdTaskIds
    }
    
    public var successRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(successCount) / Double(totalCount) * 100
    }
    
    public var summary: String {
        """
        Total: \(totalCount), Success: \(successCount), Failed: \(failedCount)
        Success Rate: \(String(format: "%.1f", successRate))%
        Duration: \(String(format: "%.2f", duration))s
        """
    }
}

// MARK: - Batch Operation Error

/// Errors that can occur during batch operations
public enum BatchOperationError: Error, LocalizedError {
    case invalidURL(String)
    case invalidFilePath
    case fileReadError(Error)
    case clipboardEmpty
    case noURLsFound
    case patternError(String)
    case validationFailed([String])
    case duplicateURLs([String])
    case categoryDetectionFailed
    case sequentialNamingError
    case renamePatternError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidFilePath:
            return "Invalid file path"
        case .fileReadError(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .clipboardEmpty:
            return "Clipboard is empty"
        case .noURLsFound:
            return "No valid URLs found"
        case .patternError(let pattern):
            return "Invalid pattern: \(pattern)"
        case .validationFailed(let urls):
            return "Validation failed for \(urls.count) URLs"
        case .duplicateURLs(let urls):
            return "Found \(urls.count) duplicate URLs"
        case .categoryDetectionFailed:
            return "Failed to detect category"
        case .sequentialNamingError:
            return "Sequential naming failed"
        case .renamePatternError(let pattern):
            return "Rename pattern error: \(pattern)"
        }
    }
}

// MARK: - Batch Export Config

/// Configuration for exporting URLs
public struct BatchExportConfig: Codable {
    public var includeMetadata: Bool
    public var includeCategory: Bool
    public var includeFilename: Bool
    public var format: ExportFormat
    
    public enum ExportFormat: String, Codable {
        case plainText
        case json
        case csv
        case markdown
        
        var fileExtension: String {
            switch self {
            case .plainText: return "txt"
            case .json: return "json"
            case .csv: return "csv"
            case .markdown: return "md"
            }
        }
    }
    
    public init(
        includeMetadata: Bool = false,
        includeCategory: Bool = false,
        includeFilename: Bool = false,
        format: ExportFormat = .plainText
    ) {
        self.includeMetadata = includeMetadata
        self.includeCategory = includeCategory
        self.includeFilename = includeFilename
        self.format = format
    }
}

// MARK: - Batch Task Info

/// Information about a batch download task
public struct BatchTaskInfo: Codable, Identifiable {
    public let id: UUID
    public let batchId: UUID
    public let url: String
    public var filename: String
    public var category: BatchCategory?
    public var destinationPath: String
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        batchId: UUID = UUID(),
        url: String,
        filename: String,
        category: BatchCategory? = nil,
        destinationPath: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.batchId = batchId
        self.url = url
        self.filename = filename
        self.category = category
        self.destinationPath = destinationPath
        self.createdAt = createdAt
    }
}

// MARK: - Batch Import Session

/// Session tracking for batch imports
public struct BatchImportSession: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var config: BatchImportConfig
    public var result: BatchOperationResult?
    public var createdAt: Date
    public var completedAt: Date?
    public var status: SessionStatus
    
    public enum SessionStatus: String, Codable {
        case preparing
        case validating
        case importing
        case completed
        case failed
        case cancelled
        
        var icon: String {
            switch self {
            case .preparing: return "clock"
            case .validating: return "checkmark.circle"
            case .importing: return "arrow.down.circle"
            case .completed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .cancelled: return "xmark.circle"
            }
        }
        
        var color: String {
            switch self {
            case .preparing: return "blue"
            case .validating: return "orange"
            case .importing: return "blue"
            case .completed: return "green"
            case .failed: return "red"
            case .cancelled: return "gray"
            }
        }
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        config: BatchImportConfig,
        result: BatchOperationResult? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        status: SessionStatus = .preparing
    ) {
        self.id = id
        self.name = name
        self.config = config
        self.result = result
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.status = status
    }
    
    public var duration: TimeInterval? {
        guard let completedAt = completedAt else { return nil }
        return completedAt.timeIntervalSince(createdAt)
    }
}
