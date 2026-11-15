//
//  HTMLSanitizer.swift
//  viewMD
//
//  Neutralizes script in raw HTML embedded in Markdown (REQ-007).
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

/// Removes script-capable constructs from raw HTML found in a Markdown
/// document (HTML blocks and inline HTML).
///
/// GFM allows raw HTML, and most of it, like `<details>`, `<kbd>` and
/// `<sup>`, is useful and kept. The sanitizer:
///
/// 1. Applies GFM's *tagfilter* extension, extended with a few more
///    elements. The opening `<` of `<script>`, `<iframe>`, `<style>` and
///    similar tags becomes `&lt;`, so the tag shows as text instead of
///    running. See ``filteredTags``.
/// 2. Drops every `on*` event-handler attribute (`onclick`, `onerror`, …).
/// 3. Drops URL attributes (`href`, `src`, …) whose value fails
///    ``URLPolicy/isSafe(_:context:)``, e.g. `javascript:` URLs.
///
/// It works on tags it recognizes with the CommonMark raw-HTML grammar, and
/// leaves text between tags untouched. It is one layer of defense: the
/// preview page also sets a Content-Security-Policy that blocks inline script
/// (Phase 2).
nonisolated enum HTMLSanitizer {

    /// Tags whose opening `<` is escaped. The first nine are GFM's
    /// tagfilter list; the rest can load or run active content, or change
    /// how the page resolves URLs.
    static let filteredTags: Set<String> = [
        // GFM tagfilter (spec §6.11).
        "title", "textarea", "style", "xmp", "iframe", "noembed", "noframes", "script", "plaintext",
        // Additional active-content / page-altering elements.
        "object", "embed", "applet", "frame", "frameset", "base", "meta", "link",
    ]

    /// Attributes that hold a hyperlink target.
    private static let linkAttributes: Set<String> = ["href", "action", "formaction", "xlink:href", "cite"]

    /// Attributes that hold an embedded-resource URL.
    private static let resourceAttributes: Set<String> = ["src", "poster", "background", "data", "srcset"]

    /// Matches an open or closing tag, following the CommonMark raw-HTML
    /// grammar (spec §6.6), so quoted attribute values may contain `>`.
    /// Group 1 is `/` for closing tags, group 2 the tag name, group 3 the
    /// attribute text, group 4 the optional self-closing `/`.
    private static let tagPattern = try! NSRegularExpression(pattern: #"""
        <(/?)([A-Za-z][A-Za-z0-9-]*)((?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*(/?)>
        """#)

    /// Matches one attribute inside a tag's attribute text. Group 1 is the
    /// name; group 2 the value with its quotes, if any.
    private static let attributePattern = try! NSRegularExpression(pattern: #"""
        \s+([A-Za-z_:][A-Za-z0-9_.:-]*)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s"'=<>`]+))?
        """#)

    /// Matches the start of a filtered tag, open or closing, for the
    /// tagfilter step: `<` + optional `/` + tag name + a delimiter.
    private static let tagFilterPattern: NSRegularExpression = {
        let names = filteredTags.sorted().joined(separator: "|")
        return try! NSRegularExpression(pattern: "<(?=/?(?:\(names))(?:[\\s/>]|$))", options: [.caseInsensitive])
    }()

    /// Returns `html` with script-capable constructs removed.
    ///
    /// - Parameter html: Raw HTML from the Markdown source. It may be a
    ///   fragment, such as a lone opening tag from inline HTML.
    /// - Returns: HTML that is safe to insert into the preview page.
    static func sanitize(_ html: String) -> String {
        guard html.contains("<") else { return html }
        let filtered = applyTagFilter(html)
        return rewriteTags(in: filtered)
    }

    /// Step 1: escapes the `<` of every filtered tag.
    private static func applyTagFilter(_ html: String) -> String {
        let range = NSRange(html.startIndex..., in: html)
        return tagFilterPattern.stringByReplacingMatches(in: html, range: range, withTemplate: "&lt;")
    }

    /// Steps 2 and 3: rebuilds each tag without unsafe attributes. Text and
    /// tags that need no changes are copied through byte-for-byte.
    private static func rewriteTags(in html: String) -> String {
        let nsHTML = html as NSString
        var result = ""
        var cursor = 0
        for match in tagPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            result += nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let isClosing = match.range(at: 1).length > 0
            let attributes = nsHTML.substring(with: match.range(at: 3))
            if isClosing || attributes.isEmpty {
                result += nsHTML.substring(with: match.range)
            } else {
                let name = nsHTML.substring(with: match.range(at: 2))
                let selfClosing = match.range(at: 4).length > 0
                result += "<" + name + safeAttributes(attributes) + (selfClosing ? " />" : ">")
            }
            cursor = match.range.location + match.range.length
        }
        result += nsHTML.substring(from: cursor)
        return result
    }

    /// Returns the attribute text with event handlers and unsafe URL
    /// attributes removed. Kept attributes are copied as written.
    private static func safeAttributes(_ attributes: String) -> String {
        let nsAttributes = attributes as NSString
        var kept = ""
        for match in attributePattern.matches(in: attributes, range: NSRange(location: 0, length: nsAttributes.length)) {
            let name = nsAttributes.substring(with: match.range(at: 1)).lowercased()
            if name.hasPrefix("on") { continue }
            if match.range(at: 2).location != NSNotFound {
                let value = unquote(nsAttributes.substring(with: match.range(at: 2)))
                if linkAttributes.contains(name), !URLPolicy.isSafe(value, context: .link) { continue }
                if resourceAttributes.contains(name), !isSafeResourceValue(value, attribute: name) { continue }
            }
            kept += nsAttributes.substring(with: match.range)
        }
        return kept
    }

    /// Checks a resource attribute. `srcset` holds a comma-separated list of
    /// `URL [descriptor]` candidates, and each URL is checked.
    private static func isSafeResourceValue(_ value: String, attribute: String) -> Bool {
        guard attribute == "srcset" else { return URLPolicy.isSafe(value, context: .image) }
        return value.split(separator: ",").allSatisfy { candidate in
            let url = candidate.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            return URLPolicy.isSafe(url, context: .image)
        }
    }

    /// Strips one pair of matching surrounding quotes, if present.
    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
