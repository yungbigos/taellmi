---
paths:
  - "**/Tests/**"
  - "**/TestSupport/**"
---
# Testing rules

- Use Swift Testing: `import Testing`, `@Suite`, `@Test("readable sentence")`, `#expect`, `#require`. Use XCTest only for UI tests.
- Prefer table-driven tests with `@Test(arguments:)` over copy-pasted cases.
- One behaviour per test. Name tests by behaviour: "user-edited rows survive a seed upgrade".
- **Databases:** create a fresh in-memory `DatabaseQueue` per test via `TestSupport.makeDatabase()`. It runs the real migrator. Never share state between tests.
- **ML:** unit tests use the fakes in `TestSupport` (`FakeTranscriber`, `FakeLanguageModel`, `FakeEmbedder`). Real models belong only in `*IntegrationTests` targets.
  - Gate integration tests with `.enabled(if: ModelFixtures.isInstalled(...))`.
  - Assert thresholds (word error rate, similarity), never exact strings.
- **Files:** use a temporary directory per test and clean it up.
- **Time and randomness:** inject a clock and seeds. No `sleep` in tests; use `Clock` injection or confirmations.
- **German test data:** use realistic German sentences with umlauts, ß, compounds and English words mixed in.
- Never delete, skip or loosen an existing test to get green. If a test is wrong, say so and explain why.
