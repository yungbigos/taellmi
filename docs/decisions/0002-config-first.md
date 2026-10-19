# 0002 — Config first: models, prompts and settings live in the database

- **Status:** accepted (2026-10-19)
- **Context:** Models improve quickly. Swapping a model, a prompt or a tunable must not require a code change.
- **Decision:**
  - Every replaceable choice is a row in SQLite: provider, model, role assignment, prompt, pipeline step, setting.
  - Code contains only *engines*, the adapters per model family. Code never names a specific model.
  - Defaults are seeded from versioned JSON, and edits you make are never overwritten by a seed upgrade.
- **Consequences:**
  - A new model of a supported family is a new row.
  - A new kind of runtime is one new engine adapter, and it must pass the shared engine contract tests.
  - Full design: [config.md](../architecture/config.md).
