//
//  Autolinker.swift
//  viewMD
//
//  GFM "extended autolinks" (spec §6.9): bare URLs and email addresses in text
//  become links. swift-markdown doesn't enable cmark-gfm's autolink
//  extension, so viewMD implements it here (REQ-016).
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

/// Converts plain text to HTML, turning bare `http(s)://…`, `www.…` and
/// email addresses into links the way GitHub does.
nonisolated enum Autolinker {

    /// Candidate links: group 1 is a URL (`https://…`, `http://…`,
    /// `www.…`), group 2 an email address. A candidate must start at the
    /// beginning of the text or after whitespace or one of `*_~(`, per the
    /// spec. Trailing punctuation is trimmed afterwards in ``trimTrailing(_:)``.
    private static let candidatePattern = try! NSRegularExpression(pattern: #"""
        (?<=^|[\s*_~(])(?:((?:https?://|www\.)[^\s<]+)|([A-Za-z0-9._+-]+@[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+))
        """#)

    /// Returns `text` as escaped HTML with GFM extended autolinks applied.
    ///
    /// - Parameter text: Plain text from a Markdown text run (not inside a
    ///   link or code span).
    /// - Returns: HTML-escaped text where each autolink is an `<a href>`.
    static func linkify(_ text: String) -> String {
        let nsText = text as NSString
        let matches = candidatePattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return HTMLEscaping.escape(text) }

        var result = ""
        var cursor = 0
        for match in matches {
            let isURL = match.range(at: 1).location != NSNotFound
            var link = nsText.substring(with: match.range)
            link = isURL ? trimTrailing(link) : trimEmail(link)
            guard !link.isEmpty, isURL ? isValidURLCandidate(link) : true else { continue }

            let linkLength = (link as NSString).length
            result += HTMLEscaping.escape(nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            let href: String
            if isURL {
                href = link.lowercased().hasPrefix("www.") ? "http://" + link : link
            } else {
                href = "mailto:" + link
            }
            result += "<a href=\"\(HTMLEscaping.escape(URLPolicy.percentEncodeUnsafe(href)))\">\(HTMLEscaping.escape(link))</a>"
            cursor = match.range.location + linkLength
        }
        result += HTMLEscaping.escape(nsText.substring(from: cursor))
        return result
    }

    /// Applies the spec's trailing-character rules to a URL candidate:
    /// trailing `?!.,:*_~` and `'"` are not part of the link, an unbalanced
    /// trailing `)` is excluded, and so is a trailing entity-like `&name;`.
    /// The rules repeat until nothing changes.
    static func trimTrailing(_ candidate: String) -> String {
        var link = Substring(candidate)
        while let last = link.last {
            if "?!.,:*_~'\"".contains(last) {
                link = link.dropLast()
            } else if last == ")" {
                let opens = link.filter { $0 == "(" }.count
                let closes = link.filter { $0 == ")" }.count
                guard closes > opens else { break }
                link = link.dropLast()
            } else if last == ";", let ampersand = link.lastIndex(of: "&"),
                      link[link.index(after: ampersand)..<link.index(before: link.endIndex)].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                link = link[..<ampersand]
            } else {
                break
            }
        }
        return String(link)
    }

    /// Email candidates may not end in `-` or `_`, and a trailing `.` ends
    /// the sentence rather than the address.
    private static func trimEmail(_ candidate: String) -> String {
        var email = Substring(candidate)
        while email.last == "." { email = email.dropLast() }
        if let last = email.last, last == "-" || last == "_" { return "" }
        return String(email)
    }

    /// Checks the domain against the spec's "valid domain" rule: after the
    /// scheme or `www.` prefix it has at least one `.`, no empty segments,
    /// and no `_` in its last two segments.
    private static func isValidURLCandidate(_ link: String) -> Bool {
        var rest = Substring(link)
        for prefix in ["https://", "http://", "www."] where rest.lowercased().hasPrefix(prefix) {
            rest = rest.dropFirst(prefix.count)
        }
        let domain = rest.prefix { !"/?#".contains($0) }
        let segments = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.allSatisfy({ !$0.isEmpty }) else { return false }
        return segments.suffix(2).allSatisfy { !$0.contains("_") }
    }
}
