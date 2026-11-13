# Security policy

CopySaver's community beta is early-access software. No stable release or independent security review is claimed. The [threat model and acceptance checks](spec.md#7-security-model) distinguish implemented controls from remaining native verification. Keep another copy of important information; there is no portable backup/recovery service.

## Private reporting

Public distribution requires maintainers to enable and verify GitHub private vulnerability reporting. When available, use [Report a vulnerability](https://github.com/rafsuntaskin/copysaver/security/advisories/new) under Security → Advisories. This sends the report privately to repository maintainers. If that option is unavailable, request private reporting instructions from the maintainer; do not put exploit details into a public issue. No dedicated security email is invented.

Never attach actual clipboard content, saved libraries, Keychain files, keys, account details or authentication recordings. Use a minimal reproduction with synthetic data and include the app version/build, source revision, macOS/chip and community/protected profile. Do not test against another person's vault or production credentials.

## Scope and response

Reports on the latest community beta will be triaged on a best-effort basis. Earlier development previews and the protected compatibility profile are not separately maintained public release lines. There is no guaranteed response time, vulnerability reward or recovery service. Missing-key failures must preserve the existing library, not regenerate a key or encourage a reset.

The login Keychain and open user session are part of the community trust boundary. A compromised/unlocked account is outside its at-rest guarantee. Website previews contact external sites for the selected nonsensitive link and can be disabled in Privacy & Storage; they are not telemetry. Do not claim exclusive app access, secure deletion or forensic memory erasure.
