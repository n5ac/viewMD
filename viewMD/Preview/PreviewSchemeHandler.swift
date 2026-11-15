//
//  PreviewSchemeHandler.swift
//  viewMD
//
//  Serves the preview page and the document's local images to the WKWebView
//  through a private URL scheme (REQ-006, REQ-022).
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
import WebKit

/// Maps `viewmd:` URLs to content.
///
/// The preview page is loaded from `viewmd://app/preview.html`, and its CSS
/// and scripts from the same origin, all bundled in the app, so nothing is
/// fetched from the network. Local files the document references, such as
/// images, are served from `viewmd://doc/<absolute path>`. The renderer
/// resolves relative URLs against ``documentBaseURL(forFolder:)``.
///
/// Using a custom scheme rather than `file:` URLs means the app process does
/// the reading. That's where the sandbox access granted to the document (and
/// to folders the user grants through ``FolderAccessStore``) lives.
nonisolated enum PreviewURLs {

    /// The private URL scheme.
    static let scheme = "viewmd"

    /// The URL of the preview page.
    static let pageURL = URL(string: "viewmd://app/preview.html")!

    /// The bundled resources the `app` host may serve. Anything else is
    /// refused.
    static let bundledResources: Set<String> = [
        "preview.html", "preview.css", "bridge.js",
        "highlight.min.js", "highlight-github.css", "highlight-github-dark.css",
    ]

    /// What a `viewmd:` URL refers to.
    enum Resource: Equatable {
        /// A bundled resource, by file name.
        case bundled(String)
        /// A local file, by file URL.
        case file(URL)
        /// Not a valid preview URL.
        case invalid
    }

    /// The base URL that relative links and images in a document resolve
    /// against: `viewmd://doc/<folder path>/`.
    ///
    /// - Parameter folder: The folder containing the document.
    /// - Returns: The base URL for the renderer.
    static func documentBaseURL(forFolder folder: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "doc"
        let path = folder.standardizedFileURL.path
        components.path = path.hasSuffix("/") ? path : path + "/"
        return components.url!
    }

    /// Classifies a request URL.
    ///
    /// - Parameter url: The URL WebKit asked for.
    /// - Returns: The resource it names.
    static func resource(for url: URL) -> Resource {
        guard url.scheme == scheme else { return .invalid }
        switch url.host {
        case "app":
            let name = url.lastPathComponent
            return bundledResources.contains(name) && url.path == "/" + name ? .bundled(name) : .invalid
        case "doc":
            let path = url.path // percent-decoded
            guard path.hasPrefix("/") else { return .invalid }
            return .file(URL(fileURLWithPath: path).standardizedFileURL)
        default:
            return .invalid
        }
    }

    /// The MIME type for a file name, from its extension.
    ///
    /// - Parameter name: A file name or path.
    /// - Returns: The MIME type, or `application/octet-stream` if unknown.
    static func mimeType(for name: String) -> String {
        let pathExtension = (name as NSString).pathExtension
        return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

/// The `WKURLSchemeHandler` that serves ``PreviewURLs`` content.
@MainActor
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {

    /// Grants access to folders the user has approved.
    let folderAccess: FolderAccessStore

    /// Called when a local file couldn't be read because the sandbox denies
    /// access, so the UI can offer to grant folder access.
    var onAccessDenied: ((URL) -> Void)?

    /// Creates a handler.
    ///
    /// - Parameter folderAccess: The store of granted folders.
    init(folderAccess: FolderAccessStore) {
        self.folderAccess = folderAccess
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        switch PreviewURLs.resource(for: url) {
        case .bundled(let name):
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            guard let fileURL = Bundle.main.url(forResource: base, withExtension: ext),
                  let data = try? Data(contentsOf: fileURL) else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            respond(task, url: url, data: data, mimeType: PreviewURLs.mimeType(for: name))
        case .file(let fileURL):
            folderAccess.startAccessingGrantedFolder(containing: fileURL)
            do {
                let data = try Data(contentsOf: fileURL)
                respond(task, url: url, data: data, mimeType: PreviewURLs.mimeType(for: fileURL.path))
            } catch {
                if Self.isPermissionError(error) { onAccessDenied?(fileURL) }
                task.didFailWithError(error)
            }
        case .invalid:
            task.didFailWithError(URLError(.unsupportedURL))
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // Responses are delivered synchronously in start(), so there's
        // nothing in flight to cancel.
    }

    /// Sends a complete response for a task.
    private func respond(_ task: any WKURLSchemeTask, url: URL, data: Data, mimeType: String) {
        var headers = ["Content-Type": mimeType, "Content-Length": String(data.count), "Cache-Control": "no-store"]
        if mimeType == "text/html" {
            headers["Content-Type"] = "text/html; charset=utf-8"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// Whether an error from reading a file means "not permitted" (sandbox),
    /// as opposed to "doesn't exist".
    nonisolated static func isPermissionError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == Int(EPERM) || underlying.code == Int(EACCES) {
            return true
        }
        return false
    }
}
