//
//  ScrollIntegrationTests.swift
//  viewMDTests
//
//  Integration tests for scroll sync (REQ-020) against the real panes: a
//  live WKWebView preview and the source NSTextView, hosted in off-screen
//  windows.
//

import AppKit
import Testing
import WebKit
@testable import viewMD

/// A long document: a heading and 80 paragraphs, one source line each with
/// blank lines between (so paragraph n is on line 2n + 1).
private let longDocument = "# Top\n\n" + (1...80).map { "Paragraph \($0) of filler text." }.joined(separator: "\n\n")

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

/// Puts a view in an off-screen window so it lays out and renders.
@MainActor
private func host(_ view: NSView, size: NSSize = NSSize(width: 600, height: 400)) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -5000, y: -5000), size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.orderBack(nil)
    return window
}

@Suite("Scroll sync integration", .serialized)
@MainActor
struct ScrollIntegrationTests {

    /// Evaluates JavaScript in the preview and returns a number.
    private func number(_ script: String, in webView: WKWebView) async -> Double {
        (try? await webView.evaluateJavaScript(script) as? NSNumber)?.doubleValue ?? -1
    }

    @Test("The preview scrolls to a source line, to the top, and to the end")
    func previewScrollsToLines() async throws {
        let controller = PreviewController(folderAccess: .shared)
        let window = host(controller.webView)
        defer { window.close() }
        controller.update(text: longDocument, baseURL: nil)
        let rendered = await waitUntil {
            await number("document.querySelectorAll('#content > *').length", in: controller.webView) >= 81
        }
        try #require(rendered, "Preview should render the document")

        // Paragraph 40 is on line 81.
        controller.scroll(toLine: 81)
        let scrolled = await waitUntil {
            await number("window.scrollY", in: controller.webView) > 100
        }
        #expect(scrolled, "Preview should scroll down to line 81")
        let paragraphTop = await number(
            "Array.from(document.querySelectorAll('#content > p')).find(p => p.textContent.startsWith('Paragraph 40 ')).getBoundingClientRect().top",
            in: controller.webView)
        #expect(abs(paragraphTop) < 30, "Paragraph 40 should be at the top, was at \(paragraphTop)")

        controller.scroll(toLine: 1)
        #expect(await waitUntil { await number("window.scrollY", in: controller.webView) == 0 })

        controller.scroll(toLine: SourceEditorController.endOfDocument)
        let atEnd = await waitUntil {
            await number("window.scrollY + window.innerHeight >= document.scrollingElement.scrollHeight - 2 ? 1 : 0", in: controller.webView) == 1
        }
        #expect(atEnd, "Past the last line, the preview should scroll to its end")
    }

    @Test("The source pane scrolls to a line and reports its top line")
    func sourceScrollsToLines() throws {
        let controller = SourceEditorController()
        let scrollView = controller.makeScrollView()
        let window = host(scrollView)
        defer { window.close() }
        scrollView.frame = window.contentView!.bounds
        controller.setInitialText(longDocument)
        controller.textView.layoutManager?.ensureLayout(for: controller.textView.textContainer!)

        controller.scroll(toLine: 81)
        #expect(abs(controller.topVisibleLine - 81) <= 1, "Top line was \(controller.topVisibleLine)")

        controller.scroll(toLine: 1)
        #expect(controller.topVisibleLine == 1)

        controller.scroll(toLine: SourceEditorController.endOfDocument)
        #expect(controller.topVisibleLine == SourceEditorController.endOfDocument, "Scrolled to the end should report the end")
    }
}
