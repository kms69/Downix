//
//  DownloadFolderStore.swift
//  The default download folder plus the user's own folders (IDM-style
//  "categories"). Used by the confirmation window and by every download engine.
//

import Foundation
import SwiftUI

@MainActor
final class DownloadFolderStore: ObservableObject {
    static let shared = DownloadFolderStore()

    private let defaultKey = "defaultDownloadFolder"
    private let listKey = "customDownloadFolders"

    @Published private(set) var defaultFolder: URL
    @Published private(set) var folders: [URL]

    private static var systemDownloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private init() {
        let d = UserDefaults.standard
        if let path = d.string(forKey: defaultKey), !path.isEmpty {
            defaultFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            defaultFolder = Self.systemDownloads
        }
        folders = (d.stringArray(forKey: listKey) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The default folder, falling back to ~/Downloads if it no longer exists.
    var resolvedDefault: URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: defaultFolder.path, isDirectory: &isDir), isDir.boolValue {
            return defaultFolder
        }
        return Self.systemDownloads
    }

    /// Folders to offer in the picker: default first, then Downloads, then custom ones.
    var choices: [URL] {
        var result: [URL] = [resolvedDefault]
        for url in [Self.systemDownloads] + folders where !result.contains(where: { $0.path == url.path }) {
            if FileManager.default.fileExists(atPath: url.path) { result.append(url) }
        }
        return result
    }

    func setDefault(_ url: URL) {
        defaultFolder = url
        UserDefaults.standard.set(url.path, forKey: defaultKey)
        DownloadManager.shared.defaultSaveLocation = url
        remember(url)
    }

    /// Keep a folder the user picked so it shows up in the list next time.
    func remember(_ url: URL) {
        guard url.path != Self.systemDownloads.path else { return }
        folders.removeAll { $0.path == url.path }
        folders.insert(url, at: 0)
        if folders.count > 12 { folders = Array(folders.prefix(12)) }
        UserDefaults.standard.set(folders.map { $0.path }, forKey: listKey)
    }

    func forget(_ url: URL) {
        folders.removeAll { $0.path == url.path }
        UserDefaults.standard.set(folders.map { $0.path }, forKey: listKey)
    }

    static func display(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
