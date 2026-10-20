# Architecture overview

## Code layout

```
<repo>/
├── project.yml                 XcodeGen spec for the thin app shell (the .xcodeproj is generated and gitignored)
├── App/                        @main, Info.plist, entitlements, assets — nothing else
├── Packages/TaellmiKit/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── Domain/             value types + protocols (Transcriber, LanguageModel, Embedder, Reranker,
│   │   │                       ConfigStore, EntryStore, JobQueue). No dependencies at all.
│   │   ├── CSQLiteVec/         vendored sqlite-vec (C), compiled into the app (ADR 0011)
│   │   ├── Persistence/        GRDB: schema, migrations, FTS5, sqlite-vec, graph nodes/edges, entry files on disk
│   │   ├── Config/             config tables, seed JSON (Resources/Seeds), validation, model resolution
│   │   ├── Pipeline/           durable job queue + steps (transcribe, enrich, chunk, embed), against Domain only
│   │   ├── Search/             hybrid keyword + vector search, RRF, reranking
│   │   ├── Audio/              AVAudioEngine capture, file writing, level metering
│   │   ├── Engines/            one target per engine; the only targets that import heavy ML SDKs
│   │   │   ├── FluidAudioEngine/        Parakeet etc. (Core ML, Neural Engine)
│   │   │   ├── SpeechAnalyzerEngine/    Apple live transcription
│   │   │   ├── FoundationModelsEngine/  Apple on-device LLM
│   │   │   ├── MLXEngine/               MLX LLMs + embedders
│   │   │   └── OpenAICompatibleEngine/  optional localhost server (Ollama / LM Studio)
│   │   ├── Features/           SwiftUI views + @Observable view models (MainActor by default)
│   │   ├── AppComposition/     composition root: the only place that wires engines to protocols
│   │   └── TestSupport/        fakes, in-memory DB factory, fixtures
│   └── Tests/
│       ├── <Module>Tests/                fast unit tests, no ML SDKs, run on every change
│       └── <Engine>IntegrationTests/     real models on short audio fixtures, run on demand
├── scripts/check.sh            the single quality gate (format lint → build → fast tests)
├── docs/                       plan, architecture, decisions (ADRs), research
└── .claude/                    agent rules, skills, subagents, hooks
```

## Dependency direction

```
Features ─┐
Pipeline ─┼──► Domain ◄── Persistence ◄── Config
Search ───┘       ▲
Engines/* ────────┘
AppComposition ──► everything (wires concrete engines into protocols)
```

- Arrows point **inward to Domain**. Domain imports nothing.
- Features, Pipeline and Search never import an engine. They ask the config layer for "the model for role X" and receive a protocol.
- Heavy SDKs (MLX, FluidAudio) compile only into their engine target and its integration tests. Fast unit tests never build them, which keeps the test loop at seconds.

## Concurrency

- Swift 6 language mode, complete concurrency checking, warnings are errors.
- `Features` and the app shell use **default MainActor isolation**. The other modules don't.
- Every engine is an `actor` that owns its model, loads it lazily and unloads it after the configured idle time.
- The pipeline is an `actor` draining a `job` table, so work survives quit and crash.
- UI state lives in `@Observable` view models. Dependencies are passed in through `init` from the composition root. No TCA.

## Where things are stored

- **Config** lives in the SQLite database: models, providers, role assignments, prompts, pipeline steps and settings. See [config.md](config.md).
- **Entries** (audio + text) are folders on disk. The database indexes them. See [ADR 0004](../decisions/0004-entries-as-files.md).
- **Derived data** lives in the database and always records the model and prompt version that produced it.
