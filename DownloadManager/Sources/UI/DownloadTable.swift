//
//  DownloadTable.swift
//  Download Manager for Mac
//
//  Main download table. The native column headers are the sorting UI;
//  on macOS 14+ the header context menu also lets the user hide or
//  reorder columns.
//

import Foundation
import SwiftUI

enum DownloadColumnLayout {
    static let size: CGFloat = 80
    static let status: CGFloat = 120
    static let speed: CGFloat = 90
    static let remaining: CGFloat = 130
    static let lastTry: CGFloat = 120
}

/// macOS 14+ table with user-customizable columns. Visibility and order are
/// persisted in user defaults, keyed by the customization identifiers below.
@available(macOS 14.0, *)
struct DownloadTable: View {
    let downloads: [DownloadTask]
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<DownloadTask>]

    @AppStorage("downloadTableColumns")
    private var columnCustomization = TableColumnCustomization<DownloadTask>()

    var body: some View {
        Table(downloads, selection: $selection, sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            TableColumn("File Name", value: \DownloadTask.filename) { download in
                DownloadNameCell(download: download)
            }
            .width(min: 180, ideal: 230, max: 10_000)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Size", value: \DownloadTask.totalBytes) { download in
                DownloadSizeCell(download: download)
            }
            .width(DownloadColumnLayout.size)
            .customizationID("size")

            TableColumn("Status", value: \DownloadTask.statusSortRank) { download in
                DownloadStatusCell(download: download)
            }
            .width(DownloadColumnLayout.status)
            .customizationID("status")

            TableColumn("Speed") { download in
                DownloadSpeedCell(download: download)
            }
            .width(DownloadColumnLayout.speed)
            .customizationID("speed")

            TableColumn("Remaining Time") { download in
                DownloadTimeLeftCell(download: download)
            }
            .width(DownloadColumnLayout.remaining)
            .customizationID("remaining")

            TableColumn("Last Try", value: \DownloadTask.lastAttemptSortValue,
                        comparator: NewestFirstDateComparator()) { download in
                DownloadLastTryCell(download: download)
            }
            .width(DownloadColumnLayout.lastTry)
            .customizationID("lastTry")
        }
    }
}

/// macOS 13 fallback: same columns and header sorting, without the
/// column customization API.
struct LegacyDownloadTable: View {
    let downloads: [DownloadTask]
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<DownloadTask>]

    var body: some View {
        Table(downloads, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("File Name", value: \DownloadTask.filename) { download in
                DownloadNameCell(download: download)
            }
            .width(min: 180, ideal: 230, max: 10_000)

            TableColumn("Size", value: \DownloadTask.totalBytes) { download in
                DownloadSizeCell(download: download)
            }
            .width(DownloadColumnLayout.size)

            TableColumn("Status", value: \DownloadTask.statusSortRank) { download in
                DownloadStatusCell(download: download)
            }
            .width(DownloadColumnLayout.status)

            TableColumn("Speed") { download in
                DownloadSpeedCell(download: download)
            }
            .width(DownloadColumnLayout.speed)

            TableColumn("Remaining Time") { download in
                DownloadTimeLeftCell(download: download)
            }
            .width(DownloadColumnLayout.remaining)

            TableColumn("Last Try", value: \DownloadTask.lastAttemptSortValue,
                        comparator: NewestFirstDateComparator()) { download in
                DownloadLastTryCell(download: download)
            }
            .width(DownloadColumnLayout.lastTry)
        }
    }
}
