//
//  ContentView.swift
//  viewMD
//
//  Created by Stephen Hicks on 11/14/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: viewMDDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(viewMDDocument()))
}
