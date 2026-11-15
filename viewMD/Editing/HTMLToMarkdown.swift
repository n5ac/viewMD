//
//  HTMLToMarkdown.swift
//  viewMD
//
//  Converts blocks edited in the rendered pane back to Markdown (REQ-013).
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

/// Style choices for generated Markdown. They're taken from the block being
/// replaced where possible, so an edit keeps the author's conventions.
nonisolated struct MarkdownStyle: Equatable, Sendable {
    /// The bullet character for unordered lists: `-`, `*` or `+`.
    var bullet: Character = "-"

    /// Infers the style from existing Markdown (the block's original source).
    ///
    /// - Parameter source: Markdown text, or `""`.
    /// - Returns: The inferred style; defaults where nothing can be inferred.
    static func inferred(from source: String) -> MarkdownStyle {
        var style = MarkdownStyle()
        for line in source.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
                style.bullet = first
                break
            }
        }
        return style
    }
}

/// Converts HTML (as produced by ``MarkdownRenderer`` and then edited in the
/// preview's `contenteditable`) to GitHub Flavored Markdown.
///
/// It understands every element the renderer emits, plus what WebKit's
/// editing commands and pasting typically produce: `<b>`, `<i>`, `<strike>`,
/// `<div>`, `<br>`, `<span>` and `&nbsp;`. Other formatting elements are
/// unwrapped to their text, a few harmless inline tags (`<kbd>`, `<sup>`,
/// `<sub>`, `<mark>`, …) are kept as raw HTML, and `<script>`/`<style>` are
/// dropped.
///
/// The HTML is parsed with Foundation's `XMLDocument` in tidy-HTML mode,
/// which tolerates the fragments browsers serialize.
nonisolated enum HTMLToMarkdown {

    /// Inline HTML elements preserved as raw HTML (GFM renders them).
    private static let rawInlineTags: Set<String> = ["kbd", "sup", "sub", "mark", "abbr", "ins", "small", "u"]

    /// Elements dropped with their content.
    private static let droppedTags: Set<String> = ["script", "style", "template", "head", "title", "meta", "link", "button", "select", "textarea"]

    /// Block-level elements (used to decide whether a container's children
    /// form blocks or inline content).
    private static let blockTags: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol", "li",
        "pre", "table", "hr", "section", "article", "header", "footer", "details", "figure",
    ]

    /// Converts an HTML fragment to Markdown blocks separated by blank lines.
    ///
    /// - Parameters:
    ///   - html: Zero or more top-level block elements.
    ///   - style: Marker conventions to follow.
    /// - Returns: The Markdown, without a trailing newline. Empty if the
    ///   fragment has no content.
    static func convert(_ html: String, style: MarkdownStyle = MarkdownStyle()) -> String {
        // Tidy collapses newlines in text to spaces, which would lose soft
        // line breaks. Newlines between two text characters are swapped for a
        // private-use character before parsing and restored wherever text is
        // read (see `text(_:)`). Newlines next to a tag are structural
        // formatting (`<li>a</li>\n<li>`) and are left for tidy, which would
        // otherwise treat the sentinel as content.
        let protected = html.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"(?<=[^>\n])\n(?=[^<\n])"#, with: newlineSentinel, options: .regularExpression)
        let wrapped = "<html><head><meta charset=\"utf-8\"></head><body>\(protected)</body></html>"
        // The document must stay alive while its nodes are used.
        guard let document = try? XMLDocument(xmlString: wrapped, options: [.documentTidyHTML, .nodePreserveWhitespace]),
              let body = document.rootElement()?.elements(forName: "body").first
                ?? findElement(named: "body", in: document.rootElement()) else {
            return escapeInline(plainText(fromHTML: html), atLineStart: true)
        }
        var converter = Converter(style: style)
        let markdown = converter.blocks(of: body).joined(separator: "\n\n")
        return withExtendedLifetime(document) { markdown }
    }

    /// Stands in for `\n` while tidy parses the HTML.
    static let newlineSentinel = "\u{E000}"

    /// Reads text from the parsed tree, restoring protected newlines.
    static func text(_ value: String?) -> String {
        (value ?? "").replacingOccurrences(of: newlineSentinel, with: "\n")
    }

    /// Finds the first descendant element with a given name (depth-first).
    static func findElement(named name: String, in root: XMLElement?) -> XMLElement? {
        guard let root else { return nil }
        if root.name?.lowercased() == name { return root }
        for child in root.children ?? [] {
            if let found = findElement(named: name, in: child as? XMLElement) { return found }
        }
        return nil
    }

    /// All descendant elements with a given name, in document order.
    static func descendants(named name: String, in root: XMLElement) -> [XMLElement] {
        var result: [XMLElement] = []
        for child in root.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            if element.name?.lowercased() == name { result.append(element) }
            result += descendants(named: name, in: element)
        }
        return result
    }

    /// Falls back to stripping tags when parsing fails.
    private static func plainText(fromHTML html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    // MARK: Escaping

    /// Escapes characters in plain text that Markdown would otherwise read as
    /// syntax.
    ///
    /// - Parameters:
    ///   - text: Text from a text node.
    ///   - atLineStart: Whether the text begins a line, where `#`, `>`, list
    ///     markers and similar need escaping too.
    /// - Returns: Escaped Markdown text.
    static func escapeInline(_ text: String, atLineStart: Bool) -> String {
        var result = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            switch character {
            case "\\", "*", "`", "[", "]":
                result += "\\" + String(character)
            case "_":
                // Intraword underscores (snake_case) never form emphasis in GFM.
                let wordBefore = previous.map { $0.isLetter || $0.isNumber } ?? false
                let wordAfter = next.map { $0.isLetter || $0.isNumber } ?? false
                result += (wordBefore && wordAfter) ? "_" : "\\_"
            case "~":
                result += (previous == "~" || next == "~") ? "\\~" : "~"
            case "<":
                let startsTag = next.map { $0.isLetter || $0 == "/" || $0 == "!" || $0 == "?" } ?? false
                result += startsTag ? "\\<" : "<"
            case "&":
                let rest = String(characters[(index + 1)...].prefix(12))
                result += rest.range(of: #"^#?[A-Za-z0-9]+;"#, options: .regularExpression) != nil ? "\\&" : "&"
            default:
                result.append(character)
            }
        }
        // Escape block syntax at the start of each line.
        let lines = result.components(separatedBy: "\n")
        return lines.enumerated().map { index, line in
            (index > 0 || atLineStart) ? escapeLineStart(line) : line
        }.joined(separator: "\n")
    }

    /// Escapes a leading `#`, `>`, `-`, `+`, `=` or ordered-list marker that
    /// would turn a line into a heading, quote or list item.
    private static func escapeLineStart(_ line: String) -> String {
        let leading = line.prefix { $0 == " " }
        let rest = line.dropFirst(leading.count)
        guard let first = rest.first else { return line }
        if first == "#" || first == ">" {
            return leading + "\\" + rest
        }
        if "-+".contains(first), rest.count == 1 || rest.dropFirst().first == " " {
            return leading + "\\" + rest
        }
        if first == "=", rest.allSatisfy({ $0 == "=" }) {
            return leading + "\\" + rest
        }
        if first.isNumber {
            let digits = rest.prefix { $0.isNumber }
            let after = rest.dropFirst(digits.count)
            if digits.count <= 9, let marker = after.first, marker == "." || marker == ")",
               after.count == 1 || after.dropFirst().first == " " {
                return leading + digits + "\\" + after
            }
        }
        return line
    }

    // MARK: Converter

    /// Walks the parsed tree. A struct so per-conversion state stays local.
    private struct Converter {
        let style: MarkdownStyle

        /// Converts the children of a block container to Markdown blocks.
        mutating func blocks(of element: XMLElement) -> [String] {
            var result: [String] = []
            var pendingInline: [XMLNode] = []
            func flushInline(_ result: inout [String], _ pending: inout [XMLNode], converter: inout Converter) {
                guard !pending.isEmpty else { return }
                let text = converter.trimTrailingBreaks(converter.inline(pending))
                if !text.isEmpty { result.append(text) }
                pending.removeAll()
            }
            for child in element.children ?? [] {
                if let childElement = child as? XMLElement, let name = childElement.name?.lowercased(), HTMLToMarkdown.blockTags.contains(name) {
                    flushInline(&result, &pendingInline, converter: &self)
                    let block = self.block(childElement).trimmingCharacters(in: .newlines)
                    if !block.isEmpty { result.append(block) }
                } else {
                    pendingInline.append(child)
                }
            }
            flushInline(&result, &pendingInline, converter: &self)
            return result
        }

        /// Converts one block element.
        mutating func block(_ element: XMLElement) -> String {
            let name = element.name?.lowercased() ?? ""
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(String(name.last!)) ?? 1
                let text = inline(element.children ?? []).replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                return String(repeating: "#", count: level) + " " + text
            case "p":
                return trimTrailingBreaks(inline(element.children ?? []))
            case "div":
                if (element.attribute(forName: "class")?.stringValue ?? "").split(separator: " ").contains("html-block") {
                    // Raw HTML block: keep its inner HTML.
                    return HTMLToMarkdown.text((element.children ?? []).map { $0.xmlString(options: [.nodePreserveWhitespace]) }.joined())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return blocks(of: element).joined(separator: "\n\n")
            case "blockquote":
                let inner = blocks(of: element).joined(separator: "\n\n")
                return inner.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
            case "ul", "ol":
                return list(element, ordered: name == "ol")
            case "li":
                // A stray list item (e.g. pasted) becomes a one-item list.
                return listItem(element, marker: "\(style.bullet) ")
            case "pre":
                return codeBlock(element)
            case "table":
                return table(element)
            case "hr":
                return "---"
            default:
                return blocks(of: element).joined(separator: "\n\n")
            }
        }

        /// Trims whitespace and any hard breaks at the end of a paragraph
        /// (WebKit leaves a `<br>` in an emptied paragraph).
        func trimTrailingBreaks(_ markdown: String) -> String {
            var result = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            while result.hasSuffix("\\") {
                result.removeLast()
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return result
        }

        /// Converts a list.
        mutating func list(_ element: XMLElement, ordered: Bool) -> String {
            var number = Int(element.attribute(forName: "start")?.stringValue ?? "") ?? 1
            let items = (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name?.lowercased() == "li" }
            // A list is loose if any item holds paragraphs.
            let loose = items.contains { item in
                (item.children ?? []).contains { ($0 as? XMLElement)?.name?.lowercased() == "p" }
            }
            var rendered: [String] = []
            for item in items {
                let marker = ordered ? "\(number). " : "\(style.bullet) "
                rendered.append(listItem(item, marker: marker))
                number += 1
            }
            return rendered.joined(separator: loose ? "\n\n" : "\n")
        }

        /// Converts a list item: marker, optional task box, then content with
        /// continuation lines indented to the content column.
        mutating func listItem(_ item: XMLElement, marker: String) -> String {
            var children = item.children ?? []
            var taskBox = ""
            if let index = children.firstIndex(where: { ($0 as? XMLElement)?.name?.lowercased() == "input" }),
               let input = children[index] as? XMLElement,
               input.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" {
                taskBox = input.attribute(forName: "checked") != nil ? "[x] " : "[ ] "
                children.remove(at: index)
                // Drop the space that followed the checkbox.
                if index < children.count, children[index].kind == .text {
                    let text = children[index]
                    let trimmed = (text.stringValue ?? "").drop { $0 == " " || $0 == "\u{00A0}" }
                    if trimmed.isEmpty { children.remove(at: index) } else { text.stringValue = String(trimmed) }
                }
            }
            let container = XMLElement(name: "li")
            for child in children {
                child.detach()
                container.addChild(child)
            }
            // In a tight item (no <p>), nested blocks follow on the next line.
            let isTight = !(container.children ?? []).contains { ($0 as? XMLElement)?.name?.lowercased() == "p" }
            let content = blocks(of: container).joined(separator: isTight ? "\n" : "\n\n")
            let indent = String(repeating: " ", count: marker.count)
            let lines = content.components(separatedBy: "\n")
            let body = lines.enumerated().map { index, line in
                index == 0 ? line : (line.isEmpty ? "" : indent + line)
            }.joined(separator: "\n")
            return marker + taskBox + body
        }

        /// Converts `<pre><code class="language-x">` to a fenced block.
        func codeBlock(_ pre: XMLElement) -> String {
            let code = (pre.children ?? []).compactMap { $0 as? XMLElement }.first { $0.name?.lowercased() == "code" }
            let classes = (code?.attribute(forName: "class")?.stringValue ?? "").split(separator: " ")
            let language = classes.first { $0.hasPrefix("language-") }.map { String($0.dropFirst("language-".count)) } ?? ""
            var text = HTMLToMarkdown.text((code ?? pre).stringValue)
            text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
            if text.hasSuffix("\n") { text.removeLast() }
            // The fence must be longer than any backtick run in the code.
            let longestRun = text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(3, longestRun + 1))
            return fence + language + "\n" + text + "\n" + fence
        }

        /// Converts a table to a GFM pipe table.
        mutating func table(_ element: XMLElement) -> String {
            let rows = HTMLToMarkdown.descendants(named: "tr", in: element)
            guard let header = rows.first else { return "" }
            func cells(_ row: XMLElement) -> [XMLElement] {
                (row.children ?? []).compactMap { $0 as? XMLElement }.filter { ["th", "td"].contains($0.name?.lowercased() ?? "") }
            }
            let headerCells = cells(header)
            let columnCount = max(1, headerCells.count)
            func cellText(_ cell: XMLElement) -> String {
                inline(cell.children ?? [])
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
                    .trimmingCharacters(in: .whitespaces)
            }
            func line(_ values: [String]) -> String {
                let padded = values + Array(repeating: "", count: max(0, columnCount - values.count))
                return "| " + padded.prefix(columnCount).joined(separator: " | ") + " |"
            }
            let alignments = headerCells.map { cell -> String in
                let styleValue = (cell.attribute(forName: "style")?.stringValue ?? "") + " " + (cell.attribute(forName: "align")?.stringValue ?? "")
                if styleValue.contains("center") { return ":-:" }
                if styleValue.contains("right") { return "--:" }
                if styleValue.contains("left") { return ":--" }
                return "---"
            }
            var lines = [line(headerCells.map(cellText)), line(alignments + Array(repeating: "---", count: max(0, columnCount - alignments.count)))]
            for row in rows.dropFirst() {
                lines.append(line(cells(row).map(cellText)))
            }
            return lines.joined(separator: "\n")
        }

        /// Converts inline content.
        mutating func inline(_ nodes: [XMLNode]) -> String {
            var result = ""
            for node in nodes {
                let atLineStart = result.isEmpty || result.hasSuffix("\n")
                result += inlineNode(node, atLineStart: atLineStart)
            }
            return result
        }

        /// Converts one inline node.
        mutating func inlineNode(_ node: XMLNode, atLineStart: Bool) -> String {
            if node.kind == .text {
                let text = HTMLToMarkdown.text(node.stringValue).replacingOccurrences(of: "\u{00A0}", with: " ")
                return HTMLToMarkdown.escapeInline(text, atLineStart: atLineStart)
            }
            guard let element = node as? XMLElement, let name = element.name?.lowercased() else { return "" }
            if HTMLToMarkdown.droppedTags.contains(name) { return "" }
            let children = element.children ?? []
            switch name {
            case "strong", "b":
                return wrap(inline(children), "**")
            case "em", "i":
                return wrap(inline(children), "*")
            case "del", "s", "strike":
                return wrap(inline(children), "~~")
            case "code":
                return codeSpan(HTMLToMarkdown.text(element.stringValue))
            case "br":
                return "\\\n"
            case "a":
                return link(element)
            case "img":
                return image(element)
            case "input":
                return ""
            default:
                if HTMLToMarkdown.rawInlineTags.contains(name) {
                    return "<\(name)>" + inline(children) + "</\(name)>"
                }
                if HTMLToMarkdown.blockTags.contains(name) {
                    // Block content inside inline context (rare; from pasting).
                    return blocks(of: element).joined(separator: "\n\n")
                }
                return inline(children)
            }
        }

        /// Wraps content in emphasis markers, moving surrounding spaces
        /// outside them (`** bold**` isn't emphasis in Markdown).
        func wrap(_ content: String, _ marker: String) -> String {
            let leading = content.prefix { $0 == " " }
            let trailing = String(content.reversed().prefix { $0 == " " })
            let core = content.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return content }
            return leading + marker + core + marker + trailing
        }

        /// A code span with enough backticks to contain the code.
        func codeSpan(_ code: String) -> String {
            let text = code.replacingOccurrences(of: "\u{00A0}", with: " ")
            let longestRun = text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let ticks = String(repeating: "`", count: longestRun + 1)
            let pad = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
            return ticks + pad + text + pad + ticks
        }

        /// Converts a link, restoring the source URL and autolinks.
        mutating func link(_ element: XMLElement) -> String {
            let text = inline(element.children ?? [])
            let href = element.attribute(forName: "data-md-href")?.stringValue
                ?? element.attribute(forName: "href")?.stringValue ?? ""
            let plain = HTMLToMarkdown.text(element.stringValue)
            // Bare autolinks render with the URL as their text: keep them bare.
            if href == plain || href == "http://" + plain || href == "mailto:" + plain {
                return plain
            }
            let title = element.attribute(forName: "title")?.stringValue.map { " \"\(escapeTitle($0))\"" } ?? ""
            return "[\(text)](\(destination(href))\(title))"
        }

        /// Converts an image, restoring the source URL.
        func image(_ element: XMLElement) -> String {
            let src = element.attribute(forName: "data-md-src")?.stringValue
                ?? element.attribute(forName: "src")?.stringValue ?? ""
            let alt = (element.attribute(forName: "alt")?.stringValue ?? "")
                .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            let title = element.attribute(forName: "title")?.stringValue.map { " \"\(escapeTitle($0))\"" } ?? ""
            return "![\(alt)](\(destination(src))\(title))"
        }

        /// A link destination; wrapped in `<>` when it contains spaces or
        /// parentheses, which would end a bare destination.
        func destination(_ url: String) -> String {
            url.contains(where: { $0 == " " || $0 == "(" || $0 == ")" }) ? "<\(url)>" : url
        }

        /// Escapes `"` in a link title.
        func escapeTitle(_ title: String) -> String {
            title.replacingOccurrences(of: "\"", with: "\\\"")
        }
    }
}
