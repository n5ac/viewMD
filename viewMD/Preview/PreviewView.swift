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
    /// A disabled undo manager for WebKit's own editing steps.
    ///
    /// Every edit in the pane reaches the Markdown source, and undo is
    /// handled there: by the source text view, or by `PreviewView` when the
    /// source pane is hidden. If WebKit also recorded DOM steps on the
    /// window's undo manager, the two stacks would interleave, and undoing a
    /// DOM step for nodes that a re-render had replaced would misbehave.
    private let webKitUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.disableUndoRegistration()
        return manager
    }()

    override var undoManager: UndoManager? { webKitUndoManager }

    /// Undo and redo act on the document (the window's undo manager), not on
    /// WebKit's DOM history.
    @objc func undo(_ sender: Any?) { window?.undoManager?.undo() }
    @objc func redo(_ sender: Any?) { window?.undoManager?.redo() }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return window?.undoManager?.canUndo ?? false
        case #selector(redo(_:)): return window?.undoManager?.canRedo ?? false
        default: return super.validateUserInterfaceItem(item)
        }
    }

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

    /// Applies an edit made in the rendered pane to the document and returns
    /// the new source text (REQ-013).
    var onEdit: ((PreviewEdit) -> String)?

    /// Inserts a block snippet into the source after the given line and
    /// returns the new source text (REQ-015, rendered pane).
    var onInsertBlock: ((MarkdownSnippet, Int) -> String)?

    /// Called with the source line at the top of the rendered pane when the
    /// user scrolls it (REQ-020).
    var onScroll: ((Int) -> Void)?

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
    /// - Parameter force: Render even if the text is unchanged. After an
    ///   edit in the pane, the page waits for a render to resync, even when
    ///   the edit didn't change the Markdown.
    func update(text: String, baseURL: URL?, force: Bool = false) {
        guard force || text != lastRenderedText || baseURL != lastBaseURL else { return }
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

    /// Inserts a snippet in the rendered pane (REQ-015).
    ///
    /// Inline formats, headings, lists and quotes are applied to the
    /// selection with WebKit's editing commands, and the result reaches the
    /// source through the normal edit path. Structures that editing commands
    /// can't build well (code blocks, tables, rules, task lists) are inserted
    /// into the source after the block containing the caret.
    ///
    /// - Parameter snippet: The structure to insert.
    func insert(_ snippet: MarkdownSnippet) {
        if let command = Self.formatCommand(for: snippet) {
            webView.callAsyncJavaScript("window.viewmd.format(command)", arguments: ["command": command], in: nil, in: .page) { _ in }
            return
        }
        webView.callAsyncJavaScript("return window.viewmd.caretLine()", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, case .success(let value) = result else { return }
            let line = (value as? NSNumber)?.intValue ?? 0
            if let newText = self.onInsertBlock?(snippet, line) {
                self.update(text: newText, baseURL: self.lastBaseURL, force: true)
            }
        }
    }

    /// The `viewmd.format` command for a snippet, or `nil` if the snippet is
    /// inserted through the source instead.
    nonisolated static func formatCommand(for snippet: MarkdownSnippet) -> String? {
        switch snippet {
        case .heading(let level): return "heading\(level)"
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .inlineCode: return "inlineCode"
        case .link: return "link"
        case .image: return "image"
        case .bulletList: return "bulletList"
        case .numberedList: return "numberedList"
        case .blockquote: return "blockquote"
        case .taskList, .codeBlock, .table, .horizontalRule: return nil
        }
    }

    /// Scrolls the rendered pane so a source line is at the top (REQ-020).
    ///
    /// - Parameter line: A 1-based source line.
    func scroll(toLine line: Int) {
        guard isPageReady else { return }
        webView.callAsyncJavaScript("window.viewmd.scrollToLine(line)", arguments: ["line": line], in: nil, in: .page) { _ in }
    }

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
        let payload: [String: Any] = ["blocks": blocks, "placeholder": "Start typing…", "editable": true]
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
        case "edit":
            guard let edit = Self.parseEdit(body), let newText = onEdit?(edit) else { return }
            update(text: newText, baseURL: lastBaseURL, force: true)
        case "scroll":
            if let line = (body["line"] as? NSNumber)?.intValue { onScroll?(line) }
        case "openLink":
            if let href = body["href"] as? String, let url = URL(string: href) {
                Self.open(LinkRouter.destination(for: url))
            }
        default:
            break
        }
    }

    /// Decodes an `edit` message from the page.
    ///
    /// - Parameter body: The message: `start`/`end` (lines replaced) or
    ///   `afterLine` (insertion point), and `html`.
    /// - Returns: The edit, or `nil` if the message is malformed.
    nonisolated static func parseEdit(_ body: [String: Any]) -> PreviewEdit? {
        guard let html = body["html"] as? String else { return nil }
        if let start = (body["start"] as? NSNumber)?.intValue, let end = (body["end"] as? NSNumber)?.intValue, start >= 1, end >= start {
            return PreviewEdit(location: .replacing(start...end), html: html)
        }
        if let afterLine = (body["afterLine"] as? NSNumber)?.intValue, afterLine >= 0 {
            return PreviewEdit(location: .inserting(afterLine: afterLine), html: html)
        }
        return nil
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
    /// The document's Markdown source. Edits in the pane write back to it.
    @Binding var text: String
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
        controller.onScroll = { line in model.paneDidScroll(.preview, toLine: line) }
        model.preview = controller
        controller.update(text: text, baseURL: baseURL)
        return controller.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let controller = context.coordinator
        model.preview = controller
        // Re-bind closures each update so they capture the current binding.
        controller.onEdit = { edit in
            let newText = SourceSplicer.apply(edit, to: text)
            applyFromPreview(newText, webView: webView)
            return newText
        }
        controller.onInsertBlock = { snippet, line in
            let newText = SourceSplicer.insertSnippet(snippet, afterLine: line, in: text)
            applyFromPreview(newText, webView: webView)
            return newText
        }
        controller.update(text: text, baseURL: baseURL)
    }

    /// Writes text changed in the rendered pane to the document.
    ///
    /// When the source pane is visible, its text view records the change for
    /// undo. When it's hidden, the change is registered here, so ⌘Z still
    /// works.
    private func applyFromPreview(_ newText: String, webView: WKWebView) {
        let oldText = text
        guard newText != oldText else { return }
        // Undo is registered explicitly (by the source text view, or below),
        // so SwiftUI's automatic registration for the binding is paused.
        let undoManager = webView.window?.undoManager
        undoManager?.disableUndoRegistration()
        text = newText
        undoManager?.enableUndoRegistration()
        if model.sourceEditor == nil || !model.isSourceVisible, let undoManager {
            Self.registerUndo(on: undoManager, binding: $text, target: model, restoring: oldText)
        }
    }

    /// Registers an undo step that restores `oldText`, and a redo step when
    /// it runs.
    @MainActor
    private static func registerUndo(on undoManager: UndoManager, binding: Binding<String>, target: EditorModel, restoring oldText: String) {
        undoManager.registerUndo(withTarget: target) { target in
            let current = binding.wrappedValue
            binding.wrappedValue = oldText
            registerUndo(on: undoManager, binding: binding, target: target, restoring: current)
        }
        undoManager.setActionName("Edit")
    }
}
