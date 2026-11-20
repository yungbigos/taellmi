# 0016 — Signed with Developer ID and notarized

- **Status:** accepted (2026-11-20). Answers open question 6 in [plan.md](../plan.md) (distribution).

## Context

Until now a release was signed ad hoc. macOS stopped it the first time, and you had to choose **Open Anyway** in System Settings. Local builds signed with a free personal team, which works but shows no developer.

The owner now has a paid Apple Developer Program membership, team **FormuFix GmbH** (`284CCFBH2H`). The company becomes fixOS GmbH on 1 January 2027; once Apple shows the new name, the Developer ID certificate is renewed so releases show it too.

## Decision

- **Releases are signed with Developer ID and notarized by Apple**, then the ticket is stapled to the disk image. A downloaded tällmi opens with no warning, also offline.
- **Distribution stays a disk image on GitHub releases.** No Mac App Store for now.
- **The release builds unsigned, then signs.** The build runs third-party package code, so the signing key enters a temporary keychain only after the build, and the notarization key only in the notarize step. Both come from GitHub secrets; the release fails if they are missing rather than ship an unsigned app.
- **What gets signed:** the app with the hardened runtime, a secure timestamp and `App/taellmi.entitlements`; then the disk image. The verify step still refuses an app with the network-client entitlement or without the sandbox (AGENTS.md rule 1), and now also one not signed by the team with the hardened runtime.
- **Notarizing uploads the disk image to Apple from the GitHub runner.** The app itself still never goes online.
- **Local builds** sign with the owner's Apple Development certificate for the team, set in the git-ignored `Config/Signing.local.xcconfig`. Anyone else builds ad hoc, as before.

## GitHub secrets the release needs

| secret | what it is |
|---|---|
| `DEVELOPER_ID_CERT_P12` | the "Developer ID Application" certificate and its private key, exported as .p12, base64 |
| `DEVELOPER_ID_CERT_PASSWORD` | the password the .p12 was exported with |
| `NOTARY_KEY` | an App Store Connect team API key (.p8 contents), role Developer |
| `NOTARY_KEY_ID` | that key's Key ID |
| `NOTARY_ISSUER_ID` | the Issuer ID shown above the team keys |

## Consequences

- The release notes no longer explain "Open Anyway".
- A release takes a few minutes longer while Apple notarizes.
- The certificate expires on 20 December 2027, the API key when revoked; either makes the release fail loudly until it is replaced. The certificate and its key are in the owner's login keychain; the .p12 password is the Keychain item "taellmi Developer ID p12 password".
