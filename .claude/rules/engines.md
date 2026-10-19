---
paths:
  - "**/Sources/Engines/**"
  - "**/*IntegrationTests/**"
---
# Engine adapter rules

An engine runs one *family* of models (Parakeet via FluidAudio, MLX LLMs, Apple Foundation Models, …). It never targets one specific model.

- Each engine is an `actor` conforming to a `Domain` protocol (`Transcriber`, `LanguageModel`, `Embedder`, `Reranker`).
- It is constructed from a `ModelConfig` row. Everything model-specific (repo, files, parameters) comes from that row.
- **Load lazily on first use.** Unload after `models.idle_unload_s`, and immediately on memory pressure.
- Report progress and cancellation through `AsyncThrowingStream` / `Task` cancellation.
- **No network.** Engines read model files from the local models folder only. Downloading is the downloader's job, not the engine's.
- **Testing:**
  - The shared contract suite (`TestSupport/EngineContracts`) is created together with the second engine, and from then on every engine must pass it. Until then, the Parakeet adapter is covered by `FluidAudioEngineTests` and its integration suite.
  - Every engine has an `*IntegrationTests` target with a tiny real fixture.
- **Imports:** only `Engines/*` and their integration tests may import MLX, FluidAudio, FoundationModels or Speech.
