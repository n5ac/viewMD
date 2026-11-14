//
//  AppMetadataTests.swift
//  viewMDTests
//
//  Checks the app bundle carries what TestFlight and the App Store require
//  (REQ-024).
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
