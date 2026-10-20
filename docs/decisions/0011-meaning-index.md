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
- **Thoughts containing every search word come first.** They are ordered by Reciprocal Rank Fusion (`search.rrf_k`) of keyword relevance (FTS5 bm25) and meaning.
- **Thoughts found only by meaning follow, as *related*.** Meaning finds passages within `search.min_similarity`, among the nearest `search.vector_candidates`. `HybridSearch.hits` marks each result `.words` or `.related`.
- **Why "related":** measured on 1,000 synthetic journal thoughts and two public controls ([research](../research/2026-10-search-eval.md)), the embedding model ranks very well (MRR 97%). But its similarity scores for searches with and without an answer overlap, so no cut-off can say "nothing relevant". Meaning alone therefore never makes a thought an answer, and "nothing found" refers to words.
- **Empty search stays newest first.**
- **Search never waits for a model.** If the embedding model isn't installed, or another heavy model is busy, search answers instantly with words alone.
- **A relative cut-off exists but is off** (`search.relative_similarity_window` = 0); measuring showed it hurts.

### The embedding engine
- **`MLXEmbedder` (engine key `mlx_embedder`) runs MLX embedding models from their local folder.** It uses mlx-swift-lm 3.32.3 for the model and swift-transformers 1.3.5 for the tokenizer, both pinned exactly. It never downloads.
- **Everything model-specific is a param:** size (`dimensions`, cut before normalising), `pooling` (last, mean, cls, first) and the `query_template` for searches.
- **The seeded model is Qwen3-Embedding-0.6B 8-bit** at 512 dimensions, with last-token pooling.
- **Padding is masked by length, not by token id.** Qwen's pad token is the very end token that last-token pooling reads.
- **The Metal shaders come from the Xcode build.** MLX needs them, and only Xcode compiles them (it needs Xcode's Metal Toolchain, installed once with `xcodebuild -downloadComponent MetalToolchain`).
  - The app bundles them automatically.
  - `scripts/test-integration.sh` builds the app and points the real-model tests at them.
  - The fast gate never runs MLX.
- **MLX's memory is capped from the model's params:** `cache_limit_mb` (256) and `memory_limit_mb` (2048). Without the caps, the GPU buffer cache grows without bound over a long run (26 GB observed). With them, it stays at about 2 GB.
- **Every embedding engine keeps `EmbedderContract`**, checked for the fake in the fast tests and for the real model in the integration tests.

## Why

- **Keeping vectors inside the one SQLite file** means one thing to back up, rebuild and delete, as ADR 0004 wants. Vendoring sqlite-vec avoids runtime extension loading, which macOS's SQLite and the sandbox make awkward. sqlite-vec's speed is enough at personal scale.
- **Content-derived passage ids plus the sweep** make the meaning layer an exact function of the Archive and config. A rebuild needs no special code path.
- **A model-free splitter first** gives search by meaning now. Splitting by topic (embeddings + LLM, #4) can replace it behind the same fingerprint, and changing the method re-splits everything automatically.

## Consequences

- An Entry edited in Explore triggers the pipeline right away. Anything else is caught by the next sweep, at the latest after `app.maintenance_interval_s`.
- Vectors from a model of a different size stay in their own table until pruned. A model swap re-embeds every passage in the background.
- **If sqlite-vec ever gets too slow** (well beyond 100k passages), USearch can replace `VectorStore` behind the same interface.
