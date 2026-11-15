//
//  SourceSplicer.swift
//  viewMD
//
//  Applies an edit made in the rendered pane to the Markdown source, changing
//  only the edited block's lines (REQ-013).
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

/// An edit made in the rendered pane, as reported by the preview page.
nonisolated struct PreviewEdit: Equatable, Sendable {
    /// Where the edited blocks sit in the source.
    enum Location: Equatable, Sendable {
        /// The blocks replace these 1-based, inclusive source lines.
        case replacing(ClosedRange<Int>)
        /// The blocks are new and go after this line (0 = document start).
        case inserting(afterLine: Int)
    }

    /// Where the edit applies.
    var location: Location
    /// The edited blocks' HTML (zero or more top-level elements; empty when
    /// the blocks were deleted).
    var html: String
}

/// Splices Markdown into source text by line number.
nonisolated enum SourceSplicer {

    /// Applies a preview edit to the source.
    ///
    /// The edited HTML is converted to Markdown, following the bullet style
    /// of the lines it replaces, and spliced in. Every line outside the
    /// edited range is kept byte-for-byte.
    ///
    /// - Parameters:
    ///   - edit: The edit reported by the preview.
    ///   - source: The current Markdown source.
    /// - Returns: The new source.
    static func apply(_ edit: PreviewEdit, to source: String) -> String {
        switch edit.location {
        case .replacing(let lines):
            let original = Self.lines(lines, of: source)
            let markdown = HTMLToMarkdown.convert(edit.html, style: .inferred(from: original))
            return replace(lines: lines, in: source, with: markdown)
        case .inserting(let afterLine):
            let markdown = HTMLToMarkdown.convert(edit.html)
            return insert(markdown, afterLine: afterLine, in: source)
        }
    }

    /// Inserts a block snippet (code block, table, rule, task list, …) after
    /// a source line. Used for structures inserted from the rendered pane,
    /// where the caret is in a rendered block rather than in the text.
    ///
    /// - Parameters:
    ///   - snippet: The structure to insert.
    ///   - afterLine: The last line of the block containing the caret
    ///     (0 = start of the document).
    ///   - source: The current Markdown source.
    /// - Returns: The new source.
    static func insertSnippet(_ snippet: MarkdownSnippet, afterLine: Int, in source: String) -> String {
        insert(template(for: snippet), afterLine: afterLine, in: source)
    }

    /// The Markdown a snippet produces on its own, e.g. `---` or a table
    /// template. A task list gets placeholder text, because an empty
    /// `- [ ] ` item wouldn't render as a task.
    static func template(for snippet: MarkdownSnippet) -> String {
        if snippet == .taskList { return "- [ ] task" }
        let edit = MarkdownSnippets.edit(for: snippet, in: "", selection: NSRange(location: 0, length: 0))
        return edit.applied(to: "").trimmingCharacters(in: .newlines)
    }

    /// Returns the text of the given 1-based, inclusive lines.
    ///
    /// - Parameters:
    ///   - range: The lines; clamped to the document.
    ///   - source: The text.
    /// - Returns: The lines joined with `\n`, or `""`.
    static func lines(_ range: ClosedRange<Int>, of source: String) -> String {
        let all = source.components(separatedBy: "\n")
        let lower = max(1, range.lowerBound)
        let upper = min(all.count, range.upperBound)
        guard lower <= upper else { return "" }
        return all[(lower - 1)..<upper].joined(separator: "\n")
    }

    /// Replaces lines with new Markdown. If the Markdown is empty (the blocks
    /// were deleted), the lines are removed along with one of the blank lines
    /// around them, so no extra gap is left behind.
    ///
    /// - Parameters:
    ///   - range: 1-based, inclusive lines to replace; clamped to the document.
    ///   - source: The text.
    ///   - markdown: The replacement (no trailing newline).
    /// - Returns: The new text.
    static func replace(lines range: ClosedRange<Int>, in source: String, with markdown: String) -> String {
        var all = source.components(separatedBy: "\n")
        let lower = min(max(1, range.lowerBound), all.count)
        let upper = min(max(lower, range.upperBound), all.count)
        if markdown.isEmpty {
            all.removeSubrange((lower - 1)..<upper)
            let index = lower - 1
            let blankBefore = index > 0 && all[index - 1].trimmingCharacters(in: .whitespaces).isEmpty
            let blankAfter = index < all.count && all[index].trimmingCharacters(in: .whitespaces).isEmpty
            if blankAfter && (blankBefore || index == 0) {
                all.remove(at: index)
            } else if blankBefore && index == all.count {
                all.remove(at: index - 1)
            }
            return all.joined(separator: "\n")
        }
        all.replaceSubrange((lower - 1)..<upper, with: markdown.components(separatedBy: "\n"))
        return all.joined(separator: "\n")
    }

    /// Inserts Markdown blocks after a line, separated by blank lines.
    ///
    /// - Parameters:
    ///   - markdown: The new blocks (no trailing newline). Nothing happens if
    ///     it's empty.
    ///   - afterLine: The line to insert after; 0 inserts at the start.
    ///   - source: The text.
    /// - Returns: The new text.
    static func insert(_ markdown: String, afterLine: Int, in source: String) -> String {
        guard !markdown.isEmpty else { return source }
        if source.isEmpty { return markdown + "\n" }
        var all = source.components(separatedBy: "\n")
        let index = min(max(0, afterLine), all.count)
        var block = markdown.components(separatedBy: "\n")
        let isBlank: (Int) -> Bool = { $0 >= 0 && $0 < all.count && all[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        if index > 0, !isBlank(index - 1) { block.insert("", at: 0) }
        if index < all.count, !isBlank(index) { block.append("") }
        all.insert(contentsOf: block, at: index)
        return all.joined(separator: "\n")
    }
}
