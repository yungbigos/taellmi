---
name: add-model
description: Add or swap a model (transcription, LLM, embedding, reranker) in tällmi via config, without code changes. Use when the owner wants to try a new or better model.
---
# Add or swap a model (config only)

1. **Identify the engine** that can run it: `fluidaudio`, `whisperkit`, `mlx_llm`, `mlx_embedder`, `apple_foundation`, `apple_speech`, `openai_compatible_local`. If no engine fits, stop and use the `add-engine` skill.
2. **Gather the facts** from the model card:
   - source repo and **pinned revision**
   - the files and their SHA-256 hashes
   - license
   - estimated memory
   - languages
   - capabilities
3. **Add a `model` row** to the seed JSON, with `origin: "seed"` and a new `seed_version`. Add an `assignment` for the role(s), with a priority. Keep the previous model as a fallback unless the owner says otherwise.
4. **Embedding models:** changing the `embed` assignment triggers a re-embed of the archive. Tell the owner how long that takes for their entry count.
5. **Run `scripts/check.sh`.** Seed validation tests must pass.
6. If the model is downloaded, run its engine's integration tests with `scripts/test-integration.sh <Engine>`.
7. **Tell the owner** which model now does which job, the expected memory use, and how to switch back.
