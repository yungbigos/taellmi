# 0010 — How the Archive is encrypted

- **Status:** accepted (2026-10-20). Details ADR 0004 (encrypted by default) and ADR 0008 (sync).

## Threat model

- **Encryption protects the Archive wherever its files go:** a sync folder (iCloud Drive), a backup, a copied folder, another person's disk.
- **On your own logged-in Mac, the protection comes from macOS:** FileVault, plus app-container protection, which keeps other apps out of tällmi's data.
- **Therefore:**
  - Archive files are encrypted.
  - The local index database (in the app container, never synced) is not. It is rebuildable from the Archive.

## Decision

- **One random 256-bit Archive key.**
  - Every file in the Archive (entry.md, recording, transcript, curation.json) is sealed with AES-GCM.
  - File format: a small header (`TLM1`), then the sealed box.
- **Random ids for Entry folders:** `entries/<random id>/`. Dates live only inside the encrypted content, so a synced Archive reveals nothing readable.
- **The key lives in the Keychain** on this Mac.
  - It is available after login (this device only), so capture and tälli never ask.
  - **Optional setting "lock tällmi with Touch ID":** asks when the window opens. Capture keeps working without asking.
- **Recovery Key:** 30 characters in six groups, with the last group a checksum.
  - Shown once at setup; you confirm it by typing the last group.
  - It encrypts a copy of the Archive key stored in the Archive as `archive.key`, so a new Mac plus the Archive plus the Recovery Key restores everything.
  - It can optionally be saved in the Keychain.
- **Recordings are encrypted too.** Transcription and playback decrypt into the app's protected scratch area only, never into the Archive, and that area is cleared on start.
- **Existing plain Archives migrate automatically** on first start: encrypt, rename to random ids, verify, then remove the plain original. It is crash-safe and runs in the background.
- **Folder choice (Settings → privacy):**
  - Library by default, or any folder you choose, kept as a security-scoped bookmark.
  - Switching moves and verifies the Archive.
  - If the folder is missing (e.g. a NAS offline), recordings wait in the scratch area and are filed when it returns.
- **"Export as plain files"** writes readable Markdown and audio into a folder you choose, on request only.

## Why

Per-file encryption keeps the Archive sync-friendly (each file stands alone, no container to corrupt). The key after login keeps capture instant. The Recovery Key in the Archive makes a new device or a lost Keychain recoverable without any server.
