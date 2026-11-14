//
//  URLPolicy.swift
//  viewMD
//
//  Decides which link and image URLs are safe to emit, and resolves relative
//  URLs against the document's folder (REQ-007, REQ-022).
//

import Foundation

/// Rules for URLs that appear in rendered Markdown (link `href`s, image `src`s,
/// and URL attributes in raw HTML).
nonisolated enum URLPolicy {

    /// The kind of element a URL belongs to. Images may use `data:` URLs for
    /// raster images; links may not use `data:` at all.
    enum Context {
        /// A hyperlink (`<a href>`, `<form action>`, …).
        case link
        /// An embedded resource (`<img src>`, `<video poster>`, …).
        case image
    }

    /// `data:` media types allowed for images. SVG is excluded because an SVG
    /// document can carry script.
    private static let safeImageDataPrefixes = [
        "data:image/png", "data:image/gif", "data:image/jpeg", "data:image/jpg", "data:image/webp",
    ]

    /// Reports whether a URL is safe to put in a rendered document.
    ///
    /// Script-capable schemes (`javascript:`, `vbscript:`) are always
    /// rejected, and so is `data:` except raster images in an image context.
    /// Browsers ignore embedded whitespace and control characters in a scheme
    /// and decode character references in attributes, so the check is made
    /// on a normalized copy: `java&#x09;script:` is rejected the same as
    /// `javascript:`.
    ///
    /// - Parameters:
    ///   - url: The URL as written in the document.
    ///   - context: Whether the URL is a link target or an embedded resource.
    /// - Returns: `true` if the URL may be emitted.
    static func isSafe(_ url: String, context: Context) -> Bool {
        let normalized = normalizeForSchemeCheck(url)
        if normalized.hasPrefix("javascript:") || normalized.hasPrefix("vbscript:") {
            return false
        }
        if normalized.hasPrefix("data:") {
            return context == .image && safeImageDataPrefixes.contains { normalized.hasPrefix($0) }
        }
        return true
    }

    /// Resolves a relative URL against a base folder.
    ///
    /// Absolute URLs (any `scheme:`), protocol-relative URLs (`//host`),
    /// fragment-only links (`#section`) and empty strings are returned
    /// unchanged, as is everything when `baseURL` is `nil` (an unsaved
    /// document has no folder).
    ///
    /// - Parameters:
    ///   - url: The URL as written in the document (already entity-decoded).
    ///   - baseURL: The folder containing the document, or `nil`.
    /// - Returns: The absolute URL string, or `url` unchanged.
    static func resolve(_ url: String, against baseURL: URL?) -> String {
        guard let baseURL,
              !url.isEmpty,
              !url.hasPrefix("#"),
              !url.hasPrefix("//"),
              !hasScheme(url)
        else { return url }
        // A file URL without a trailing slash would resolve against its
        // parent folder, so make sure the base is treated as a directory.
        let base = baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent("", isDirectory: true)
        guard let resolved = URL(string: percentEncodeUnsafe(url), relativeTo: base) else { return url }
        return resolved.absoluteString
    }

    /// Percent-encodes characters that are never valid unencoded in a URL
    /// (whitespace, controls and ``"<>\^`{|}``), leaving existing `%`
    /// escapes and reserved characters alone. This mirrors cmark's
    /// `houdini_escape_href`, so `[x](my file.md)` produces a working link.
    ///
    /// - Parameter url: A URL string that may contain unsafe characters.
    /// - Returns: The URL with only those characters percent-encoded.
    static func percentEncodeUnsafe(_ url: String) -> String {
        let unsafe = CharacterSet(charactersIn: "\"<>\\^`{|}")
            .union(.whitespacesAndNewlines)
            .union(.controlCharacters)
        guard url.unicodeScalars.contains(where: unsafe.contains) else { return url }
        var result = ""
        for scalar in url.unicodeScalars {
            if unsafe.contains(scalar) {
                for byte in String(scalar).utf8 {
                    result += String(format: "%%%02X", byte)
                }
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Reports whether `url` starts with a URL scheme (`letter *(letter /
    /// digit / "+" / "-" / ".") ":"`, RFC 3986 §3.1).
    ///
    /// A Windows-style drive letter (`C:`) isn't special-cased; it's
    /// irrelevant on macOS.
    private static func hasScheme(_ url: String) -> Bool {
        guard let colon = url.firstIndex(of: ":"), colon != url.startIndex else { return false }
        let scheme = url[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }
    }

    /// Lowercases `url`, decodes numeric and the common named character
    /// references, and removes whitespace and control characters, the way a
    /// browser would before interpreting the scheme.
    private static func normalizeForSchemeCheck(_ url: String) -> String {
        var decoded = decodeCharacterReferences(url)
        decoded.unicodeScalars.removeAll { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
        return decoded.lowercased()
    }

    /// Decodes `&#NN;`, `&#xNN;` and the named references attackers use to
    /// split a scheme (`&colon;`, `&Tab;`, `&NewLine;`). The trailing `;` is
    /// optional for numeric references, as it is in browsers.
    private static func decodeCharacterReferences(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (name, value) in [("&colon;", ":"), ("&tab;", "\t"), ("&newline;", "\n")] {
            result = result.replacingOccurrences(of: name, with: value, options: .caseInsensitive)
        }
        let pattern = #/&#([xX][0-9A-Fa-f]+|[0-9]+);?/#
        return result.replacing(pattern) { match in
            let body = match.output.1
            let value = body.first == "x" || body.first == "X"
                ? UInt32(body.dropFirst(), radix: 16)
                : UInt32(body, radix: 10)
            guard let value, let scalar = Unicode.Scalar(value) else { return "" }
            return String(Character(scalar))
        }
    }
}
