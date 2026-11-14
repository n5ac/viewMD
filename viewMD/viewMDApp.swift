//
//  viewMDApp.swift
//  viewMD
//
//  Created by Stephen Hicks on 11/14/26.
//

import SwiftUI

@main
struct viewMDApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: viewMDDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
