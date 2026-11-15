//
//  PreviewEditingUITests.swift
//  viewMDUITests
//
//  UI tests for editing in the rendered pane (REQ-013), inserting from it
//  (REQ-015), and undo across both panes.
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

import XCTest

/// Drives edits in the rendered (left) pane and checks the Markdown source.
final class PreviewEditingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithoutRestoredWindows()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private var window: XCUIElement { app.windows.firstMatch }
    private var sourceEditor: XCUIElement { window.textViews["source-editor"] }
    private var preview: XCUIElement { window.webViews.firstMatch }
    private var sourceText: String { sourceEditor.value as? String ?? "" }

    /// Waits until the source text satisfies a condition.
    private func waitForSource(_ description: String, timeout: TimeInterval = 5, _ condition: @escaping (String) -> Bool) {
        let predicate = NSPredicate { _, _ in condition(self.sourceText) }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        expectation.expectationDescription = description
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(description). Source was: \(sourceText)")
    }

    /// Types `markdown` into the source pane and waits for the preview.
    private func seed(_ markdown: String, waitingFor text: String) {
        sourceEditor.click()
        sourceEditor.typeText(markdown)
        XCTAssertTrue(preview.staticTexts[text].waitForExistence(timeout: 5))
    }

    /// Typing at the end of a rendered paragraph updates that line of the
    /// source and leaves the other blocks alone.
    @MainActor
    func testTypingInPreviewUpdatesSource() throws {
        seed("# Title\n\nHello\n\nLast", waitingFor: "Hello")
        preview.staticTexts["Hello"].click()
        app.typeKey(.rightArrow, modifierFlags: .command) // end of line
        app.typeText(" world")
        waitForSource("Edit should reach the source") { $0 == "# Title\n\nHello world\n\nLast" }
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "Edited in preview"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// ⌘B in the rendered pane bolds the selection, which becomes ** in the source.
    @MainActor
    func testBoldInPreview() throws {
        seed("make this bold", waitingFor: "make this bold")
        preview.staticTexts["make this bold"].doubleClick() // selects a word
        app.typeKey("b", modifierFlags: .command)
        waitForSource("⌘B in preview should add ** markers") { $0.contains("**") }
    }

    /// Inserting a table while the rendered pane has focus adds it after the
    /// block containing the caret.
    @MainActor
    func testInsertTableFromPreview() throws {
        seed("First\n\nSecond", waitingFor: "First")
        preview.staticTexts["First"].click()
        window.toolbars.menuButtons["menu-Insert"].click()
        window.menuItems["insert-Table"].click()
        waitForSource("Table should follow the first paragraph") { $0.hasPrefix("First\n\n| Column 1 | Column 2 |") && $0.hasSuffix("Second") }
    }

    /// ⌘Z after an edit in the rendered pane restores the source.
    @MainActor
    func testUndoPreviewEdit() throws {
        seed("Alpha", waitingFor: "Alpha")
        preview.staticTexts["Alpha"].click()
        app.typeKey(.rightArrow, modifierFlags: .command)
        app.typeText(" Beta")
        waitForSource("Edit should reach the source") { $0 == "Alpha Beta" }
        app.typeKey("z", modifierFlags: .command)
        waitForSource("Undo should restore the source") { $0 == "Alpha" }
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "After undo"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(preview.staticTexts["Alpha"].waitForExistence(timeout: 5))
    }

    /// Typing in the source then undoing restores the earlier text in one step.
    @MainActor
    func testUndoSourceTyping() throws {
        seed("Alpha", waitingFor: "Alpha")
        sourceEditor.typeText("\n\nGamma")
        XCTAssertTrue(preview.staticTexts["Gamma"].waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: .command)
        waitForSource("Undo should remove the typing") { !$0.contains("Gamma") }
        // The document (and so the preview) must follow the undo too.
        XCTAssertTrue(preview.staticTexts["Gamma"].waitForNonExistence(timeout: 5), "Preview should drop the undone text")
    }

    /// With the source pane hidden, edits in the rendered pane can still be
    /// undone.
    @MainActor
    func testUndoWithSourceHidden() throws {
        seed("Alpha", waitingFor: "Alpha")
        // Hide the source with the toolbar button (the shortcut has its own
        // test; a keystroke here was occasionally delivered too early).
        window.toolbars.buttons["toggle-source"].click()
        XCTAssertTrue(sourceEditor.waitForNonExistence(timeout: 5))
        preview.staticTexts["Alpha"].click()
        app.typeKey(.rightArrow, modifierFlags: .command)
        app.typeText(" Beta")
        XCTAssertTrue(preview.staticTexts["Alpha Beta"].waitForExistence(timeout: 5))
        sleep(1) // let the debounced edit reach the document
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(preview.staticTexts["Alpha"].waitForExistence(timeout: 5), "Undo should restore the rendered text")
        app.typeKey("s", modifierFlags: [.command, .option])
        // Wait for the pane itself first: reading the text of a pane that
        // isn't there yet fails at once instead of waiting.
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 5), "⌥⌘S should show the source again")
        waitForSource("The document should hold the undone text") { $0 == "Alpha" }
    }
}
