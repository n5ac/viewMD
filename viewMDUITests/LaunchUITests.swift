//
//  LaunchUITests.swift
//  viewMDUITests
//
//  UI tests that drive the built app: new documents (REQ-010), the two-pane
//  layout (REQ-011), live preview (REQ-012) and hiding the source pane
//  (REQ-014).
//

import XCTest

/// UI tests that drive the built app through XCUIApplication.
final class LaunchUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithoutRestoredWindows()
        // A document app may show an open panel on launch; ⌘N always opens
        // a new untitled window regardless.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        // Close without saving so runs don't leave documents behind.
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

    /// The source text view (right pane).
    @MainActor
    private var sourceEditor: XCUIElement {
        app.windows.firstMatch.textViews["source-editor"]
    }

    /// The rendered pane's web view (left pane).
    @MainActor
    private var preview: XCUIElement {
        app.windows.firstMatch.webViews.firstMatch
    }

    /// A new window shows both panes, with the preview to the left of the
    /// source.
    @MainActor
    func testNewDocumentShowsTwoPanes() throws {
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertLessThan(preview.frame.midX, sourceEditor.frame.midX, "Rendered pane must be on the left (P-006)")
        attachScreenshot(named: "Two panes")
    }

    /// Typing Markdown in the source updates the rendered pane.
    @MainActor
    func testTypingUpdatesPreview() throws {
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        sourceEditor.click()
        sourceEditor.typeText("# Hello viewMD\n\nSome **bold** text.")
        let heading = preview.staticTexts["Hello viewMD"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5), "Preview should show the typed heading")
        XCTAssertTrue(preview.staticTexts["bold"].waitForExistence(timeout: 5))
        attachScreenshot(named: "Live preview")
    }

    /// The toolbar button and ⌥⌘S hide and show the source pane.
    @MainActor
    func testToggleSourcePane() throws {
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        let toggle = app.windows.firstMatch.toolbars.buttons["toggle-source"]
        XCTAssertTrue(toggle.exists)

        toggle.click()
        XCTAssertTrue(sourceEditor.waitForNonExistence(timeout: 5), "Source pane should hide")
        XCTAssertTrue(preview.exists, "Rendered pane stays visible")
        attachScreenshot(named: "Source hidden")

        let viewMenu = app.menuBars.menuBarItems["View"]
        viewMenu.click()
        let showItem = viewMenu.menuItems["Show/Hide Source"]
        XCTAssertTrue(showItem.waitForExistence(timeout: 2), "View menu should offer Show/Hide Source")
        XCTAssertEqual(showItem.value(forKey: "isEnabled") as? Bool, true)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("s", modifierFlags: [.command, .option])
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 5), "⌥⌘S should show the source again")
    }
}
