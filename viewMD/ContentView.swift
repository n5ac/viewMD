//
//  ContentView.swift
//  viewMD
//
//  Created by Stephen Hicks on 11/14/26.
//

import SwiftUI

/// The content of a document window.
///
/// Phase 0 placeholder: a plain text editor bound to the document's source.
/// Phase 2 replaces it with the two-pane layout (rendered left, source
/// right; REQ-011).
struct ContentView: View {
    /// The document being edited, owned by the window's `DocumentGroup`.
    @Binding var document: MarkdownDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(MarkdownDocument()))
}
