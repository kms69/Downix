//
//  DownloadSortStore.swift
//  Saves the main table's sort column and direction (e.g. Last Try, newest
//  first) so the list comes back the way you left it.
//

import Foundation

enum DownloadSortStore {
    private static let key = "downloadTableSort.v1"

    static func save(_ order: [KeyPathComparator<DownloadTask>]) {
        guard let first = order.first else { return }
        let column: String
        if first.keyPath == \DownloadTask.filename { column = "filename" }
        else if first.keyPath == \DownloadTask.totalBytes { column = "size" }
        else if first.keyPath == \DownloadTask.statusSortRank { column = "status" }
        else if first.keyPath == \DownloadTask.lastAttemptSortValue { column = "lastTry" }
        else { return }
        UserDefaults.standard.set(["column": column,
                                   "forward": first.order == .forward ? "1" : "0"],
                                  forKey: key)
    }

    static func load() -> [KeyPathComparator<DownloadTask>] {
        let fallback = [KeyPathComparator(\DownloadTask.filename)]
        guard let d = UserDefaults.standard.dictionary(forKey: key) as? [String: String],
              let column = d["column"] else { return fallback }
        let order: SortOrder = d["forward"] == "1" ? .forward : .reverse
        switch column {
        case "filename": return [KeyPathComparator(\DownloadTask.filename, order: order)]
        case "size": return [KeyPathComparator(\DownloadTask.totalBytes, order: order)]
        case "status": return [KeyPathComparator(\DownloadTask.statusSortRank, order: order)]
        case "lastTry":
            return [KeyPathComparator(\DownloadTask.lastAttemptSortValue,
                                      comparator: NewestFirstDateComparator(order: order),
                                      order: order)]
        default: return fallback
        }
    }
}
