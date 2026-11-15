//
//  HTMLEscaping.swift
//  viewMD
//
//  Escaping helpers shared by the renderer and sanitizer.
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
