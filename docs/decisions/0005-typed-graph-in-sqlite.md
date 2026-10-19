# 0005 — A generic, configurable graph inside SQLite

- **Status:** accepted (2026-10-19)

## Decision

- **Everything is a typed graph.** Everything in the Archive's meaning layer (Entries, Fragments, the smallest units, Concepts, …) is a **node** with a kind. Every relationship is an **edge** with a kind.
- **Kinds are config.** Node kinds and edge kinds, including which kinds an edge may connect, are rows in config tables. A new level of structure, or a "Concept that groups Concepts", is a config change, not a code change.
- **System kinds are protected.** The pipeline depends on a small set of system kinds (entry, fragment, concept, …). They can be renamed and restyled but not deleted.
- **Derived versus hand-made edges:**
  - Derived edges (co-occurrence, similarity, clusters) are recomputable. Each records the evidence it came from and the Model that made it.
  - Edges you create by hand are permanent.
- **It all lives in the existing SQLite file**, as node and edge tables, with traversal in SQL and clustering and ranking computed in memory in Swift.

## Why not a graph database

At personal scale (about 100k Fragments and tens of thousands of Concepts), the whole graph fits in memory and clustering takes well under a second. The leading embedded graph database, Kùzu, was archived in October 2025, and its active fork's Swift binding lags behind. A second store would have to be kept in sync, backed up and migrated.

If ad-hoc graph queries are ever wanted, a graph database (for example LadybugDB) can be added as a **rebuildable copy**, never as the source of truth.
