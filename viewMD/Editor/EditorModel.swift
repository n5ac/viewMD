//
//  EditorModel.swift
//  viewMD
//
//  Per-window editor state shared by the two panes, the toolbar and the menu
//  commands.
//

import Foundation
import Observation

/// Which pane an action or edit applies to.
nonisolated enum EditorPane: Hashable, Sendable {
    /// The rendered Markdown (left).
    case preview
    /// The Markdown source (right).
    case source
}

/// State for one document window.
///
/// The document text itself lives in the `MarkdownDocument` binding, the
/// single source of truth. This model holds everything else the window
/// needs: which pane is focused, whether the source pane is shown, and weak
/// links to the two pane controllers so menu commands can act on whichever
/// pane has focus.
@MainActor
@Observable
final class EditorModel {

    /// Whether the source pane (right) is visible. When `false`, the rendered
    /// view fills the window (REQ-014).
    var isSourceVisible = true

    /// The pane the user last worked in. Insert commands go here (REQ-015).
    /// If the source pane is hidden, the preview is used whatever this says.
    var lastFocusedPane: EditorPane = .source

    /// Set when the preview can't show local images because the app hasn't
    /// been granted access to the document's folder (sandbox). Drives the
    /// "Grant Access" banner (REQ-022).
    var needsFolderAccess = false

    /// The source editor of this window, registered by `SourceEditorView`.
    @ObservationIgnored weak var sourceEditor: SourceEditorController?

    /// The preview of this window, registered by `PreviewView`.
    @ObservationIgnored weak var preview: PreviewController?

    /// The pane that insert commands should target right now.
    var activePane: EditorPane {
        isSourceVisible ? lastFocusedPane : .preview
    }

    /// The editor model of the window the user most recently worked in.
    ///
    /// Menu commands (View and Format menus, ⌘B, …) act on this. It's
    /// updated when either pane of a window gains focus and when a window
    /// appears. A SwiftUI `FocusedValue` isn't used, because menu shortcuts
    /// bound through it never fired (see `ViewCommands`).
    static weak var active: EditorModel?

    /// Makes this window's model the target of menu commands.
    func becomeActive() {
        Self.active = self
    }

    /// Keeps the panes' scroll positions together (REQ-020).
    @ObservationIgnored let scrollSync = ScrollSync()

    /// Reports that a pane scrolled, and scrolls the other pane to match.
    ///
    /// - Parameters:
    ///   - pane: The pane that scrolled.
    ///   - line: The 1-based source line at its top.
    func paneDidScroll(_ pane: EditorPane, toLine line: Int) {
        guard isSourceVisible, let target = scrollSync.paneDidScroll(pane, toLine: line) else { return }
        switch pane {
        case .source: preview?.scroll(toLine: target)
        case .preview: sourceEditor?.scroll(toLine: target)
        }
    }

    /// Shows or hides the source pane.
    func toggleSourcePane() {
        isSourceVisible.toggle()
    }

    /// Exports the window's document; set by `ContentView`, which owns the
    /// document (REQ-017, REQ-018).
    @ObservationIgnored var exportHandler: ((ExportFormat) -> Void)?

    /// Exports the document in the given format, asking where to save.
    ///
    /// - Parameter format: HTML or PDF.
    func export(_ format: ExportFormat) {
        exportHandler?(format)
    }

    /// Inserts a Markdown structure in the active pane (REQ-015).
    ///
    /// In the source pane, the snippet edits the text at the insertion point
    /// (see ``MarkdownSnippets``). In the rendered pane, it formats the
    /// selection or inserts after the block being edited (see
    /// ``PreviewController/insert(_:)``).
    ///
    /// - Parameter snippet: The structure to insert.
    func insert(_ snippet: MarkdownSnippet) {
        switch activePane {
        case .source:
            sourceEditor?.insert(snippet)
        case .preview:
            preview?.insert(snippet)
        }
    }
}
