//
//  MarkdownHighlighter.swift
//  viewMD
//
//  Light syntax coloring for the source pane (REQ-023).
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

import AppKit

/// The kinds of Markdown syntax the source pane colors.
nonisolated enum MarkdownSyntaxStyle: Equatable, Sendable {
    /// An ATX heading line (`# Title`).
    case heading
    /// `**strong**` or `__strong__`.
    case strong
    /// `*emphasis*` or `_emphasis_`.
    case emphasis
    /// `` `code` `` spans and fenced code blocks.
    case code
    /// `[text](url)` links and `![alt](src)` images.
    case link
    /// `> quote` lines.
    case quote
    /// List markers (`-`, `*`, `+`, `1.`) and task boxes (`[ ]`, `[x]`).
    case listMarker
    /// Thematic breaks (`---`).
    case rule
}

/// A styled range of source text, in UTF-16 units.
nonisolated struct MarkdownSyntaxRun: Equatable, Sendable {
    /// The range the style applies to.
    var range: NSRange
    /// The style.
    var style: MarkdownSyntaxStyle
}

/// Computes and applies syntax coloring for Markdown source.
///
/// The scan is regex-based rather than a full parse. It runs on every
/// keystroke and must stay fast, and coloring tolerates the rare
/// misclassification (it doesn't change the text). Code blocks are found
/// first, and nothing inside them gets other styles.
nonisolated struct MarkdownHighlighter: Sendable {

    /// The source pane's font.
    static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private static let fencedCode = try! NSRegularExpression(
        pattern: #"^ {0,3}(`{3,}|~{3,})[^\n]*\n(?:.*\n)*?(?: {0,3}\1[`~]*[ \t]*$|\z)"#,
        options: [.anchorsMatchLines])
    private static let heading = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}(?:[ \t].*)?$"#, options: [.anchorsMatchLines])
    private static let quote = try! NSRegularExpression(pattern: #"^ {0,3}>.*$"#, options: [.anchorsMatchLines])
    private static let rule = try! NSRegularExpression(pattern: #"^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$"#, options: [.anchorsMatchLines])
    private static let listMarker = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d{1,9}[.)])(?=[ \t])(?:[ \t]+\[[ xX]\](?=[ \t]))?"#, options: [.anchorsMatchLines])
    private static let inlineCode = try! NSRegularExpression(pattern: #"(`+)(?!`).+?(?<!`)\1(?!`)"#)
    private static let strong = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let emphasis = try! NSRegularExpression(pattern: #"(?<![*_\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*_\w])"#)
    private static let link = try! NSRegularExpression(pattern: #"!?\[[^\]\n]*\]\([^)\n]*\)"#)

    /// Returns the styled runs for `text`.
    ///
    /// - Parameter text: The Markdown source.
    /// - Returns: Runs in an unspecified order; later runs in the array take
    ///   precedence when applied.
    func runs(for text: String) -> [MarkdownSyntaxRun] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var runs: [MarkdownSyntaxRun] = []

        let codeBlocks = Self.fencedCode.matches(in: text, range: whole).map(\.range)
        func insideCode(_ range: NSRange) -> Bool {
            codeBlocks.contains { NSIntersectionRange($0, range).length > 0 }
        }
        func add(_ regex: NSRegularExpression, _ style: MarkdownSyntaxStyle) {
            for match in regex.matches(in: text, range: whole) where !insideCode(match.range) {
                runs.append(MarkdownSyntaxRun(range: match.range, style: style))
            }
        }

        add(Self.heading, .heading)
        add(Self.quote, .quote)
        add(Self.rule, .rule)
        add(Self.listMarker, .listMarker)
        add(Self.link, .link)
        add(Self.emphasis, .emphasis)
        add(Self.strong, .strong)
        add(Self.inlineCode, .code)
        runs += codeBlocks.map { MarkdownSyntaxRun(range: $0, style: .code) }
        return runs
    }

    /// The text attributes for a style. Colors are semantic system colors,
    /// so they adapt to light and dark mode (REQ-021).
    static func attributes(for style: MarkdownSyntaxStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .heading:
            return [.foregroundColor: NSColor.systemBlue,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)]
        case .strong:
            return [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)]
        case .emphasis:
            let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            return [.font: italic, .obliqueness: 0.12]
        case .code:
            return [.foregroundColor: NSColor.systemPink]
        case .link:
            return [.foregroundColor: NSColor.linkColor]
        case .quote:
            return [.foregroundColor: NSColor.secondaryLabelColor]
        case .listMarker:
            return [.foregroundColor: NSColor.systemOrange]
        case .rule:
            return [.foregroundColor: NSColor.tertiaryLabelColor]
        }
    }

    /// Re-colors a text storage in place. Only attributes change, so this
    /// doesn't affect undo or the selection.
    ///
    /// - Parameter storage: The text view's storage (no-op if `nil`).
    @MainActor
    func highlight(_ storage: NSTextStorage?) {
        guard let storage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: Self.baseFont, .foregroundColor: NSColor.textColor], range: whole)
        for run in runs(for: storage.string) {
            storage.addAttributes(Self.attributes(for: run.style), range: run.range)
        }
        storage.endEditing()
    }
}
