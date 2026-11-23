import XCTest
@testable import DownloadManager

@MainActor
final class DownloadHistoryTests: XCTestCase {
    
    var manager: HistoryManager!
    
    override func setUp() async throws {
        manager = HistoryManager.shared
        manager.clearHistory()
    }
    
    override func tearDown() async throws {
        manager.clearHistory()
        manager = nil
    }
    
    // MARK: - Model Tests
    
    func testHistoryEntryCreation() {
        let url = URL(string: "https://example.com/file.zip")!
        let entry = DownloadHistoryEntry(
            url: url,
            fileName: "file.zip",
            filePath: "/Downloads/file.zip",
            fileSize: 1024 * 1024,
            fileType: "zip"
        )
        
        XCTAssertEqual(entry.fileName, "file.zip")
        XCTAssertEqual(entry.fileSize, 1024 * 1024)
        XCTAssertEqual(entry.fileType, "zip")
        XCTAssertEqual(entry.status, .completed)
    }
    
    func testHistoryEntryFormatting() {
        let entry = DownloadHistoryEntry(
            url: URL(string: "https://example.com/file.zip")!,
            fileName: "file.zip",
            filePath: "/Downloads/file.zip",
            fileSize: 1024 * 1024 * 10, // 10 MB
            fileType: "zip",
            averageSpeed: 1024 * 1024, // 1 MB/s
            duration: 125 // 2m 5s
        )
        
        XCTAssertEqual(entry.fileSizeFormatted, "10 MB")
        XCTAssertEqual(entry.averageSpeedFormatted, "1 MB/s")
        XCTAssertEqual(entry.durationFormatted, "2m 5s")
    }
    
    func testDownloadHistoryStatus() {
        XCTAssertEqual(DownloadHistoryStatus.completed.icon, "checkmark.circle.fill")
        XCTAssertEqual(DownloadHistoryStatus.failed.icon, "xmark.circle.fill")
        XCTAssertEqual(DownloadHistoryStatus.cancelled.icon, "minus.circle.fill")
        XCTAssertEqual(DownloadHistoryStatus.partial.icon, "exclamationmark.circle.fill")
        XCTAssertEqual(DownloadHistoryStatus.removed.icon, "trash.circle.fill")
    }
    
    func testDownloadStatisticsCalculations() {
        var stats = DownloadStatistics(
            totalDownloads: 100,
            completedDownloads: 85,
            failedDownloads: 10,
            cancelledDownloads: 5
        )
        
        XCTAssertEqual(stats.successRate, 85.0)
        
        stats.totalDownloads = 0
        XCTAssertEqual(stats.successRate, 0.0)
    }
    
    // MARK: - History Manager Tests
    
    func testAddEntry() {
        let entry = createSampleEntry(fileName: "test.zip")
        manager.addEntry(entry)
        
        XCTAssertEqual(manager.history.count, 1)
        XCTAssertEqual(manager.history.first?.fileName, "test.zip")
    }
    
    func testUpdateEntry() {
        var entry = createSampleEntry(fileName: "test.zip")
        manager.addEntry(entry)
        
        entry.metadata.retryCount = 3
        manager.updateEntry(entry)
        
        XCTAssertEqual(manager.history.first?.metadata.retryCount, 3)
    }
    
    func testDeleteEntry() {
        let entry1 = createSampleEntry(fileName: "test1.zip")
        let entry2 = createSampleEntry(fileName: "test2.zip")
        manager.addEntry(entry1)
        manager.addEntry(entry2)
        
        XCTAssertEqual(manager.history.count, 2)
        
        manager.deleteEntry(entry1)
        
        XCTAssertEqual(manager.history.count, 1)
        XCTAssertEqual(manager.history.first?.fileName, "test2.zip")
    }
    
    func testDeleteMultipleEntries() {
        let entries = (1...5).map { createSampleEntry(fileName: "test\($0).zip") }
        entries.forEach { manager.addEntry($0) }
        
        XCTAssertEqual(manager.history.count, 5)
        
        manager.deleteEntries(Array(entries.prefix(3)))
        
        XCTAssertEqual(manager.history.count, 2)
    }
    
    func testClearHistory() {
        let entries = (1...10).map { createSampleEntry(fileName: "test\($0).zip") }
        entries.forEach { manager.addEntry($0) }
        
        XCTAssertEqual(manager.history.count, 10)
        
        manager.clearHistory()
        
        XCTAssertEqual(manager.history.count, 0)
        XCTAssertEqual(manager.statistics.totalDownloads, 0)
    }
    
    func testClearHistoryOlderThan() {
        let now = Date()
        let calendar = Calendar.current
        
        // Add entries from different dates
        for i in 0..<10 {
            let date = calendar.date(byAdding: .day, value: -i, to: now)!
            var entry = createSampleEntry(fileName: "test\(i).zip")
            entry = DownloadHistoryEntry(
                id: entry.id,
                url: entry.url,
                fileName: entry.fileName,
                filePath: entry.filePath,
                fileSize: entry.fileSize,
                fileType: entry.fileType,
                startDate: date,
                status: entry.status
            )
            manager.addEntry(entry)
        }
        
        XCTAssertEqual(manager.history.count, 10)
        
        // Clear entries older than 5 days
        let cutoffDate = calendar.date(byAdding: .day, value: -5, to: now)!
        manager.clearHistoryOlderThan(cutoffDate)
        
        XCTAssertEqual(manager.history.count, 6) // 0-5 days (inclusive)
    }
    
    func testClearFailedDownloads() {
        let completed = createSampleEntry(fileName: "completed.zip", status: .completed)
        let failed1 = createSampleEntry(fileName: "failed1.zip", status: .failed)
        let failed2 = createSampleEntry(fileName: "failed2.zip", status: .failed)
        let cancelled = createSampleEntry(fileName: "cancelled.zip", status: .cancelled)
        
        [completed, failed1, failed2, cancelled].forEach { manager.addEntry($0) }
        
        XCTAssertEqual(manager.history.count, 4)
        
        manager.clearFailedDownloads()
        
        XCTAssertEqual(manager.history.count, 2)
        XCTAssertTrue(manager.history.allSatisfy { $0.status != .failed })
    }
    
    // MARK: - Filter Tests
    
    func testSearchFilter() {
        manager.addEntry(createSampleEntry(fileName: "document.pdf"))
        manager.addEntry(createSampleEntry(fileName: "image.jpg"))
        manager.addEntry(createSampleEntry(fileName: "video.mp4"))
        
        manager.filter.searchQuery = "doc"
        
        XCTAssertEqual(manager.filteredHistory.count, 1)
        XCTAssertEqual(manager.filteredHistory.first?.fileName, "document.pdf")
    }
    
    func testStatusFilter() {
        manager.addEntry(createSampleEntry(fileName: "test1.zip", status: .completed))
        manager.addEntry(createSampleEntry(fileName: "test2.zip", status: .failed))
        manager.addEntry(createSampleEntry(fileName: "test3.zip", status: .completed))
        
        manager.filter.status = .completed
        
        XCTAssertEqual(manager.filteredHistory.count, 2)
    }
    
    func testFileTypeFilter() {
        manager.addEntry(createSampleEntry(fileName: "doc.pdf", fileType: "pdf"))
        manager.addEntry(createSampleEntry(fileName: "pic.jpg", fileType: "jpg"))
        manager.addEntry(createSampleEntry(fileName: "vid.mp4", fileType: "mp4"))
        manager.addEntry(createSampleEntry(fileName: "doc2.pdf", fileType: "pdf"))
        
        manager.filter.fileType = "pdf"
        
        XCTAssertEqual(manager.filteredHistory.count, 2)
    }
    
    func testCategoryFilter() {
        manager.addEntry(createSampleEntry(fileName: "test1.zip", category: "Documents"))
        manager.addEntry(createSampleEntry(fileName: "test2.zip", category: "Images"))
        manager.addEntry(createSampleEntry(fileName: "test3.zip", category: "Documents"))
        
        manager.filter.category = "Documents"
        
        XCTAssertEqual(manager.filteredHistory.count, 2)
    }
    
    func testSourceWebsiteFilter() {
        manager.addEntry(createSampleEntry(fileName: "test1.zip", sourceWebsite: "example.com"))
        manager.addEntry(createSampleEntry(fileName: "test2.zip", sourceWebsite: "test.com"))
        manager.addEntry(createSampleEntry(fileName: "test3.zip", sourceWebsite: "example.com"))
        
        manager.filter.sourceWebsite = "example.com"
        
        XCTAssertEqual(manager.filteredHistory.count, 2)
    }
    
    func testDateRangeFilter() {
        let now = Date()
        let calendar = Calendar.current
        
        let today = createSampleEntry(fileName: "today.zip")
        manager.addEntry(today)
        
        var yesterday = createSampleEntry(fileName: "yesterday.zip")
        yesterday = DownloadHistoryEntry(
            id: yesterday.id,
            url: yesterday.url,
            fileName: yesterday.fileName,
            filePath: yesterday.filePath,
            fileSize: yesterday.fileSize,
            fileType: yesterday.fileType,
            startDate: calendar.date(byAdding: .day, value: -1, to: now)!,
            status: yesterday.status
        )
        manager.addEntry(yesterday)
        
        manager.filter.dateRange = .today
        
        XCTAssertEqual(manager.filteredHistory.count, 1)
        XCTAssertEqual(manager.filteredHistory.first?.fileName, "today.zip")
    }
    
    func testFileSizeFilter() {
        manager.addEntry(createSampleEntry(fileName: "small.zip", fileSize: 1024))
        manager.addEntry(createSampleEntry(fileName: "medium.zip", fileSize: 1024 * 1024))
        manager.addEntry(createSampleEntry(fileName: "large.zip", fileSize: 1024 * 1024 * 10))
        
        manager.filter.minFileSize = 1024 * 1024 // 1 MB
        
        XCTAssertEqual(manager.filteredHistory.count, 2)
    }
    
    func testTagsFilter() {
        var entry1 = createSampleEntry(fileName: "test1.zip")
        entry1 = DownloadHistoryEntry(
            id: entry1.id,
            url: entry1.url,
            fileName: entry1.fileName,
            filePath: entry1.filePath,
            fileSize: entry1.fileSize,
            fileType: entry1.fileType,
            status: entry1.status,
            tags: ["work", "important"]
        )
        manager.addEntry(entry1)
        
        var entry2 = createSampleEntry(fileName: "test2.zip")
        entry2 = DownloadHistoryEntry(
            id: entry2.id,
            url: entry2.url,
            fileName: entry2.fileName,
            filePath: entry2.filePath,
            fileSize: entry2.fileSize,
            fileType: entry2.fileType,
            status: entry2.status,
            tags: ["personal"]
        )
        manager.addEntry(entry2)
        
        manager.filter.tags = ["work"]
        
        XCTAssertEqual(manager.filteredHistory.count, 1)
        XCTAssertEqual(manager.filteredHistory.first?.fileName, "test1.zip")
    }
    
    func testMultipleFilters() {
        manager.addEntry(createSampleEntry(fileName: "work_doc.pdf", fileType: "pdf", category: "Work", status: .completed))
        manager.addEntry(createSampleEntry(fileName: "personal_pic.jpg", fileType: "jpg", category: "Personal", status: .completed))
        manager.addEntry(createSampleEntry(fileName: "work_sheet.pdf", fileType: "pdf", category: "Work", status: .failed))
        
        manager.filter.fileType = "pdf"
        manager.filter.category = "Work"
        manager.filter.status = .completed
        
        XCTAssertEqual(manager.filteredHistory.count, 1)
        XCTAssertEqual(manager.filteredHistory.first?.fileName, "work_doc.pdf")
    }
    
    func testClearFilters() {
        manager.filter.searchQuery = "test"
        manager.filter.status = .failed
        manager.filter.fileType = "pdf"
        
        XCTAssertFalse(manager.filter.isEmpty)
        
        manager.clearFilters()
        
        XCTAssertTrue(manager.filter.isEmpty)
    }
    
    // MARK: - Sort Tests
    
    func testSortByDateNewest() {
        let calendar = Calendar.current
        let now = Date()
        
        for i in 0..<5 {
            let date = calendar.date(byAdding: .hour, value: -i, to: now)!
            var entry = createSampleEntry(fileName: "test\(i).zip")
            entry = DownloadHistoryEntry(
                id: entry.id,
                url: entry.url,
                fileName: entry.fileName,
                filePath: entry.filePath,
                fileSize: entry.fileSize,
                fileType: entry.fileType,
                startDate: date,
                status: entry.status
            )
            manager.addEntry(entry)
        }
        
        manager.sortOption = .dateNewest
        
        let sorted = manager.filteredHistory
        for i in 0..<sorted.count - 1 {
            XCTAssertTrue(sorted[i].startDate >= sorted[i + 1].startDate)
        }
    }
    
    func testSortBySize() {
        manager.addEntry(createSampleEntry(fileName: "small.zip", fileSize: 1024))
        manager.addEntry(createSampleEntry(fileName: "large.zip", fileSize: 1024 * 1024 * 10))
        manager.addEntry(createSampleEntry(fileName: "medium.zip", fileSize: 1024 * 1024))
        
        manager.sortOption = .sizeLargest
        
        let sorted = manager.filteredHistory
        XCTAssertEqual(sorted[0].fileName, "large.zip")
        XCTAssertEqual(sorted[1].fileName, "medium.zip")
        XCTAssertEqual(sorted[2].fileName, "small.zip")
    }
    
    func testSortByName() {
        manager.addEntry(createSampleEntry(fileName: "charlie.zip"))
        manager.addEntry(createSampleEntry(fileName: "alice.zip"))
        manager.addEntry(createSampleEntry(fileName: "bob.zip"))
        
        manager.sortOption = .nameAZ
        
        let sorted = manager.filteredHistory
        XCTAssertEqual(sorted[0].fileName, "alice.zip")
        XCTAssertEqual(sorted[1].fileName, "bob.zip")
        XCTAssertEqual(sorted[2].fileName, "charlie.zip")
    }
    
    func testSortBySpeed() {
        manager.addEntry(createSampleEntry(fileName: "slow.zip", averageSpeed: 100_000))
        manager.addEntry(createSampleEntry(fileName: "fast.zip", averageSpeed: 1_000_000))
        manager.addEntry(createSampleEntry(fileName: "medium.zip", averageSpeed: 500_000))
        
        manager.sortOption = .speedFastest
        
        let sorted = manager.filteredHistory
        XCTAssertEqual(sorted[0].fileName, "fast.zip")
        XCTAssertEqual(sorted[1].fileName, "medium.zip")
        XCTAssertEqual(sorted[2].fileName, "slow.zip")
    }
    
    // MARK: - Statistics Tests
    
    func testStatisticsCalculation() {
        manager.addEntry(createSampleEntry(fileName: "test1.zip", fileSize: 1024 * 1024, status: .completed))
        manager.addEntry(createSampleEntry(fileName: "test2.zip", fileSize: 2 * 1024 * 1024, status: .completed))
        manager.addEntry(createSampleEntry(fileName: "test3.zip", fileSize: 3 * 1024 * 1024, status: .failed))
        
        manager.calculateStatistics()
        
        XCTAssertEqual(manager.statistics.totalDownloads, 3)
        XCTAssertEqual(manager.statistics.completedDownloads, 2)
        XCTAssertEqual(manager.statistics.failedDownloads, 1)
        XCTAssertEqual(manager.statistics.totalBytesDownloaded, 6 * 1024 * 1024)
    }
    
    func testTopFileTypesStatistics() {
        manager.addEntry(createSampleEntry(fileName: "doc1.pdf", fileType: "pdf"))
        manager.addEntry(createSampleEntry(fileName: "doc2.pdf", fileType: "pdf"))
        manager.addEntry(createSampleEntry(fileName: "pic.jpg", fileType: "jpg"))
        
        manager.calculateStatistics()
        
        XCTAssertFalse(manager.statistics.topFileTypes.isEmpty)
        let pdfCount = manager.statistics.topFileTypes.first { $0.fileType == "pdf" }?.count
        XCTAssertEqual(pdfCount, 2)
    }
    
    func testTopWebsitesStatistics() {
        manager.addEntry(createSampleEntry(fileName: "test1.zip", sourceWebsite: "example.com"))
        manager.addEntry(createSampleEntry(fileName: "test2.zip", sourceWebsite: "example.com"))
        manager.addEntry(createSampleEntry(fileName: "test3.zip", sourceWebsite: "test.com"))
        
        manager.calculateStatistics()
        
        XCTAssertFalse(manager.statistics.topWebsites.isEmpty)
        let exampleCount = manager.statistics.topWebsites.first { $0.website == "example.com" }?.count
        XCTAssertEqual(exampleCount, 2)
    }
    
    func testTopCategoriesStatistics() {
        manager.addEntry(createSampleEntry(fileName: "test1.zip", category: "Work"))
        manager.addEntry(createSampleEntry(fileName: "test2.zip", category: "Work"))
        manager.addEntry(createSampleEntry(fileName: "test3.zip", category: "Personal"))
        
        manager.calculateStatistics()
        
        XCTAssertFalse(manager.statistics.topCategories.isEmpty)
        let workCount = manager.statistics.topCategories.first { $0.category == "Work" }?.count
        XCTAssertEqual(workCount, 2)
    }
    
    // MARK: - Export Tests
    
    func testExportToCSV() {
        manager.addEntry(createSampleEntry(fileName: "test.zip"))
        
        let csv = manager.exportHistory(format: .csv)
        
        XCTAssertTrue(csv.contains("ID,URL,File Name"))
        XCTAssertTrue(csv.contains("test.zip"))
    }
    
    func testExportToJSON() {
        manager.addEntry(createSampleEntry(fileName: "test.zip"))
        
        let json = manager.exportHistory(format: .json)
        
        XCTAssertTrue(json.contains("fileName"))
        XCTAssertTrue(json.contains("test.zip"))
    }
    
    func testExportToText() {
        manager.addEntry(createSampleEntry(fileName: "test.zip"))
        
        let text = manager.exportHistory(format: .txt)
        
        XCTAssertTrue(text.contains("Download History Export"))
        XCTAssertTrue(text.contains("test.zip"))
    }
    
    func testExportToHTML() {
        manager.addEntry(createSampleEntry(fileName: "test.zip"))
        
        let html = manager.exportHistory(format: .html)
        
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("test.zip"))
        XCTAssertTrue(html.contains("<table>"))
    }
    
    // MARK: - Date Range Tests
    
    func testDateRangeToday() {
        let interval = DateRange.today.dateInterval()
        
        XCTAssertNotNil(interval)
        XCTAssertTrue(Calendar.current.isDateInToday(interval!.start))
    }
    
    func testDateRangeLast7Days() {
        let interval = DateRange.last7Days.dateInterval()
        
        XCTAssertNotNil(interval)
        
        let daysDiff = Calendar.current.dateComponents([.day], from: interval!.start, to: interval!.end).day
        XCTAssertEqual(daysDiff, 7)
    }
    
    func testDateRangeThisMonth() {
        let interval = DateRange.thisMonth.dateInterval()
        
        XCTAssertNotNil(interval)
        
        let calendar = Calendar.current
        let startMonth = calendar.component(.month, from: interval!.start)
        let nowMonth = calendar.component(.month, from: Date())
        XCTAssertEqual(startMonth, nowMonth)
    }
    
    // MARK: - Helper Methods
    
    private func createSampleEntry(
        fileName: String,
        fileType: String = "zip",
        fileSize: Int64 = 1024 * 1024,
        status: DownloadHistoryStatus = .completed,
        category: String? = nil,
        sourceWebsite: String? = nil,
        averageSpeed: Double = 1024 * 1024
    ) -> DownloadHistoryEntry {
        DownloadHistoryEntry(
            url: URL(string: "https://example.com/\(fileName)")!,
            fileName: fileName,
            filePath: "/Downloads/\(fileName)",
            fileSize: fileSize,
            fileType: fileType,
            status: status,
            averageSpeed: averageSpeed,
            category: category,
            sourceWebsite: sourceWebsite
        )
    }
}
