# 0008 — Phone and Mac share the Archive through a synced folder, encrypted, with three-way merge

- **Status:** accepted (2026-10-20). Builds on ADR 0004 (files canonical, encrypted) and ADR 0007 (network rules).

## Context

The owner is mostly on the phone, and dream capture happens right after waking. The iPhone therefore has to be a first-class source, without giving up local-first and privacy-first.

## Decision

- **The iPhone records and transcribes on the device.** An Entry is complete there, even without the Mac.
- **Everything is encrypted on the device before it can leave it,** with the same Archive key as the Mac. Folder and file names are random ids, and dates live inside the encrypted content, so nothing readable leaks.
- **Sync channels**, which are all "a folder that reaches the other device":
  - **Default: an iCloud Drive folder.** macOS and iOS move the files; tällmi itself makes no network calls. Apple only sees encrypted blobs.
  - **Option: local network only.** iPhone and Mac sync directly on the same Wi-Fi, with no cloud at all. This needs an amendment for LAN connections (ADR 0007).
  - **Any other folder you choose** (Syncthing, NAS, …) works without extra code.
- **The key reaches the phone once,** by scanning a QR code shown on the Mac. It is never stored in a cloud. The Recovery Key still applies.
- **Each device keeps its own local index,** rebuilt from the synced Archive. The database is never synced.
- **iPhone v1 is capture-first:** record, live text, type, recent Entries, Action Button and lock screen control. Later the phone can hold the whole Archive.
- **Concurrent edits use a three-way merge.**
  - Each device remembers the version of a Text it last synced (the base).
  - Non-overlapping edits from both sides merge automatically, as in git.
  - Overlapping edits show a diff and you choose; nothing is ever silently lost.
  - New Entries never conflict, because each is its own folder with a unique id.
- **Developer programme:** not now. Installing on your own phone with a free account means the build has to be reinstalled every 7 days. Revisit when the iPhone app is in daily use.

## Why

Files with unique ids make sync nearly conflict-free, and an OS-synced folder keeps the app free of network code. Encrypting before anything leaves the device makes the channel's trustworthiness irrelevant to privacy.
