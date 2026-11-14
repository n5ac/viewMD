//
//  MarkdownSnippets.swift
//  viewMD
//
//  The quick-insert structures offered by the toolbar pull-downs and the
//  Format menu (REQ-015), and how each one edits the source text.
//

import Foundation

/// A common Markdown structure the user can insert.
nonisolated enum MarkdownSnippet: Hashable, Sendable, CaseIterable {
    case heading(Int)
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    case image
    case bulletList
    case numberedList
    case taskList
    case blockquote
    case codeBlock
    case table
    case horizontalRule

    static var allCases: [MarkdownSnippet] {
        (1...6).map { .heading($0) } + [
            .bold, .italic, .strikethrough, .inlineCode, .link, .image,
            .bulletList, .numberedList, .taskList, .blockquote,
            .codeBlock, .table, .horizontalRule,
        ]
    }

    /// The name shown in menus and in Edit ▸ Undo.
    var title: String {
        switch self {
        case .heading(let level): return "Heading \(level)"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .inlineCode: return "Inline Code"
        case .link: return "Link"
        case .image: return "Image"
        case .bulletList: return "Bulleted List"
        case .numberedList: return "Numbered List"
        case .taskList: return "Task List"
        case .blockquote: return "Quote"
        case .codeBlock: return "Code Block"
        case .table: return "Table"
        case .horizontalRule: return "Horizontal Rule"
        }
    }

    /// The SF Symbol shown next to the item.
    var systemImage: String {
        switch self {
        case .heading: return "number"
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .image: return "photo"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .taskList: return "checklist"
        case .blockquote: return "text.quote"
        case .codeBlock: return "curlybraces"
        case .table: return "tablecells"
        case .horizontalRule: return "minus"
        }
    }

    /// Whether the snippet formats text within a line (as opposed to
    /// inserting or converting whole blocks).
    var isInline: Bool {
        switch self {
        case .bold, .italic, .strikethrough, .inlineCode, .link, .image: return true
        default: return false
        }
    }
}

/// The result of applying a snippet: replace `range` with `replacement`, then
/// select `selection`. Ranges are in UTF-16 units of the original text,
/// except `selection`, which is in the edited text.
nonisolated struct SnippetEdit: Equatable, Sendable {
    /// The range of the original text to replace.
    var range: NSRange
    /// The new text for that range.
    var replacement: String
    /// The selection after the edit.
    var selection: NSRange

    /// Applies the edit to `text`.
    ///
    /// - Parameter text: The original text the edit was computed for.
    /// - Returns: The edited text.
    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// Computes how a snippet edits the text at the current selection.
///
/// The rules:
///
/// - **Inline formats** wrap the selection (`**sel**`) and keep it selected.
///   Applying the same format to already-wrapped text removes it, so the
///   command toggles. With no selection they insert placeholder text, which
///   is then selected so typing replaces it.
/// - **Line formats** (headings, lists, quotes) apply to every line the
///   selection touches, replacing any other line format there. If every line
///   already has that format, it's removed.
/// - **Block inserts** (code block, table, rule) go on their own lines,
///   with blank lines around them, after the line containing the caret. A
///   code block wraps the selected lines if there's a selection.
nonisolated enum MarkdownSnippets {

    /// Computes the edit for a snippet.
    ///
    /// - Parameters:
    ///   - snippet: The structure to insert.
    ///   - text: The full source text.
    ///   - selection: The current selection, in UTF-16 units.
    /// - Returns: The edit to apply.
    static func edit(for snippet: MarkdownSnippet, in text: String, selection: NSRange) -> SnippetEdit {
        let ns = text as NSString
        let selection = clamp(selection, length: ns.length)
        switch snippet {
        case .bold: return wrap(ns, selection, marker: "**", placeholder: "bold text")
        case .italic: return wrap(ns, selection, marker: "*", placeholder: "italic text")
        case .strikethrough: return wrap(ns, selection, marker: "~~", placeholder: "struck text")
        case .inlineCode: return wrap(ns, selection, marker: "`", placeholder: "code")
        case .link: return link(ns, selection)
        case .image: return image(ns, selection)
        case .heading(let level): return heading(ns, selection, level: min(max(level, 1), 6))
        case .bulletList: return linePrefix(ns, selection) { _ in "- " }
        case .numberedList: return linePrefix(ns, selection) { "\($0 + 1). " }
        case .taskList: return linePrefix(ns, selection) { _ in "- [ ] " }
        case .blockquote: return linePrefix(ns, selection) { _ in "> " }
        case .codeBlock: return codeBlock(ns, selection)
        case .table:
            let table = "| Column 1 | Column 2 |\n| -------- | -------- |\n| Cell     | Cell     |"
            return insertBlock(table, in: ns, at: selection, select: NSRange(location: 2, length: 8))
        case .horizontalRule:
            return insertBlock("---", in: ns, at: selection, select: nil)
        }
    }

    // MARK: Inline

    /// Wraps the selection in `marker`, or unwraps it if it's already
    /// wrapped (inside or just outside the selection).
    private static func wrap(_ ns: NSString, _ selection: NSRange, marker: String, placeholder: String) -> SnippetEdit {
        let m = (marker as NSString).length
        let selected = ns.substring(with: selection)

        // Already wrapped, markers just outside the selection: **[sel]**
        if selection.location >= m, NSMaxRange(selection) + m <= ns.length,
           ns.substring(with: NSRange(location: selection.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(selection), length: m)) == marker,
           !isPartOfLongerMarker(ns, NSRange(location: selection.location - m, length: selection.length + 2 * m), marker: marker) {
            return SnippetEdit(range: NSRange(location: selection.location - m, length: selection.length + 2 * m),
                               replacement: selected,
                               selection: NSRange(location: selection.location - m, length: selection.length))
        }
        // Already wrapped, markers inside the selection: [**sel**]
        if selection.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: m, length: selection.length - 2 * m))
            if !(inner.hasPrefix(String(marker.first!)) && marker.count == 1) {
                return SnippetEdit(range: selection, replacement: inner,
                                   selection: NSRange(location: selection.location, length: (inner as NSString).length))
            }
        }

        let body = selection.length > 0 ? selected : placeholder
        let bodyLength = (body as NSString).length
        return SnippetEdit(range: selection, replacement: marker + body + marker,
                           selection: NSRange(location: selection.location + m, length: bodyLength))
    }

    /// Whether markers at the ends of `range` belong to a longer run, e.g.
    /// the `*` of `**bold**` when toggling italic.
    private static func isPartOfLongerMarker(_ ns: NSString, _ range: NSRange, marker: String) -> Bool {
        guard marker.count == 1 else { return false }
        let before = range.location > 0 ? ns.substring(with: NSRange(location: range.location - 1, length: 1)) : ""
        let after = NSMaxRange(range) < ns.length ? ns.substring(with: NSRange(location: NSMaxRange(range), length: 1)) : ""
        return before == marker || after == marker
    }

    /// `[text](https://)`. A selected URL becomes the target; other selected
    /// text becomes the link text.
    private static func link(_ ns: NSString, _ selection: NSRange) -> SnippetEdit {
        let selected = ns.substring(with: selection)
        let isURL = selected.range(of: #"^(https?://|mailto:|www\.)\S+$"#, options: .regularExpression) != nil
        if isURL {
            let replacement = "[link text](\(selected))"
            return SnippetEdit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + 1, length: 9))
        }
        let label = selected.isEmpty ? "link text" : selected
        let labelLength = (label as NSString).length
        let replacement = "[\(label)](https://)"
        if selected.isEmpty {
            return SnippetEdit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + 1, length: labelLength))
        }
        // Text was selected: select the URL placeholder so it can be typed.
        return SnippetEdit(range: selection, replacement: replacement,
                           selection: NSRange(location: selection.location + labelLength + 3, length: 8))
    }

    /// `![alt text](image.png)`; selected text becomes the alt text.
    private static func image(_ ns: NSString, _ selection: NSRange) -> SnippetEdit {
        let selected = ns.substring(with: selection)
        let alt = selected.isEmpty ? "alt text" : selected
        let altLength = (alt as NSString).length
        let replacement = "![\(alt)](image.png)"
        let select = selected.isEmpty
            ? NSRange(location: selection.location + 2, length: altLength)
            : NSRange(location: selection.location + altLength + 4, length: 9)
        return SnippetEdit(range: selection, replacement: replacement, selection: select)
    }

    // MARK: Lines

    /// Any list, quote or heading marker at the start of a line.
    private static let lineMarker = try! NSRegularExpression(pattern: #"^[ \t]*(?:#{1,6}[ \t]+|>[ \t]?|(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)"#)

    /// The full lines the selection touches (without the final newline).
    private static func lineBlock(_ ns: NSString, _ selection: NSRange) -> NSRange {
        var range = ns.lineRange(for: selection)
        // A selection ending at the start of a line doesn't include that line.
        if selection.length > 0, NSMaxRange(selection) == range.location + range.length,
           NSMaxRange(selection) > 0, ns.character(at: NSMaxRange(selection) - 1) == 10 {
            range = ns.lineRange(for: NSRange(location: selection.location, length: selection.length - 1))
        }
        if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
        return range
    }

    /// Strips any line marker from `line`.
    private static func stripMarker(_ line: String) -> (marker: String, content: String) {
        let ns = line as NSString
        guard let match = lineMarker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return ("", line)
        }
        return (ns.substring(with: match.range), ns.substring(from: match.range.length))
    }

    /// Applies a line prefix to every line of the selection, toggling it off
    /// if all lines already have it.
    private static func linePrefix(_ ns: NSString, _ selection: NSRange, prefix: (Int) -> String) -> SnippetEdit {
        let block = lineBlock(ns, selection)
        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let stripped = lines.map(stripMarker)
        let alreadyApplied = stripped.enumerated().allSatisfy { index, line in
            line.marker.trimmingCharacters(in: .whitespaces) == prefix(index).trimmingCharacters(in: .whitespaces)
        }
        let newLines = stripped.enumerated().map { index, line in
            alreadyApplied ? line.content : prefix(index) + line.content
        }
        return replaceLines(block, with: newLines, originalSelection: selection, lines: lines)
    }

    /// Sets the heading level of the current line(s); the same level toggles
    /// it off.
    private static func heading(_ ns: NSString, _ selection: NSRange, level: Int) -> SnippetEdit {
        let block = lineBlock(ns, selection)
        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let hashes = String(repeating: "#", count: level) + " "
        let stripped = lines.map(stripMarker)
        let alreadyApplied = stripped.allSatisfy { $0.marker.trimmingCharacters(in: .whitespaces) == hashes.trimmingCharacters(in: .whitespaces) }
        let newLines = stripped.map { alreadyApplied ? $0.content : hashes + $0.content }
        return replaceLines(block, with: newLines, originalSelection: selection, lines: lines)
    }

    /// Builds the edit for a line-format change. A caret on a single line
    /// moves with its text; a multi-line selection selects the new lines.
    private static func replaceLines(_ block: NSRange, with newLines: [String], originalSelection: NSRange, lines: [String]) -> SnippetEdit {
        let replacement = newLines.joined(separator: "\n")
        let newLength = (replacement as NSString).length
        let selection: NSRange
        if lines.count == 1 {
            let delta = newLength - block.length
            let caretOffset = originalSelection.location - block.location
            let newOffset = max(0, min(newLength, caretOffset + delta))
            selection = NSRange(location: block.location + newOffset, length: min(originalSelection.length, newLength - newOffset))
        } else {
            selection = NSRange(location: block.location, length: newLength)
        }
        return SnippetEdit(range: block, replacement: replacement, selection: selection)
    }

    // MARK: Blocks

    /// Wraps the selected lines in a fence, or inserts an empty fenced block.
    private static func codeBlock(_ ns: NSString, _ selection: NSRange) -> SnippetEdit {
        guard selection.length > 0 else {
            return insertBlock("```\ncode\n```", in: ns, at: selection, select: NSRange(location: 4, length: 4))
        }
        let block = lineBlock(ns, selection)
        let body = ns.substring(with: block)
        let replacement = "```\n" + body + "\n```"
        return SnippetEdit(range: block, replacement: replacement,
                           selection: NSRange(location: block.location + 4, length: (body as NSString).length))
    }

    /// Inserts `block` on its own lines after the caret's line (or on the
    /// caret's line if it's blank), with a blank line before and after.
    ///
    /// - Parameter select: The range within `block` to select afterwards, or
    ///   `nil` to put the caret after the block.
    static func insertBlock(_ block: String, in ns: NSString, at selection: NSRange, select: NSRange?) -> SnippetEdit {
        let caret = NSMaxRange(selection)
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        var lineContentEnd = NSMaxRange(line)
        if lineContentEnd > line.location, ns.character(at: lineContentEnd - 1) == 10 { lineContentEnd -= 1 }
        let lineText = ns.substring(with: NSRange(location: line.location, length: lineContentEnd - line.location))
        let isBlankLine = lineText.trimmingCharacters(in: .whitespaces).isEmpty

        let position = isBlankLine ? line.location : lineContentEnd
        // For a blank line, replace its whitespace (not its newline).
        let replaceLength = isBlankLine ? lineContentEnd - line.location : 0
        let before = ns.substring(to: position)
        let after = ns.substring(from: position + replaceLength)

        let trailingNewlines = before.reversed().prefix { $0 == "\n" }.count
        let leadingNewlines = after.prefix { $0 == "\n" }.count
        let prefix = before.isEmpty ? "" : String(repeating: "\n", count: max(0, 2 - trailingNewlines))
        let suffix = after.isEmpty ? "\n" : String(repeating: "\n", count: max(0, 2 - leadingNewlines))

        let replacement = prefix + block + suffix
        let blockStart = position + (prefix as NSString).length
        // With no placeholder to select, put the caret at the start of the
        // line after the block (there's always a newline there: either from
        // the suffix or one already in the text).
        let newSelection = select.map { NSRange(location: blockStart + $0.location, length: $0.length) }
            ?? NSRange(location: blockStart + (block as NSString).length + 1, length: 0)
        return SnippetEdit(range: NSRange(location: position, length: replaceLength), replacement: replacement, selection: newSelection)
    }

    /// Clamps a range to a string length.
    private static func clamp(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }
}
