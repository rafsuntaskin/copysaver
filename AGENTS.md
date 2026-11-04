# CopySaver repository instructions

## Start here

Read [spec.md](spec.md), its delivery checklist and progress log, [CONTRIBUTING.md](CONTRIBUTING.md), and [docs/development.md](docs/development.md) before changing code. For UI work, also read [PRODUCT.md](PRODUCT.md), [DESIGN.md](DESIGN.md), and [designs/README.md](designs/README.md), and inspect the selected mockups.

`spec.md` is the source of truth for requirements, scope, defaults, and delivery status. The repository contains tested core libraries and a native development scaffold. Clipboard capture, retention, snippet workflows, and a launcher widget have source implementations and tests. Signed security/release checks and widget discovery remain unfinished. Do not invent build targets, commands, passing tests, or implemented features.

## Product and architecture

- Build a macOS-first, local-only clipboard history and named-snippet app using Swift 6, SwiftUI, and targeted AppKit integration. Rust/Tauri is not the selected stack.
- Keep the approved interface: concept 1 for the full three-column library and concept 2 for the globally accessible Focus panel. Use the same shell for History and Snippets. Concept 3 is an unselected exploration.
- The global Focus Mode shortcut is user-configurable, initially Option-Command-V. Ordinary use copies text; users paste with Command-V. Do not introduce Accessibility permission or simulated paste for the MVP.
- The WidgetKit extension is a launcher with generic labels. It must not access clipboard content, the vault, or its Keychain key, or expose saved content through snapshots or URLs.
- Separate domain policies, persistence/crypto, clipboard integration, platform adapters, and UI. Use actors and session generations to prevent work from crossing a lock boundary.
- Prefer OS frameworks and zero third-party runtime dependencies initially. Explain a concrete need, license implications, and maintenance cost before adding a dependency.
- Keep Windows, rich clipboard formats, sync, and encrypted export/import outside v0.1 unless the user changes scope. Record material requirement changes in the spec in the same change.

## Security requirements

- Encrypt complete record payloads before handing them to SQLite. Use CryptoKit AES-256-GCM, fresh nonces, and authenticated vault/record/version identity as specified.
- Default community builds use the macOS login Keychain with a caller-only ACL and automatic open/resume, as the user requested on November 3, 2026. Protected compatibility builds retain device-only data-protection Keychain user presence. Never use a file-stored key, hardcoded key, broad trusted-app list or plaintext fallback, or silently migrate existing protected vaults.
- New community vaults capture automatically after OS clipboard approval; respect saved pause/disable choices. Suspend closes capture/write admission, invalidates pending work, clears owned sensitive clipboard content and decrypted state; corresponding return events resume automatically. Explicit Hide and pause remains until explicit resume. Protected builds start locked. Missing keys and authentication/decryption failures preserve the vault and fail closed.
- Exclude concealed/transient/generated clipboard types and app-owned writes. Treat source attribution, secret heuristics, and application exclusions as best-effort privacy controls.
- Keep secrets, queries, titles, previews, content hashes, and user-derived metadata out of logs, preferences, widget state, URLs, fixtures, and diagnostics. Use only synthetic data in tests and screenshots.
- Community builds trust the open user session: Sensitive means concealed previews/search/VoiceOver output and owned clipboard expiry, with explicit reveal/edit but no additional authentication. Protected compatibility builds retain fresh sensitive-action authentication. Do not silently change the selected profile or weaken encryption at rest.
- Do not overstate app exclusivity, secure deletion, memory erasure, secret detection, or recovery guarantees. Tests of unsigned builds do not establish signed Keychain access control.
- Development builds use their own app identity and vault; never access a user's production vault for tests.
- System-wide changes, installer packages, developer directory changes, and trust/security settings are not routine repository work. Do not silently perform them. The user explicitly approved the bundled Apple-signed XcodeSystemResources repair on October 26, 2026; installation completed and Xcode SDK loading works. This approval does not authorize other system changes.

## Git workflow

- Inspect `git status --short --branch` and the current diff before work. Preserve unrelated user changes; never reset, clean, overwrite, or stash them without a concrete need and authorization.
- `main` is the integration baseline. The one-time bootstrap commit is already on `main`; normal work belongs on a focused branch created from the current integration baseline.
- Branch names: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `test/<topic>`, `refactor/<topic>`, or `chore/<topic>`. Use short lowercase hyphenated topics.
- Reuse an existing branch only when continuing the same task. Start a separate branch for an unrelated task. Check the user's current branch and uncommitted changes first.
- If prerequisite work is not integrated, an explicitly documented stacked branch may start from that dependency. Record its base and integration order; do not merge into `main` silently. The initial vault feature depends on the planning baseline at `11caee9`; `feat/native-app` is stacked on `feat/vault-foundation` at `06359fe`. These branches were integrated into `main` through `4e00273` after the user authorized ongoing local merges. Continue with focused branches from `main`, validate, review, and fast-forward merge completed changes as authorized.
- Make small, coherent commits using Conventional Commit subjects: `type(scope): imperative summary`. Include the implementation, relevant tests, and matching spec progress update together. A commit must not contain unrelated cleanup.
- Before each commit, inspect staged paths and the staged diff, run `git diff --cached --check`, and run relevant available validation. Stage explicit paths rather than blindly staging the entire workspace.
- Record unavailable validation as pending/blocked with its reason. Never mark a gate passed just to produce a clean commit or finish a milestone.
- Normal authorized work may include local commits. Do not amend, rebase, force-push, merge into `main`, create a remote repository, or publish/push without authorization for that action. Do not invent a remote URL or signing identity.
- Use pull requests for integration once a remote exists. Report the problem addressed, behavior changed, tests/evidence, remaining blockers, and relevant checklist IDs. Do not merge your own unreviewed work automatically.
- Do not disable configured hooks or commit signing to get a commit through. If author identity is missing, ask for it rather than making one up or changing global configuration.

See [CONTRIBUTING.md](CONTRIBUTING.md) for examples and integration details.

## Keep the spec current

- Update the delivery checklist and progress log in `spec.md` in every commit that changes requirements, implementation, tests, or milestone status. Docs-only changes outside delivery scope need an entry only when they change the plan or contributor workflow.
- Checklist IDs are stable. Do not renumber completed or referenced items. Add new IDs for new work, and explain removals or superseded items in the progress log.
- `[x]` means the deliverable exists and its stated validation passed. `[ ]` means pending, in progress, or blocked; distinguish these in the status table and evidence column. Do not invent nonstandard checkbox markers.
- Add evidence: an exact command and result, test target, file, or manual scenario. A future test plan is not completion evidence. A temporary toolchain check is not an app security test.
- Keep unfinished acceptance checks unchecked, even when a related implementation task is done. Mark a milestone complete only after all of its exit checks pass.
- Add a dated progress entry summarizing IDs changed, validation, blockers, and the next actionable task. Prefer concise evidence over a transcript of every command. Do not embed real user content or sensitive command output.

## Implementation and validation

- Read existing code before changing it. Use `rg` for discovery, keep APIs small, and avoid speculative frameworks and abstractions.
- Swift uses four-space indentation, descriptive types and methods, immutable values where practical, explicit error handling, and concurrency boundaries that satisfy Swift 6 checking. Keep UI and AppKit work on the main actor where required.
- Inject clock, clipboard, authentication, storage, and lifecycle interfaces so retention, lock races, and permission failures can be tested deterministically.
- Test meaningful behavior and regressions: round trips/tampering, exact text preservation, duplicate/retention limits, denied authentication, write failures, self-copy suppression, and lock races. Do not add tests that only mirror the implementation or meaningless tests for documentation edits.
- Run targeted tests first, then the relevant complete suite once. Broaden/repeat only when changes or unresolved failures justify it.
- Never modify system developer frameworks or accept licenses to unblock a repository test. Use the documented process-scoped Command Line Tools fallback where appropriate.
- Do not add an implicit fallback that bypasses the selected protection profile, weakens encryption, grants broad entitlements, or silently swallows a security failure. The explicitly selected community profile is a distinct release policy, not an authentication-error fallback. Retain App Sandbox/hardened runtime and never claim app exclusivity against a compromised account.
- Review UI in light/dark appearance and keyboard/VoiceOver use. The selected screenshots are layout references, not proof of implemented interactions, accessibility, or security.

## Handoff

Report what changed, validation performed, what remains blocked, current branch/commit, and the next checklist task. Link to real repository files. State clearly when no runnable app or release artifact exists. Leave temporary files, vaults, signing credentials, compiler output, and local editor state out of commits.
