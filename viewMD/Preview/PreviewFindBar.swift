//
//  PreviewFindBar.swift
//  viewMD
//
//  The find bar above the rendered pane (REQ-025), laid out like AppKit's
//  find bar in the source pane so the two look alike.
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

/// A slim bar with a search field, the match status, previous/next buttons
/// and Done. Return goes to the next match; Escape or Done closes it.
struct PreviewFindBar: View {
    /// The window's rendered-pane find state.
    @Bindable var find: PreviewFindModel

    /// Whether the search field has keyboard focus.
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find", text: $find.query, prompt: Text("Find in rendered view"))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, maxWidth: 280)
                .focused($isFieldFocused)
                .onSubmit { find.perform(.next) }
                .accessibilityIdentifier("find-field")
            Text(find.matches.summary(for: find.query))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("find-status")
            ControlGroup {
                Button { find.perform(.previous) } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .help("Find previous (⇧⌘G)")
                .accessibilityIdentifier("find-previous")
                Button { find.perform(.next) } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .help("Find next (⌘G)")
                .accessibilityIdentifier("find-next")
            }
            .controlGroupStyle(.navigation)
            .fixedSize()
            .disabled(find.matches.count == 0)
            Spacer(minLength: 0)
            Button("Done", action: find.close)
                .controlSize(.small)
                .accessibilityIdentifier("find-done")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
        .onExitCommand(perform: find.close)
        .onChange(of: find.query) { _, _ in
            Task { await find.queryDidChange() }
        }
        .onChange(of: find.focusRequest, initial: true) { _, _ in
            isFieldFocused = true
        }
    }
}
