//
//  PreviewEditingTests.swift
//  viewMDTests
//
//  Unit tests for editing in the rendered pane (REQ-013): HTML → Markdown
//  conversion and splicing edits into the source.
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

/// Renders Markdown to HTML and converts it back.
private func roundTrip(_ markdown: String, baseURL: URL? = nil) -> String {
    HTMLToMarkdown.convert(MarkdownRenderer(baseURL: baseURL).render(markdown).html)
}

@Suite("HTMLToMarkdown: round trips")
struct HTMLToMarkdownRoundTripTests {

    @Test("Canonical Markdown survives render → convert unchanged", arguments: [
        "# Heading",
        "### Third level",
        "Plain paragraph.",
        "Line one\nline two",
        "Some **bold**, *italic*, ~~struck~~ and `code`.",
        "A [link](https://example.com) and [titled](https://e.com \"Title\").",
        "![alt text](image.png)",
        "- one\n- two\n- three",
        "1. one\n2. two",
        "3. three\n4. four",
        "- [ ] todo\n- [x] done",
        "- outer\n  - inner",
        "> quoted\n> text",
        "```swift\nlet x = 1\n```",
        "```\nplain code\n```",
        "| a | b |\n| --- | --- |\n| 1 | 2 |",
        "| L | C | R |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |",
        "---",
        "Visit https://example.com today",
        "Mail a@example.com",
        "Press <kbd>Cmd</kbd>",
        "Hard\\\nbreak",
        "snake_case_name stays",
        "Escaped \\*not emphasis\\*",
    ])
    func canonical(markdown: String) {
        #expect(roundTrip(markdown) == markdown)
    }

    @Test("Several blocks are separated by blank lines")
    func multipleBlocks() {
        let markdown = "# Title\n\nPara one.\n\n- a\n- b"
        #expect(roundTrip(markdown) == markdown)
    }

    @Test("Resolved URLs convert back to what the author wrote")
    func originalURLsRestored() {
        let base = URL(string: "viewmd://doc/Users/me/Notes/")!
        #expect(roundTrip("![pic](img/a.png)", baseURL: base) == "![pic](img/a.png)")
        #expect(roundTrip("[next](other.md)", baseURL: base) == "[next](other.md)")
        #expect(roundTrip("[sp](<my file.md>)", baseURL: base) == "[sp](<my file.md>)")
    }

    @Test("Loose lists stay loose")
    func looseList() {
        #expect(roundTrip("- a\n\n- b") == "- a\n\n- b")
    }
}

@Suite("HTMLToMarkdown: editor and paste HTML")
struct HTMLToMarkdownEditingTests {

    @Test("WebKit editing markup converts to Markdown", arguments: [
        ("<p>a <b>bold</b> b</p>", "a **bold** b"),
        ("<p>a <i>it</i> b</p>", "a *it* b"),
        ("<p><strike>x</strike></p>", "~~x~~"),
        ("<p>one<br>two</p>", "one\\\ntwo"),
        ("<div>typed in a new line</div>", "typed in a new line"),
        ("<p>a&nbsp;b&nbsp;</p>", "a b"),
        ("<p><span style=\"color:red\">styled</span> text</p>", "styled text"),
        ("<h2>Title <b>bold</b></h2>", "## Title **bold**"),
        ("<p><b> spaced </b>x</p>", " **spaced** x"),
    ])
    func editingMarkup(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html).trimmingCharacters(in: .whitespaces) == expected.trimmingCharacters(in: .whitespaces))
    }

    @Test("Text that looks like Markdown syntax is escaped", arguments: [
        ("<p># not a heading</p>", "\\# not a heading"),
        ("<p>- not a list</p>", "\\- not a list"),
        ("<p>1. not a list</p>", "1\\. not a list"),
        ("<p>&gt; not a quote</p>", "\\> not a quote"),
        ("<p>a * b [c] `d`</p>", "a \\* b \\[c\\] \\`d\\`"),
        ("<p>&lt;div&gt; literal</p>", "\\<div> literal"),
        ("<p>AT&amp;T &amp;amp;</p>", "AT&T \\&amp;"),
    ])
    func escaping(html: String, expected: String) {
        #expect(HTMLToMarkdown.convert(html) == expected)
    }

    @Test("Scripts and styles are dropped")
    func droppedElements() {
        #expect(HTMLToMarkdown.convert("<p>a<script>alert(1)</script>b</p>") == "ab")
        #expect(HTMLToMarkdown.convert("<p>x<style>p{}</style></p>") == "x")
    }

    @Test("Code containing backticks gets a longer fence")
    func backtickFence() {
        #expect(HTMLToMarkdown.convert("<pre><code>a ``` b\n</code></pre>") == "````\na ``` b\n````")
        #expect(HTMLToMarkdown.convert("<p><code>a`b</code></p>") == "``a`b``")
    }

    @Test("Highlighted code converts from its text")
    func highlightedCode() {
        let html = "<pre><code class=\"hljs language-swift\"><span class=\"hljs-keyword\">let</span> x = <span class=\"hljs-number\">1</span>\n</code></pre>"
        #expect(HTMLToMarkdown.convert(html) == "```swift\nlet x = 1\n```")
    }

    @Test("Toggled task boxes keep their state")
    func taskToggle() {
        let html = "<ul class=\"contains-task-list\"><li class=\"task-list-item\"><input type=\"checkbox\" checked=\"\"> a</li><li class=\"task-list-item\"><input type=\"checkbox\"> b</li></ul>"
        #expect(HTMLToMarkdown.convert(html) == "- [x] a\n- [ ] b")
    }

    @Test("Bullet style follows the replaced source")
    func bulletStyle() {
        let style = MarkdownStyle.inferred(from: "* one\n* two")
        #expect(HTMLToMarkdown.convert("<ul><li>one</li><li>two</li></ul>", style: style) == "* one\n* two")
    }

    @Test("Empty HTML converts to nothing")
    func empty() {
        #expect(HTMLToMarkdown.convert("") == "")
        #expect(HTMLToMarkdown.convert("<p></p>") == "")
        #expect(HTMLToMarkdown.convert("<p><br></p>") == "")
    }
}

@Suite("SourceSplicer")
struct SourceSplicerTests {

    let source = "# Title\n\nFirst para.\n\nSecond para.\n"

    @Test("Replacing a block changes only its lines")
    func replaceBlock() {
        let result = SourceSplicer.replace(lines: 3...3, in: source, with: "First **edited**.")
        #expect(result == "# Title\n\nFirst **edited**.\n\nSecond para.\n")
    }

    @Test("Replacing one block with two keeps blank-line separation from the HTML")
    func replaceWithTwo() {
        let edit = PreviewEdit(location: .replacing(3...3), html: "<p>First</p><p>New</p>")
        #expect(SourceSplicer.apply(edit, to: source) == "# Title\n\nFirst\n\nNew\n\nSecond para.\n")
    }

    @Test("Deleting a block removes its lines and one blank line")
    func deleteBlock() {
        #expect(SourceSplicer.replace(lines: 3...3, in: source, with: "") == "# Title\n\nSecond para.\n")
        #expect(SourceSplicer.replace(lines: 1...1, in: source, with: "") == "First para.\n\nSecond para.\n")
        #expect(SourceSplicer.replace(lines: 5...5, in: source, with: "") == "# Title\n\nFirst para.\n")
    }

    @Test("Inserting new blocks adds blank lines as needed", arguments: [
        (0, "New\n\n# Title\n\nFirst para.\n\nSecond para.\n"),
        (3, "# Title\n\nFirst para.\n\nNew\n\nSecond para.\n"),
        (5, "# Title\n\nFirst para.\n\nSecond para.\n\nNew\n"),
    ])
    func insert(afterLine: Int, expected: String) {
        #expect(SourceSplicer.insert("New", afterLine: afterLine, in: source) == expected)
    }

    @Test("Inserting into an empty document")
    func insertIntoEmpty() {
        #expect(SourceSplicer.insert("Hello", afterLine: 0, in: "") == "Hello\n")
    }

    @Test("Lines outside the edit are byte-for-byte unchanged, even with odd formatting")
    func untouchedLinesPreserved() {
        let quirky = "Title\n=====\n\n*   loose   bullet\n\nTarget para.\n\n__strong__ and _em_   \n"
        let edit = PreviewEdit(location: .replacing(6...6), html: "<p>Target <b>changed</b>.</p>")
        let result = SourceSplicer.apply(edit, to: quirky)
        #expect(result == "Title\n=====\n\n*   loose   bullet\n\nTarget **changed**.\n\n__strong__ and _em_   \n")
    }

    @Test("A full edit cycle: render, edit the HTML of one block, splice")
    func fullCycle() throws {
        let markdown = "# Notes\n\n- one\n- two\n\nEnd."
        let blocks = MarkdownRenderer().render(markdown).blocks
        let list = try #require(blocks.first { $0.html.hasPrefix("<ul") })
        let editedHTML = list.html.replacingOccurrences(of: "<li>two</li>", with: "<li>two</li>\n<li>three</li>")
        let result = SourceSplicer.apply(PreviewEdit(location: .replacing(list.lines), html: editedHTML), to: markdown)
        #expect(result == "# Notes\n\n- one\n- two\n- three\n\nEnd.")
    }
}

@Suite("Preview edit plumbing")
struct PreviewEditPlumbingTests {

    @Test("Edit messages decode to replacements or insertions")
    func parseEdit() {
        #expect(PreviewController.parseEdit(["type": "edit", "start": 3, "end": 5, "html": "<p>x</p>"])
                == PreviewEdit(location: .replacing(3...5), html: "<p>x</p>"))
        #expect(PreviewController.parseEdit(["type": "edit", "afterLine": 0, "html": "<p>x</p>"])
                == PreviewEdit(location: .inserting(afterLine: 0), html: "<p>x</p>"))
        #expect(PreviewController.parseEdit(["type": "edit", "start": 5, "end": 3, "html": ""]) == nil)
        #expect(PreviewController.parseEdit(["type": "edit", "start": 1, "end": 1]) == nil)
    }

    @Test("Inline and line formats use editing commands; blocks go through the source")
    func formatCommands() {
        #expect(PreviewController.formatCommand(for: .bold) == "bold")
        #expect(PreviewController.formatCommand(for: .heading(3)) == "heading3")
        #expect(PreviewController.formatCommand(for: .blockquote) == "blockquote")
        for snippet in [MarkdownSnippet.table, .codeBlock, .horizontalRule, .taskList] {
            #expect(PreviewController.formatCommand(for: snippet) == nil)
        }
    }

    @Test("Block snippets from the preview go after the caret's block", arguments: [
        (MarkdownSnippet.horizontalRule, 1, "# A\n\n---\n\nPara\n"),
        (.horizontalRule, 3, "# A\n\nPara\n\n---\n"),
        (.horizontalRule, 0, "---\n\n# A\n\nPara\n"),
        (.taskList, 1, "# A\n\n- [ ] task\n\nPara\n"),
    ])
    func insertSnippet(snippet: MarkdownSnippet, afterLine: Int, expected: String) {
        #expect(SourceSplicer.insertSnippet(snippet, afterLine: afterLine, in: "# A\n\nPara\n") == expected)
    }
}
