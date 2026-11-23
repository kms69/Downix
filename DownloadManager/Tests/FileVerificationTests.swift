//
//  FileVerificationTests.swift
//  DownloadManager Tests
//
//  Feature #21: File Verification & Integrity - XCTest Unit Tests
//

import XCTest
@testable import DownloadManager

class FileVerificationTests: XCTestCase {
    
    var verificationManager: FileVerificationManager!
    var testFileURL: URL!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        verificationManager = FileVerificationManager.shared
        verificationManager.resetConfiguration()
        verificationManager.resetStatistics()
        verificationManager.clearHistory()
        
        // Create a temporary test file
        testFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_file_\(UUID().uuidString).txt")
        let testContent = "Hello, Download Manager! This is a test file for verification."
        try testContent.write(to: testFileURL, atomically: true, encoding: .utf8)
    }
    
    override func tearDown() async throws {
        // Clean up test file
        try? FileManager.default.removeItem(at: testFileURL)
        verificationManager.resetConfiguration()
        verificationManager.resetStatistics()
        verificationManager.clearHistory()
    }
    
    // MARK: - Hash Algorithm Tests
    
    func testHashAlgorithmProperties() {
        XCTAssertEqual(HashAlgorithm.allCases.count, 5)
        
        XCTAssertEqual(HashAlgorithm.md5.hashLength, 32)
        XCTAssertEqual(HashAlgorithm.sha1.hashLength, 40)
        XCTAssertEqual(HashAlgorithm.sha256.hashLength, 64)
        XCTAssertEqual(HashAlgorithm.sha512.hashLength, 128)
        XCTAssertEqual(HashAlgorithm.crc32.hashLength, 8)
    }
    
    func testHashAlgorithmSecurity() {
        XCTAssertTrue(HashAlgorithm.sha256.isSecure)
        XCTAssertTrue(HashAlgorithm.sha512.isSecure)
        XCTAssertFalse(HashAlgorithm.md5.isSecure)
        XCTAssertFalse(HashAlgorithm.sha1.isSecure)
        XCTAssertFalse(HashAlgorithm.crc32.isSecure)
    }
    
    func testHashAlgorithmStrength() {
        XCTAssertGreaterThan(HashAlgorithm.sha512.securityStrength, HashAlgorithm.sha256.securityStrength)
        XCTAssertGreaterThan(HashAlgorithm.sha256.securityStrength, HashAlgorithm.sha1.securityStrength)
        XCTAssertGreaterThan(HashAlgorithm.sha1.securityStrength, HashAlgorithm.md5.securityStrength)
        XCTAssertGreaterThan(HashAlgorithm.md5.securityStrength, HashAlgorithm.crc32.securityStrength)
    }
    
    // MARK: - Verification Status Tests
    
    func testVerificationStatusProperties() {
        XCTAssertTrue(VerificationStatus.verified.isComplete)
        XCTAssertTrue(VerificationStatus.failed.isComplete)
        XCTAssertTrue(VerificationStatus.skipped.isComplete)
        XCTAssertFalse(VerificationStatus.verifying.isComplete)
        XCTAssertFalse(VerificationStatus.pending.isComplete)
    }
    
    func testVerificationStatusSuccess() {
        XCTAssertTrue(VerificationStatus.verified.isSuccess)
        XCTAssertFalse(VerificationStatus.failed.isSuccess)
        XCTAssertFalse(VerificationStatus.skipped.isSuccess)
    }
    
    // MARK: - Failure Action Tests
    
    func testFailureActionProperties() {
        XCTAssertTrue(VerificationFailureAction.delete.isDestructive)
        XCTAssertTrue(VerificationFailureAction.quarantine.isDestructive)
        XCTAssertFalse(VerificationFailureAction.none.isDestructive)
        XCTAssertFalse(VerificationFailureAction.notify.isDestructive)
        XCTAssertFalse(VerificationFailureAction.redownload.isDestructive)
    }
    
    // MARK: - File Checksum Tests
    
    func testFileChecksumCreation() {
        let checksum = FileChecksum(
            algorithm: .sha256,
            expectedHash: "test_hash",
            actualHash: nil
        )
        
        XCTAssertEqual(checksum.algorithm, .sha256)
        XCTAssertEqual(checksum.expectedHash, "test_hash")
        XCTAssertNil(checksum.actualHash)
        XCTAssertFalse(checksum.isVerified)
    }
    
    func testFileChecksumVerificationMatch() {
        var checksum = FileChecksum(
            algorithm: .sha256,
            expectedHash: "abc123",
            actualHash: nil
        )
        
        checksum.actualHash = "abc123"
        XCTAssertTrue(checksum.isVerified)
    }
    
    func testFileChecksumVerificationMismatch() {
        var checksum = FileChecksum(
            algorithm: .sha256,
            expectedHash: "abc123",
            actualHash: nil
        )
        
        checksum.actualHash = "def456"
        XCTAssertFalse(checksum.isVerified)
    }
    
    func testFileChecksumCaseInsensitive() {
        var checksum = FileChecksum(
            algorithm: .md5,
            expectedHash: "ABCDEF123456",
            actualHash: nil
        )
        
        checksum.actualHash = "abcdef123456"
        XCTAssertTrue(checksum.isVerified, "Checksum verification should be case insensitive")
    }
    
    func testHashFormatValidation() {
        let checksum = FileChecksum(algorithm: .sha256)
        
        // Valid SHA-256 hash
        let validHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertTrue(checksum.isValidHashFormat(validHash))
        
        // Invalid: wrong length
        XCTAssertFalse(checksum.isValidHashFormat("abc123"))
        
        // Invalid: non-hex characters
        let invalidHash = "g3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertFalse(checksum.isValidHashFormat(invalidHash))
    }
    
    // MARK: - Verification Configuration Tests
    
    func testDefaultConfiguration() {
        let config = VerificationConfig.default
        
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.autoVerifyOnComplete)
        XCTAssertTrue(config.defaultAlgorithms.contains(.sha256))
        XCTAssertEqual(config.failureAction, .notify)
        XCTAssertEqual(config.maxRetries, 3)
    }
    
    func testSecureConfiguration() {
        let config = VerificationConfig.secure
        
        XCTAssertTrue(config.defaultAlgorithms.contains(.sha256))
        XCTAssertTrue(config.defaultAlgorithms.contains(.sha512))
        XCTAssertEqual(config.failureAction, .quarantine)
    }
    
    func testFastConfiguration() {
        let config = VerificationConfig.fast
        
        XCTAssertEqual(config.defaultAlgorithms, [.crc32])
        XCTAssertEqual(config.failureAction, .notify)
    }
    
    func testParanoidConfiguration() {
        let config = VerificationConfig.paranoid
        
        XCTAssertEqual(config.defaultAlgorithms.count, 4)
        XCTAssertTrue(config.defaultAlgorithms.contains(.md5))
        XCTAssertTrue(config.defaultAlgorithms.contains(.sha1))
        XCTAssertTrue(config.defaultAlgorithms.contains(.sha256))
        XCTAssertTrue(config.defaultAlgorithms.contains(.sha512))
        XCTAssertEqual(config.failureAction, .redownload)
        XCTAssertEqual(config.maxRetries, 5)
    }
    
    // MARK: - Verification Result Tests
    
    func testVerificationResultAllVerified() {
        let checksums = [
            FileChecksum(algorithm: .sha256, expectedHash: "abc", actualHash: "abc"),
            FileChecksum(algorithm: .md5, expectedHash: "def", actualHash: "def")
        ]
        
        let result = VerificationResult(
            downloadTaskId: UUID(),
            status: .verified,
            checksums: checksums,
            fileSize: 1024
        )
        
        XCTAssertTrue(result.allChecksumsVerified)
        XCTAssertEqual(result.verifiedCount, 2)
        XCTAssertEqual(result.failedCount, 0)
    }
    
    func testVerificationResultSomeFailed() {
        let checksums = [
            FileChecksum(algorithm: .sha256, expectedHash: "abc", actualHash: "abc"),
            FileChecksum(algorithm: .md5, expectedHash: "def", actualHash: "xyz")
        ]
        
        let result = VerificationResult(
            downloadTaskId: UUID(),
            status: .failed,
            checksums: checksums,
            fileSize: 1024
        )
        
        XCTAssertFalse(result.allChecksumsVerified)
        XCTAssertEqual(result.verifiedCount, 1)
        XCTAssertEqual(result.failedCount, 1)
    }
    
    func testVerificationResultProgress() {
        let checksums = [
            FileChecksum(algorithm: .sha256, expectedHash: "abc", actualHash: "abc"),
            FileChecksum(algorithm: .md5, expectedHash: "def", actualHash: nil),
            FileChecksum(algorithm: .sha1, expectedHash: "ghi", actualHash: nil)
        ]
        
        let result = VerificationResult(
            downloadTaskId: UUID(),
            checksums: checksums
        )
        
        // One out of three processed
        XCTAssertEqual(result.progress, 100.0 / 3.0, accuracy: 0.1)
    }
    
    // MARK: - Verification Statistics Tests
    
    func testStatisticsSuccessRate() {
        var stats = VerificationStatistics()
        stats.totalVerifications = 10
        stats.successfulVerifications = 8
        
        XCTAssertEqual(stats.successRate, 80.0, accuracy: 0.1)
    }
    
    func testStatisticsAverageSpeed() {
        var stats = VerificationStatistics()
        stats.totalBytesVerified = 1024000
        stats.totalVerificationTime = 10.0
        
        XCTAssertEqual(stats.averageVerificationSpeed, 102400.0, accuracy: 0.1)
    }
    
    func testStatisticsReset() {
        var stats = VerificationStatistics()
        stats.totalVerifications = 100
        stats.successfulVerifications = 80
        stats.failedVerifications = 20
        stats.totalBytesVerified = 1024000
        
        stats.reset()
        
        XCTAssertEqual(stats.totalVerifications, 0)
        XCTAssertEqual(stats.successfulVerifications, 0)
        XCTAssertEqual(stats.failedVerifications, 0)
        XCTAssertEqual(stats.totalBytesVerified, 0)
    }
    
    // MARK: - Manager Configuration Tests
    
    @MainActor
    func testManagerConfiguration() {
        let config = VerificationConfig(
            isEnabled: true,
            autoVerifyOnComplete: true,
            defaultAlgorithms: [.sha256, .sha512]
        )
        
        verificationManager.updateConfiguration(config)
        
        XCTAssertTrue(verificationManager.configuration.isEnabled)
        XCTAssertTrue(verificationManager.configuration.autoVerifyOnComplete)
        XCTAssertEqual(verificationManager.configuration.defaultAlgorithms.count, 2)
    }
    
    @MainActor
    func testManagerResetConfiguration() {
        // Modify configuration
        var config = verificationManager.configuration
        config.isEnabled = false
        config.failureAction = .delete
        verificationManager.updateConfiguration(config)
        
        // Reset
        verificationManager.resetConfiguration()
        
        XCTAssertTrue(verificationManager.configuration.isEnabled)
        XCTAssertEqual(verificationManager.configuration.failureAction, .notify)
    }
    
    @MainActor
    func testManagerStatisticsReset() {
        // Add some statistics
        verificationManager.statistics.totalVerifications = 100
        verificationManager.statistics.successfulVerifications = 80
        
        verificationManager.resetStatistics()
        
        XCTAssertEqual(verificationManager.statistics.totalVerifications, 0)
        XCTAssertEqual(verificationManager.statistics.successfulVerifications, 0)
    }
    
    // MARK: - Hash Computation Tests
    
    @MainActor
    func testComputeSHA256Hash() async throws {
        let hash = try await verificationManager.computeHash(
            filePath: testFileURL.path,
            algorithm: .sha256
        )
        
        XCTAssertEqual(hash.count, 64)
        XCTAssertFalse(hash.isEmpty)
        
        // Verify hash format (hex string)
        XCTAssertTrue(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }
    
    @MainActor
    func testComputeMD5Hash() async throws {
        let hash = try await verificationManager.computeHash(
            filePath: testFileURL.path,
            algorithm: .md5
        )
        
        XCTAssertEqual(hash.count, 32)
        XCTAssertFalse(hash.isEmpty)
    }
    
    @MainActor
    func testComputeMultipleHashes() async throws {
        let sha256 = try await verificationManager.computeHash(
            filePath: testFileURL.path,
            algorithm: .sha256
        )
        let md5 = try await verificationManager.computeHash(
            filePath: testFileURL.path,
            algorithm: .md5
        )
        
        XCTAssertNotEqual(sha256, md5)
        XCTAssertEqual(sha256.count, 64)
        XCTAssertEqual(md5.count, 32)
    }
    
    @MainActor
    func testComputeHashNonexistentFile() async {
        do {
            _ = try await verificationManager.computeHash(
                filePath: "/nonexistent/file.txt",
                algorithm: .sha256
            )
            XCTFail("Should throw error for nonexistent file")
        } catch {
            // Expected error
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - File Verification Tests
    
    @MainActor
    func testVerifyFileWithoutExpectedHash() async {
        let checksums = [
            FileChecksum(algorithm: .sha256)
        ]
        
        let result = await verificationManager.verifyFile(
            filePath: testFileURL.path,
            downloadTaskId: UUID(),
            checksums: checksums
        )
        
        XCTAssertEqual(result.status, .notVerified)
        XCTAssertNotNil(result.checksums.first?.actualHash)
        XCTAssertGreaterThan(result.fileSize, 0)
    }
    
    @MainActor
    func testVerifyFileWithMatchingHash() async throws {
        // First compute the expected hash
        let expectedHash = try await verificationManager.computeHash(
            filePath: testFileURL.path,
            algorithm: .sha256
        )
        
        let checksums = [
            FileChecksum(algorithm: .sha256, expectedHash: expectedHash)
        ]
        
        let result = await verificationManager.verifyFile(
            filePath: testFileURL.path,
            downloadTaskId: UUID(),
            checksums: checksums
        )
        
        XCTAssertEqual(result.status, .verified)
        XCTAssertTrue(result.allChecksumsVerified)
        XCTAssertEqual(result.verifiedCount, 1)
    }
    
    @MainActor
    func testVerifyFileWithMismatchedHash() async {
        let checksums = [
            FileChecksum(algorithm: .sha256, expectedHash: "wronghash123")
        ]
        
        let result = await verificationManager.verifyFile(
            filePath: testFileURL.path,
            downloadTaskId: UUID(),
            checksums: checksums
        )
        
        XCTAssertEqual(result.status, .failed)
        XCTAssertFalse(result.allChecksumsVerified)
        XCTAssertEqual(result.failedCount, 1)
    }
    
    @MainActor
    func testVerifyFileWithDefaultAlgorithms() async {
        let result = await verificationManager.verifyFileWithDefaults(
            filePath: testFileURL.path,
            downloadTaskId: UUID()
        )
        
        XCTAssertNotEqual(result.status, .notVerified)
        XCTAssertFalse(result.checksums.isEmpty)
    }
    
    @MainActor
    func testVerifyFileDisabled() async {
        var config = verificationManager.configuration
        config.isEnabled = false
        verificationManager.updateConfiguration(config)
        
        let checksums = [FileChecksum(algorithm: .sha256)]
        let result = await verificationManager.verifyFile(
            filePath: testFileURL.path,
            downloadTaskId: UUID(),
            checksums: checksums
        )
        
        XCTAssertEqual(result.status, .skipped)
    }
    
    // MARK: - History Tests
    
    @MainActor
    func testHistoryManagement() async {
        let checksums = [FileChecksum(algorithm: .sha256)]
        
        _ = await verificationManager.verifyFile(
            filePath: testFileURL.path,
            downloadTaskId: UUID(),
            checksums: checksums
        )
        
        XCTAssertEqual(verificationManager.verificationHistory.count, 1)
    }
    
    @MainActor
    func testClearHistory() async {
        let checksums = [FileChecksum(algorithm: .sha256)]
        
        _ = await verificationManager.verifyFile(
            filePath: testFileURL.path,
            downloadTaskId: UUID(),
            checksums: checksums
        )
        
        verificationManager.clearHistory()
        XCTAssertEqual(verificationManager.verificationHistory.count, 0)
    }
}
