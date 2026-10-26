# Contributing to CopySaver

## Scope and source of truth

Read [spec.md](spec.md), [AGENTS.md](AGENTS.md), and [development setup](docs/development.md). The spec defines v0.1 scope, security requirements, and stable delivery checklist IDs. Update it alongside implementation rather than maintaining a competing task list.

The repository contains core/platform/desktop Swift libraries and tests, a runnable sample-data development app, an Xcode app project, planning documents, and design references. Clipboard capture and retention are implemented; the widget target and signed native validation are pending. Do not describe planned commands, app downloads, signed validation, or release artifacts as available until they exist and have been verified.

## Branches

Use a lightweight branch-and-review workflow:

1. Check the current branch, working tree, and relevant diffs. Preserve other people's changes.
2. Create a focused branch from `main`. When a remote exists, fetch it and use the current integration baseline; update a clean local `main` with a fast-forward-only pull rather than an implicit merge.
3. Implement one coherent concern, with relevant tests and spec progress updates.
4. Review and validate the staged change, then commit.
5. When a remote is configured, push only with authorization and open a pull request. Use the PR template and link checklist IDs.
6. Integrate after review and passing applicable checks. Prefer squash merge for a multi-commit feature; a reviewed single-commit branch may be fast-forwarded. Do not create merge commits just to keep a branch current. Never rewrite a shared branch or force-push without explicit agreement.
7. Delete a feature branch only after its work is integrated and the branch is no longer needed.

If required foundation work is not yet integrated, use an explicitly documented stacked branch from that dependency instead of silently merging it into `main` or dropping its files. The initial `feat/vault-foundation` branch is based on `docs/project-foundation` at `11caee9`; review/integrate the planning baseline before its dependent feature work. `feat/native-app` is stacked on `feat/vault-foundation` at `06359fe`. Review/integrate planning, vault, then native app, without silently merging into `main`.

Examples of branch names:

- `feat/vault-foundation`
- `fix/clipboard-self-capture`
- `docs/project-foundation`
- `test/retention-boundaries`
- `chore/build-configuration`

Use lowercase, hyphenated topics. Release tags use `v<major>.<minor>.<patch>` after release validation; no release tag is appropriate for the planning baseline.

The initial repository bootstrap commit on `main` is a one-time exception to branch-based work. The planning baseline is developed on `docs/project-foundation`. No remote, push, pull request, or merge is implied by local commits.

## Commits

Use `type(scope): summary`, with an imperative summary and a concise subject (aim for 72 characters or fewer). Types include `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, and `revert`.

Examples:

```text
feat(vault): add authenticated encrypted record storage
fix(clipboard): ignore app-owned clipboard writes
test(vault): cover tampered record identities
docs(plan): record signed Keychain validation blocker
```

Each commit should be reviewable and focused. Keep related implementation, tests, and spec status together. Use a commit body to explain a non-obvious tradeoff or pending integration check. Use `BREAKING CHANGE:` in the body for incompatible public behavior or persisted formats, with migration implications documented.

Before committing:

- Review `git status --short --branch` and the working diff.
- Run relevant available validation. For documentation-only changes, check links, checklist consistency, and whitespace; do not invent application test results.
- Stage explicit files and inspect `git diff --cached --stat` and `git diff --cached`.
- Run `git diff --cached --check`.
- Confirm the change includes no vaults, signing material, real clipboard data, generated builds, or user-specific Xcode state.
- Update the spec progress log and affected checklist items with evidence and blockers.

Do not bypass hooks or disable signing. Use the developer's configured Git identity. Do not amend or rebase someone else's work, reset unrelated changes, or publish changes without authorization.

## Progress tracking

Use the checklist and progress log in spec section 0:

- Check a task only after its deliverable and stated validation are complete.
- Leave blocked tasks unchecked and record the dependency, next action, and evidence in the status table.
- Keep acceptance criteria independent of implementation tasks. Code existing does not imply signed platform behavior or release readiness has passed.
- Add a dated progress-log entry in each implementation commit. Reference stable IDs rather than copying the entire requirement text.
- Record later requirement changes in the affected spec section and checklist at the same time.

## Tests and reviews

Use synthetic fixtures. Test crypto authenticity, lossless text handling, retention boundaries, storage failure, permission denial, and session/lock races. Signed Keychain checks, widget discovery/navigation, VoiceOver, system lifecycle behavior, and clean-install testing require separate integration evidence.

An unsigned preview or passing core suite must not be used to claim authentication isolation, notarization, full platform compatibility, or security review. Report unavailable tests plainly.

Follow the selected design references and native macOS accessibility conventions. Keep dependencies limited and intentional. See [SECURITY.md](SECURITY.md) before reporting a vulnerability.
