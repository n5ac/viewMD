//
//  ScrollSync.swift
//  viewMD
//
//  Keeps the two panes scrolled to the same part of the document (REQ-020).
//

import Foundation

/// Converts between source line numbers and UTF-16 offsets.
nonisolated enum LineIndex {

    /// The 1-based line containing a UTF-16 offset.
    ///
    /// - Parameters:
    ///   - offset: A UTF-16 offset into `text` (clamped).
    ///   - text: The source text.
    /// - Returns: The line number, starting at 1.
    static func line(atUTF16Offset offset: Int, in text: String) -> Int {
        let utf16 = text.utf16
        let end = utf16.index(utf16.startIndex, offsetBy: min(max(0, offset), utf16.count))
        return utf16[utf16.startIndex..<end].reduce(1) { $1 == 10 ? $0 + 1 : $0 }
    }

    /// The UTF-16 offset where a 1-based line starts.
    ///
    /// - Parameters:
    ///   - line: The line number (clamped to the document).
    ///   - text: The source text.
    /// - Returns: The offset of the line's first character.
    static func utf16Offset(ofLine line: Int, in text: String) -> Int {
        guard line > 1 else { return 0 }
        var current = 1
        for (index, unit) in text.utf16.enumerated() where unit == 10 {
            current += 1
            if current == line { return index + 1 }
        }
        return text.utf16.count
    }
}

/// Decides when one pane's scrolling should move the other.
///
/// When the user scrolls a pane, the other pane is scrolled to the same
/// source line. That programmatic scroll makes the other pane report a
/// scroll of its own, which must not echo back. So after driving a pane,
/// its reports are ignored for a short window.
@MainActor
final class ScrollSync {

    /// How long a driven pane's own scroll reports are ignored.
    static let echoWindow: TimeInterval = 0.3

    /// The clock (injectable for tests).
    var now: () -> Date = Date.init

    private var ignoreUntil: [EditorPane: Date] = [:]

    /// Reports that `pane` scrolled so `line` is at its top.
    ///
    /// - Parameters:
    ///   - pane: The pane that scrolled.
    ///   - line: The 1-based source line now at its top.
    /// - Returns: The line the other pane should scroll to, or `nil` if this
    ///   report is an echo of a scroll this object caused.
    func paneDidScroll(_ pane: EditorPane, toLine line: Int) -> Int? {
        if let until = ignoreUntil[pane], now() < until { return nil }
        ignoreUntil[pane.other] = now().addingTimeInterval(Self.echoWindow)
        return max(1, line)
    }
}

extension EditorPane {
    /// The pane on the other side of the window.
    nonisolated var other: EditorPane {
        self == .source ? .preview : .source
    }
}
