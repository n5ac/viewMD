//
//  viewMDApp.swift
//  viewMD
//
//  Created by Stephen Hicks on 11/14/26.
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
            FindCommands()
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

/// The Edit ▸ Find submenu (REQ-025), with the standard macOS shortcuts.
/// Each command goes to the pane the user is working in, through
/// ``EditorModel/active`` like the other menus.
struct FindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Menu("Find") {
                item(.showFind, key: "f")
                item(.showReplace, key: "f", modifiers: [.command, .option])
                item(.next, key: "g")
                item(.previous, key: "g", modifiers: [.command, .shift])
                Divider()
                item(.useSelection, key: "e")
            }
        }
    }

    /// One menu item that runs `action`, with its shortcut.
    private func item(_ action: FindAction, key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        Button(action.title) { EditorModel.active?.find(action) }
            .keyboardShortcut(key, modifiers: modifiers)
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
