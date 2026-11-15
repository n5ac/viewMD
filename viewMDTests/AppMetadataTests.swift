//
//  AppMetadataTests.swift
//  viewMDTests
//
//  Checks the app bundle carries what TestFlight and the App Store require
//  (REQ-024).
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

import Foundation
import Testing

@Suite("App metadata")
struct AppMetadataTests {

    /// The app's Info.plist (tests run hosted in the app).
    private let info = Bundle.main.infoDictionary ?? [:]

    @Test("Declares the Developer Tools category")
    func category() {
        #expect(info["LSApplicationCategoryType"] as? String == "public.app-category.developer-tools")
    }

    @Test("Declares the encryption exemption")
    func encryptionExemption() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    @Test("Has a version and build number")
    func versions() {
        #expect((info["CFBundleShortVersionString"] as? String)?.isEmpty == false)
        #expect(Int(info["CFBundleVersion"] as? String ?? "") ?? 0 >= 1)
    }

    @Test("Is sandboxed (required for the Mac App Store and TestFlight)")
    func sandboxed() {
        // A sandboxed app's home directory is inside its container.
        #expect(NSHomeDirectory().contains("/Library/Containers/"))
    }
}
