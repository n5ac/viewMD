//
//  MarkdownPackageTests.swift
//  viewMDTests
//
//  Smoke test that Apple's swift-markdown package is linked and parses GFM
//  extensions (REQ-006, REQ-016). The full renderer tests arrive in Phase 1.
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

import Markdown
import Testing

@Suite("swift-markdown package")
struct MarkdownPackageTests {

    @Test("Parses a GFM table and a strikethrough")
    func parsesGFMExtensions() {
        let document = Document(parsing: """
            | A | B |
            |---|---|
            | 1 | 2 |

            ~~gone~~
            """)
        let children = Array(document.children)
        #expect(children.first is Table)
        let paragraph = children.last as? Paragraph
        #expect(paragraph?.children.contains { $0 is Strikethrough } == true)
    }

    @Test("Reports source line ranges for blocks (needed for two-way editing)")
    func reportsSourceRanges() throws {
        let document = Document(parsing: "# Title\n\nBody text.\n")
        let paragraph = try #require(document.child(at: 1))
        #expect(paragraph.range?.lowerBound.line == 3)
    }
}
