//
//  MarkdownRenderer.swift
//  viewMD
//
//  Turns GitHub Flavored Markdown source into HTML for the preview pane and
//  exports (REQ-016), tagging each top-level block with the source lines it
//  came from so the preview can be edited (REQ-013).
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
import Markdown

/// One top-level block of a rendered document (a paragraph, heading, list,
/// table, …) and the source lines it came from.
nonisolated struct RenderedBlock: Equatable, Sendable {
    /// The 1-based, inclusive range of source lines the block occupies.
    var lines: ClosedRange<Int>
    /// The block's HTML. Its outermost element carries
    /// `data-src="<first>-<last>"`.
    var html: String
}

/// The result of rendering a Markdown document.
nonisolated struct RenderedDocument: Equatable, Sendable {
    /// The top-level blocks, in document order.
    var blocks: [RenderedBlock]

    /// The whole document's HTML body (the blocks' HTML joined in order).
    var html: String { blocks.map(\.html).joined() }
}

/// Renders GitHub Flavored Markdown to HTML.
///
/// Parsing is done by Apple's swift-markdown (cmark-gfm), with the GFM
/// table, strikethrough and task-list extensions. viewMD adds:
///
/// - **Extended autolinks** (bare URLs and emails), via ``Autolinker``.
/// - **Heading anchors**: each heading gets a GitHub-style `id` slug so
///   `[link](#section-title)` works.
/// - **Source line tags**: each top-level block's element has
///   `data-src="first-last"` (1-based, inclusive), which the preview uses to
///   map an edit back to the source.
/// - **Sanitizing**: raw HTML goes through ``HTMLSanitizer``, and unsafe
///   link and image URLs (``URLPolicy``) are dropped (REQ-007).
/// - **Relative URLs** resolve against ``baseURL`` (REQ-022).
///
/// Smart punctuation is turned off, so `"quotes"` and `--` render as typed,
/// like GitHub. It also keeps the round trip from the rendered pane to the
/// source exact.
nonisolated struct MarkdownRenderer: Sendable {

    /// The folder containing the document, used to resolve relative link and
    /// image URLs. `nil` for an unsaved document, in which case relative URLs
    /// are left as written.
    var baseURL: URL?

    /// Creates a renderer.
    ///
    /// - Parameter baseURL: The document's folder, or `nil` if unsaved.
    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    /// Renders Markdown source to HTML.
    ///
    /// - Parameter source: The Markdown text.
    /// - Returns: The rendered top-level blocks with their source line ranges.
    func render(_ source: String) -> RenderedDocument {
        let document = Document(parsing: source, options: [.disableSmartOpts])
        var visitor = HTMLVisitor(baseURL: baseURL)
        var blocks: [RenderedBlock] = []
        for child in document.children {
            // Every block cmark produces has a range; skip defensively if not.
            guard let lines = Self.lineSpan(of: child) else { continue }
            blocks.append(RenderedBlock(lines: lines, html: visitor.visit(child)))
        }
        return RenderedDocument(blocks: blocks)
    }

    /// Returns the 1-based, inclusive source lines a node occupies.
    ///
    /// cmark sometimes ends a block at column 1 of the following line (e.g. a
    /// list followed by a blank line). Column 1 is an exclusive end, so
    /// nothing on that line belongs to the block, and it isn't counted.
    ///
    /// - Parameter markup: A parsed node.
    /// - Returns: The line range, or `nil` if the node has no source range.
    static func lineSpan(of markup: Markup) -> ClosedRange<Int>? {
        guard let range = markup.range else { return nil }
        let first = range.lowerBound.line
        var last = range.upperBound.line
        if range.upperBound.column == 1, last > first {
            last -= 1
        }
        return first...last
    }
}

// MARK: - HTML visitor

/// Walks a swift-markdown tree and produces HTML.
///
/// Output format: each block element ends with `\n`, matching cmark's HTML
/// renderer closely enough that its output is predictable in tests.
nonisolated private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    /// See ``MarkdownRenderer/baseURL``.
    let baseURL: URL?

    /// Heading slugs used so far, so duplicates get `-1`, `-2`, … like
    /// GitHub.
    private var usedSlugs: [String: Int] = [:]

    /// How many links enclose the current node. Autolinking is suppressed
    /// inside links, because nested `<a>` elements are invalid.
    private var linkDepth = 0

    /// Whether the list currently being rendered is tight (its item
    /// paragraphs render without `<p>`).
    private var inTightList = false

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    // MARK: Helpers

    /// The ` data-src="a-b"` attribute for top-level blocks, or `""` for
    /// nested ones.
    private func sourceAttribute(_ markup: Markup) -> String {
        guard markup.parent is Document, let lines = MarkdownRenderer.lineSpan(of: markup) else { return "" }
        return " data-src=\"\(lines.lowerBound)-\(lines.upperBound)\""
    }

    /// Renders all children of `markup` and concatenates the results.
    private mutating func renderChildren(_ markup: Markup) -> String {
        var html = ""
        for child in markup.children {
            html += visit(child)
        }
        return html
    }

    /// Renders inline children, merging adjacent text runs first. cmark can
    /// split one run of text into several `Text` nodes (at `[`, `!` or `_`,
    /// for example), and a URL must be seen whole to be autolinked.
    private mutating func renderInlineChildren(_ markup: Markup) -> String {
        var html = ""
        var pendingText = ""
        func flush(_ html: inout String, _ pendingText: inout String, linkDepth: Int) {
            guard !pendingText.isEmpty else { return }
            html += linkDepth == 0 ? Autolinker.linkify(pendingText) : HTMLEscaping.escape(pendingText)
            pendingText = ""
        }
        for child in markup.children {
            if let text = child as? Text {
                pendingText += text.string
            } else {
                flush(&html, &pendingText, linkDepth: linkDepth)
                html += visit(child)
            }
        }
        flush(&html, &pendingText, linkDepth: linkDepth)
        return html
    }

    /// Returns a URL ready for an attribute, or `nil` if it's unsafe.
    private func attributeURL(_ url: String?, context: URLPolicy.Context) -> String? {
        let url = url ?? ""
        guard URLPolicy.isSafe(url, context: context) else { return nil }
        return HTMLEscaping.escape(URLPolicy.percentEncodeUnsafe(URLPolicy.resolve(url, against: baseURL)))
    }

    /// Makes a GitHub-style anchor slug: lowercase, keep letters, digits,
    /// spaces, `-` and `_`, turn spaces into `-`, and de-duplicate.
    private mutating func slug(for text: String) -> String {
        let base = String(text.lowercased().compactMap { character -> Character? in
            if character == " " { return "-" }
            if character.isLetter || character.isNumber || character == "-" || character == "_" { return character }
            return nil
        })
        let count = usedSlugs[base, default: 0]
        usedSlugs[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }

    /// Whether a list is *tight*, per CommonMark §5.3: no blank line between
    /// items, and no blank line between two direct children of an item.
    private func isTight(_ list: Markup) -> Bool {
        let items = Array(list.children)
        for (index, item) in items.enumerated() {
            if index + 1 < items.count,
               let current = MarkdownRenderer.lineSpan(of: item),
               let next = MarkdownRenderer.lineSpan(of: items[index + 1]),
               next.lowerBound > current.upperBound + 1 {
                return false
            }
            let children = Array(item.children)
            for pair in zip(children, children.dropFirst()) {
                if let a = MarkdownRenderer.lineSpan(of: pair.0),
                   let b = MarkdownRenderer.lineSpan(of: pair.1),
                   b.lowerBound > a.upperBound + 1 {
                    return false
                }
            }
        }
        return true
    }

    /// Renders an ordered or unordered list.
    private mutating func renderList(_ list: Markup, tag: String, extraAttributes: String) -> String {
        let hasTasks = list.children.contains { ($0 as? ListItem)?.checkbox != nil }
        let classAttribute = hasTasks ? " class=\"contains-task-list\"" : ""
        let savedTight = inTightList
        inTightList = isTight(list)
        defer { inTightList = savedTight }
        return "<\(tag)\(sourceAttribute(list))\(classAttribute)\(extraAttributes)>\n" + renderChildren(list) + "</\(tag)>\n"
    }

    // MARK: Visitor

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        renderChildren(document)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        // In tight lists, an item's paragraphs are rendered bare.
        if inTightList, paragraph.parent is ListItem {
            let isLast = paragraph.indexInParent == (paragraph.parent?.childCount ?? 0) - 1
            return renderInlineChildren(paragraph) + (isLast ? "" : "\n")
        }
        return "<p\(sourceAttribute(paragraph))>" + renderInlineChildren(paragraph) + "</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(max(heading.level, 1), 6)
        let id = slug(for: heading.plainText)
        return "<h\(level)\(sourceAttribute(heading)) id=\"\(HTMLEscaping.escape(id))\">" + renderInlineChildren(heading) + "</h\(level)>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        // Paragraphs inside a quote inside a tight list still get <p>.
        let savedTight = inTightList
        inTightList = false
        defer { inTightList = savedTight }
        return "<blockquote\(sourceAttribute(blockQuote))>\n" + renderChildren(blockQuote) + "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        // The info string's first word is the language, e.g. ```swift title
        let language = codeBlock.language?.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let classAttribute = language.isEmpty ? "" : " class=\"language-\(HTMLEscaping.escape(language))\""
        return "<pre\(sourceAttribute(codeBlock))><code\(classAttribute)>" + HTMLEscaping.escape(codeBlock.code) + "</code></pre>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr\(sourceAttribute(thematicBreak)) />\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        let sanitized = HTMLSanitizer.sanitize(html.rawHTML)
        // Top-level raw HTML has no element of ours to tag, so wrap it.
        guard html.parent is Document else { return sanitized }
        return "<div\(sourceAttribute(html)) class=\"html-block\">\n" + sanitized + "</div>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        return renderList(orderedList, tag: "ol", extraAttributes: start)
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        renderList(unorderedList, tag: "ul", extraAttributes: "")
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        var open = "<li>"
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked=\"\"" : ""
            open = "<li class=\"task-list-item\"><input type=\"checkbox\" disabled=\"\"\(checked) /> "
        }
        let body = renderChildren(listItem)
        // In loose lists (or items starting with a non-paragraph), block
        // content begins on its own line, as in cmark's output.
        let startsWithBlock = !(inTightList && listItem.child(at: 0) is Paragraph)
        return open + (startsWithBlock && !body.isEmpty ? "\n" : "") + body + "</li>\n"
    }

    mutating func visitTable(_ table: Table) -> String {
        var html = "<table\(sourceAttribute(table))>\n<thead>\n"
        html += renderRow(table.head, cellTag: "th", alignments: table.columnAlignments)
        html += "</thead>\n"
        if table.body.childCount > 0 {
            html += "<tbody>\n"
            for row in table.body.rows {
                html += renderRow(row, cellTag: "td", alignments: table.columnAlignments)
            }
            html += "</tbody>\n"
        }
        return html + "</table>\n"
    }

    /// Renders one table row; cell alignment comes from the delimiter row.
    private mutating func renderRow(_ row: Markup, cellTag: String, alignments: [Table.ColumnAlignment?]) -> String {
        var html = "<tr>\n"
        for (column, cell) in row.children.enumerated() {
            var style = ""
            if column < alignments.count, let alignment = alignments[column] {
                switch alignment {
                case .left: style = " style=\"text-align: left\""
                case .center: style = " style=\"text-align: center\""
                case .right: style = " style=\"text-align: right\""
                }
            }
            html += "<\(cellTag)\(style)>" + renderInlineChildren(cell) + "</\(cellTag)>\n"
        }
        return html + "</tr>\n"
    }

    mutating func visitText(_ text: Text) -> String {
        // Reached only for a Text with no inline-container parent handling;
        // containers normally go through renderInlineChildren.
        linkDepth == 0 ? Autolinker.linkify(text.string) : HTMLEscaping.escape(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>" + renderInlineChildren(emphasis) + "</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>" + renderInlineChildren(strong) + "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>" + renderInlineChildren(strikethrough) + "</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>" + HTMLEscaping.escape(inlineCode.code) + "</code>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        HTMLSanitizer.sanitize(inlineHTML.rawHTML)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br />\n"
    }

    /// When a URL was rewritten (resolved or percent-encoded), the original
    /// as written in the source is kept in a `data-md-*` attribute, so
    /// converting an edited block back to Markdown (`HTMLToMarkdown`)
    /// restores what the user wrote instead of the resolved URL.
    private func originalURLAttribute(_ name: String, original: String?, emitted: String) -> String {
        let original = original ?? ""
        let escapedOriginal = HTMLEscaping.escape(original)
        return escapedOriginal == emitted ? "" : " data-md-\(name)=\"\(escapedOriginal)\""
    }

    mutating func visitLink(_ link: Link) -> String {
        linkDepth += 1
        defer { linkDepth -= 1 }
        let content = renderInlineChildren(link)
        // An unsafe target (e.g. javascript:) keeps its text but loses the link.
        guard let href = attributeURL(link.destination, context: .link) else { return content }
        let title = link.title.map { " title=\"\(HTMLEscaping.escape($0))\"" } ?? ""
        let original = originalURLAttribute("href", original: link.destination, emitted: href)
        return "<a href=\"\(href)\"\(title)\(original)>" + content + "</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alt = HTMLEscaping.escape(image.plainText)
        guard let src = attributeURL(image.source, context: .image) else { return alt }
        let title = image.title.map { " title=\"\(HTMLEscaping.escape($0))\"" } ?? ""
        let original = originalURLAttribute("src", original: image.source, emitted: src)
        return "<img src=\"\(src)\" alt=\"\(alt)\"\(title)\(original) />"
    }
}
