//
//  viewMDApp.swift
//  viewMD
//
//  Created by Stephen Hicks on 11/14/26.
//

import SwiftUI

/// The viewMD application: a document-based app with one window per
/// Markdown file (REQ-010).
@main
struct viewMDApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
