//
//  ExportController.swift
//  viewMD
//
//  The user-facing export flow: ask where to save, build the file, write it
//  (REQ-017, REQ-018).
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

import AppKit
import UniformTypeIdentifiers

/// The export formats viewMD offers.
enum ExportFormat: CaseIterable, Sendable {
    /// A standalone `.html` file.
    case html
    /// A paginated `.pdf` file.
    case pdf

    /// The menu title.
    var menuTitle: String {
        switch self {
        case .html: return "Export as HTML…"
        case .pdf: return "Export as PDF…"
        }
    }

    /// The file type written.
    var contentType: UTType {
        switch self {
        case .html: return .html
        case .pdf: return .pdf
        }
    }
}

/// Runs exports for a document window.
@MainActor
enum ExportController {

    /// The default export file name: the document's name with the export
    /// extension, or "Untitled" for an unsaved document.
    ///
    /// - Parameters:
    ///   - fileURL: The document's location, if saved.
    ///   - format: The export format.
    /// - Returns: A file name such as `Notes.pdf`.
    static func suggestedFileName(for fileURL: URL?, format: ExportFormat) -> String {
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        return base + "." + (format.contentType.preferredFilenameExtension ?? "")
    }

    /// Asks where to save, then writes the export.
    ///
    /// - Parameters:
    ///   - format: HTML or PDF.
    ///   - markdown: The document's Markdown source.
    ///   - fileURL: The document's location, if saved (for the default name,
    ///     folder and local images).
    ///   - window: The document window, for the save sheet and error alerts.
    static func export(_ format: ExportFormat, markdown: String, fileURL: URL?, window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = suggestedFileName(for: fileURL, format: format)
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = "Export"
        panel.message = format == .html
            ? "Export a standalone web page. Relative images keep their paths, so save it next to the document to keep them."
            : "Export a paginated PDF."

        let title = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try await makeData(format, markdown: markdown, title: title, fileURL: fileURL)
                    try data.write(to: destination, options: .atomic)
                } catch {
                    let alert = NSAlert(error: error)
                    if let window { alert.beginSheetModal(for: window, completionHandler: nil) } else { alert.runModal() }
                }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: completion) } else { completion(panel.runModal()) }
    }

    /// Builds the exported file's contents.
    ///
    /// - Parameters:
    ///   - format: HTML or PDF.
    ///   - markdown: The Markdown source.
    ///   - title: The document title.
    ///   - fileURL: The document's location, if saved.
    /// - Returns: The file data.
    /// - Throws: ``PDFExportError`` for PDF failures.
    static func makeData(_ format: ExportFormat, markdown: String, title: String, fileURL: URL?) async throws -> Data {
        let exporter = HTMLExporter()
        switch format {
        case .html:
            return Data(exporter.makeHTML(markdown: markdown, title: title).utf8)
        case .pdf:
            // Resolve local images through the preview scheme so the
            // sandboxed app can load them.
            let base = fileURL.map { PreviewURLs.documentBaseURL(forFolder: $0.deletingLastPathComponent()) }
            let html = exporter.makeHTML(markdown: markdown, title: title, baseURL: base)
            return try await PDFExporter().makePDF(html: html)
        }
    }
}
