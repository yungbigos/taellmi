# 0004 — Entries are encrypted files; the database is their index

- **Status:** accepted (2026-10-19), revised the same day after a domain-modelling session

## Decision

The rule is **files hold what you put in or decided; the database holds what the app computes.** The test: delete the database, and the app must be able to rebuild everything from the Archive, at the cost of re-running models.

```
Archive/                              (encrypted by default)
├── entries/YYYY/MM/<entry-id>/
│   ├── entry.md          your Text + metadata (date, Source, title). Kept forever; only you change it after creation.
│   ├── recording.m4a     the audio. Deleted or moved after the Retention period.
│   └── transcript.json   verbatim model output with timings. Expires together with the recording.
├── curation.json         your Curation: Links, Concept merges/renames/hides, edited Atoms, focus weights
└── config.json           only your changes to config (models, settings, prompts, node and edge kinds)
```

- **In SQLite, all rebuildable:**
  - the index of Entries
  - Fragments, Atoms, Mentions, Concepts
  - derived edges and Clusters
  - vectors
  - the job queue
  - the effective config (Seeds + `config.json`)
- **Recomputation reads Curation and config** and never overrides them.
- **Export of Fragments and Atoms to plain files** is an explicit feature, not how they are stored.
- **Location is configurable.** The Archive lives in the app's Library folder by default, or in any folder you choose, including mounted network or cloud volumes. The app itself never uses the network.
- **Encryption** (after Phase 0):
  - Every file is encrypted with a key in the Keychain, unlocked by Touch ID or your Mac password.
  - A Recovery Key is shown once at setup.
  - All file access goes through one storage layer, so this changes one place.
- **Deleting** moves an Entry to the app's Trash. A later cleanup moves it to the macOS Trash.

## Why

- Files keep the archive yours: easy to back up, and independent of this app's database.
- Encryption by default reflects how intimate the content is.
- Recordings and Transcripts grow without limit and carry little value once the Text exists, so they expire.
- Curation and config are the only things a model cannot recreate, so they live with the Entries and travel with backups.
