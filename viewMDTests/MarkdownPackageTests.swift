//
//  MarkdownPackageTests.swift
//  viewMDTests
//
//  Smoke test that Apple's swift-markdown package is linked and parses GFM
//  extensions (REQ-006, REQ-016). The full renderer tests arrive in Phase 1.
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
