//
//  ExportUITests.swift
//  viewMDUITests
//
//  UI tests for the export commands (REQ-017, REQ-018): they're available
//  from the File menu and the toolbar, and they ask where to save.
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

/// Checks the export entry points open a save sheet with a sensible name.
final class ExportUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithoutRestoredWindows()
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
