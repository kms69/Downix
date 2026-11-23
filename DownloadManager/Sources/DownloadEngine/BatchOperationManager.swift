import Foundation
import Combine
import AppKit

/// Manager for batch download operations
public class BatchOperationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var sessions: [BatchImportSession] = []
    @Published public var currentSession: BatchImportSession?
    @Published public var validationResults: [URLValidationResult] = []
    @Published public var isProcessing: Bool = false
    @Published public var progress: Double = 0.0
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Singleton
    
    public static let shared = BatchOperationManager()
    
    private init() {
        loadSessions()
    }
    
    // MARK: - URL Import
    
    /// Import URLs from clipboard
    public func importFromClipboard() -> Result<[String], BatchOperationError> {
        let pasteboard = NSPasteboard.general
        
        guard let clipboardText = pasteboard.string(forType: .string), !clipboardText.isEmpty else {
            return .failure(.clipboardEmpty)
        }
        
        let urls = extractURLs(from: clipboardText)
        
        guard !urls.isEmpty else {
            return .failure(.noURLsFound)
        }
        
        return .success(urls)
    }
    
    /// Import URLs from text file
    public func importFromFile(at path: String) -> Result<[String], BatchOperationError> {
        let fileURL = URL(fileURLWithPath: path)
        
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(.invalidFilePath)
        }
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let urls = extractURLs(from: content)
            
            guard !urls.isEmpty else {
                return .failure(.noURLsFound)
            }
            
            return .success(urls)
        } catch {
            return .failure(.fileReadError(error))
        }
    }
    
    /// Extract URLs from text
    private func extractURLs(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var urls: [String] = []
        
        // Regex for URL detection
        let urlPattern = #"https?://[^\s<>"{}|\\^`\[\]]+"#
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: []) else {
            return []
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else {
                continue
            }
            
            // Check if line is a direct URL
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                urls.append(trimmed)
            } else {
                // Extract URLs from line using regex
                let range = NSRange(line.startIndex..., in: line)
                let matches = regex.matches(in: line, options: [], range: range)
                
                for match in matches {
                    if let range = Range(match.range, in: line) {
                        urls.append(String(line[range]))
                    }
                }
            }
        }
        
        return urls
    }
    
    // MARK: - URL Validation
    
    /// Validate and process URLs
    public func validateURLs(
        _ urls: [String],
        with config: BatchImportConfig
    ) async -> [URLValidationResult] {
        await withTaskGroup(of: URLValidationResult.self) { group in
            var results: [URLValidationResult] = []
            
            for (index, url) in urls.enumerated() {
                group.addTask {
                    await self.validateURL(
                        url,
                        at: index,
                        with: config
                    )
                }
            }
            
            for await result in group {
                results.append(result)
            }
            
            return results.sorted { $0.url < $1.url }
        }
    }
    
    /// Validate single URL
    private func validateURL(
        _ urlString: String,
        at index: Int,
        with config: BatchImportConfig
    ) async -> URLValidationResult {
        var result = URLValidationResult(url: urlString)
        
        // Basic URL validation
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https", "ftp"].contains(scheme.lowercased()) else {
            result.isValid = false
            result.error = "Invalid URL format"
            return result
        }
        
        result.isValid = true
        
        // Apply URL patterns filter
        if !config.urlPatterns.isEmpty {
            let matches = config.urlPatterns.contains { $0.matches(urlString) }
            if !matches {
                result.isValid = false
                result.error = "URL doesn't match any pattern"
                return result
            }
        }
        
        // Detect category
        result.detectedCategory = detectCategory(from: url)
        
        // Generate filename
        if config.useSequentialNaming, let pattern = config.sequentialPattern {
            result.suggestedFilename = pattern.generateFilename(at: index)
        } else {
            result.suggestedFilename = url.lastPathComponent
        }
        
        // Apply rename patterns
        if var filename = result.suggestedFilename {
            for pattern in config.renamePatterns {
                filename = pattern.apply(to: filename)
            }
            result.finalFilename = filename
        }
        
        return result
    }
    
    /// Detect category from URL
    private func detectCategory(from url: URL) -> BatchCategory? {
        let pathExtension = url.pathExtension.lowercased()
        
        // Video extensions
        if ["mp4", "avi", "mkv", "mov", "wmv", "flv", "webm", "mpeg", "m4v"].contains(pathExtension) {
            return .video
        }
        
        // Audio extensions
        if ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma"].contains(pathExtension) {
            return .audio
        }
        
        // Document extensions
        if ["pdf", "doc", "docx", "txt", "rtf", "pages", "xls", "xlsx", "ppt", "pptx"].contains(pathExtension) {
            return .document
        }
        
        // Archive extensions
        if ["zip", "tar", "gz", "7z", "rar", "dmg", "iso"].contains(pathExtension) {
            return .archive
        }
        
        // Image extensions
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic"].contains(pathExtension) {
            return .image
        }
        
        // Software extensions
        if ["dmg", "pkg", "app", "exe", "msi"].contains(pathExtension) {
            return .software
        }
        
        // eBook extensions
        if ["epub", "mobi", "azw", "azw3"].contains(pathExtension) {
            return .ebook
        }
        
        // Torrent extensions
        if pathExtension == "torrent" {
            return .torrent
        }
        
        return .other
    }
    
    // MARK: - Batch Processing
    
    /// Process batch import
    public func processBatchImport(
        config: BatchImportConfig
    ) async -> BatchOperationResult {
        let startTime = Date()
        
        await MainActor.run {
            isProcessing = true
            progress = 0.0
        }
        
        var result = BatchOperationResult()
        
        // Get URLs based on source
        var urls = config.urls
        if urls.isEmpty {
            let importResult: Result<[String], BatchOperationError>
            
            switch config.source {
            case .clipboard:
                importResult = importFromClipboard()
            case .textFile:
                if let path = config.sourceFilePath {
                    importResult = importFromFile(at: path)
                } else {
                    importResult = .failure(.invalidFilePath)
                }
            default:
                importResult = .success([])
            }
            
            switch importResult {
            case .success(let extractedURLs):
                urls = extractedURLs
            case .failure(let error):
                result.errors.append(error.localizedDescription)
                result.totalCount = 0
                result.duration = Date().timeIntervalSince(startTime)
                await MainActor.run { isProcessing = false }
                return result
            }
        }
        
        result.totalCount = urls.count
        
        // Remove duplicates if enabled
        if config.removeDuplicates {
            let uniqueURLs = Array(Set(urls))
            let duplicates = urls.count - uniqueURLs.count
            if duplicates > 0 {
                result.errors.append("Removed \(duplicates) duplicate URLs")
            }
            urls = uniqueURLs
            result.totalCount = urls.count
        }
        
        // Validate URLs
        let validationResults = await validateURLs(urls, with: config)
        result.validationResults = validationResults
        
        // Count results
        result.successCount = validationResults.filter { $0.isValid }.count
        result.failedCount = validationResults.filter { !$0.isValid }.count
        
        // Calculate duration
        result.duration = Date().timeIntervalSince(startTime)
        
        await MainActor.run {
            isProcessing = false
            progress = 1.0
            self.validationResults = validationResults
        }
        
        return result
    }
    
    /// Create download tasks from batch
    public func createDownloadTasks(
        from validationResults: [URLValidationResult],
        with config: BatchImportConfig
    ) -> [BatchTaskInfo] {
        var tasks: [BatchTaskInfo] = []
        let batchId = UUID()
        
        let validResults = validationResults.filter { $0.isValid }
        
        for result in validResults {
            let filename = result.finalFilename ?? result.suggestedFilename ?? URL(string: result.url)?.lastPathComponent ?? "download"
            let category = config.targetCategory ?? result.detectedCategory ?? .other
            
            // Determine destination path
            var destinationPath = config.targetDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
            
            // Append category subdirectory if no specific directory provided
            if config.targetDirectory == nil {
                destinationPath = (destinationPath as NSString).appendingPathComponent("Downloads")
                destinationPath = (destinationPath as NSString).appendingPathComponent(category.defaultSubdirectory)
            }
            
            destinationPath = (destinationPath as NSString).appendingPathComponent(filename)
            
            let task = BatchTaskInfo(
                batchId: batchId,
                url: result.url,
                filename: filename,
                category: category,
                destinationPath: destinationPath
            )
            
            tasks.append(task)
        }
        
        return tasks
    }
    
    // MARK: - Pattern Matching
    
    /// Test URL pattern
    public func testPattern(_ pattern: URLPattern, against urls: [String]) -> [String] {
        urls.filter { pattern.matches($0) }
    }
    
    /// Test rename pattern
    public func testRenamePattern(_ pattern: BatchRenamePattern, on filenames: [String]) -> [String: String] {
        var results: [String: String] = [:]
        for filename in filenames {
            results[filename] = pattern.apply(to: filename)
        }
        return results
    }
    
    // MARK: - Sequential Naming
    
    /// Preview sequential filenames
    public func previewSequentialNames(
        _ pattern: SequentialNamePattern,
        count: Int
    ) -> [String] {
        (0..<count).map { pattern.generateFilename(at: $0) }
    }
    
    // MARK: - Export
    
    /// Export URLs to file
    public func exportURLs(
        _ urls: [String],
        to path: String,
        config: BatchExportConfig
    ) throws {
        let fileURL = URL(fileURLWithPath: path)
        
        var content = ""
        
        switch config.format {
        case .plainText:
            content = urls.joined(separator: "\n")
            
        case .json:
            let data = try JSONEncoder().encode(urls)
            content = String(data: data, encoding: .utf8) ?? ""
            
        case .csv:
            content = "URL\n" + urls.joined(separator: "\n")
            
        case .markdown:
            content = "# Batch Download URLs\n\n"
            content += urls.map { "- [\($0)](\($0))" }.joined(separator: "\n")
        }
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    /// Export validation results
    public func exportValidationResults(
        _ results: [URLValidationResult],
        to path: String,
        config: BatchExportConfig
    ) throws {
        let fileURL = URL(fileURLWithPath: path)
        
        var content = ""
        
        switch config.format {
        case .plainText:
            for result in results {
                content += "URL: \(result.url)\n"
                content += "Valid: \(result.isValid)\n"
                if let error = result.error {
                    content += "Error: \(error)\n"
                }
                if let filename = result.finalFilename {
                    content += "Filename: \(filename)\n"
                }
                if let category = result.detectedCategory {
                    content += "Category: \(category.displayName)\n"
                }
                content += "\n"
            }
            
        case .json:
            let data = try JSONEncoder().encode(results)
            content = String(data: data, encoding: .utf8) ?? ""
            
        case .csv:
            content = "URL,Valid,Error,Filename,Category\n"
            for result in results {
                let error = result.error?.replacingOccurrences(of: ",", with: ";") ?? ""
                let filename = result.finalFilename ?? ""
                let category = result.detectedCategory?.displayName ?? ""
                content += "\"\(result.url)\",\(result.isValid),\"\(error)\",\"\(filename)\",\"\(category)\"\n"
            }
            
        case .markdown:
            content = "# Batch Validation Results\n\n"
            content += "| URL | Valid | Filename | Category |\n"
            content += "|-----|-------|----------|----------|\n"
            for result in results {
                let filename = result.finalFilename ?? "-"
                let category = result.detectedCategory?.displayName ?? "-"
                content += "| \(result.url) | \(result.isValid ? "✅" : "❌") | \(filename) | \(category) |\n"
            }
        }
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Session Management
    
    /// Create new batch import session
    public func createSession(name: String, config: BatchImportConfig) -> BatchImportSession {
        let session = BatchImportSession(name: name, config: config)
        sessions.append(session)
        currentSession = session
        saveSessions()
        return session
    }
    
    /// Update session
    public func updateSession(_ session: BatchImportSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            if currentSession?.id == session.id {
                currentSession = session
            }
            saveSessions()
        }
    }
    
    /// Delete session
    public func deleteSession(_ session: BatchImportSession) {
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = nil
        }
        saveSessions()
    }
    
    /// Complete session with result
    public func completeSession(_ sessionId: UUID, result: BatchOperationResult) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].result = result
            sessions[index].completedAt = Date()
            sessions[index].status = result.successCount > 0 ? .completed : .failed
            saveSessions()
        }
    }
    
    // MARK: - Persistence
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: "batchImportSessions"),
           let decoded = try? JSONDecoder().decode([BatchImportSession].self, from: data) {
            sessions = decoded
        }
    }
    
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: "batchImportSessions")
        }
    }
    
    // MARK: - Utility
    
    /// Clear all validation results
    public func clearValidationResults() {
        validationResults.removeAll()
    }
    
    /// Get statistics
    public func getStatistics() -> (totalSessions: Int, totalURLs: Int, averageSuccessRate: Double) {
        let totalSessions = sessions.count
        let totalURLs = sessions.reduce(0) { $0 + ($1.result?.totalCount ?? 0) }
        let successRates = sessions.compactMap { $0.result?.successRate }
        let averageSuccessRate = successRates.isEmpty ? 0 : successRates.reduce(0, +) / Double(successRates.count)
        
        return (totalSessions, totalURLs, averageSuccessRate)
    }
    
    /// Validate pattern syntax
    public func validatePattern(_ pattern: String, isRegex: Bool) -> Bool {
        if isRegex {
            return (try? NSRegularExpression(pattern: pattern, options: [])) != nil
        }
        return true
    }
}
