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

## License

GPL-3.0. See [`LICENSE`](LICENSE).
