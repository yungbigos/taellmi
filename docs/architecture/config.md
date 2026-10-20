# Config-first: models, providers, prompts, settings

**Rule:** if a value could reasonably change without the app's logic changing, it lives in the database, not in Swift code. That covers which model does a job, where its weights come from, what a prompt says, and how big a chunk is. Code holds only the *mechanisms*: how to run a given engine, how to chunk, how to search.

## What is config, what is code

| In the database (change at runtime, no rebuild) | In code (change needs a commit + tests) |
|---|---|
| Which model is assigned to which job, with fallbacks | **Engines**: the adapters that know how to run a model family (FluidAudio/Parakeet, WhisperKit, MLX LLM, MLX embedder, Apple Foundation Models, Apple SpeechTranscriber, OpenAI-compatible localhost server) |
| Model entries: repo, revision, files, SHA-256, parameters | Pipeline step *implementations* (transcribe, chunk, embed, …) |
| Providers (where weights come from) | Database schema and migrations |
| Prompt templates and output schemas | Search algorithm (hybrid + RRF) |
| Pipeline settings: which steps run, in what order, under which conditions | UI |
| Tunables: chunk size, overlap, RRF k, idle-unload seconds, hotkey, … | Default values (seed files, see below) |

**What "plug and play" means in practice.** A new model of a family we already support needs only a new row: a newer Parakeet, a new Whisper fine-tune, any MLX-format LLM or embedder (Qwen 4, Gemma 5, …), or any model served by a local Ollama/LM Studio. No code change. A completely new *kind* of runtime needs one new engine adapter (one file plus its tests), registered under an `engine` key. After that, every model of that kind is config too.

## Tables

```
provider          id, kind, name, base_url, enabled
                  kind ∈ huggingface | local_folder | apple_system | openai_compatible_local
                  (huggingface is the only kind that ever touches the network, and only during a user-started download)

model             id, name, engine, provider_id, source_ref, revision,
                  files_json [{path, sha256, bytes}], params_json,
                  capabilities_json  (e.g. ["transcribe","word_timestamps","languages:de,en"]),
                  est_memory_mb, license, enabled, origin (seed|user), seed_version

assignment        role, priority, model_id, conditions_json
                  role ∈ live_transcription | transcription | title | tags | summary | entities | mood
                         | cleanup | ask | embed | rerank
                  lowest priority whose model is installed and whose conditions hold wins
                  (e.g. {"power":"ac_only"} or {"max_duration_s": 1800})

prompt            id, role, language, version, template, output_schema_json, origin, seed_version
                  (templates use named placeholders: {{transcript}}, {{chunks}}, {{question}}, {{today}})

pipeline_step     id, step, ordinal, enabled, role, conditions_json

setting           key, value_json, type, origin, seed_version
                  e.g. fragment.target_chars=600, fragment.max_chars=1200, search.rrf_k=60,
                       search.min_similarity=0.45, models.idle_unload_s=60, capture.hotkey="⌥⌘Space"
                  (a model's vector size and query phrasing are model params: params.dimensions,
                   params.query_template)
                  brand.tokens (type json) holds the whole design-token document from Seeds/brand.json

node_kind         id, name, parent_id, system, style_json, enabled, origin, seed_version
edge_kind         id, name, system, derived, directed, from_kinds_json, to_kinds_json, style_json, enabled,
                  origin, seed_version
                  (the graph's kinds, ADR 0005/0011; system kinds cannot be deleted)
```

Each embedding vector stores the `model_id` and `dimensions` that produced it. Changing the `embed` assignment therefore queues a background re-embed automatically, and search only compares vectors from the active model.

Derived data stores the model that produced it. A title, a summary or a cleaned transcript records its `model_id` + `prompt_id@version`, so "regenerate everything made by model X" is a query.

## Defaults: seeded from versioned JSON

- The repo holds `Resources/Seeds/*.json` (providers, models, assignments, prompts, settings), reviewed like code.
- On launch, a migrator compares each row's `seed_version` and only **adds or updates rows with `origin = seed`**. Rows you edited become `origin = user` and are never overwritten.
- A "reset to default" action per row or table.
- **Your changes (`origin = user`) are also written to `config.json` in the Archive** ([ADR 0004](../decisions/0004-entries-as-files.md)). On a fresh database the effective config is the Seeds plus `config.json`, so a new Mac plus your Archive gives you back exactly your setup.
- This also covers settings that steer recomputation, such as focus weights. Weights on specific Concepts or Atoms are Curation and live in `curation.json`.

## Loading and validation

- One `ConfigStore` (actor) reads the tables through GRDB `ValueObservation`. A change in the database reaches the running app immediately: there is no restart, and the next job uses the new model.
- On every change, rows are validated before they take effect:
  - the engine key exists,
  - the model's capabilities cover the role,
  - files are present and match their hashes,
  - the prompt output schema parses.
- An invalid row is skipped with a visible warning, and the next assignment in priority order is used. A bad config never crashes the app or silently does nothing.
- Code never names a model. It asks `models.resolve(role: .transcription)` and gets an engine instance back.

## Tests that guard this

- **Seed files.** They decode, validate, and every role has at least one valid assignment.
- **Resolution.** Given a set of rows, the expected model wins, including fallback and conditions (table-driven, parameterized tests).
- **Migrator.** Seeding twice is a no-op, user-edited rows survive a seed upgrade, and a new seed version updates seed rows.
- **Change propagation.** Changing an assignment in an in-memory database changes what the pipeline resolves, without a restart.
- **Engine contracts.** Every engine adapter passes the same shared contract test suite, using a fake model for unit tests and a real tiny model in a separately tagged integration suite.
