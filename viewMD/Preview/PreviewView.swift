//
//  PreviewView.swift
//  viewMD
//
//  The rendered Markdown pane (left): a WKWebView showing the bundled preview
//  page, updated live as the source changes (REQ-011, REQ-012).
//

import AppKit
import SwiftUI
import WebKit

/// Forwards script messages to a target without retaining it, breaking the
/// retain cycle `WKUserContentController` would otherwise create.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// The preview's web view.
///
/// WKWebView claims key equivalents while it has focus, so app menu
/// shortcuts (⌥⌘S, and the Format menu's ⌘B and ⌘I) wouldn't fire. This
/// subclass offers ⌘ shortcuts to the main menu first. Standard items like
/// Copy and Select All still reach the web view, because their menu actions
/// go to the first responder.
final class PreviewWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Owns the preview web view: renders the source, sends the result to the
/// page, and handles messages from it.
@MainActor
final class PreviewController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    /// The web view. Its page is loaded once; later updates are patches.
    let webView: PreviewWebView

    /// Called when the rendered pane gains focus.
    var onFocus: (() -> Void)?

    /// Called when a local file couldn't be shown because of the sandbox.
    var onAccessDenied: (() -> Void)?

    /// How long to wait after a keystroke before re-rendering. Short enough
    /// to feel instant (REQ-012's 150 ms target includes this), long enough
    /// to coalesce fast typing.
    static let renderDelay: Duration = .milliseconds(30)

    private let schemeHandler: PreviewSchemeHandler
    private var isPageReady = false
    private var renderTask: Task<Void, Never>?
    private var lastRenderedText: String?
    private var lastBaseURL: URL?

    /// The most recent render, kept so it can be re-sent (page reload,
    /// export).
    private(set) var lastRendered = RenderedDocument(blocks: [])

    /// Creates the controller and starts loading the preview page.
    ///
    /// - Parameter folderAccess: The store of folders the user granted.
    init(folderAccess: FolderAccessStore) {
        schemeHandler = PreviewSchemeHandler(folderAccess: folderAccess)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: PreviewURLs.scheme)
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = PreviewWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: "viewmd")
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.setAccessibilityIdentifier("preview")
        webView.underPageBackgroundColor = .textBackgroundColor
        schemeHandler.onAccessDenied = { [weak self] _ in self?.onAccessDenied?() }
        webView.load(URLRequest(url: PreviewURLs.pageURL))
    }

    /// Renders `text` and shows it, after a short debounce. Rendering runs off
    /// the main thread; a newer call supersedes an older one still pending.
    ///
    /// - Parameters:
    ///   - text: The Markdown source.
    ///   - baseURL: The URL relative links resolve against, or `nil`.
    func update(text: String, baseURL: URL?) {
        guard text != lastRenderedText || baseURL != lastBaseURL else { return }
        lastRenderedText = text
        lastBaseURL = baseURL
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: Self.renderDelay)
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) {
                MarkdownRenderer(baseURL: baseURL).render(text)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.show(rendered)
        }
    }

    /// Re-renders and reloads everything, e.g. after folder access was
    /// granted so images can now load.
    func reload() {
        isPageReady = false
        webView.load(URLRequest(url: PreviewURLs.pageURL))
    }

    /// Inserts a snippet in the rendered pane. Editing in the rendered pane
    /// arrives in Phase 4; until then, this does nothing.
    ///
    /// - Parameter snippet: The structure to insert.
    func insert(_ snippet: MarkdownSnippet) {}

    /// Gives the web view keyboard focus.
    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    /// Sends a rendered document to the page (or keeps it until the page is
    /// ready).
    private func show(_ rendered: RenderedDocument) {
        lastRendered = rendered
        guard isPageReady else { return }
        let blocks = rendered.blocks.map { ["src": "\($0.lines.lowerBound)-\($0.lines.upperBound)", "html": $0.html] }
        let payload: [String: Any] = ["blocks": blocks, "placeholder": "Start typing Markdown in the source pane."]
        webView.callAsyncJavaScript("window.viewmd.render(payload)", arguments: ["payload": payload], in: nil, in: .page) { _ in }
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isPageReady = true
            show(lastRendered)
        case "focus":
            onFocus?()
        case "openLink":
            if let href = body["href"] as? String, let url = URL(string: href) {
                Self.open(LinkRouter.destination(for: url))
            }
        default:
            break
        }
    }

    /// Performs a link destination.
    private static func open(_ destination: LinkDestination) {
        switch destination {
        case .external(let url), .localFile(let url):
            NSWorkspace.shared.open(url)
        case .markdownDocument(let url):
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        case .ignore:
            break
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Only the preview page itself may load in the web view. Links are
        // handled by bridge.js; anything else (e.g. a form submission) is
        // refused.
        navigationAction.request.url == PreviewURLs.pageURL ? .allow : .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // WebKit's content process can be killed under memory pressure;
        // reload so the pane doesn't stay blank.
        reload()
    }
}

/// SwiftUI wrapper for the rendered pane.
struct PreviewView: NSViewRepresentable {
    /// The document's Markdown source.
    let text: String
    /// The URL relative links resolve against (the document folder), or
    /// `nil` for an unsaved document.
    let baseURL: URL?
    /// The window's editor state; the controller registers itself here.
    let model: EditorModel

    func makeCoordinator() -> PreviewController {
        PreviewController(folderAccess: .shared)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = context.coordinator
        controller.onFocus = {
            model.lastFocusedPane = .preview
            model.becomeActive()
        }
        controller.onAccessDenied = { model.needsFolderAccess = true }
        model.preview = controller
        controller.update(text: text, baseURL: baseURL)
        return controller.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        model.preview = context.coordinator
        context.coordinator.update(text: text, baseURL: baseURL)
    }
}
