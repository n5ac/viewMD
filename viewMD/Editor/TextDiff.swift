//
//  TextDiff.swift
//  viewMD
//
//  Finds the smallest single edit that turns one string into another, so an
//  external change (e.g. an edit made in the rendered pane) can be applied to
//  the source text view as one undoable replacement that leaves the caret
//  and scroll position alone.
//

import Foundation

/// A single replacement within a string, measured in UTF-16 code units
/// (the units `NSTextView` and `NSString` use).
nonisolated struct TextReplacement: Equatable, Sendable {
    /// The range in the old string to replace.
    var range: NSRange
    /// The text to put in its place.
    var replacement: String
}

/// Computes minimal replacements between strings.
nonisolated enum TextDiff {

    /// Returns the smallest single replacement that turns `old` into `new`,
    /// found by trimming their common prefix and common suffix, or `nil` if
    /// the strings are equal.
    ///
    /// The prefix and suffix are compared on UTF-16 code units and then
    /// widened to whole composed characters, so an edit never splits an
    /// emoji or an accented letter.
    ///
    /// - Parameters:
    ///   - old: The current text.
    ///   - new: The desired text.
    /// - Returns: The replacement, or `nil` if there is no difference.
    static func replacement(from old: String, to new: String) -> TextReplacement? {
        guard old != new else { return nil }
        let oldNS = old as NSString
        let newNS = new as NSString
        let oldLength = oldNS.length
        let newLength = newNS.length

        var prefix = 0
        let maxPrefix = min(oldLength, newLength)
        while prefix < maxPrefix, oldNS.character(at: prefix) == newNS.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        let maxSuffix = min(oldLength, newLength) - prefix
        while suffix < maxSuffix,
              oldNS.character(at: oldLength - 1 - suffix) == newNS.character(at: newLength - 1 - suffix) {
            suffix += 1
        }

        // Widen to composed-character boundaries in the old string; the same
        // offsets are boundaries in the new string because the prefix and
        // suffix text is identical.
        var start = prefix
        if start > 0, start < oldLength {
            start = oldNS.rangeOfComposedCharacterSequence(at: start).location
        }
        var oldEnd = oldLength - suffix
        if oldEnd > start, oldEnd < oldLength {
            let composed = oldNS.rangeOfComposedCharacterSequence(at: oldEnd)
            if composed.location < oldEnd { oldEnd = composed.location + composed.length }
        }
        // Keep the new string's end consistent with how far the suffix moved.
        let newEnd = newLength - (oldLength - oldEnd)
        let replacement = newNS.substring(with: NSRange(location: start, length: max(0, newEnd - start)))
        return TextReplacement(range: NSRange(location: start, length: oldEnd - start), replacement: replacement)
    }
}
