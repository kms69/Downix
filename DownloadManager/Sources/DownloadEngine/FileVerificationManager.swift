//
//  FileVerificationManager.swift
//  DownloadManager
//
//  Feature #21: File Verification & Integrity
//  Manager for computing and verifying file checksums
//

import Foundation
import CryptoKit
import Combine

@MainActor
public class FileVerificationManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = FileVerificationManager()
    
    // MARK: - Published Properties
    
    @Published public var configuration: VerificationConfig
    @Published public var statistics: VerificationStatistics
    @Published public var activeVerifications: [UUID: VerificationResult]
    @Published public var verificationHistory: [VerificationResult]
    @Published public var isVerifying: Bool = false
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "com.downloadmanager.verificationConfig"
    private let statsKey = "com.downloadmanager.verificationStats"
    private let historyKey = "com.downloadmanager.verificationHistory"
    private let maxHistoryItems = 1000
    
    private var verificationQueue: [UUID] = []
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        self.configuration = VerificationConfig.default
        self.statistics = VerificationStatistics()
        self.activeVerifications = [:]
        self.verificationHistory = []
        
        loadConfiguration()
        loadStatistics()
        loadHistory()
    }
    
    // MARK: - Configuration Management
    
    public func updateConfiguration(_ config: VerificationConfig) {
        configuration = config
        saveConfiguration()
    }
    
    public func resetConfiguration() {
        configuration = VerificationConfig.default
        saveConfiguration()
    }
    
    private func saveConfiguration() {
        if let encoded = try? JSONEncoder().encode(configuration) {
            userDefaults.set(encoded, forKey: configKey)
        }
    }
    
    private func loadConfiguration() {
        if let data = userDefaults.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(VerificationConfig.self, from: data) {
            configuration = decoded
        }
    }
    
    // MARK: - Statistics Management
    
    public func resetStatistics() {
        statistics.reset()
        saveStatistics()
    }
    
    private func saveStatistics() {
        if let encoded = try? JSONEncoder().encode(statistics) {
            userDefaults.set(encoded, forKey: statsKey)
        }
    }
    
    private func loadStatistics() {
        if let data = userDefaults.data(forKey: statsKey),
           let decoded = try? JSONDecoder().decode(VerificationStatistics.self, from: data) {
            statistics = decoded
        }
    }
    
    private func updateStatistics(result: VerificationResult) {
        statistics.totalVerifications += 1
        
        switch result.status {
        case .verified:
            statistics.successfulVerifications += 1
        case .failed:
            statistics.failedVerifications += 1
        case .skipped:
            statistics.skippedVerifications += 1
        default:
            break
        }
        
        statistics.totalBytesVerified += result.fileSize
        if let duration = result.duration {
            statistics.totalVerificationTime += duration
        }
        
        for checksum in result.checksums {
            statistics.verificationsByAlgorithm[checksum.algorithm, default: 0] += 1
        }
        
        statistics.lastVerificationDate = Date()
        saveStatistics()
    }
    
    // MARK: - History Management
    
    private func addToHistory(_ result: VerificationResult) {
        verificationHistory.insert(result, at: 0)
        
        // Limit history size
        if verificationHistory.count > maxHistoryItems {
            verificationHistory = Array(verificationHistory.prefix(maxHistoryItems))
        }
        
        saveHistory()
    }
    
    public func clearHistory() {
        verificationHistory.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(verificationHistory) {
            userDefaults.set(encoded, forKey: historyKey)
        }
    }
    
    private func loadHistory() {
        if let data = userDefaults.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([VerificationResult].self, from: data) {
            verificationHistory = decoded
        }
    }
    
    // MARK: - Hash Computation
    
    /// Compute hash for a file using specified algorithm
    public func computeHash(
        filePath: String,
        algorithm: HashAlgorithm,
        bufferSize: Int? = nil
    ) async throws -> String {
        let url = URL(fileURLWithPath: filePath)
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw VerificationError.fileNotFound
        }
        
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        
        let buffer = bufferSize ?? configuration.bufferSize
        var hash: String
        
        switch algorithm {
        case .md5:
            hash = try await computeMD5(fileHandle: file, bufferSize: buffer)
        case .sha1:
            hash = try await computeSHA1(fileHandle: file, bufferSize: buffer)
        case .sha256:
            hash = try await computeSHA256(fileHandle: file, bufferSize: buffer)
        case .sha512:
            hash = try await computeSHA512(fileHandle: file, bufferSize: buffer)
        case .crc32:
            hash = try await computeCRC32(fileHandle: file, bufferSize: buffer)
        }
        
        return hash
    }
    
    private func computeMD5(fileHandle: FileHandle, bufferSize: Int) async throws -> String {
        var hasher = Insecure.MD5()
        
        try fileHandle.seek(toOffset: 0)
        while autoreleasepool(invoking: {
            if let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty {
                hasher.update(data: data)
                return true
            }
            return false
        }) {}
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func computeSHA1(fileHandle: FileHandle, bufferSize: Int) async throws -> String {
        var hasher = Insecure.SHA1()
        
        try fileHandle.seek(toOffset: 0)
        while autoreleasepool(invoking: {
            if let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty {
                hasher.update(data: data)
                return true
            }
            return false
        }) {}
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func computeSHA256(fileHandle: FileHandle, bufferSize: Int) async throws -> String {
        var hasher = SHA256()
        
        try fileHandle.seek(toOffset: 0)
        while autoreleasepool(invoking: {
            if let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty {
                hasher.update(data: data)
                return true
            }
            return false
        }) {}
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func computeSHA512(fileHandle: FileHandle, bufferSize: Int) async throws -> String {
        var hasher = SHA512()
        
        try fileHandle.seek(toOffset: 0)
        while autoreleasepool(invoking: {
            if let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty {
                hasher.update(data: data)
                return true
            }
            return false
        }) {}
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func computeCRC32(fileHandle: FileHandle, bufferSize: Int) async throws -> String {
        var crc: UInt32 = 0xFFFFFFFF
        
        try fileHandle.seek(toOffset: 0)
        while autoreleasepool(invoking: {
            if let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty {
                crc = data.reduce(crc) { (crc, byte) in
                    let index = Int((crc ^ UInt32(byte)) & 0xFF)
                    return (crc >> 8) ^ crc32Table[index]
                }
                return true
            }
            return false
        }) {}
        
        crc = crc ^ 0xFFFFFFFF
        return String(format: "%08x", crc)
    }
    
    // MARK: - File Verification
    
    /// Verify file against expected checksums
    public func verifyFile(
        filePath: String,
        downloadTaskId: UUID,
        checksums: [FileChecksum]
    ) async -> VerificationResult {
        guard configuration.isEnabled else {
            var result = VerificationResult(
                downloadTaskId: downloadTaskId,
                status: .skipped,
                checksums: checksums,
                filePath: filePath
            )
            result.endTime = Date()
            return result
        }
        
        // Check file size threshold
        if configuration.skipVerificationForSmallFiles {
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64 {
                let sizeMB = fileSize / (1024 * 1024)
                if sizeMB < configuration.smallFileThresholdMB {
                    var result = VerificationResult(
                        downloadTaskId: downloadTaskId,
                        status: .skipped,
                        checksums: checksums,
                        fileSize: fileSize,
                        filePath: filePath
                    )
                    result.endTime = Date()
                    return result
                }
            }
        }
        
        var result = VerificationResult(
            downloadTaskId: downloadTaskId,
            status: .verifying,
            checksums: checksums,
            filePath: filePath
        )
        
        // Get file size
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64 {
            result.fileSize = fileSize
        }
        
        // Add to active verifications
        activeVerifications[result.id] = result
        isVerifying = !activeVerifications.isEmpty
        
        // Verify each checksum
        var updatedChecksums: [FileChecksum] = []
        
        for checksum in checksums {
            var updated = checksum
            
            do {
                let hash = try await computeHash(
                    filePath: filePath,
                    algorithm: checksum.algorithm
                )
                updated.actualHash = hash
                updated.verificationDate = Date()
            } catch {
                result.errorMessage = error.localizedDescription
            }
            
            updatedChecksums.append(updated)
        }
        
        result.checksums = updatedChecksums
        result.endTime = Date()
        
        // Determine overall status
        if result.checksums.isEmpty {
            result.status = .unavailable
        } else if result.allChecksumsVerified {
            result.status = .verified
        } else if result.failedCount > 0 {
            result.status = .failed
        } else {
            result.status = .notVerified
        }
        
        // Remove from active
        activeVerifications.removeValue(forKey: result.id)
        isVerifying = !activeVerifications.isEmpty
        
        // Update statistics
        updateStatistics(result: result)
        
        // Add to history
        addToHistory(result)
        
        // Handle failure
        if result.status == .failed {
            await handleVerificationFailure(result: result)
        }
        
        return result
    }
    
    /// Verify file with default algorithms
    public func verifyFileWithDefaults(
        filePath: String,
        downloadTaskId: UUID
    ) async -> VerificationResult {
        let checksums = configuration.defaultAlgorithms.map { algorithm in
            FileChecksum(algorithm: algorithm)
        }
        return await verifyFile(filePath: filePath, downloadTaskId: downloadTaskId, checksums: checksums)
    }
    
    // MARK: - Failure Handling
    
    private func handleVerificationFailure(result: VerificationResult) async {
        switch configuration.failureAction {
        case .none:
            break
            
        case .notify:
            if configuration.showNotifications {
                await sendNotification(result: result)
            }
            
        case .quarantine:
            await quarantineFile(filePath: result.filePath)
            if configuration.showNotifications {
                await sendNotification(result: result)
            }
            
        case .delete:
            deleteFile(filePath: result.filePath)
            if configuration.showNotifications {
                await sendNotification(result: result)
            }
            
        case .redownload:
            // Would trigger re-download in DownloadManager
            if configuration.showNotifications {
                await sendNotification(result: result)
            }
        }
    }
    
    private func quarantineFile(filePath: String) async {
        guard let quarantinePath = configuration.quarantinePath else {
            // Use default quarantine location
            let quarantine = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".DownloadManagerQuarantine")
            
            try? FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
            
            let filename = URL(fileURLWithPath: filePath).lastPathComponent
            let destination = quarantine.appendingPathComponent(filename)
            
            try? FileManager.default.moveItem(atPath: filePath, toPath: destination.path)
            return
        }
        
        let destination = URL(fileURLWithPath: quarantinePath)
            .appendingPathComponent(URL(fileURLWithPath: filePath).lastPathComponent)
        
        try? FileManager.default.moveItem(atPath: filePath, toPath: destination.path)
    }
    
    private func deleteFile(filePath: String) {
        try? FileManager.default.removeItem(atPath: filePath)
    }
    
    private func sendNotification(result: VerificationResult) async {
        // Would integrate with NotificationManager
        print("Verification notification: \(result.status)")
    }
    
    // MARK: - Checksum File Parsing
    
    /// Parse checksum from a common checksum file format
    public func parseChecksumFile(
        filePath: String,
        targetFilename: String
    ) -> FileChecksum? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }
        
        // Detect format from extension
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        
        for format in ChecksumFileFormat.allCases {
            if format.rawValue.contains(ext) {
                return format.parseFile(content, filename: targetFilename)
            }
        }
        
        return nil
    }
    
    /// Extract checksums from URL metadata or HTTP headers
    public func extractChecksumsFromMetadata(
        url: URL,
        headers: [String: String]
    ) -> [FileChecksum] {
        var checksums: [FileChecksum] = []
        
        // Check common headers
        if let md5 = headers["Content-MD5"] ?? headers["X-Checksum-MD5"] {
            checksums.append(FileChecksum(algorithm: .md5, expectedHash: md5))
        }
        
        if let sha256 = headers["X-Checksum-SHA256"] ?? headers["Digest"]?.extractSHA256() {
            checksums.append(FileChecksum(algorithm: .sha256, expectedHash: sha256))
        }
        
        return checksums
    }
    
    // MARK: - Batch Operations
    
    /// Verify multiple files
    public func verifyFiles(
        files: [(path: String, downloadTaskId: UUID, checksums: [FileChecksum])]
    ) async -> [VerificationResult] {
        var results: [VerificationResult] = []
        
        for file in files {
            let result = await verifyFile(
                filePath: file.path,
                downloadTaskId: file.downloadTaskId,
                checksums: file.checksums
            )
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - Queue Management
    
    public func addToQueue(downloadTaskId: UUID) {
        if !verificationQueue.contains(downloadTaskId) {
            verificationQueue.append(downloadTaskId)
        }
    }
    
    public func removeFromQueue(downloadTaskId: UUID) {
        verificationQueue.removeAll { $0 == downloadTaskId }
    }
    
    public func processQueue() async {
        // Would process queued verifications
        // Integration with DownloadManager needed
    }
}

// MARK: - Verification Error

public enum VerificationError: LocalizedError {
    case fileNotFound
    case permissionDenied
    case corruptedFile
    case unsupportedAlgorithm
    case checksumMismatch
    case computationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File not found"
        case .permissionDenied:
            return "Permission denied"
        case .corruptedFile:
            return "File is corrupted"
        case .unsupportedAlgorithm:
            return "Unsupported hash algorithm"
        case .checksumMismatch:
            return "Checksum does not match"
        case .computationFailed(let reason):
            return "Hash computation failed: \(reason)"
        }
    }
}

// MARK: - CRC32 Table

private let crc32Table: [UInt32] = {
    (0...255).map { i -> UInt32 in
        var crc = UInt32(i)
        for _ in 0..<8 {
            crc = (crc % 2 == 0) ? (crc >> 1) : (0xEDB88320 ^ (crc >> 1))
        }
        return crc
    }
}()

// MARK: - String Extensions

private extension String {
    func extractSHA256() -> String? {
        // Parse Digest header: "SHA-256=base64hash"
        if hasPrefix("SHA-256=") {
            let base64 = String(dropFirst(8))
            if let data = Data(base64Encoded: base64) {
                return data.map { String(format: "%02x", $0) }.joined()
            }
        }
        return nil
    }
}
