//
//  UITestSupport.swift
//  viewMDUITests
//
//  Shared setup for the UI tests.
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
