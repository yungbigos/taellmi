---
name: add-engine
description: Add a new engine adapter to tällmi, for a model family or runtime the app cannot run yet. Use only when no existing engine fits a model.
---
# Add a new engine adapter

1. **Write an ADR** in `docs/decisions/` stating why existing engines can't run this model family.
2. **Create the target.** Add `Sources/Engines/<Name>Engine` and `Tests/<Name>EngineIntegrationTests` targets in `Package.swift`. The heavy SDK dependency goes **only** on these targets.
3. **Implement the Domain protocol** (`Transcriber`, `LanguageModel`, `Embedder` or `Reranker`) as an `actor`, constructed from a `ModelConfig`. Follow `.claude/rules/engines.md`: lazy load, idle unload, cancellation, no network.
4. **Register the engine key** in `AppComposition`'s engine registry. This is the only wiring point.
5. **Run the shared contract suite** (`TestSupport/EngineContracts`) against it, using a tiny real model in the integration target.
6. **Add at least one seed `model` row** that uses the engine, so it is exercised.
7. Run `scripts/check.sh` and the new integration tests.
