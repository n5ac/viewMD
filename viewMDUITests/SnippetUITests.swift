//
//  SnippetUITests.swift
//  viewMDUITests
//
//  UI tests for the quick-insert pull-downs and Format menu shortcuts
//  (REQ-015).
//

import XCTest

/// Drives the toolbar pull-downs and Format menu against the source pane.
final class SnippetUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithoutRestoredWindows()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        sourceEditor.click()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private var sourceEditor: XCUIElement {
        app.windows.firstMatch.textViews["source-editor"]
    }

    private var sourceText: String {
        sourceEditor.value as? String ?? ""
    }

    /// ⌘B wraps the selection in bold markers; ⌘B again removes them.
    @MainActor
    func testBoldShortcutTogglesSelection() throws {
        sourceEditor.typeText("word")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("b", modifierFlags: .command)
        XCTAssertEqual(sourceText, "**word**")
        app.typeKey("b", modifierFlags: .command)
        XCTAssertEqual(sourceText, "word")
    }

    /// ⌘2 makes the current line a level-2 heading.
    @MainActor
    func testHeadingShortcut() throws {
        sourceEditor.typeText("Title")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(sourceText, "## Title")
    }

    /// The toolbar's Insert ▸ Table pull-down inserts a table template, and
    /// the preview renders it.
    @MainActor
    func testInsertTableFromToolbar() throws {
        sourceEditor.typeText("Intro")
        let window = app.windows.firstMatch
        window.toolbars.menuButtons["menu-Insert"].click()
        window.menuItems["insert-Table"].click()
        XCTAssertTrue(sourceText.hasPrefix("Intro\n\n| Column 1 | Column 2 |"), "Got: \(sourceText)")
        let preview = window.webViews.firstMatch
        XCTAssertTrue(preview.staticTexts["Column 1"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "Inserted table"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Typing replaces the selected placeholder of an inserted snippet.
    @MainActor
    func testPlaceholderIsSelectedForTyping() throws {
        app.typeKey("k", modifierFlags: .command)
        sourceEditor.typeText("viewMD")
        XCTAssertEqual(sourceText, "[viewMD](https://)")
    }
}
