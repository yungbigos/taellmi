# 0011 — The meaning index: passages as graph nodes, vectors in vendored sqlite-vec, refreshed by a sweep

- **Status:** accepted (2026-10-20). Builds on ADR 0004 (database rebuildable), ADR 0005 (typed graph), ADR 0002 (config first).
- **Issues:** #2 (search by meaning), groundwork for #4 (extraction).

## Decision

### The graph schema
- **Kinds are config.** Migration `v3_graph` adds `node_kind`, `edge_kind`, `node` and `edge`. The kinds are seeded from `node_kinds.json` and `edge_kinds.json`.
- **System kinds are protected by triggers.** These are the ones the code names in `GraphKinds`:
  - nodes: entry, fragment, atom, concept, cluster
  - edges: contains, mentions, co_occurs, similar, member_of, link

  They cannot be deleted or lose their system flag. Renaming or restyling them is allowed.
- **Concept kinds are node kinds with `parent_id = concept`** (person, place, topic, emotion). A new kind of Concept is a new seed row.
- **Every derived row records how it was made:** `method`, plus `model_id` and `prompt_ref` when a model made it. Nodes extracted from an Entry carry `entry_id` and are deleted with it.

### Passages (Fragments)
- **The first splitter is model-free.** Blank lines always separate passages. Long paragraphs are grouped into whole sentences of about `fragment.target_chars`, never more than `fragment.max_chars`.
- **Positions are UTF-16 offsets** into the Text, the unit text views use, so a passage can be highlighted exactly.
- **Ids are content-derived:** a hash of the Entry id, the words and the occurrence. Editing one paragraph keeps the other passages' ids, and so their vectors. Only the changed passage is embedded again.
- **The Entry node stores the Text it was split from and the splitting method** (name, version, settings). An Entry is stale when either differs, which is one SQL comparison.

### Vectors
- **sqlite-vec v0.1.9 is vendored** as the C target `CSQLiteVec`, compiled against the macOS system SQLite that GRDB already uses. `AppDatabase.configuration()` registers it on every connection. Nothing is loaded at runtime, so the sandbox doesn't matter.
  - Measured on this Mac: nearest 30 of 100,000 vectors of size 512 in about 55 ms.
- **One table per vector size** (`vec_d<size>`), partitioned by **vector space** (model id plus configured size, `ModelConfig.vectorSpace`), with cosine distance. Changing a model's `params.dimensions` makes a new space, so everything is embedded again.
- **`vector_meta` (node, space, size) is an indexed side table.** It records which node has a vector in which space, so "what is missing" and "what is orphaned" are indexed queries, never scans of the vectors.
  - The tables are created on demand, because the size is part of the table definition and depends on the configured model. They are a rebuildable cache outside the migrated schema.
  - A node keeps one vector per size: re-embedding with another model of the same size replaces it.
- **The embedding model is an Assignment** for the `embed` role. Its size and query phrasing (`params.dimensions`, `params.query_template`) are on the model row.

### Keeping it current: one sweep, not hooks everywhere
Before working the queue, the pipeline:
- finds Entries whose stored Text or method doesn't match,
- finds passages without a vector in the active vector space,
- and requeues the `fragment` and `embed` steps for them.

After the queue is drained, it prunes vectors whose node is gone. Doing it afterwards means a thought removed and put back (e.g. Trash and restore) gets its passages back under the same ids and keeps its vectors.

The same rule covers typed thoughts, edits, Entries from before this layer existed, a deleted database, a changed setting and a swapped model. - **Requeueing touches only finished jobs,** so a step that keeps failing is not retried forever.
- **A failed earlier step doesn't block later ones.** Text you type into a recording that could not be transcribed is still split and embedded.
- **"Another model is busy" is waiting, not failing:** the job retries later without using up an attempt.

### Search
- **`HybridSearch` merges two rankings with Reciprocal Rank Fusion** (`search.rrf_k`):
  - Entries containing every search word, ordered by FTS5 bm25
  - Entries with a passage within `search.min_similarity` of the query, among the nearest `search.vector_candidates`
- **Empty search stays newest first.**
- **Search never waits for a model.** If the embedding model isn't installed, or another heavy model is busy, search answers from words alone.

### The embedding engine comes separately
- **The embedding model is configured but has no engine yet.** The seeded model is Qwen3-Embedding-0.6B 8-bit (MLX) at 512 dimensions, with pinned file hashes. Until its engine (`mlx_embedder`) exists, the `embed` step waits without using up attempts, and search uses words.
- **MLX needs Metal shaders that only Xcode builds**, so the engine comes in its own change. Building them needs the Metal Toolchain component of Xcode 26, which is not part of the default install.

## Why

- **Keeping vectors inside the one SQLite file** means one thing to back up, rebuild and delete, as ADR 0004 wants. Vendoring sqlite-vec avoids runtime extension loading, which macOS's SQLite and the sandbox make awkward. sqlite-vec's speed is enough at personal scale.
- **Content-derived passage ids plus the sweep** make the meaning layer an exact function of the Archive and config. A rebuild needs no special code path.
- **A model-free splitter first** gives search by meaning now. Splitting by topic (embeddings + LLM, #4) can replace it behind the same fingerprint, and changing the method re-splits everything automatically.

## Consequences

- An Entry edited in Explore triggers the pipeline right away. Anything else is caught by the next sweep, at the latest after `app.maintenance_interval_s`.
- Vectors from a model of a different size stay in their own table until pruned. A model swap re-embeds every passage in the background.
- **If sqlite-vec ever gets too slow** (well beyond 100k passages), USearch can replace `VectorStore` behind the same interface.
