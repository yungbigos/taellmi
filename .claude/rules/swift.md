---
paths:
  - "**/*.swift"
---
# Swift code rules

- Swift 6 language mode, complete concurrency checking, warnings are errors. Never silence the compiler with `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` without a comment explaining why it is safe.
- Prefer value types (`struct`, `enum`). Use `actor` for anything that owns mutable state shared across tasks (engines, pipeline, config store).
- No force unwraps (`!`) or `try!` outside tests. Throw typed, descriptive errors.
- No `print`. Use `Logger` from `os` with subsystem `app.taellmi` and a category per module. Never log transcript text or personal content at a level above `.debug`.
- No singletons or global mutable state. Dependencies arrive through `init`.
- No hard-coded model names, paths, prompts or tunable numbers. They come from the config layer.
- Keep files small and named after their main type. Public API in each module is minimal: `internal` by default.
- Document *why*, not *what*. Doc comments only on public API.
