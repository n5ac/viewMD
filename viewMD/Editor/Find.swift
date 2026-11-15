//
//  Find.swift
//  viewMD
//
//  Find (⌘F) in either pane (REQ-025). The source pane uses NSTextView's
//  built-in find bar. WKWebView has no public find bar, so the rendered pane
//  gets its own, driven by `PreviewFindModel` and searched by bridge.js.
//

import AppKit
import Observation

/// A command from the Edit ▸ Find menu.
nonisolated enum FindAction: CaseIterable, Sendable {
    /// Show the find bar and focus its search field (⌘F).
    case showFind
    /// Show the find bar with replace (⌥⌘F). The rendered pane has no
    /// replace, so there it shows the plain find bar.
    case showReplace
    /// Go to the next match (⌘G).
    case next
    /// Go to the previous match (⇧⌘G).
    case previous
    /// Search for the selected text (⌘E).
    case useSelection

    /// The menu item title.
    var title: String {
        switch self {
        case .showFind: "Find…"
        case .showReplace: "Find and Replace…"
        case .next: "Find Next"
        case .previous: "Find Previous"
        case .useSelection: "Use Selection for Find"
        }
    }

    /// The equivalent `NSTextFinder` action, used for the source pane.
    var textFinderAction: NSTextFinder.Action {
        switch self {
        case .showFind: .showFindInterface
        case .showReplace: .showReplaceInterface
        case .next: .nextMatch
        case .previous: .previousMatch
        case .useSelection: .setSearchString
        }
    }
}

/// How the rendered pane's search moves to a match. The raw values are the
/// `step` argument of `viewmd.find` in bridge.js.
nonisolated enum FindStep: String, Sendable {
    /// The query changed (or the bar was reopened): go to the first match
    /// at or below the top of the view, and scroll to it.
    case update
    /// Go to the next match, wrapping at the end.
    case next
    /// Go to the previous match, wrapping at the start.
    case previous
    /// The page re-rendered: recount and repaint without moving or
    /// scrolling.
    case refresh
}

/// The result of a search in the rendered pane.
nonisolated struct FindMatches: Equatable, Sendable {
    /// How many matches there are.
    var count: Int
    /// The 0-based index of the current match, or `nil` if there is none.
    var current: Int?

    /// No matches.
    static let none = FindMatches(count: 0, current: nil)

    /// The status shown in the find bar: "3 of 12", "Not found", or nothing
    /// while the query is empty.
    ///
    /// - Parameter query: The text being searched for.
    /// - Returns: The status text.
    func summary(for query: String) -> String {
        guard !query.isEmpty else { return "" }
        guard count > 0 else { return "Not found" }
        guard let current else { return count == 1 ? "1 match" : "\(count) matches" }
        return "\(current + 1) of \(count)"
    }

    /// Decodes a result from bridge.js: `{count, current}`, where `current`
    /// is `-1` when there's no current match.
    ///
    /// - Parameter value: The value returned by, or posted from, the page.
    /// - Returns: The matches, or ``none`` if the value is malformed.
    static func parse(_ value: Any?) -> FindMatches {
        guard let body = value as? [String: Any],
              let count = (body["count"] as? NSNumber)?.intValue, count > 0 else { return .none }
        let current = (body["current"] as? NSNumber)?.intValue
        return FindMatches(count: count, current: current.flatMap { (0..<count).contains($0) ? $0 : nil })
    }
}

/// Something that can search the rendered pane. `PreviewController`
/// implements it; tests use a fake.
@MainActor
protocol PreviewSearching: AnyObject {
    /// Searches for `query` (case-insensitive), highlights every match and
    /// moves to one as `step` says.
    ///
    /// - Parameters:
    ///   - query: The text to find. Empty clears the highlights.
    ///   - step: How to choose the current match.
    /// - Returns: The match count and current match.
    func find(_ query: String, step: FindStep) async -> FindMatches

    /// Clears the highlights. If `selectingMatch` is true, the current match
    /// becomes the selection, so the user can edit it.
    func endFind(selectingMatch: Bool)

    /// The text selected in the pane (empty if none).
    func selectedText() async -> String
}

/// State of the rendered pane's find bar (REQ-025).
///
/// Searches go to ``searcher`` (the window's preview). Each search is
/// numbered, and a result is only shown if no newer search has started, so
/// fast typing can't leave a stale count.
@MainActor
@Observable
final class PreviewFindModel {

    /// Whether the find bar is shown above the rendered pane.
    private(set) var isVisible = false

    /// The text being searched for, bound to the bar's search field.
    var query = ""

    /// The current matches, for the bar's status text.
    private(set) var matches = FindMatches.none

    /// Incremented to ask the bar to focus its search field.
    private(set) var focusRequest = 0

    /// The pane to search.
    @ObservationIgnored weak var searcher: (any PreviewSearching)?

    /// Reads the shared Find pasteboard, so a search started in another
    /// pane or app carries over (standard macOS behavior).
    @ObservationIgnored var readFindString: () -> String? = {
        NSPasteboard(name: .find).string(forType: .string)
    }

    /// Writes the shared Find pasteboard.
    @ObservationIgnored var writeFindString: (String) -> Void = { string in
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// The number of the most recent search.
    @ObservationIgnored private var generation = 0

    /// Runs a menu command without waiting for it.
    ///
    /// - Parameter action: The Edit ▸ Find command.
    func perform(_ action: FindAction) {
        Task { await handle(action) }
    }

    /// Runs a menu command.
    ///
    /// - Parameter action: The Edit ▸ Find command.
    func handle(_ action: FindAction) async {
        switch action {
        case .showFind, .showReplace:
            if !isVisible {
                isVisible = true
                if query.isEmpty, let shared = readFindString(), !shared.isEmpty { query = shared }
            }
            focusRequest += 1
            await search(.update)
        case .next, .previous:
            if query.isEmpty, let shared = readFindString() { query = shared }
            guard !query.isEmpty else { return await handle(.showFind) }
            isVisible = true
            await search(action == .next ? .next : .previous)
        case .useSelection:
            guard let selected = await searcher?.selectedText(), !selected.isEmpty else { return }
            query = selected
            writeFindString(selected)
            isVisible = true
            await search(.update)
        }
    }

    /// Searches again after the user edits the query.
    func queryDidChange() async {
        if !query.isEmpty { writeFindString(query) }
        await search(.update)
    }

    /// Hides the bar and clears the highlights, leaving the current match
    /// selected. The query is kept for next time.
    func close() {
        guard isVisible else { return }
        isVisible = false
        generation += 1
        let hadMatch = matches.current != nil
        matches = .none
        searcher?.endFind(selectingMatch: hadMatch)
    }

    /// Takes a recount the page made by itself after re-rendering.
    ///
    /// - Parameter newMatches: The matches in the updated page.
    func pageDidUpdate(_ newMatches: FindMatches) {
        guard isVisible else { return }
        matches = newMatches
    }

    /// Searches for ``query`` and shows the result if it's still the latest.
    private func search(_ step: FindStep) async {
        guard let searcher else { return }
        generation += 1
        let mine = generation
        let result = await searcher.find(query, step: step)
        guard mine == generation, isVisible else { return }
        matches = result
    }
}
