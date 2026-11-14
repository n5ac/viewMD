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

## Functional requirements

| ID | Requirement | Priority | Status | Verified by |
|----|-------------|----------|--------|-------------|
| _None yet. To be defined with the owner before development starts._ | | | | |

## Non-functional requirements

| ID | Requirement | Priority | Status | Verified by |
|----|-------------|----------|--------|-------------|
| REQ-001 | Native macOS app written in Swift. | Must | Agreed | Xcode project setup |
| REQ-002 | Every code change has unit tests where possible, and the full suite passes before commit. | Must | Agreed | Commit history / CI test run |
| REQ-003 | All code is well documented (DocC `///` comments on non-trivial declarations, inline comments for non-obvious logic). | Must | Agreed | Code review |

## Change log

| Date | Change |
|------|--------|
| 2026-11-14 | Document created; process requirements REQ-001 to REQ-003 recorded. |
