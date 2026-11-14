//
//  HTMLEscaping.swift
//  viewMD
//
//  Escaping helpers shared by the renderer and sanitizer.
//

import Foundation

/// Escapes text for safe inclusion in HTML.
///
/// The same rules are used for element content and for double-quoted
/// attribute values. They match cmark's HTML renderer: `&`, `<`, `>` and `"`
/// are replaced with entities.
nonisolated enum HTMLEscaping {

    /// Returns `text` with HTML-special characters replaced by entities.
    ///
    /// - Parameter text: Raw text that must display literally.
    /// - Returns: The escaped text, safe inside element content or a
    ///   double-quoted attribute value.
    static func escape(_ text: String) -> String {
        // Fast path: most text runs contain nothing to escape.
        guard text.contains(where: { $0 == "&" || $0 == "<" || $0 == ">" || $0 == "\"" }) else {
            return text
        }
        var result = ""
        result.reserveCapacity(text.utf8.count + 16)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }
}
