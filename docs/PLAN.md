# viewMD Build Plan

How viewMD gets built, phase by phase. Every phase follows the per-change
workflow in `CLAUDE.md` (requirements check → documented code → unit tests →
full test run → commit → push). Requirement IDs refer to `docs/REQUIREMENTS.md`.

## Architecture

```
┌──────────────────────────── Document window ─────────────────────────────┐
│ Toolbar: [Heading ▾] [Format ▾] [Lists ▾] [Insert ▾]  ·  [Export ▾] [◨]  │
├───────────────────────────────────┬──────────────────────────────────────┤
│  PreviewView  (WKWebView)         │  SourceEditorView  (NSTextView)      │
│  rendered GFM, editable blocks    │  monospaced, syntax-colored          │
└───────────────┬───────────────────┴──────────────────┬───────────────────┘
                │  block edit (HTML + source lines)     │  text edit
                ▼                                       ▼
        HTMLToMarkdown ──► SourceSplicer ──►  EditorModel.text  ◄── typing
                                                │
                                                ▼
                         MarkdownRenderer (swift-markdown → HTML + line tags)
                                                │
                                                ▼
                                     PreviewView.update(html)
```

The Markdown source text is the **single source of truth**. Both panes are
views of it.

| Component | Responsibility | Testable as pure Swift? |
|-----------|----------------|------------------------|
| `MarkdownDocument` | `FileDocument` that reads and writes `.md` / `.markdown` / plain text (replaces the template's `viewMDDocument`). | Yes |
| `MarkdownRenderer` | Parses GFM with Apple's `swift-markdown` and renders HTML using a custom `MarkupVisitor`. Each top-level block is tagged with its source line range (`data-src="12-18"`). | Yes |
| `HTMLSanitizer` | Strips `<script>`, inline event handlers and `javascript:` URLs from raw HTML (REQ-007). | Yes |
| `EditorModel` | `@Observable` per-window state: text, selection, focused pane, source-pane visibility, and which pane an edit came from (stops update loops). | Yes |
| `SourceEditorView` | `NSViewRepresentable` around `NSTextView`: exposes the insertion point and selection, and applies `MarkdownHighlighter` coloring. | Partly |
| `MarkdownHighlighter` | Computes attribute ranges for syntax coloring (REQ-023). | Yes |
| `PreviewView` | `NSViewRepresentable` around `WKWebView`. Loads a bundled `preview.html` (CSS, highlight.js, `bridge.js`) once, then patches the body over JS, so there's no flicker and scroll position is kept. | Partly (bridge has JS tests in a host app) |
| `HTMLToMarkdown` | Converts an edited block's HTML back to Markdown. Uses macOS `XMLDocument` (`.documentTidyHTML`) and only needs to cover the elements our renderer emits. | Yes |
| `SourceSplicer` | Replaces exactly the edited block's line range in the source (REQ-013's "only the edited block changes"). | Yes |
| `MarkdownSnippets` | A pure function `(text, selection, snippet) → (newText, newSelection)` for every pull-down item (REQ-015). | Yes |
| `HTMLExporter` / `PDFExporter` | Standalone HTML with inlined CSS; paginated PDF made by printing an off-screen `WKWebView` (REQ-017/018). | HTML yes; PDF by integration test |

**Why these choices** (P-009: delegated to Claude):

- **swift-markdown** is Apple's own package. It's built on `cmark-gfm`, GitHub's
  reference GFM implementation, and gives source ranges for every node, which
  is what makes block-level two-way editing possible.
- **WKWebView** for the preview gives full-fidelity HTML/CSS, the same engine
  for PDF export, and `contenteditable` for editing.
- **NSTextView** rather than SwiftUI `TextEditor`, for reliable insertion-point
  control and syntax coloring.
- **macOS 15** as the minimum OS: modern SwiftUI (`@Observable`, current
  toolbar APIs) while still covering most Macs in use.

## Phases

Each phase ends with a check-in: what was built, test results, a screenshot,
and any requirement that needs a decision.

### Phase 0: Foundation (done 2026-11-14)
- Set the deployment target to macOS 15.0 (REQ-004).
- Replace the template's document type with `MarkdownDocument` and register
  `net.daringfireball.markdown` plus plain text in `Info.plist` (REQ-010).
- Add the `viewMDTests` unit-test target (Swift Testing) and the `viewMDUITests` UI-test target, plus a shared `viewMD` scheme (REQ-002).
- Add the `swift-markdown` package (REQ-006).
- Add a GitHub Actions workflow for build and test on push/PR (REQ-008). CI runs unit tests only; an ad-hoc-signed UI-test runner hangs without automation permission, so UI tests run locally.
- **Done when:** the app opens and saves `.md` files, `xcodebuild test` passes
  locally and in CI.

### Phase 1: Rendering core, no UI (done 2026-11-14)
- `MarkdownRenderer` covering all GFM constructs, with `data-src` line tags (REQ-016).
- `HTMLSanitizer` (REQ-007).
- Relative-URL resolution against the document's folder (REQ-022).
- **Done when:** unit tests cover every GFM construct and the sanitizer
  rejects known script-injection cases.
- Notes:
  - swift-markdown doesn't enable cmark-gfm's autolink extension or report
    whether a list is tight, so viewMD implements both (`Autolinker`, and
    `isTight` in the renderer).
  - GFM footnotes aren't supported by swift-markdown and aren't rendered;
    they're outside REQ-016's list.

### Phase 2: Two-pane window with live one-way updates (done 2026-11-14)
- Split window: preview on the left, source on the right (REQ-011, P-006).
- `SourceEditorView` and `PreviewView`, plus a debounced live update and a latency test (REQ-012).
- Show/hide source pane: toolbar button, View menu, ⌥⌘S (REQ-014).
- Light/dark appearance (REQ-021); links open in the browser (REQ-022).
- **Done when:** typing in the source updates the preview live, and the pane toggle works.
- Notes:
  - The preview loads from a private `viewmd:` URL scheme
    (`PreviewSchemeHandler`). Local images are read by the app process,
    which holds the sandbox access. When a sibling image is blocked, a
    "Grant Access…" banner saves a security-scoped folder bookmark.
  - A Content-Security-Policy in `preview.html` blocks all inline script
    (a second layer behind REQ-007's sanitizer).
  - ⌥⌘S is bound on the toolbar button, because a shortcut on the
    `FocusedValue`-driven menu item never fired.
  - Source syntax coloring (REQ-023) was pulled forward from Phase 6, and
    highlight.js 11.11.1 (BSD-3-Clause) is now bundled.

### Phase 3: Quick-insert pull-downs (done 2026-11-14)
- `MarkdownSnippets` engine for every REQ-015 structure, with wrap-selection behavior.
- Toolbar pull-downs (Heading ▾, Format ▾, Lists ▾, Insert ▾), a matching
  Format menu, and standard shortcuts (⌘B, ⌘I, ⌘K).
- **Done when:** each snippet has unit tests for an empty selection, a
  selection, and a document start or end.
- Notes:
  - Shortcuts: ⌘1–⌘6 headings, ⌘B bold, ⌘I italic, ⇧⌘X strikethrough,
    ⇧⌘8 / ⇧⌘7 / ⇧⌘9 bulleted / numbered / task list, ⌘' quote, ⌘K link,
    ⌥⌘S show/hide source.
  - Menu commands target `EditorModel.active`, the window last worked in.
    Shortcuts on SwiftUI `FocusedValue`-driven menu items never fired.

### Phase 4: Editing in the rendered pane (done 2026-11-14)
- `bridge.js`: makes top-level blocks `contenteditable` and posts
  `{lines, html}` to Swift on a debounced input.
- `HTMLToMarkdown` + `SourceSplicer` (REQ-013).
- Loop prevention: a preview-originated edit re-renders every block except the
  one being edited, so the caret doesn't jump.
- The pull-downs work in the preview too: they act on the focused block (REQ-015).
- **Done when:** round-trip tests pass (Markdown → HTML → edit → Markdown
  changes only that block), and manual QA confirms typing in the preview is
  smooth.
- Notes:
  - `bridge.js` keeps a snapshot of each block. After 250 ms without
    typing, it sends the changed run of blocks with its source lines. Until
    the re-render arrives, it holds back further edits, and it keeps
    unsent typing in place instead of overwriting it.
  - Links and images carry their source URL in `data-md-href` /
    `data-md-src`, so edits don't write resolved `viewmd://` URLs into the
    file.
  - `HTMLToMarkdown` protects newlines between text characters before
    tidy-HTML parsing, which would otherwise collapse soft line breaks.
  - Undo: WebKit's own DOM undo is disabled. ⌘Z in either pane acts on the
    document. SwiftUI's automatic per-keystroke registration is paused when
    the binding is written. A text-storage delegate catches undo and redo
    of programmatic changes, which `textDidChange` misses.
  - In the rendered pane, ⌘-click opens a link; a plain click places the
    caret.

### Phase 5: Export (done 2026-11-14)
- File ▸ Export ▸ HTML… / PDF…, with a save panel (REQ-017, REQ-018). The toolbar Export ▾ mirrors it.
- **Done when:** the HTML export is a single self-contained file (tested), and
  the PDF export is paginated and correct (checked with PDFKit in an integration test).
- Notes:
  - Shortcuts: ⇧⌘E exports HTML, ⇧⌘P exports PDF. The toolbar Export
    pull-down mirrors them.
  - HTML export is script-free. Code is pre-highlighted by running the
    bundled highlight.js in JavaScriptCore, and relative paths are kept as
    written, so save the file next to the document to keep its images.
  - PDF export prints the same HTML from an off-screen WKWebView, using
    the user's default paper with 0.6-inch margins. `@media print` forces
    light colors and keeps backgrounds (`print-color-adjust: exact`).

### Phase 6: Polish (done 2026-11-14)
- Code-block highlighting (REQ-019), scroll sync (REQ-020), source syntax coloring (REQ-023).
- Performance pass on a 5,000-line document (REQ-012).
- App icon, accessibility labels, VoiceOver check, and a final design review (REQ-005).
- **Done when:** every `Must` requirement is `Done`, and each `Should` is
  `Done` or deferred with the owner's agreement.
- Notes:
  - Scroll sync matches the source line at the top of each pane. At the
    very end of one pane, the other goes to its end too. A short echo
    window (`ScrollSync`) stops programmatic scrolls from bouncing back.
  - The source text view now uses an explicit TextKit 1 stack, so line
    positions come from `NSLayoutManager`.
  - App icon: the CC0 Markdown mark on a blue squircle, generated by
    `tools/make-icon.swift`.
  - Not done by Claude: a hands-on VoiceOver pass. Accessibility labels
    and identifiers are set on both panes and every toolbar control.

## Risks

| Risk | Mitigation |
|------|------------|
| Editing in the preview rewrites the user's Markdown style (e.g. `*` becomes `_`). | Rewrite only the edited block (REQ-013); the converter reuses the original block's markers where it can. |
| The caret jumps while typing in the preview. | Never replace the DOM of the block being edited; only patch the others. |
| Some blocks are awkward to edit as rich text (tables, code blocks). | Code blocks are edited as plain text. Table cells are edited one cell at a time, and the table structure changes only through the source pane or the pull-downs. |
| CI runners lag behind the local Xcode 26.6. | Pin the runner image and Xcode version in the workflow; check this in Phase 0. |

## Releases

| Version | Date | Channel | Notes |
|---------|------|---------|-------|
| 0.1 (1) | 2026-11-14 | TestFlight external group **Alpha** (Ed Gonzalez); internal group **viewMD Team** | First alpha. App Store Connect app "viewMD – Markdown Editor" (the name "viewMD" was taken), bundle ID `com.n5ac.viewMD`, SKU `viewMD-mac`. Submitted for Beta App Review. |
| 0.1 (2) | 2026-11-15 | TestFlight **viewMD Team** (internal) and **Alpha** | Adds Find (⌘F) in both panes (REQ-025). Available to viewMD Team at once. Replaced build 1 in Beta App Review for Alpha (Apple allows one build per version in review at a time), so build 1 was never released externally. |

**How a release is made:** bump `CURRENT_PROJECT_VERSION` (the build number must increase for every upload), run the full test suite, then `xcodebuild archive -scheme viewMD -configuration Release -archivePath <path>.xcarchive -allowProvisioningUpdates`, then `xcodebuild -exportArchive` with an ExportOptions plist containing `method = app-store-connect` and `destination = upload`. Add the build to the TestFlight group in App Store Connect. Internal groups get a new build as soon as it's processed; an external group needs Beta App Review, and only one build per version can be in review at a time.

