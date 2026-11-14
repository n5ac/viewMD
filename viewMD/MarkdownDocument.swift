//
//  MarkdownDocument.swift
//  viewMD
//
//  Created by Stephen Hicks on 11/14/26.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The Markdown text type (`net.daringfireball.markdown`, extensions `.md`
    /// and `.markdown`).
    ///
    /// Declared as an imported type in `Info.plist` so the app works whether
    /// or not another app on the system has already declared it.
    /// `nonisolated` because the app target defaults to main-actor isolation
    /// and the nonisolated document type reads it.
    nonisolated static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A Markdown file opened in a viewMD window.
///
/// The document holds the raw Markdown source as a `String`. That source is
/// the single source of truth: the rendered pane and the source pane are both
/// views of it (see `docs/PLAN.md`).
///
/// Reading and writing are implemented in terms of `Data` (``init(data:)`` and
/// ``data()``) so they can be unit tested without SwiftUI's file
/// configurations, which can't be constructed in tests.
nonisolated struct MarkdownDocument: FileDocument {
    /// The Markdown source text.
    var text: String

    /// Creates a document with the given Markdown source.
    ///
    /// - Parameter text: The initial Markdown source. New documents start empty.
    init(text: String = "") {
        self.text = text
    }

    /// Types viewMD can open: Markdown, plus any plain text file.
    static let readableContentTypes: [UTType] = [.markdown, .plainText]

    /// Types viewMD can save. Markdown comes first, so new documents are saved
    /// as `.md`; plain text is kept so an opened `.txt` file saves in place.
    static let writableContentTypes: [UTType] = [.markdown, .plainText]

    /// Decodes a document from file contents.
    ///
    /// Files are expected to be UTF-8 (the de facto encoding for Markdown).
    /// A UTF-8 byte-order mark is dropped. UTF-16 is accepted only when the
    /// file starts with a UTF-16 byte-order mark, because without one any
    /// even-length byte sequence would "decode" as garbage.
    ///
    /// - Parameter data: The raw file contents.
    /// - Throws: `CocoaError(.fileReadInapplicableStringEncoding)` if the data
    ///   isn't valid UTF-8 or BOM-marked UTF-16.
    init(data: Data) throws {
        let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
        let bytes = [UInt8](data.prefix(3))
        if bytes == utf8BOM, let string = String(data: data.dropFirst(3), encoding: .utf8) {
            text = string
        } else if let string = String(data: data, encoding: .utf8) {
            text = string
        } else if bytes.count >= 2,
                  (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF),
                  let string = String(data: data, encoding: .utf16) {
            // `.utf16` reads the BOM to pick the byte order and strips it.
            text = string
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    /// Encodes the document's text for saving, always as UTF-8 without a BOM.
    ///
    /// - Returns: The UTF-8 bytes of ``text``.
    func data() -> Data {
        Data(text.utf8)
    }

    /// Reads a document from disk (called by SwiftUI's `DocumentGroup`).
    ///
    /// - Parameter configuration: The file to read.
    /// - Throws: `CocoaError(.fileReadCorruptFile)` if the file has no
    ///   contents, or any error from ``init(data:)``.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    /// Produces the file to save (called by SwiftUI's `DocumentGroup`).
    ///
    /// - Parameter configuration: The save context (unused; the output is
    ///   the same for every writable type).
    /// - Returns: A regular-file wrapper containing ``data()``.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data())
    }
}
