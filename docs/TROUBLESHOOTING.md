# Troubleshooting the community beta

## macOS blocks opening

Confirm that you downloaded from the project's GitHub release and verified the checksum. This app has no Apple Developer ID certificate or notarization. Use the supported [Privacy & Security approval flow](https://support.apple.com/en-us/102445) if you trust it. Managed devices can forbid this. Do not disable Gatekeeper, remove quarantine, or install trust certificates.

## Clipboard history stays empty

Open the library and check the capture status. Resume capture or enable Keep clipboard history if paused/off. On permission-controlled macOS versions allow CopySaver under Privacy & Security → Paste from Other Apps. Then copy new synthetic text such as `CopySaver test text`. The existing clipboard is skipped on startup/resume. Concealed/generated content, excluded apps, likely secrets and oversized or non-text copies can be skipped deliberately.

## Keychain access fails after an update

Quit all old copies and open the Applications copy. Approve the system's request only if expected. The community app uses your login Keychain; it may need to be available/unlocked. Use Try again after resolving the OS condition. Do not reset the library, delete its Keychain item or replace database files. Missing keys cannot be reconstructed by CopySaver.

## Duplicate copies appear

Keep the same `/Applications/CopySaver.app` when upgrading. Eject old DMGs and remove obsolete Dock pins. Development builds can have separate identities. Do not delete saved-library or Keychain locations to remove a duplicate app icon.

## A website has no preview

Check that previews are enabled in Privacy & Storage and that you selected a non-sensitive HTTPS link in the active Library. Local/IP/nonstandard-port addresses are not fetched. Sites can omit metadata or block requests; images can exceed the size/type limits. Retry preview after connectivity returns. Copy and Open in browser still use the original saved URL.

## Focus mode or the widget is unavailable

CopySaver must be running for the global shortcut. Rebind it in General if another app owns the key combination; menu bar actions remain available. Widget gallery discovery in ad-hoc builds is experimental and unverified. Report the OS version and reproducible synthetic scenario rather than granting unrelated Accessibility/Full Disk Access permissions.

## Report a bug

Include CopySaver version/build, macOS version, chip type, installation method and synthetic reproduction steps. Never include real clipboard content, saved libraries, tokens, Keychain files or unredacted screenshots. Security issues should follow [the security policy](../SECURITY.md), not a public bug report.
