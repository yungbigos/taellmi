---
paths:
  - "**/Sources/Persistence/**"
---
# Persistence rules (GRDB / SQLite)

- **Migrations are append-only and named** (`v1_initial`, `v2_add_links`, …). Never edit a migration once it is committed. Write a new one.
- Every migration gets a test that migrates an in-memory database from empty to latest and checks the schema.
- **Entries are canonical on disk** (`entries/YYYY/MM/<id>/audio.m4a` + `entry.md`). The database must be rebuildable from those folders, and `ReindexTests` must keep passing.
- **Writes:**
  - Use `dbQueue.write`/`dbPool.write` with one transaction per logical operation.
  - Never do slow work (ML, file I/O over a few KB) inside a database transaction.
- **Search tables:**
  - FTS5 tables: one `unicode61 remove_diacritics 2` table and one `trigram` table.
  - Vectors live in sqlite-vec tables keyed by chunk id and carry `model_id` + `dimensions`.
- **Live updates:** use `ValueObservation` for anything the UI or config needs to react to.
