//
//  UITestSupport.swift
//  viewMDUITests
//
//  Shared setup for the UI tests.
//

import XCTest

extension XCUIApplication {
    /// Launches viewMD without restoring windows saved by earlier runs, and
    /// without the Open panel.
    ///
    /// Without this, macOS reopens whatever windows were open when the app
    /// last quit: windows left by other tests, or the owner's own
    /// documents. A restored window can come first in `windows` or cover
    /// the test's new window, making tests depend on what ran before them.
    ///
    /// With nothing restored, a document app shows the Open panel at
    /// launch instead. The panel runs in another process, and while it has
    /// focus it takes keystrokes meant for viewMD (such as ⌥⌘S), so the app
    /// is told to open an untitled document instead.
    func launchWithoutRestoredWindows() {
        launchArguments += ["-ApplePersistenceIgnoreState", "YES",
                            "-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO"]
        launch()
    }
}
