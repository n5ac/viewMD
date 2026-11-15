//
//  PreviewFindBar.swift
//  viewMD
//
//  The find bar above the rendered pane (REQ-025), laid out like AppKit's
//  find bar in the source pane so the two look alike.
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
