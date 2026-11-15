//
//  MarkdownRendererTests.swift
//  viewMDTests
//
//  Unit tests for MarkdownRenderer: GFM output (REQ-016), source line tags
//  (REQ-013), sanitizing (REQ-007) and relative URLs (REQ-022).
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
@testable import viewMD

/// Renders `source` with no base URL and returns the HTML body.
private func html(_ source: String, baseURL: URL? = nil) -> String {
    MarkdownRenderer(baseURL: baseURL).render(source).html
}

@Suite("MarkdownRenderer: block elements")
struct RendererBlockTests {

    @Test("An empty document renders nothing")
    func emptyDocument() {
        #expect(MarkdownRenderer().render("").blocks.isEmpty)
        #expect(html("\n\n") == "")
    }

    @Test("Paragraphs are tagged with their source lines")
    func paragraph() {
        #expect(html("Hello\nworld") == "<p data-src=\"1-2\">Hello\nworld</p>\n")
    }

    @Test("Headings get levels and GitHub-style anchor ids", arguments: [
        ("# Title", "<h1 data-src=\"1-1\" id=\"title\">Title</h1>\n"),
        ("###### Six", "<h6 data-src=\"1-1\" id=\"six\">Six</h6>\n"),
        ("## Hello, World! 2", "<h2 data-src=\"1-1\" id=\"hello-world-2\">Hello, World! 2</h2>\n"),
        ("Setext\n===", "<h1 data-src=\"1-2\" id=\"setext\">Setext</h1>\n"),
    ])
    func headings(source: String, expected: String) {
        #expect(html(source) == expected)
    }

    @Test("Duplicate heading slugs are numbered")
    func duplicateSlugs() {
        let output = html("# A\n\n# A\n\n# A")
        #expect(output.contains("id=\"a\""))
        #expect(output.contains("id=\"a-1\""))
        #expect(output.contains("id=\"a-2\""))
    }

    @Test("Fenced code keeps its text, escapes HTML, and records the language")
    func fencedCode() {
        let output = html("```swift title\nlet a = 1 < 2 && b\n```")
        #expect(output == "<pre data-src=\"1-3\"><code class=\"language-swift\">let a = 1 &lt; 2 &amp;&amp; b\n</code></pre>\n")
    }

    @Test("Indented code has no language class")
    func indentedCode() {
        #expect(html("    code") == "<pre data-src=\"1-1\"><code>code\n</code></pre>\n")
    }

    @Test("Block quotes contain paragraphs")
    func blockQuote() {
        #expect(html("> quoted\n> text") == "<blockquote data-src=\"1-2\">\n<p>quoted\ntext</p>\n</blockquote>\n")
    }

    @Test("Thematic break")
    func thematicBreak() {
        #expect(html("---") == "<hr data-src=\"1-1\" />\n")
    }

    @Test("Tight lists render items without <p>")
    func tightList() {
        #expect(html("- a\n- b") == "<ul data-src=\"1-2\">\n<li>a</li>\n<li>b</li>\n</ul>\n")
    }

    @Test("Loose lists render items with <p>")
    func looseList() {
        #expect(html("- a\n\n- b") == "<ul data-src=\"1-3\">\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n")
    }

    @Test("A blank line inside one item makes the whole list loose")
    func looseByInnerBlankLine() {
        let output = html("- a\n- b\n\n  more\n- c")
        #expect(output.contains("<li>\n<p>a</p>\n</li>"))
        #expect(output.contains("<p>more</p>"))
    }

    @Test("Ordered lists keep a non-1 start number")
    func orderedListStart() {
        #expect(html("1. one\n2. two").hasPrefix("<ol data-src=\"1-2\">\n"))
        #expect(html("3. three\n4. four").hasPrefix("<ol data-src=\"1-2\" start=\"3\">\n"))
    }

    @Test("Nested lists render inside their parent item")
    func nestedList() {
        #expect(html("- a\n  - b") == "<ul data-src=\"1-2\">\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n")
    }

    @Test("Task list items render disabled checkboxes")
    func taskList() {
        let output = html("- [ ] todo\n- [x] done")
        #expect(output.hasPrefix("<ul data-src=\"1-2\" class=\"contains-task-list\">"))
        #expect(output.contains("<li class=\"task-list-item\"><input type=\"checkbox\" disabled=\"\" /> todo</li>"))
        #expect(output.contains("<li class=\"task-list-item\"><input type=\"checkbox\" disabled=\"\" checked=\"\" /> done</li>"))
    }

    @Test("Tables render head, body and column alignment")
    func table() {
        let source = """
            | L | C | R | N |
            |:--|:-:|--:|---|
            | 1 | 2 | 3 | 4 |
            """
        let output = html(source)
        #expect(output.hasPrefix("<table data-src=\"1-3\">\n<thead>\n<tr>\n"))
        #expect(output.contains("<th style=\"text-align: left\">L</th>"))
        #expect(output.contains("<th style=\"text-align: center\">C</th>"))
        #expect(output.contains("<th style=\"text-align: right\">R</th>"))
        #expect(output.contains("<th>N</th>"))
        #expect(output.contains("<tbody>\n<tr>\n<td style=\"text-align: left\">1</td>"))
        #expect(output.hasSuffix("</tbody>\n</table>\n"))
    }

    @Test("A header-only table has no tbody")
    func headerOnlyTable() {
        #expect(!html("| a |\n|---|").contains("<tbody>"))
    }
}

@Suite("MarkdownRenderer: inline elements")
struct RendererInlineTests {

    @Test("Emphasis, strong, strikethrough and code spans", arguments: [
        ("*em* _em_", "<em>em</em> <em>em</em>"),
        ("**strong** __strong__", "<strong>strong</strong> <strong>strong</strong>"),
        ("~~gone~~", "<del>gone</del>"),
        ("`a < b`", "<code>a &lt; b</code>"),
        ("***both***", "<em><strong>both</strong></em>"),
    ])
    func inlineFormatting(source: String, inner: String) {
        #expect(html(source) == "<p data-src=\"1-1\">\(inner)</p>\n")
    }

    @Test("Special characters in text are escaped")
    func escaping() {
        #expect(html("a < b & \"c\" > d") == "<p data-src=\"1-1\">a &lt; b &amp; &quot;c&quot; &gt; d</p>\n")
    }

    @Test("Smart punctuation is off: quotes and dashes render as typed")
    func noSmartPunctuation() {
        let output = html("\"quote\" 'single' -- ---x ...")
        #expect(output.contains("&quot;quote&quot; 'single' -- ---x ..."))
    }

    @Test("Hard line breaks (two spaces or backslash) become <br />")
    func hardBreaks() {
        #expect(html("a  \nb") == "<p data-src=\"1-2\">a<br />\nb</p>\n")
        #expect(html("a\\\nb") == "<p data-src=\"1-2\">a<br />\nb</p>\n")
    }

    @Test("Links render with href and title")
    func links() {
        #expect(html("[x](https://e.com \"T\")") == "<p data-src=\"1-1\"><a href=\"https://e.com\" title=\"T\">x</a></p>\n")
        #expect(html("[x](https://e.com)") == "<p data-src=\"1-1\"><a href=\"https://e.com\">x</a></p>\n")
    }

    @Test("Reference-style links resolve")
    func referenceLinks() {
        #expect(html("[x][r]\n\n[r]: https://e.com").contains("<a href=\"https://e.com\">x</a>"))
    }

    @Test("Images render with alt text from their label")
    func images() {
        #expect(html("![a *b*](pic.png \"T\")") == "<p data-src=\"1-1\"><img src=\"pic.png\" alt=\"a b\" title=\"T\" /></p>\n")
    }

    @Test("Script URLs are dropped from links and images; the text stays")
    func unsafeURLs() {
        #expect(html("[click](javascript:alert(1))") == "<p data-src=\"1-1\">click</p>\n")
        #expect(html("![pic](javascript:alert(1))") == "<p data-src=\"1-1\">pic</p>\n")
        #expect(html("[x](data:text/html,hi)") == "<p data-src=\"1-1\">x</p>\n")
        #expect(html("![x](data:image/png;base64,AAAA)").contains("<img src=\"data:image/png;base64,AAAA\""))
    }

    @Test("Spaces in a link destination are percent-encoded")
    func encodedDestination() {
        #expect(html("[x](<my file.md>)").contains("href=\"my%20file.md\""))
    }
}

@Suite("MarkdownRenderer: GFM autolinks")
struct RendererAutolinkTests {

    @Test("Bare URLs, www. hosts and emails become links", arguments: [
        ("see https://example.com/a?b=1 now", "see <a href=\"https://example.com/a?b=1\">https://example.com/a?b=1</a> now"),
        ("visit www.example.com.", "visit <a href=\"http://www.example.com\">www.example.com</a>."),
        ("mail a.b+c@example.org!", "mail <a href=\"mailto:a.b+c@example.org\">a.b+c@example.org</a>!"),
        ("(www.example.com/x)", "(<a href=\"http://www.example.com/x\">www.example.com/x</a>)"),
        ("www.example.com/a_(b)", "<a href=\"http://www.example.com/a_(b)\">www.example.com/a_(b)</a>"),
    ])
    func autolinks(source: String, inner: String) {
        #expect(html(source) == "<p data-src=\"1-1\">\(inner)</p>\n")
    }

    @Test("Explicit <autolinks> work")
    func angleAutolink() {
        #expect(html("<https://e.com>").contains("<a href=\"https://e.com\">https://e.com</a>"))
    }

    @Test("No autolinks inside links or code spans")
    func noAutolinkInsideLinkOrCode() {
        #expect(html("[https://a.com](https://b.com)") == "<p data-src=\"1-1\"><a href=\"https://b.com\">https://a.com</a></p>\n")
        #expect(html("`https://a.com`") == "<p data-src=\"1-1\"><code>https://a.com</code></p>\n")
    }

    @Test("Text that only looks link-like is left alone", arguments: ["www.x", "foo@bar", "notwww.example.com"])
    func nonLinks(source: String) {
        #expect(!html(source).contains("<a "))
    }
}

@Suite("MarkdownRenderer: source line tags")
struct RendererSourceLineTests {

    @Test("Each top-level block records its source lines")
    func blockLines() {
        let source = """
            # Title

            Para one
            continues.

            - a
            - b

            ```
            code
            ```
            """
        let blocks = MarkdownRenderer().render(source).blocks
        #expect(blocks.map(\.lines) == [1...1, 3...4, 6...7, 9...11])
        #expect(blocks[2].html.hasPrefix("<ul data-src=\"6-7\">"))
    }

    @Test("A block ending before a blank line doesn't include it")
    func trailingBlankLineExcluded() {
        let blocks = MarkdownRenderer().render("- a\n- b\n\nnext").blocks
        #expect(blocks.first?.lines == 1...2)
    }

    @Test("Only top-level blocks are tagged")
    func nestedBlocksUntagged() {
        let output = html("> # Quoted heading\n> - item")
        #expect(output.components(separatedBy: "data-src").count == 2)
    }

    @Test("The document HTML is the blocks joined")
    func documentHTMLJoinsBlocks() {
        let rendered = MarkdownRenderer().render("a\n\nb")
        #expect(rendered.html == rendered.blocks.map(\.html).joined())
        #expect(rendered.blocks.count == 2)
    }
}

@Suite("MarkdownRenderer: raw HTML")
struct RendererRawHTMLTests {

    @Test("Top-level HTML blocks are wrapped, tagged and kept")
    func htmlBlock() {
        let output = html("<details>\n<summary>More</summary>\n</details>")
        #expect(output == "<div data-src=\"1-3\" class=\"html-block\">\n<details>\n<summary>More</summary>\n</details>\n</div>\n")
    }

    @Test("Script in raw HTML is neutralized")
    func scriptNeutralized() {
        let output = html("<script>alert(1)</script>")
        #expect(!output.contains("<script"))
        #expect(output.contains("&lt;script>"))
    }

    @Test("Inline HTML keeps safe tags and loses event handlers")
    func inlineHTML() {
        #expect(html("Press <kbd onclick=\"x()\">⌘</kbd>") == "<p data-src=\"1-1\">Press <kbd>⌘</kbd></p>\n")
    }
}

@Suite("MarkdownRenderer: relative URLs")
struct RendererRelativeURLTests {

    let base = URL(fileURLWithPath: "/Users/me/Notes/", isDirectory: true)

    @Test("Relative image and link URLs resolve against the document folder")
    func resolvesRelative() {
        #expect(html("![p](img/a.png)", baseURL: base).contains("src=\"file:///Users/me/Notes/img/a.png\""))
        #expect(html("[n](../other.md)", baseURL: base).contains("href=\"file:///Users/me/other.md\""))
    }

    @Test("Absolute URLs and fragments are untouched")
    func leavesAbsoluteAndFragments() {
        #expect(html("[a](https://e.com/x)", baseURL: base).contains("href=\"https://e.com/x\""))
        #expect(html("[a](#title)", baseURL: base).contains("href=\"#title\""))
    }

    @Test("Without a base URL, relative URLs are left as written")
    func noBase() {
        #expect(html("![p](img/a.png)").contains("src=\"img/a.png\""))
    }
}
