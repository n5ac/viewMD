# viewMD

A native macOS app written in Swift.

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
| [highlight.js](https://highlightjs.org) 11.11.1 + GitHub themes | BSD-3-Clause | Code-block highlighting in the preview |

## License

GPL-3.0. See [`LICENSE`](LICENSE).
