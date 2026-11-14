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
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            ViewCommands()
        }
    }
}

/// View menu items for the frontmost window.
///
/// The ⌥⌘S shortcut is attached to the toolbar button in `ContentView`, not
/// to this menu item. A shortcut on a `FocusedValue`-driven menu item never
/// fired in testing, though clicking the item works. Window-level shortcuts
/// on the toolbar button work in both panes.
struct ViewCommands: Commands {
    @FocusedValue(\.editorModel) private var model

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(model?.isSourceVisible == false ? "Show Source" : "Hide Source") {
                model?.toggleSourcePane()
            }
            .disabled(model == nil)
            Divider()
        }
    }
}
