# Install CopySaver community beta

Requires macOS 14 or later. The universal DMG includes Apple silicon and Intel; runtime validation on minimum macOS and Intel hardware is pending. Windows is not included.

## Install or update

1. Download the versioned universal DMG from [GitHub Releases](https://github.com/rafsuntaskin/copysaver/releases). Pick the attached `.dmg`, not the source archive.
2. Quit CopySaver using its menu bar menu. Open the DMG and drag CopySaver to Applications. Replace the same app when updating; do not keep renamed copies.
3. Open `/Applications/CopySaver.app`. This certificate-free app is ad-hoc signed and is not notarized by Apple. macOS may require **System Settings → Privacy & Security → Open Anyway** after you attempt to open it. Follow [Apple's instructions](https://support.apple.com/en-us/102445) only if you trust the download. A managed Mac may disallow it. There is no Terminal bypass or security-setting script.
4. Allow macOS clipboard access for CopySaver when asked. If available, choose Always Allow under Paste from Other Apps. Copy a new, non-sensitive piece of text to test capture.

Updates can need renewed Gatekeeper, clipboard or Keychain approval. A denied/missing Keychain key must preserve the library; do not reset your library to troubleshoot an update.

## Verify the download

Download all attached release files into one folder, then run:

```sh
shasum -a 256 -c SHA256SUMS
```

Each named file should report `OK`. Do not install if a checksum fails. Hashes establish byte consistency, not an Apple-verified publisher identity. Check the repository and release URL before downloading.

## First use

- New libraries keep future copies automatically after OS approval. Existing clipboard content is skipped.
- Option-Command-V opens Focus mode. Search, use arrow keys, press Return to copy, then paste with Command-V. No Accessibility permission is required for copying.
- Create a named snippet for reusable text. Sensitive hides body previews/search; it does not add authentication inside an open community library.
- Pause stops capture. Hide and pause clears the interface and stays paused until explicit reopening. Saved pause/disable choices persist.
- Website previews load only for the selected non-sensitive HTTPS link in the active Library. Sites/image hosts receive your IP and URL. Disable this in Settings → Privacy & Storage.

## Data and removal

Normal community updates keep the same bundle identity and encrypted library. Previous protected builds have separate data and are not automatically migrated. Keep the old protected app if you need that library.

There is no portable backup or recovery. Copying the database alone is not a usable backup without its Keychain key. Keep another copy of important snippets. Do not remove container data or Keychain entries when replacing the app.

Quit and remove the Applications app to stop using CopySaver. Removing the app is not a secure erase or guaranteed removal of saved data, backups or snapshots. Reset library is a separate destructive in-app action.

For problems see [troubleshooting](https://github.com/rafsuntaskin/copysaver/blob/main/docs/TROUBLESHOOTING.md). Widget discovery, clean-Mac upgrades, minimum-OS/Intel and full accessibility acceptance remain beta test areas.
