//
//  ContentView.swift
//  viewMD
//
//  Created by Stephen Hicks on 11/14/26.
//

import AppKit
import SwiftUI

/// The content of a document window: the rendered Markdown on the left and
/// the source on the right (REQ-011, owner preference P-006), with a toolbar
/// to hide the source pane (REQ-014).
struct ContentView: View {
    /// The document being edited, owned by the window's `DocumentGroup`.
    @Binding var document: MarkdownDocument

    /// The document's location on disk, or `nil` while it's unsaved. Relative
    /// links and images resolve against its folder (REQ-022).
    let fileURL: URL?

    /// Per-window editor state.
    @State private var model = EditorModel()

    /// Remembers per window whether the source pane is shown, across
    /// relaunches (state restoration).
    @SceneStorage("viewMD.isSourceVisible") private var storedSourceVisible = true

    /// The URL relative links resolve against in the preview.
    private var previewBaseURL: URL? {
        fileURL.map { PreviewURLs.documentBaseURL(forFolder: $0.deletingLastPathComponent()) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if model.needsFolderAccess, fileURL != nil {
                    FolderAccessBanner(grant: grantFolderAccess)
                    Divider()
                }
                PreviewView(text: $document.text, baseURL: previewBaseURL, model: model)
            }
            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Rendered Markdown")

            if model.isSourceVisible {
                SourceEditorView(text: $document.text, model: model)
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Markdown source")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .background(WindowKeyObserver { model.becomeActive() })
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                SnippetMenu(title: "Heading", systemImage: "textformat.size", snippets: (1...6).map { .heading($0) }, model: model)
                SnippetMenu(title: "Format", systemImage: "bold",
                            snippets: [.bold, .italic, .strikethrough, .inlineCode], model: model)
                SnippetMenu(title: "Lists", systemImage: "list.bullet",
                            snippets: [.bulletList, .numberedList, .taskList, .blockquote], model: model)
                SnippetMenu(title: "Insert", systemImage: "plus.square.on.square",
                            snippets: [.link, .image, .codeBlock, .table, .horizontalRule], model: model)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: model.toggleSourcePane) {
                    Label(model.isSourceVisible ? "Hide Source" : "Show Source", systemImage: "sidebar.right")
                }
                .help(model.isSourceVisible ? "Hide the Markdown source (⌥⌘S)" : "Show the Markdown source (⌥⌘S)")
                .accessibilityIdentifier("toggle-source")
            }
        }
        .onAppear {
            model.isSourceVisible = storedSourceVisible
            model.becomeActive()
        }
        .onChange(of: model.isSourceVisible) { _, visible in
            storedSourceVisible = visible
            // Keep keyboard focus in the window when the pane it was in
            // disappears.
            if !visible { model.preview?.focus() }
        }
    }

    /// Asks the user to grant access to the document's folder so local
    /// images can be shown (sandbox), then reloads the preview.
    private func grantFolderAccess() {
        guard let folder = fileURL?.deletingLastPathComponent() else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Grant Access"
        panel.message = "viewMD needs access to this folder to show the images your document uses."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FolderAccessStore.shared.grant(url)
        model.needsFolderAccess = false
        model.preview?.reload()
    }
}

/// A toolbar pull-down that inserts Markdown structures (REQ-015).
private struct SnippetMenu: View {
    /// The menu's name (shown as its tooltip and in text-only toolbars).
    let title: String
    /// The menu's SF Symbol.
    let systemImage: String
    /// The items, in order.
    let snippets: [MarkdownSnippet]
    /// The window's editor state, which routes the insert to the focused pane.
    let model: EditorModel

    var body: some View {
        Menu {
            ForEach(snippets, id: \.self) { snippet in
                Button {
                    model.insert(snippet)
                } label: {
                    Label(snippet.title, systemImage: snippet.systemImage)
                }
                .accessibilityIdentifier("insert-\(snippet.title)")
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .help("Insert \(title.lowercased()) at the insertion point")
        .accessibilityIdentifier("menu-\(title)")
    }
}

/// A slim bar above the preview explaining that local images need folder
/// access, with a button to grant it.
private struct FolderAccessBanner: View {
    /// Runs the grant flow.
    let grant: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("Some images can't be shown until viewMD has access to this folder.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Grant Access…", action: grant)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

#Preview {
    ContentView(document: .constant(MarkdownDocument(text: "# Hello\n\nSome **Markdown**.")), fileURL: nil)
}
