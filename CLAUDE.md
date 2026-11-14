# viewMD — Project Governance

viewMD is a native macOS app written in Swift (SwiftUI, Xcode project
`viewMD.xcodeproj`, bundle id `com.n5ac.viewMD`). The source of truth is the
GitHub repo `git@github.com:n5ac/viewMD.git` (branch `main`).

These rules are binding for every change. If a rule can't be followed, stop and
say why before going further.

## Governing documents

| File | Purpose |
|------|---------|
| `docs/REQUIREMENTS.md` | The agreed requirements. Every change must be checked against it. |
| `docs/PREFERENCES.md` | Log of the owner's guidance on how code should be written. Every change must respect it. |
| `CLAUDE.md` (this file) | The workflow and rules. |

## Workflow for every change

1. **Read the governing docs first.** Re-read `docs/REQUIREMENTS.md` and
   `docs/PREFERENCES.md` before planning a change.
2. **Map the change to requirements.** Name the requirement ID(s) the change
   implements or touches (e.g. `REQ-004`). If a change serves no requirement,
   or conflicts with one, raise it with the owner before writing code. New
   features need a requirement agreed first.
3. **Implement with documentation.**
   - Every type, function, property and extension that isn't trivially private
     gets a `///` DocC comment saying what it does, its parameters, its return
     value, and what it throws.
   - Non-obvious logic gets an inline comment explaining *why*.
   - User-facing behavior changes are reflected in `README.md`.
4. **Write unit tests.** Every code change gets unit tests (XCTest or Swift
   Testing in the `viewMDTests` target) where technically possible. Where a
   test isn't possible (e.g. pure view layout), say so in the commit message
   and explain how it was verified instead.
5. **Run the tests and make sure they pass.** Run the full suite, not just the
   new tests:
   ```sh
   xcodebuild test -project viewMD.xcodeproj -scheme viewMD -destination 'platform=macOS'
   ```
   Never commit with failing tests or a failing build. Never disable or delete
   a test to make the suite pass without the owner's approval.
   - Test targets: `viewMDTests` (unit tests, Swift Testing) and
     `viewMDUITests` (UI tests, XCTest/XCUIApplication).
   - The command above runs both and is the gate before every commit. UI
     tests need a properly signed build, so they run locally; CI
     (`.github/workflows/ci.yml`) runs `viewMDTests` only, with ad-hoc
     signing, and skips the render-timing suite (shared runners are too
     slow for REQ-012's budget). Timing is checked locally.
   - After pushing, check that the CI run passed (`gh run list -L 1`).
6. **Re-check requirements.** Confirm the finished change meets the
   requirement(s) it maps to and doesn't break any other requirement. Update
   the requirement's status in `docs/REQUIREMENTS.md` if it changed.
7. **Commit, then push.** Only after steps 1–6 pass. One logical change per
   commit. Commit message format:
   ```
   <short imperative summary>

   <what changed and why>

   Requirements: REQ-xxx[, REQ-yyy]
   Tests: <tests added/updated, and result of the full test run>
   ```
   Then push to `origin main`.

## Recording the owner's preferences

When the owner points out something that should shape how code is written
(style, architecture, libraries, naming, UX, process — corrections *and*
approvals), add an entry to `docs/PREFERENCES.md` in the same session, and
also save it to Claude's persistent memory. Before writing code, check
existing entries and follow them. If a new instruction contradicts an old
entry, update the old entry rather than keeping both.

## Project conventions

- Language: Swift (see the Xcode project for the Swift version); UI: SwiftUI.
- Target: macOS (deployment target set in the Xcode project).
- Don't add third-party dependencies without the owner's approval.
- Don't commit user-specific Xcode state (`xcuserdata/`, `DerivedData/`); see
  `.gitignore`.
- License: GPL-3.0 (`LICENSE`).
