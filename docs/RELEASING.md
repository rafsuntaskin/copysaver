# Community beta release procedure

This procedure distributes the automatic login-Keychain app without an Apple-issued certificate. It creates a **beta**, never a stable release while the spec's native acceptance gates are open. Developer ID/notarization is a separate optional distribution path.

## Source and version

Create a focused release branch, preserve personal Xcode edits, update `release.json`, app/widget version and beta labels, the changelog, and `docs/releases/<tag>.md` together. Run `make check` to catch version/tag drift. Review the source and keep the exact artifact commit reachable. Do not rewrite source/tag history or replace a published asset.

`v0.1.5-beta.1` uses app/widget 0.1.5 (8), Beta 1. It preserves the existing community bundle identity, encrypted database/envelope format and Keychain namespace. No protected-library migration is included.

## Build locally

From a reviewed **clean** checkout with full Xcode:

```sh
make verify
make community-dmg
make distribution
```

No Apple account, certificate, notarization credential or network key is required. Packaging makes no OS trust changes. The distribution tool audits the universal app/widget and a read-only mounted DMG, verifies its exact app/icon/layout, and creates `dist/<tag>/` with the versioned DMG, source archive, install/community/license/release notes, source/toolchain/dependency/build metadata, release manifest and checksums. It refuses dirty source, stale builds, existing output or unexpected files.

Preserve an existing `.build/community/CopySaver-community.dmg` before rebuilding. Build apps can appear as duplicate local applications; retire only those generated bundles through per-app unregistration/recovery archives as described in development.md. Never remove vaults or Keychain items.

## Hosted workflow

After source integration/review, manually run **Community beta release** from `main` using the exact tag in `release.json`. The workflow verifies source and universal Debug builds on Apple silicon/Intel runners, then packages/audits on macOS and uploads the bundle. GitHub's token has release-write permission only in the packaging job. The workflow creates a **draft prerelease** and never publishes it, changes repository visibility or replaces an existing release.

Hosted execution is a separate acceptance gate. Existing repository runs have failed at startup before any jobs; the workflow must not be advertised as proven until an actual run completes. Local compilation/tests do not establish Intel execution, clean-Mac installation, VoiceOver or widget discovery.

## Create a local-build draft

The user must authorize pushing source/release work. Push the reviewed branch so the exact `SOURCE_REVISION.txt` commit is available in the intended GitHub repository, then run:

```sh
bash scripts/draft-community-release.sh
```

The script validates the bundle and uploads every allowlisted file as a draft prerelease, targeted at the exact build commit. It never publishes, merges or changes repository visibility. Draft publication may create the tag; verify its final target after publishing.

Download **all** draft assets into a fresh folder and run:

```sh
python3 scripts/community-distribution.py verify /path/to/downloaded/assets
```

This verifies exact filenames, no links/extra files, checksums, manifest identity and safe source archive paths/commit/config. Download verification does not replace the native DMG audit done before upload or establish an independent publisher signature.

## Publication gate

Before publishing:

- Review/integrate the source PR. Keep stable FUNC/SEC/REL gates unchecked where pending; the notes must disclose beta limitations.
- Decide whether to make the existing private repository public. That exposes its committed source/history and release assets; a draft in a private repository is not a public download. Do not change visibility without explicit approval.
- Enable GitHub private vulnerability reporting once available and verify it through the API/UI. Update SECURITY.md accurately. No security email or response-time promise is invented.
- Verify draft title, prerelease status, exact target revision and all downloaded assets. Attach the complete distribution directory; do not upload development apps, vaults, credentials or local logs.
- Publish as a **prerelease**, not Latest/stable. Record the release URL/tag/source/asset verification in spec.md. For corrections, publish a new version/tag instead of replacing distributed binaries.

Clean/quarantined macOS installation/update, supported-OS/Intel, lifecycle/permissions, VoiceOver, native network observation and widget-gallery checks remain required for stable promotion. Users follow Apple's supported first-run approval flow; never strip quarantine or disable Gatekeeper to mark a release passed.
