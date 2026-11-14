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
            ExportCommands()
            ViewCommands()
            FormatCommands()
        }
    }
}

/// File menu export items (REQ-017, REQ-018), after Save.
struct ExportCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button(ExportFormat.html.menuTitle) { EditorModel.active?.export(.html) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button(ExportFormat.pdf.menuTitle) { EditorModel.active?.export(.pdf) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}

/// View menu items for the window the user last worked in.
///
/// Commands act on ``EditorModel/active`` rather than a SwiftUI
/// `FocusedValue`. With `FocusedValue`, clicking the menu item worked but
/// its keyboard shortcut never fired.
struct ViewCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Show/Hide Source") {
                EditorModel.active?.toggleSourcePane()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
        }
    }
}

/// The Format menu: every quick-insert structure, with the usual shortcuts
/// (REQ-015). Commands act on ``EditorModel/active``, the window the user
/// last worked in.
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            Menu("Heading") {
                ForEach(1...6, id: \.self) { level in
                    item(.heading(level), key: KeyEquivalent(Character(String(level))))
                }
            }
            Divider()
            item(.bold, key: "b")
            item(.italic, key: "i")
            item(.strikethrough, key: "x", modifiers: [.command, .shift])
            item(.inlineCode)
            Divider()
            item(.bulletList, key: "8", modifiers: [.command, .shift])
            item(.numberedList, key: "7", modifiers: [.command, .shift])
            item(.taskList, key: "9", modifiers: [.command, .shift])
            item(.blockquote, key: "'", modifiers: [.command])
            Divider()
            item(.link, key: "k")
            item(.image)
            item(.codeBlock)
            item(.table)
            item(.horizontalRule)
        }
    }

    /// One menu item that inserts `snippet`, with an optional shortcut.
    @ViewBuilder
    private func item(_ snippet: MarkdownSnippet, key: KeyEquivalent? = nil, modifiers: EventModifiers = .command) -> some View {
        let button = Button(snippet.title) { EditorModel.active?.insert(snippet) }
        if let key {
            button.keyboardShortcut(key, modifiers: modifiers)
        } else {
            button
        }
    }
}
