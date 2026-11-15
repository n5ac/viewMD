//
//  FolderAccessStore.swift
//  viewMD
//
//  Remembers folders the user has granted access to, so the sandboxed app can
//  show images that sit next to a document (REQ-022).
//
//  Copyright (C) 2026 Stephen Hicks, N5AC
//
//  This file is part of viewMD.
//
//  viewMD is free software: you can redistribute it and/or modify it under
//  the terms of the GNU General Public License as published by the Free
//  Software Foundation, either version 3 of the License, or (at your option)
//  any later version.
//
//  viewMD is distributed in the hope that it will be useful, but WITHOUT ANY
//  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
//  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
//  details.
//
//  You should have received a copy of the GNU General Public License along
//  with viewMD. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

/// Stores security-scoped bookmarks for folders the user granted access to.
///
/// The app is sandboxed: opening a document grants access to that one file,
/// not to the images beside it. When the preview hits that limit, the window
/// offers "Grant Access…", and the user picks the folder in an open panel.
/// The resulting bookmark is saved here, so access survives relaunches.
@MainActor
final class FolderAccessStore {

    /// The shared store used by the app.
    static let shared = FolderAccessStore(defaults: .standard)

    /// The `UserDefaults` key holding `[folder path: bookmark data]`.
    static let defaultsKey = "viewMD.folderBookmarks"

    private let defaults: UserDefaults

    /// Folders whose security scope is currently open. Access is kept for the
    /// life of the app; the set is small (one entry per granted folder that
    /// has been used).
    private var accessing: Set<String> = []

    /// Creates a store.
    ///
    /// - Parameter defaults: Where bookmarks are persisted (injectable for
    ///   tests).
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The paths of all granted folders.
    var grantedFolderPaths: [String] {
        Array(bookmarks.keys).sorted()
    }

    /// Saves a bookmark for a folder the user picked in an open panel, and
    /// starts accessing it.
    ///
    /// - Parameter folder: The folder URL returned by `NSOpenPanel`.
    /// - Throws: Any error from creating the bookmark.
    func grant(_ folder: URL) throws {
        let data = try folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        var all = bookmarks
        all[Self.key(for: folder)] = data
        defaults.set(all, forKey: Self.defaultsKey)
        startAccessing(folder: folder)
    }

    /// Opens the security scope of the granted folder that contains `file`,
    /// if there is one. Safe to call repeatedly.
    ///
    /// - Parameter file: A file the preview wants to read.
    func startAccessingGrantedFolder(containing file: URL) {
        guard let path = Self.grantedFolder(containing: file.standardizedFileURL.path, among: grantedFolderPaths),
              !accessing.contains(path),
              let data = bookmarks[path] else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return
        }
        if isStale { try? grant(url) }
        startAccessing(folder: url)
    }

    /// Returns the deepest granted folder that contains `filePath`, or `nil`.
    ///
    /// - Parameters:
    ///   - filePath: An absolute, standardized file path.
    ///   - folders: Granted folder paths.
    /// - Returns: The matching folder path.
    nonisolated static func grantedFolder(containing filePath: String, among folders: [String]) -> String? {
        folders
            .filter { folder in
                let prefix = folder.hasSuffix("/") ? folder : folder + "/"
                return filePath.hasPrefix(prefix)
            }
            .max { $0.count < $1.count }
    }

    /// The dictionary key for a folder: its standardized path.
    private static func key(for folder: URL) -> String {
        folder.standardizedFileURL.path
    }

    private var bookmarks: [String: Data] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]
    }

    private func startAccessing(folder: URL) {
        let key = Self.key(for: folder)
        guard !accessing.contains(key), folder.startAccessingSecurityScopedResource() else { return }
        accessing.insert(key)
    }
}
