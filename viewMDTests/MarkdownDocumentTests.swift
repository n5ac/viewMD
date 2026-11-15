//
//  MarkdownDocumentTests.swift
//  viewMDTests
//
//  Unit tests for `MarkdownDocument` reading and writing (REQ-010).
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
import Testing
import UniformTypeIdentifiers
@testable import viewMD

@Suite("MarkdownDocument")
struct MarkdownDocumentTests {

    @Test("New documents start empty")
    func newDocumentIsEmpty() {
        #expect(MarkdownDocument().text == "")
    }

    @Test("UTF-8 content round-trips unchanged", arguments: [
        "",
        "# Title\n\nSome *text*.\n",
        "Unicode: café, naïve, 日本語, emoji 🎉\n",
        "Windows line endings\r\nare kept\r\n",
        "No trailing newline",
    ])
    func utf8RoundTrip(source: String) throws {
        let document = try MarkdownDocument(data: Data(source.utf8))
        #expect(document.text == source)
        #expect(document.data() == Data(source.utf8))
    }

    @Test("A UTF-8 byte-order mark is dropped on read")
    func utf8BOMIsStripped() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("# Hi".utf8)
        let document = try MarkdownDocument(data: data)
        #expect(document.text == "# Hi")
        // Saving writes plain UTF-8 with no BOM.
        #expect(document.data() == Data("# Hi".utf8))
    }

    @Test("UTF-16 with a byte-order mark is accepted", arguments: [
        String.Encoding.utf16LittleEndian, .utf16BigEndian,
    ])
    func utf16WithBOM(encoding: String.Encoding) throws {
        let bom: [UInt8] = encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]
        let data = Data(bom) + "# Hi".data(using: encoding)!
        let document = try MarkdownDocument(data: data)
        #expect(document.text == "# Hi")
    }

    @Test("Data that isn't UTF-8 or BOM-marked UTF-16 is rejected")
    func invalidDataThrows() {
        // 0xC3 starts a two-byte UTF-8 sequence; 0x28 is not a valid continuation.
        let data = Data([0x23, 0x20, 0xC3, 0x28])
        #expect(throws: CocoaError.self) {
            try MarkdownDocument(data: data)
        }
    }

    @Test("Markdown is the default type and conforms to plain text")
    func contentTypes() {
        #expect(UTType.markdown.identifier == "net.daringfireball.markdown")
        #expect(UTType.markdown.conforms(to: .plainText))
        #expect(MarkdownDocument.writableContentTypes.first == .markdown)
        #expect(MarkdownDocument.readableContentTypes.contains(.plainText))
    }

    @Test("The .md and .markdown extensions map to the Markdown type", arguments: ["md", "markdown"])
    func extensionsMapToMarkdown(fileExtension: String) {
        let type = UTType(filenameExtension: fileExtension)
        #expect(type?.conforms(to: .markdown) == true)
    }
}
