//
//  MarkdownSnippetsTests.swift
//  viewMDTests
//
//  Unit tests for the quick-insert snippet engine (REQ-015). Each case is
//  written as "before" and "after" text, where `|` marks the caret, and
//  `[` `]` mark a selection.
//

import Foundation
import Testing
@testable import viewMD

/// Parses marked-up text into plain text and a selection. `|` is a caret;
/// `[` … `]` is a selection. (Tests avoid literal brackets in content.)
private func parse(_ marked: String) -> (text: String, selection: NSRange) {
    var text = ""
    var start: Int?
    var end: Int?
    for character in marked {
        switch character {
        case "|": start = (text as NSString).length; end = start
        case "[": start = (text as NSString).length
        case "]": end = (text as NSString).length
        default: text.append(character)
        }
    }
    let location = start ?? (text as NSString).length
    return (text, NSRange(location: location, length: (end ?? location) - location))
}

/// Renders text and a selection back into marked-up form.
private func mark(_ text: String, _ selection: NSRange) -> String {
    let ns = text as NSString
    if selection.length == 0 {
        return ns.substring(to: selection.location) + "|" + ns.substring(from: selection.location)
    }
    return ns.substring(to: selection.location) + "[" + ns.substring(with: selection) + "]" + ns.substring(from: NSMaxRange(selection))
}

/// Applies `snippet` to marked-up `before` and returns marked-up output.
private func apply(_ snippet: MarkdownSnippet, _ before: String) -> String {
    let (text, selection) = parse(before)
    let edit = MarkdownSnippets.edit(for: snippet, in: text, selection: selection)
    return mark(edit.applied(to: text), edit.selection)
}

@Suite("MarkdownSnippets: inline")
struct InlineSnippetTests {

    @Test("Wrapping a selection keeps it selected", arguments: [
        (MarkdownSnippet.bold, "a [word] b", "a **[word]** b"),
        (.italic, "a [word] b", "a *[word]* b"),
        (.strikethrough, "a [word] b", "a ~~[word]~~ b"),
        (.inlineCode, "a [word] b", "a `[word]` b"),
    ])
    func wrap(snippet: MarkdownSnippet, before: String, after: String) {
        #expect(apply(snippet, before) == after)
    }

    @Test("With no selection, a placeholder is inserted and selected", arguments: [
        (MarkdownSnippet.bold, "a | b", "a **[bold text]** b"),
        (.italic, "|", "*[italic text]*"),
        (.inlineCode, "x|", "x`[code]`"),
    ])
    func placeholder(snippet: MarkdownSnippet, before: String, after: String) {
        #expect(apply(snippet, before) == after)
    }

    @Test("Applying the same format again removes it", arguments: [
        (MarkdownSnippet.bold, "a **[word]** b", "a [word] b"),
        (.bold, "a [**word**] b", "a [word] b"),
        (.italic, "a *[word]* b", "a [word] b"),
        (.strikethrough, "~~[x]~~", "[x]"),
    ])
    func toggleOff(snippet: MarkdownSnippet, before: String, after: String) {
        #expect(apply(snippet, before) == after)
    }

    @Test("Italic on bold text adds italic instead of breaking the bold")
    func italicInsideBold() {
        #expect(apply(.italic, "**[word]**") == "***[word]***")
    }

    /// Applies a snippet to plain text and returns the result and the
    /// selected substring (link output contains brackets, so the marked-up
    /// helpers can't be used).
    private func applyPlain(_ snippet: MarkdownSnippet, _ text: String, _ selection: NSRange) -> (String, String) {
        let edit = MarkdownSnippets.edit(for: snippet, in: text, selection: selection)
        let result = edit.applied(to: text)
        return (result, (result as NSString).substring(with: edit.selection))
    }

    @Test("A link with no selection selects the link-text placeholder")
    func emptyLink() {
        let (result, selected) = applyPlain(.link, "", NSRange(location: 0, length: 0))
        #expect(result == "[link text](https://)")
        #expect(selected == "link text")
    }

    @Test("Selected text becomes the link text, and the URL placeholder is selected")
    func textLink() {
        let (result, selected) = applyPlain(.link, "see docs now", NSRange(location: 4, length: 4))
        #expect(result == "see [docs](https://) now")
        #expect(selected == "https://")
    }

    @Test("A selected URL becomes the link target")
    func urlLink() {
        let (result, selected) = applyPlain(.link, "https://e.com", NSRange(location: 0, length: 13))
        #expect(result == "[link text](https://e.com)")
        #expect(selected == "link text")
    }

    @Test("Images use the selection as alt text")
    func images() {
        #expect(apply(.image, "|") == "![[alt text]](image.png)")
        // "![Logo](image.png)" with "image.png" selected:
        let edit = MarkdownSnippets.edit(for: .image, in: "Logo", selection: NSRange(location: 0, length: 4))
        let result = edit.applied(to: "Logo")
        #expect(result == "![Logo](image.png)")
        #expect((result as NSString).substring(with: edit.selection) == "image.png")
    }
}

@Suite("MarkdownSnippets: lines")
struct LineSnippetTests {

    @Test("Headings set the level of the current line, keeping the caret", arguments: [
        (1, "Tit|le", "# Tit|le"),
        (3, "## Tit|le", "### Tit|le"),
        (2, "## Tit|le", "Tit|le"),
        (2, "- item|", "## item|"),
        (1, "a\nb|\nc", "a\n# b|\nc"),
    ])
    func headings(level: Int, before: String, after: String) {
        #expect(apply(.heading(level), before) == after)
    }

    @Test("List and quote prefixes apply to every selected line", arguments: [
        (MarkdownSnippet.bulletList, "[one\ntwo]", "[- one\n- two]"),
        (.numberedList, "[one\ntwo\nthree]", "[1. one\n2. two\n3. three]"),
        (.taskList, "do |it", "- [ ] do |it"),
        (.blockquote, "[a\nb]", "[> a\n> b]"),
        (.bulletList, "1. x|", "- x|"),
    ])
    func prefixes(snippet: MarkdownSnippet, before: String, after: String) {
        #expect(apply(snippet, before) == after)
    }

    @Test("Applying a list again removes it")
    func listToggle() {
        #expect(apply(.bulletList, "[- one\n- two]") == "[one\ntwo]")
        #expect(apply(.numberedList, "[1. one\n2. two]") == "[one\ntwo]")
    }

    @Test("A selection ending at the start of a line doesn't include that line")
    func selectionEndingAtLineStart() {
        #expect(apply(.bulletList, "[one\n]two") == "- [one]\ntwo")
    }
}

@Suite("MarkdownSnippets: blocks")
struct BlockSnippetTests {

    @Test("Blocks go after the caret's line with blank lines around them", arguments: [
        (MarkdownSnippet.horizontalRule, "para|", "para\n\n---\n|"),
        (.horizontalRule, "|", "---\n|"),
        (.horizontalRule, "a|\n\nb", "a\n\n---\n|\nb"),
        (.horizontalRule, "a\n\n|\n\nb", "a\n\n---\n|\nb"),
    ])
    func placement(snippet: MarkdownSnippet, before: String, after: String) {
        #expect(apply(snippet, before) == after)
    }

    @Test("An empty code block selects its placeholder")
    func emptyCodeBlock() {
        #expect(apply(.codeBlock, "text|") == "text\n\n```\n[code]\n```\n")
    }

    @Test("A code block wraps the selected lines")
    func wrappingCodeBlock() {
        #expect(apply(.codeBlock, "[let a = 1\nlet b = 2]") == "```\n[let a = 1\nlet b = 2]\n```")
    }

    @Test("Tables insert a template with the first header selected")
    func table() {
        let result = apply(.table, "|")
        #expect(result.hasPrefix("| [Column 1] | Column 2 |\n| -------- | -------- |\n| Cell     | Cell     |"))
    }

    @Test("Every snippet produces valid, renderable Markdown in an empty and a full document")
    func everySnippetRenders() {
        for snippet in MarkdownSnippet.allCases {
            for before in ["|", "# Title\n\nSome [text] here.\n", "end|"] {
                let (text, selection) = parse(before)
                let edit = MarkdownSnippets.edit(for: snippet, in: text, selection: selection)
                let result = edit.applied(to: text)
                #expect(NSMaxRange(edit.selection) <= (result as NSString).length, "\(snippet) selection out of bounds")
                #expect(!MarkdownRenderer().render(result).blocks.isEmpty, "\(snippet) produced nothing renderable")
            }
        }
    }
}
