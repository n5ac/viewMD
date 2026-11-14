//
//  ExportUITests.swift
//  viewMDUITests
//
//  UI tests for the export commands (REQ-017, REQ-018): they're available
//  from the File menu and the toolbar, and they ask where to save.
//

import XCTest

/// Checks the export entry points open a save sheet with a sensible name.
final class ExportUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.textViews["source-editor"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// File ▸ Export as PDF… opens a save sheet suggesting "Untitled.pdf".
    @MainActor
    func testExportPDFFromFileMenu() throws {
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        fileMenu.menuItems["Export as PDF…"].click()
        let sheet = app.windows.firstMatch.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "A save sheet should appear")
        let nameField = sheet.textFields.firstMatch
        XCTAssertEqual(nameField.value as? String, "Untitled.pdf")
        sheet.buttons["Cancel"].click()
    }

    /// The toolbar's Export pull-down offers HTML, and ⇧⌘E opens its sheet.
    @MainActor
    func testExportHTMLFromToolbarAndShortcut() throws {
        let window = app.windows.firstMatch
        window.toolbars.menuButtons["menu-Export"].click()
        XCTAssertTrue(window.menuItems["Export as HTML…"].waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("e", modifierFlags: [.command, .shift])
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertEqual(sheet.textFields.firstMatch.value as? String, "Untitled.html")
        sheet.buttons["Cancel"].click()
    }
}
