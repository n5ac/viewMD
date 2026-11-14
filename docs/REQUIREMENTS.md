# viewMD Requirements

This is the agreed list of requirements for viewMD. Every change must be checked
against it (see `CLAUDE.md`). Requirements are added or changed only with the
owner's agreement.

## Format

Each requirement has a stable ID that is never reused, even if the requirement
is dropped.

| Field | Meaning |
|-------|---------|
| ID | `REQ-NNN`, assigned in order |
| Requirement | What the app must do, written so it can be tested |
| Priority | `Must` / `Should` / `Could` |
| Status | `Proposed` → `Agreed` → `In progress` → `Done` (or `Dropped`) |
| Verified by | The tests or manual check that prove it |

`Agreed` means the owner stated or approved it. `Proposed` means Claude derived
it (often where the owner delegated the choice) and it is waiting for the
owner's approval.

## Functional requirements

| ID | Requirement | Priority | Status | Verified by |
|----|-------------|----------|--------|-------------|
| REQ-010 | viewMD is a quick, easy Markdown viewer **and** editor: a document-based app that creates, opens, edits and saves `.md` / `.markdown` files (plain text also opens), with standard macOS autosave, undo and multiple windows. | Must | In progress | Document read/write unit tests; manual QA |
| REQ-011 | Each window has two panes: the **rendered** Markdown on the **left**, the Markdown **source** on the **right**. | Must | Agreed | UI test; manual QA |
| REQ-012 | Editing the source pane updates the rendered pane automatically as you type (target: under 150 ms for documents up to 5,000 lines). | Must | Agreed | Renderer unit tests; performance test |
| REQ-013 | Editing text in the rendered pane updates the Markdown source automatically. Only the Markdown of the edited block is rewritten; the rest of the source stays byte-for-byte unchanged. | Must | Agreed | HTML→Markdown and splice unit tests; round-trip tests |
| REQ-014 | The user can hide and show the source pane (toolbar button, View menu item and keyboard shortcut). When it's hidden, the rendered view fills the window. | Must | Agreed | UI test; manual QA |
| REQ-015 | Quick pull-down menus insert common Markdown structures at the current insertion point: headings (H1–H6), bold, italic, strikethrough, inline code, code block, link, image, bulleted / numbered / task list, block quote, table and horizontal rule. If text is selected, it is wrapped where that makes sense (e.g. selection → **bold**). Works in whichever pane has focus. | Must | Agreed | Snippet-engine unit tests; manual QA |
| REQ-016 | The Markdown dialect is GitHub Flavored Markdown (GFM): CommonMark plus tables, task lists, strikethrough and autolinks. This is the most common dialect and the one Claude writes. | Must | Agreed | Renderer unit tests against GFM spec examples |
| REQ-017 | The user can export the document to **HTML** (a standalone file with styles embedded) on demand, choosing where to save it. | Must | Agreed | HTML exporter unit tests |
| REQ-018 | The user can export the document to **PDF** (paginated, matching the rendered view) on demand, choosing where to save it. | Must | Agreed | PDF export integration test (PDFKit page check) |
| REQ-019 | Fenced code blocks in the rendered view are syntax highlighted. | Should | Agreed | Manual QA |
| REQ-020 | The two panes keep their scroll positions in sync. | Should | Agreed | Manual QA |
| REQ-021 | The app follows the system light / dark appearance in both panes and in exports. | Should | Agreed | Manual QA |
| REQ-022 | Links in the rendered view open in the default browser. Relative image paths resolve against the document's folder. | Should | Agreed | Unit test for URL resolution; manual QA |
| REQ-023 | The source editor uses a monospaced font with light Markdown syntax coloring (headings, emphasis, code, links). | Should | Agreed | Highlighter unit tests |

## Non-functional requirements

| ID | Requirement | Priority | Status | Verified by |
|----|-------------|----------|--------|-------------|
| REQ-001 | Native macOS app written in Swift. | Must | Done | Xcode project setup |
| REQ-002 | Every code change has unit tests where possible, and the full suite passes before commit. | Must | Agreed | Commit history / CI test run |
| REQ-003 | All code is well documented (DocC `///` comments on non-trivial declarations, inline comments for non-obvious logic). | Must | Agreed | Code review |
| REQ-004 | The minimum supported OS is macOS 15.0 (Sequoia). | Must | Done | Xcode deployment target (`MACOSX_DEPLOYMENT_TARGET = 15.0`) |
| REQ-005 | The UI is crisp, clean and easy to understand: native macOS controls, toolbar and menus following Apple's Human Interface Guidelines, SF Symbols, and no clutter. | Must | Agreed | Manual design review |
| REQ-006 | Dependencies are kept small and GPL-3.0-compatible: Apple's `swift-markdown` (Apache-2.0) for parsing and `highlight.js` (BSD-3-Clause), bundled in the app. The app needs no network access to work. | Must | In progress | Package manifest review |
| REQ-007 | Rendering a document never runs scripts from that document: `<script>` tags and inline event handlers in raw HTML are removed. | Should | Agreed | Sanitizer unit tests |
| REQ-008 | A GitHub Actions workflow builds the app and runs the full test suite on every push and pull request (unit tests; UI tests run locally, see `CLAUDE.md`). | Should | In progress | CI run status |

## Change log

| Date | Change |
|------|--------|
| 2026-11-14 | Document created; process requirements REQ-001 to REQ-003 recorded. |
| 2026-11-14 | Owner's app requirements added (REQ-010 to REQ-018, REQ-005). Derived requirements REQ-004, REQ-006 to REQ-008 and REQ-019 to REQ-023 proposed. |
| 2026-11-14 | Owner approved all Proposed requirements; all now Agreed. |
| 2026-11-14 | Phase 0: REQ-001 and REQ-004 Done; REQ-006, REQ-008 and REQ-010 In progress. |
