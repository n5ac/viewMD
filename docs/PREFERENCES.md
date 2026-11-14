# Owner Preferences

A running record of guidance from the project owner that shapes how code is
written. Check this before every change (see `CLAUDE.md`). When an instruction
supersedes an older one, edit the older entry; don't keep contradictory entries.

| # | Date | Preference | Context / why |
|---|------|------------|---------------|
| P-001 | 2026-11-14 | Every code change gets unit tests where possible, is tested, and only then committed. | Initial governance setup. |
| P-002 | 2026-11-14 | All code changes must be well documented. | Initial governance setup. |
| P-003 | 2026-11-14 | Agree on requirements before starting the project, and check every change against them. | Initial governance setup. |
| P-004 | 2026-11-14 | Record guidance the owner gives that influences the code, and respect it in future work. | Initial governance setup. |
| P-005 | 2026-11-14 | Everything is stored in the GitHub repo `n5ac/viewMD`. | Initial governance setup. |
| P-006 | 2026-11-14 | Pane layout: rendered view on the **left**, Markdown source on the **right**. | App definition. Note this is the reverse of most Markdown editors; keep it. |
| P-007 | 2026-11-14 | The UI must be crisp, clean and easy to understand. | App definition. |
| P-008 | 2026-11-14 | Editing must work in **both** panes (rendered and source), each updating the other. | Owner chose this over source-only editing, knowing it's harder to build. |
| P-009 | 2026-11-14 | The owner delegates technical choices (minimum OS, packages, Markdown dialect) to Claude's judgment: pick what makes the most sense, with the most common / Claude-style Markdown (GFM). | App definition. Still record each choice as a `Proposed` requirement for approval. |
| P-010 | 2026-11-14 | Changing the Xcode template is fine where needed. | App definition. |
| P-011 | 2026-11-14 | In user-facing documents, credit **Stephen Hicks, N5AC** for the idea and **Claude** for the code. | Requested for the install guide PDF. |
| P-012 | 2026-11-14 | Alpha releases go out through **TestFlight external testing** (testers get no account access). Category: Developer Tools. Tester feedback goes to n5ac@n5ac.com, and the privacy policy is `docs/PRIVACY.md` on GitHub. | First alpha invite for Ed Gonzalez. |
