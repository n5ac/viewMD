# viewMD

A quick, clean Markdown viewer and editor for macOS 15 and later, written in Swift.

To install viewMD on another Mac and make it the default app for `.md`
files, see the [installation guide](docs/INSTALL.md)
([PDF](docs/viewMD-Install-Guide.pdf)).

## Features

- **Two panes:** the rendered document on the left, the Markdown source on
  the right. Both are editable, and each updates the other as you type.
  Hide the source (⌥⌘S or the toolbar button) to just read or edit the
  rendered view.
- **GitHub Flavored Markdown:** tables, task lists, strikethrough,
  autolinks and fenced code with syntax highlighting.
- **Quick inserts:** toolbar pull-downs and the Format menu add headings,
  emphasis, links, images, lists, quotes, code blocks, tables and rules at
  the insertion point, in whichever pane you're working in.
- **Export:** File ▸ Export as HTML… (⇧⌘E) writes a standalone web page.
  File ▸ Export as PDF… (⇧⌘P) writes a paginated PDF.
- **Scroll sync:** the panes stay on the same part of the document.
- **Light and dark:** follows the system appearance.
- **Safe:** scripts in documents never run.

### Keyboard shortcuts

| Action | Shortcut |
|--------|----------|
| Show/hide source | ⌥⌘S |
| Heading 1–6 | ⌘1 – ⌘6 |
| Bold / italic / strikethrough | ⌘B / ⌘I / ⇧⌘X |
| Bulleted / numbered / task list | ⇧⌘8 / ⇧⌘7 / ⇧⌘9 |
| Quote | ⌘' |
| Link | ⌘K |
| Export HTML / PDF | ⇧⌘E / ⇧⌘P |
| Open a link in the rendered pane | ⌘-click |

### Local images

viewMD is sandboxed. If a document shows images from its own folder, a bar
above the preview offers **Grant Access…**. Choose the folder once and
viewMD remembers it.

## Privacy

viewMD collects no data. See the [privacy policy](docs/PRIVACY.md).

## Building

Open `viewMD.xcodeproj` in Xcode, or from the command line:

```sh
xcodebuild build -project viewMD.xcodeproj -scheme viewMD
xcodebuild test  -project viewMD.xcodeproj -scheme viewMD -destination 'platform=macOS'
```

## Project governance

- [`CLAUDE.md`](CLAUDE.md): the development workflow and rules
- [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md): agreed requirements
- [`docs/PREFERENCES.md`](docs/PREFERENCES.md): the owner's recorded preferences
- [`docs/PLAN.md`](docs/PLAN.md): architecture and phased build plan

## Third-party components

| Component | License | Use |
|-----------|---------|-----|
| [swift-markdown](https://github.com/swiftlang/swift-markdown) (with swift-cmark / cmark-gfm) | Apache-2.0 / BSD-2-Clause | Markdown parsing |
| [highlight.js](https://highlightjs.org) 11.11.1 + GitHub themes | BSD-3-Clause | Code-block highlighting in the preview and exports |
| [Markdown mark](https://github.com/dcurtis/markdown-mark) | CC0 (public domain) | App icon |

## License

GPL-3.0. See [`LICENSE`](LICENSE).
