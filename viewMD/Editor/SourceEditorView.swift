//
//  SourceEditorView.swift
//  viewMD
//
//  The Markdown source pane (right): an NSTextView wrapped for SwiftUI.
//  NSTextView is used instead of SwiftUI's TextEditor for precise control of
//  the insertion point (pull-down inserts, REQ-015), undo-friendly external
//  updates (edits from the rendered pane, REQ-013) and syntax coloring
//  (REQ-023).
//

import AppKit
import SwiftUI

/// An `NSTextView` that reports when it gains keyboard focus.
final class FocusReportingTextView: NSTextView {
    /// Called after the view becomes first responder.
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}

/// Owns the source pane's text view and applies changes to it.
///
/// Registered with the window's ``EditorModel`` so menu commands can insert
/// at the insertion point.
@MainActor
final class SourceEditorController: NSObject, NSTextViewDelegate {

    /// The text view. Created by ``makeScrollView()``.
    private(set) var textView: FocusReportingTextView!

    /// Called with the new text after the user edits it.
    var onTextChange: ((String) -> Void)?

    /// Called when the text view gains focus.
    var onFocus: (() -> Void)?

    /// Applies syntax coloring after each change (REQ-023).
    private let highlighter = MarkdownHighlighter()

    /// True while this controller is changing the text itself, so the
    /// resulting delegate callback isn't reported as a user edit.
    private var isApplyingExternalChange = false

    /// Builds the scroll view and text view configured for Markdown editing:
    /// monospaced font, no smart quotes or dashes or auto-correction (they'd
    /// corrupt Markdown syntax), undo enabled, and a comfortable inset.
    ///
    /// - Returns: The scroll view containing the text view.
    func makeScrollView() -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        // Swap the stock text view for our focus-reporting subclass, reusing
        // the text container set up by scrollableTextView().
        let stock = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: stock.frame, textContainer: stock.textContainer)
        textView.autoresizingMask = stock.autoresizingMask
        textView.minSize = stock.minSize
        textView.maxSize = stock.maxSize
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        scrollView.documentView = textView

        textView.font = MarkdownHighlighter.baseFont
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 14)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.setAccessibilityIdentifier("source-editor")
        textView.setAccessibilityLabel("Markdown source")
        textView.delegate = self
        textView.onFocus = { [weak self] in self?.onFocus?() }
        self.textView = textView
        return scrollView
    }

    /// The current source text.
    var text: String { textView.string }

    /// The current selection, in UTF-16 units.
    var selectedRange: NSRange { textView.selectedRange() }

    /// Updates the text to `newText` made elsewhere (e.g. in the rendered
    /// pane), changing only the part that differs. This keeps the caret and
    /// scroll position stable and makes the change one undoable step.
    ///
    /// - Parameter newText: The full new source text.
    func applyExternalText(_ newText: String) {
        guard let change = TextDiff.replacement(from: textView.string, to: newText) else { return }
        replace(change.range, with: change.replacement, selecting: nil, actionName: "Edit")
    }

    /// Replaces a range of the text as one undoable step and optionally sets
    /// the selection afterwards. Used by pull-down inserts (REQ-015).
    ///
    /// - Parameters:
    ///   - range: The range to replace, in UTF-16 units.
    ///   - replacement: The new text.
    ///   - selection: The selection to set afterwards, or `nil` to let the
    ///     text view adjust it.
    ///   - actionName: The name shown in the Edit menu's Undo item.
    func replace(_ range: NSRange, with replacement: String, selecting selection: NSRange?, actionName: String) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        isApplyingExternalChange = true
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        isApplyingExternalChange = false
        textView.undoManager?.setActionName(actionName)
        if let selection {
            textView.setSelectedRange(selection)
            textView.scrollRangeToVisible(selection)
        }
        // Report the result: an insert command must reach the document too.
        onTextChange?(textView.string)
    }

    /// Applies a quick-insert snippet at the insertion point (REQ-015) as
    /// one undoable step, then focuses the editor.
    ///
    /// - Parameter snippet: The structure to insert.
    func insert(_ snippet: MarkdownSnippet) {
        let edit = MarkdownSnippets.edit(for: snippet, in: textView.string, selection: textView.selectedRange())
        replace(edit.range, with: edit.replacement, selecting: edit.selection, actionName: snippet.title)
        focus()
    }

    /// Replaces the whole text without recording undo. Used when the view is
    /// first created.
    ///
    /// - Parameter text: The initial text.
    func setInitialText(_ text: String) {
        isApplyingExternalChange = true
        textView.string = text
        highlighter.highlight(textView.textStorage)
        isApplyingExternalChange = false
    }

    /// Gives the text view keyboard focus.
    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        highlighter.highlight(textView.textStorage)
        guard !isApplyingExternalChange else { return }
        onTextChange?(textView.string)
    }
}

/// SwiftUI wrapper for the source pane.
struct SourceEditorView: NSViewRepresentable {
    /// The document's Markdown source.
    @Binding var text: String
    /// The window's editor state; the controller registers itself here.
    let model: EditorModel

    func makeCoordinator() -> SourceEditorController {
        SourceEditorController()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let controller = context.coordinator
        let scrollView = controller.makeScrollView()
        controller.setInitialText(text)
        controller.onTextChange = { newText in
            if text != newText { text = newText }
        }
        controller.onFocus = {
            model.lastFocusedPane = .source
            model.becomeActive()
        }
        model.sourceEditor = controller
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let controller = context.coordinator
        model.sourceEditor = controller
        if controller.text != text {
            controller.applyExternalText(text)
        }
    }
}
