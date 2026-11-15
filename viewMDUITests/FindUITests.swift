//
//  FindUITests.swift
//  viewMDUITests
//
//  UI tests for find (REQ-025): ⌘F, ⌘G and ⇧⌘G in the rendered pane, in the
//  source pane, and with the source pane hidden.
//

import XCTest

/// UI tests that drive Edit ▸ Find in the built app.
final class FindUITests: XCTestCase {

    private var app: XCUIApplication!

    /// A document with "apple" three times: twice in one paragraph (once in
    /// bold) and once in a second paragraph.
    private let document = "# Fruit\n\nAn apple and an **APPLE** a day.\n\nOne more apple here.\n"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithoutRestoredWindows()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// Attaches a screenshot of the front window to the test results.
    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private var window: XCUIElement { app.windows.firstMatch }
    @MainActor private var sourceEditor: XCUIElement { window.textViews["source-editor"] }
    @MainActor private var preview: XCUIElement { window.webViews.firstMatch }
    @MainActor private var findField: XCUIElement { window.textFields["find-field"] }
    @MainActor private var findStatus: XCUIElement { window.staticTexts["find-status"] }

    /// Types the test document into the source and waits for it to render.
    @MainActor
    private func enterDocument() {
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        sourceEditor.click()
        sourceEditor.typeText(document)
        XCTAssertTrue(preview.staticTexts["One more apple here."].waitForExistence(timeout: 5))
    }

    /// Waits until the rendered pane's find status reads `text`.
    @MainActor
    private func waitForStatus(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@ OR value == %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: findStatus)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Find status should read \"\(text)\"", file: file, line: line)
    }

    /// The Edit menu has a Find submenu with the standard items.
    @MainActor
    func testFindMenu() throws {
        let edit = app.menuBars.menuBarItems["Edit"]
        edit.click()
        let find = edit.menuItems["Find"]
        XCTAssertTrue(find.waitForExistence(timeout: 2), "Edit menu should have a Find submenu")
        find.hover()
        for title in ["Find…", "Find and Replace…", "Find Next", "Find Previous", "Use Selection for Find"] {
            XCTAssertTrue(find.menuItems[title].waitForExistence(timeout: 2), "Find submenu should offer \(title)")
        }
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
    }

    /// ⌘F in the rendered pane opens its find bar; typing counts matches,
    /// ⌘G / ⇧⌘G step through them, and Escape closes the bar.
    @MainActor
    func testFindInRenderedPane() throws {
        enterDocument()
        preview.staticTexts["One more apple here."].click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findField.waitForExistence(timeout: 5), "⌘F should open the rendered pane's find bar")

        findField.typeText("apple")
        waitForStatus("1 of 3")
        attachScreenshot(named: "Find in rendered pane")
        app.typeKey("g", modifierFlags: .command)
        waitForStatus("2 of 3")
        app.typeKey("g", modifierFlags: .command)
        waitForStatus("3 of 3")
        app.typeKey("g", modifierFlags: .command)
        waitForStatus("1 of 3")
        app.typeKey("g", modifierFlags: [.command, .shift])
        waitForStatus("3 of 3")

        findField.typeText("x")
        waitForStatus("Not found")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(findField.waitForNonExistence(timeout: 5), "Escape should close the find bar")
    }

    /// Done closes the bar and leaves the match selected; the document is
    /// unchanged by searching.
    @MainActor
    func testDoneKeepsDocument() throws {
        enterDocument()
        preview.staticTexts["One more apple here."].click()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findField.waitForExistence(timeout: 5))
        findField.typeText("more")
        waitForStatus("1 of 1")
        window.buttons["find-done"].click()
        XCTAssertTrue(findField.waitForNonExistence(timeout: 5))
        XCTAssertEqual(sourceEditor.value as? String, document, "Searching must not change the Markdown")
    }

    /// ⌘F in the source pane opens the text view's own find bar, not the
    /// rendered pane's.
    @MainActor
    func testFindInSourcePane() throws {
        enterDocument()
        sourceEditor.click()
        app.typeKey("f", modifierFlags: .command)
        let searchField = window.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "⌘F should open the source pane's find bar")
        XCTAssertFalse(findField.exists, "The rendered pane's bar should stay closed")
        searchField.typeText("apple")
        app.typeKey("g", modifierFlags: .command)
        attachScreenshot(named: "Find in source pane")
        XCTAssertEqual(sourceEditor.value as? String, document)
    }

    /// With the source pane hidden, ⌘F searches the rendered pane.
    @MainActor
    func testFindWithSourceHidden() throws {
        enterDocument()
        window.toolbars.buttons["toggle-source"].click()
        XCTAssertTrue(sourceEditor.waitForNonExistence(timeout: 5))
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(findField.waitForExistence(timeout: 5), "⌘F should open the rendered pane's find bar")
        findField.typeText("APPLE")
        waitForStatus("1 of 3")
    }
}
