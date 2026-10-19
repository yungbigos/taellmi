---
paths:
  - "**/Sources/Config/**"
  - "**/Seeds/**"
---
# Config layer rules

See `docs/architecture/config.md` for the design.

- **Seed JSON changes:**
  - Bump `seed_version` on any changed row.
  - New rows get new ids. Never reuse an id.
- **Seeding must never overwrite rows where `origin = 'user'`.** A test covers this; keep it green.
- **Every role used by an enabled pipeline step** must have at least one assignment in the seeds. `SeedBundleTests` enforces this through `SeedBundle.validate()`.
- **Every setting the code reads** (`SettingKeys.all`) must have a seed. Code never carries a fallback default for a tunable.
- **Validation runs before a row takes effect.**
  - An invalid row logs a warning and falls back to the next assignment.
  - It never crashes and never silently does nothing.
- **Prompts are versioned.** Edit by adding a new version, never by mutating text in place. Derived data references `prompt_id@version`.
- **Model file entries** carry a `sha256`. A model without hashes cannot be marked installed.
