//
//  FindTests.swift
//  viewMDTests
//
//  Tests for find (REQ-025): the menu commands, the rendered pane's find
//  state, the page's search (live WKWebView) and the source pane's
//  built-in find bar (live NSTextView).
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
import Testing
import WebKit
@testable import viewMD

/// Polls `condition` until it's true or `timeout` passes.
@MainActor
private func waitUntil(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return false
}

/// Puts a view in an off-screen window so it lays out and renders.
@MainActor
private func host(_ view: NSView, size: NSSize = NSSize(width: 600, height: 400)) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -5000, y: -5000), size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.orderBack(nil)
    return window
}

// MARK: - Commands and results

@Suite("Find commands and results")
struct FindValueTests {

    @Test("Each menu command maps to the matching NSTextFinder action")
    func textFinderActions() {
        #expect(FindAction.showFind.textFinderAction == .showFindInterface)
        #expect(FindAction.showReplace.textFinderAction == .showReplaceInterface)
        #expect(FindAction.next.textFinderAction == .nextMatch)
        #expect(FindAction.previous.textFinderAction == .previousMatch)
        #expect(FindAction.useSelection.textFinderAction == .setSearchString)
    }

    @Test("Menu titles follow macOS wording")
    func titles() {
        #expect(FindAction.allCases.map(\.title) ==
                ["Find…", "Find and Replace…", "Find Next", "Find Previous", "Use Selection for Find"])
    }

    @Test("The status reads \"n of m\", \"Not found\", or nothing for an empty query")
    func summary() {
        #expect(FindMatches(count: 12, current: 2).summary(for: "x") == "3 of 12")
        #expect(FindMatches(count: 1, current: 0).summary(for: "x") == "1 of 1")
        #expect(FindMatches.none.summary(for: "x") == "Not found")
        #expect(FindMatches.none.summary(for: "") == "")
        #expect(FindMatches(count: 4, current: 1).summary(for: "") == "")
        #expect(FindMatches(count: 4, current: nil).summary(for: "x") == "4 matches")
    }

    @Test("Page results are decoded, and malformed ones mean no matches")
    func parse() {
        #expect(FindMatches.parse(["count": 3, "current": 1]) == FindMatches(count: 3, current: 1))
        #expect(FindMatches.parse(["count": 3, "current": -1]) == FindMatches(count: 3, current: nil))
        #expect(FindMatches.parse(["count": 3, "current": 7]) == FindMatches(count: 3, current: nil))
        #expect(FindMatches.parse(["count": 0, "current": -1]) == .none)
        #expect(FindMatches.parse(nil) == .none)
        #expect(FindMatches.parse("garbage") == .none)
    }
}

// MARK: - Rendered pane find state

/// A stand-in for the preview that records calls and returns set results.
@MainActor
private final class FakeSearcher: PreviewSearching {
    var calls: [(query: String, step: FindStep)] = []
    var result = FindMatches(count: 2, current: 0)
    var selection = ""
    var ended: [Bool] = []
    /// When set, `find` waits for this before returning.
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false

    func find(_ query: String, step: FindStep) async -> FindMatches {
        calls.append((query, step))
        let result = self.result
        if holdNext {
            holdNext = false
            await withCheckedContinuation { gate = $0 }
        }
        return result
    }

    func endFind(selectingMatch: Bool) { ended.append(selectingMatch) }

    func selectedText() async -> String { selection }
}

@Suite("Rendered pane find state")
@MainActor
struct PreviewFindModelTests {

    /// A model with a fake searcher and a private stand-in for the Find
    /// pasteboard, so tests don't touch the system's.
    private func makeModel(shared: String? = nil) -> (PreviewFindModel, FakeSearcher, Box) {
        let model = PreviewFindModel()
        let searcher = FakeSearcher()
        let pasteboard = Box(value: shared)
        model.searcher = searcher
        model.readFindString = { pasteboard.value }
        model.writeFindString = { pasteboard.value = $0 }
        return (model, searcher, pasteboard)
    }

    /// A mutable string shared with the closures above.
    final class Box { var value: String?; init(value: String?) { self.value = value } }

    @Test("⌘F shows the bar, takes the shared Find string, focuses and searches")
    func showFind() async {
        let (model, searcher, _) = makeModel(shared: "needle")
        await model.handle(.showFind)
        #expect(model.isVisible)
        #expect(model.query == "needle")
        #expect(model.focusRequest == 1)
        #expect(searcher.calls.last?.query == "needle")
        #expect(searcher.calls.last?.step == .update)
        #expect(model.matches == FindMatches(count: 2, current: 0))
    }

    @Test("⌘F again keeps the query and refocuses the field")
    func showFindTwice() async {
        let (model, _, _) = makeModel(shared: "first")
        await model.handle(.showFind)
        model.query = "mine"
        await model.handle(.showFind)
        #expect(model.query == "mine")
        #expect(model.focusRequest == 2)
    }

    @Test("Find and Replace shows the plain find bar in the rendered pane")
    func showReplace() async {
        let (model, _, _) = makeModel()
        await model.handle(.showReplace)
        #expect(model.isVisible)
    }

    @Test("⌘G and ⇧⌘G step through matches")
    func nextAndPrevious() async {
        let (model, searcher, _) = makeModel(shared: "x")
        await model.handle(.next)
        #expect(model.isVisible)
        #expect(searcher.calls.last?.step == .next)
        await model.handle(.previous)
        #expect(searcher.calls.last?.step == .previous)
    }

    @Test("⌘G with nothing to find opens the bar instead")
    func nextWithoutQuery() async {
        let (model, searcher, _) = makeModel(shared: nil)
        await model.handle(.next)
        #expect(model.isVisible)
        #expect(model.focusRequest == 1)
        #expect(searcher.calls.last?.step == .update)
    }

    @Test("⌘E searches for the selection and shares it")
    func useSelection() async {
        let (model, searcher, pasteboard) = makeModel()
        searcher.selection = "picked"
        await model.handle(.useSelection)
        #expect(model.query == "picked")
        #expect(model.isVisible)
        #expect(pasteboard.value == "picked")
        #expect(searcher.calls.last?.query == "picked")
    }

    @Test("⌘E with no selection does nothing")
    func useEmptySelection() async {
        let (model, searcher, _) = makeModel()
        await model.handle(.useSelection)
        #expect(!model.isVisible)
        #expect(searcher.calls.isEmpty)
    }

    @Test("Typing a query searches and shares it")
    func typing() async {
        let (model, searcher, pasteboard) = makeModel()
        await model.handle(.showFind)
        model.query = "abc"
        await model.queryDidChange()
        #expect(searcher.calls.last?.query == "abc")
        #expect(pasteboard.value == "abc")
    }

    @Test("A slow result is dropped once a newer search has finished")
    func staleResults() async {
        let (model, searcher, _) = makeModel()
        await model.handle(.showFind)
        model.query = "a"
        searcher.result = FindMatches(count: 9, current: 0)
        searcher.holdNext = true
        let slow = Task { await model.queryDidChange() }
        _ = await waitUntil { searcher.gate != nil }
        model.query = "ab"
        searcher.result = FindMatches(count: 1, current: 0)
        await model.queryDidChange()
        searcher.gate?.resume()
        await slow.value
        #expect(model.matches == FindMatches(count: 1, current: 0))
    }

    @Test("Done hides the bar, selects the current match and keeps the query")
    func close() async {
        let (model, searcher, _) = makeModel(shared: "x")
        await model.handle(.showFind)
        model.close()
        #expect(!model.isVisible)
        #expect(model.matches == .none)
        #expect(model.query == "x")
        #expect(searcher.ended == [true])
    }

    @Test("Done without a match doesn't select anything")
    func closeWithoutMatch() async {
        let (model, searcher, _) = makeModel(shared: "x")
        searcher.result = .none
        await model.handle(.showFind)
        model.close()
        #expect(searcher.ended == [false])
    }

    @Test("Recounts from the page update the status only while the bar is shown")
    func pageUpdates() async {
        let (model, _, _) = makeModel(shared: "x")
        model.pageDidUpdate(FindMatches(count: 5, current: 4))
        #expect(model.matches == .none)
        await model.handle(.showFind)
        model.pageDidUpdate(FindMatches(count: 5, current: 4))
        #expect(model.matches == FindMatches(count: 5, current: 4))
    }

    @Test("Commands go to the pane the user is working in")
    func routing() async {
        let editor = EditorModel()
        let searcher = FakeSearcher()
        editor.previewFind.searcher = searcher
        editor.previewFind.readFindString = { nil }
        editor.lastFocusedPane = .preview
        editor.find(.showFind)
        #expect(await waitUntil { editor.previewFind.isVisible })

        // With the source pane focused, the rendered pane's bar isn't used.
        let other = EditorModel()
        other.previewFind.searcher = searcher
        other.lastFocusedPane = .source
        other.find(.showFind)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!other.previewFind.isVisible)

        // With the source pane hidden, the rendered pane always gets them.
        other.isSourceVisible = false
        other.find(.showFind)
        #expect(await waitUntil { other.previewFind.isVisible })
    }
}

// MARK: - Live panes

@Suite("Find in the live panes", .serialized)
@MainActor
struct FindIntegrationTests {

    private let document = """
        # Find Me

        A paragraph with **bo**ld text and the word find, then FIND again.

        Second paragraph: find (with [brackets] and a.b) here.

        ```swift
        let find = "find"
        ```
        """

    /// A rendered preview in an off-screen window.
    private func makePreview(_ text: String) async throws -> (PreviewController, NSWindow) {
        let controller = PreviewController(folderAccess: .shared)
        let window = host(controller.webView)
        controller.update(text: text, baseURL: nil)
        let rendered = await waitUntil {
            let count = try? await controller.webView.evaluateJavaScript("document.querySelectorAll('#content > *').length") as? NSNumber
            return (count?.intValue ?? 0) >= 4
        }
        try #require(rendered, "Preview should render the document")
        return (controller, window)
    }

    /// The number of ranges in a named highlight (0 if it isn't set).
    private func highlightCount(_ name: String, in controller: PreviewController) async -> Int {
        let script = "CSS.highlights.has('\(name)') ? CSS.highlights.get('\(name)').size : 0"
        return (try? await controller.webView.evaluateJavaScript(script) as? NSNumber)?.intValue ?? -1
    }

    @Test("The page highlights every case-insensitive match, including in code")
    func countsMatches() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        // Heading, "find", "FIND", "find" in paragraph 2, and two in the code.
        let matches = await controller.find("find", step: .update)
        #expect(matches == FindMatches(count: 6, current: 0))
        #expect(await highlightCount("viewmd-find", in: controller) == 6)
        #expect(await highlightCount("viewmd-find-current", in: controller) == 1)
    }

    @Test("A match can cross inline formatting")
    func crossesInlineElements() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        #expect(await controller.find("bold text", step: .update).count == 1)
    }

    @Test("A match doesn't cross the boundary between blocks")
    func staysInBlocks() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        #expect(await controller.find("Find MeA paragraph", step: .update) == .none)
    }

    @Test("Characters special in patterns are matched literally")
    func literalQuery() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        #expect(await controller.find("[brackets]", step: .update).count == 1)
        #expect(await controller.find("a.b", step: .update).count == 1)
        #expect(await controller.find("a*b", step: .update) == .none)
    }

    @Test("Next and previous wrap around")
    func stepsAndWraps() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        _ = await controller.find("find", step: .update)
        #expect(await controller.find("find", step: .next).current == 1)
        #expect(await controller.find("find", step: .previous).current == 0)
        #expect(await controller.find("find", step: .previous).current == 5)
        #expect(await controller.find("find", step: .next).current == 0)
    }

    @Test("Matches are recounted when the document changes")
    func recountsAfterRender() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        var posted: FindMatches?
        controller.onFindUpdate = { posted = $0 }
        _ = await controller.find("find", step: .update)
        controller.update(text: document + "\n\nOne more find.", baseURL: nil)
        #expect(await waitUntil { posted?.count == 7 })
        #expect(await highlightCount("viewmd-find", in: controller) == 7)
    }

    @Test("Ending the search clears the highlights and can select the match")
    func endsSearch() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        _ = await controller.find("bold text", step: .update)
        controller.endFind(selectingMatch: true)
        #expect(await waitUntil { await highlightCount("viewmd-find", in: controller) == 0 })
        #expect(await controller.selectedText() == "bold text")
    }

    @Test("Searching doesn't change the page's HTML, so it can't look like an edit")
    func leavesDOMAlone() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        let script = "document.getElementById('content').innerHTML"
        let before = try await controller.webView.evaluateJavaScript(script) as? String
        _ = await controller.find("find", step: .update)
        _ = await controller.find("find", step: .next)
        let after = try await controller.webView.evaluateJavaScript(script) as? String
        #expect(before == after)
    }

    @Test("An empty query clears the highlights")
    func emptyQuery() async throws {
        let (controller, window) = try await makePreview(document)
        defer { window.close() }
        _ = await controller.find("find", step: .update)
        #expect(await controller.find("", step: .update) == .none)
        #expect(await highlightCount("viewmd-find", in: controller) == 0)
    }

    @Test("The source pane's commands drive its built-in find bar")
    func sourceFindBar() async throws {
        // The test writes the system Find pasteboard; put it back afterwards.
        let findPasteboard = NSPasteboard(name: .find)
        let saved = findPasteboard.string(forType: .string)
        defer {
            findPasteboard.clearContents()
            if let saved { findPasteboard.setString(saved, forType: .string) }
        }

        let controller = SourceEditorController()
        let scrollView = controller.makeScrollView()
        let window = host(scrollView)
        defer { window.close() }
        controller.setInitialText("alpha beta alpha gamma alpha")
        controller.focus()

        // Use the first "alpha" as the search string, then step through.
        // (Stepping is checked before the bar is shown: with the bar open,
        // NSTextFinder searches incrementally, which needs a key window, and
        // a test window can't become key. FindUITests covers that path.)
        controller.textView.setSelectedRange(NSRange(location: 0, length: 5))
        controller.performFind(.useSelection)
        #expect(findPasteboard.string(forType: .string) == "alpha")
        controller.performFind(.next)
        #expect(await waitUntil { controller.selectedRange == NSRange(location: 11, length: 5) })
        controller.performFind(.next)
        #expect(await waitUntil { controller.selectedRange == NSRange(location: 23, length: 5) })
        controller.performFind(.previous)
        #expect(await waitUntil { controller.selectedRange == NSRange(location: 11, length: 5) })

        controller.performFind(.showFind)
        #expect(scrollView.isFindBarVisible)
    }
}
