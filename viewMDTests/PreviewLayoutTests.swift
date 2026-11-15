//
//  PreviewLayoutTests.swift
//  viewMDTests
//
//  Tests that the rendered pane reflows to the window's width (REQ-026)
//  while HTML exports keep a fixed reading column.
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

import AppKit
import Testing
import WebKit
@testable import viewMD

/// Polls `condition` until it's true or `timeout` passes.
@MainActor
private func waitUntil(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return false
}

@Suite("Rendered pane width", .serialized)
@MainActor
struct PreviewLayoutTests {

    /// One long paragraph, so its height shows how the text wraps.
    private let document = "# Width\n\n" + String(repeating: "Words that wrap across the line. ", count: 120)

    /// Evaluates JavaScript in the preview and returns a number.
    private func number(_ script: String, in webView: WKWebView) async -> Double {
        (try? await webView.evaluateJavaScript(script) as? NSNumber)?.doubleValue ?? -1
    }

    @Test("The text column follows the pane's width, and text reflows")
    func fillsWidth() async throws {
        let controller = PreviewController(folderAccess: .shared)
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1200, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = controller.webView
        window.orderBack(nil)
        defer { window.close() }
        controller.update(text: document, baseURL: nil)
        let rendered = await waitUntil {
            await number("document.querySelectorAll('#content > p').length", in: controller.webView) == 1
        }
        try #require(rendered, "Preview should render the document")

        let contentWidth = "document.getElementById('content').getBoundingClientRect().width"
        let paneWidth = "document.documentElement.clientWidth"
        let paragraphHeight = "document.querySelector('#content > p').getBoundingClientRect().height"

        /// Whether the text column spans the whole pane, whatever size the
        /// window actually got (a CI runner's screen may be smaller).
        func fillsPane() async -> Bool {
            let pane = await number(paneWidth, in: controller.webView)
            let content = await number(contentWidth, in: controller.webView)
            return pane > 0 && abs(content - pane) < 2
        }

        // Wide: the column uses the whole pane, past the old 860px cap.
        #expect(await waitUntil { await fillsPane() })
        #expect(await number(contentWidth, in: controller.webView) > 900)
        let wideHeight = await number(paragraphHeight, in: controller.webView)

        // Narrow: the column shrinks with the pane and the text wraps onto
        // more lines.
        window.setContentSize(NSSize(width: 500, height: 600))
        #expect(await waitUntil { await number(paneWidth, in: controller.webView) <= 520 })
        #expect(await fillsPane())
        let narrowHeight = await number(paragraphHeight, in: controller.webView)
        #expect(narrowHeight > wideHeight * 1.5, "Text should reflow to the narrower width")
    }

    @Test("HTML exports keep the fixed reading column")
    func exportKeepsColumn() {
        let html = HTMLExporter().makeHTML(markdown: document, title: "T")
        #expect(html.contains("<article class=\"markdown-body\">"))
        #expect(!html.contains("fill-width\""))
        #expect(html.contains("max-width: 860px"))
    }
}
