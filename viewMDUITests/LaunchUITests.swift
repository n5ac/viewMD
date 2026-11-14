//
//  LaunchUITests.swift
//  viewMDUITests
//
//  UI smoke test: the app launches and can open a new document window
//  (REQ-010). Later phases add the two-pane and toggle UI tests here.
//

import XCTest

/// UI tests that drive the built app through XCUIApplication.
final class LaunchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launching the app and choosing File ▸ New opens a document window.
    @MainActor
    func testNewDocumentOpensWindow() throws {
        let app = XCUIApplication()
        app.launch()
        // A document app may show an open panel on launch; ⌘N always opens
        // a new untitled window regardless.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.terminate()
    }
}
