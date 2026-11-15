//
//  LinkRouter.swift
//  viewMD
//
//  Decides what happens when the user opens a link in the rendered pane
//  (REQ-022).
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
import UniformTypeIdentifiers

/// Where an activated link should go.
nonisolated enum LinkDestination: Equatable {
    /// Open in the default browser or mail app (`http`, `https`, `mailto`, …).
    case external(URL)
    /// Open a local Markdown file in viewMD.
    case markdownDocument(URL)
    /// Open a local file in its default app.
    case localFile(URL)
    /// Do nothing (unknown or unsafe link).
    case ignore
}

/// Routes links from the preview to the right place.
nonisolated enum LinkRouter {

    /// Schemes handed to the system (browser, Mail, FaceTime, …).
    private static let externalSchemes: Set<String> = ["http", "https", "mailto", "tel", "facetime", "ftp"]

    /// Returns where a link should go.
    ///
    /// Local links arrive as `viewmd://doc/<path>`, because the renderer
    /// resolved them against the document folder. They're converted back to
    /// file URLs here, and any `#fragment` is dropped.
    ///
    /// - Parameter url: The link's absolute URL as the page reports it.
    /// - Returns: The destination.
    static func destination(for url: URL) -> LinkDestination {
        guard let scheme = url.scheme?.lowercased() else { return .ignore }
        if externalSchemes.contains(scheme) {
            return .external(url)
        }
        if scheme == PreviewURLs.scheme, case .file(let fileURL) = PreviewURLs.resource(for: url) {
            return isMarkdown(fileURL) ? .markdownDocument(fileURL) : .localFile(fileURL)
        }
        if scheme == "file" {
            return isMarkdown(url) ? .markdownDocument(url) : .localFile(url)
        }
        return .ignore
    }

    /// Whether a file looks like Markdown, by extension.
    private static func isMarkdown(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "mdown" || ext == "mkd"
    }
}
