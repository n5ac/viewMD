//
//  CodeHighlighter.swift
//  viewMD
//
//  Syntax-highlights code blocks for exports (REQ-017, REQ-019) by running the
//  bundled highlight.js in JavaScriptCore, so exported HTML needs no script.
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
import JavaScriptCore

/// Highlights fenced code blocks in rendered HTML ahead of time.
///
/// The preview highlights code in the page with highlight.js. Exported HTML
/// should be static and script-free, so the same library runs here in a
/// `JSContext` (it doesn't need a DOM for `hljs.highlight`), and the
/// resulting markup is baked into the HTML.
@MainActor
final class CodeHighlighter {

    /// Matches a fenced code block with a language class. Group 1 is the
    /// language, group 2 the escaped code.
    private static let codeBlockPattern = try! NSRegularExpression(
        pattern: #"<code class="language-([A-Za-z0-9_+#.-]+)">(.*?)</code>"#,
        options: [.dotMatchesLineSeparators])

    private let context: JSContext?

    /// Creates a highlighter by loading `highlight.min.js` from the bundle.
    /// If the script can't be loaded, ``highlight(_:)`` returns its input
    /// unchanged.
    ///
    /// - Parameter bundle: The bundle containing `highlight.min.js`.
    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "highlight.min", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else {
            self.context = nil
            return
        }
        context.evaluateScript(script)
        self.context = context.objectForKeyedSubscript("hljs").isUndefined ? nil : context
    }

    /// Whether highlight.js loaded.
    var isAvailable: Bool { context != nil }

    /// Returns `html` with each `<code class="language-x">` block highlighted
    /// (`<code class="hljs language-x">` with highlight.js spans). Blocks in
    /// unknown languages are left as they are.
    ///
    /// - Parameter html: Rendered HTML from ``MarkdownRenderer``.
    /// - Returns: The HTML with highlighted code.
    func highlight(_ html: String) -> String {
        guard let context, let hljs = context.objectForKeyedSubscript("hljs") else { return html }
        let ns = html as NSString
        var result = ""
        var cursor = 0
        for match in Self.codeBlockPattern.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = NSMaxRange(match.range)
            let language = ns.substring(with: match.range(at: 1))
            let code = Self.unescape(ns.substring(with: match.range(at: 2)))
            guard hljs.invokeMethod("getLanguage", withArguments: [language])?.isUndefined == false,
                  let output = hljs.invokeMethod("highlight", withArguments: [code, ["language": language, "ignoreIllegals": true]]),
                  let value = output.objectForKeyedSubscript("value")?.toString(),
                  !output.isUndefined else {
                result += ns.substring(with: match.range)
                continue
            }
            result += "<code class=\"hljs language-\(language)\">\(value)</code>"
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Reverses ``HTMLEscaping/escape(_:)`` (highlight.js escapes its own
    /// output, so the code must be passed in raw).
    nonisolated static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
