# tällmi — agent guide

tällmi is a local-only, privacy-first macOS voice journal. You talk into it in German, with English mixed in. It transcribes on the device, keeps every entry as plain files, indexes them for keyword and vector search, and answers questions about the archive with local models.

## Read first

- [docs/plan.md](docs/plan.md): product, phases, data model
- [docs/architecture/overview.md](docs/architecture/overview.md): modules, dependency direction, concurrency
- [docs/architecture/config.md](docs/architecture/config.md): how models, prompts and settings live in the database
- [docs/brand.md](docs/brand.md): names, UI words, voice, logo, colour, type, motion. Read before writing any UI text or visual.
- [docs/decisions/](docs/decisions/): ADRs. Add one for every decision that changes architecture, stack or principles.

## The owner does not write Swift

- Explain every change in terms of what the user sees or what changed in behaviour. Don't explain Swift.
- Never hand the owner manual Xcode steps when a command or file edit can do it.
- "Done" means `scripts/check.sh` passes, and the app was run when behaviour changed. Reading the code is not verification.

## Non-negotiables

1. **No outgoing network.** The app has no network-client entitlement. The only exception is the opt-in local MCP server, which accepts connections on 127.0.0.1 ([ADR 0007](docs/decisions/0007-local-mcp-server.md)). Never add analytics, crash reporting or any SDK that phones home. Model downloads happen only in a user-started download step and are checked against SHA-256 hashes.
2. **Config first.** Never hard-code a model name, model path, prompt text or tunable number in Swift. Add or change a row in the seed JSON (`Packages/TaellmiKit/Sources/Config/Resources/Seeds/`) and read it through the config layer. Code knows engines, never specific models.
3. **Test first.** Every behaviour change starts with a failing test (Swift Testing). Bugs get a reproducing test before the fix. Never delete or weaken a test to make the build green; fix the code or ask.
4. **The user's Text is sacred.** Only the user changes an Entry's Text after it is first written. Transcripts and Recordings are disposable under the Retention policy ([ADR 0004](docs/decisions/0004-entries-as-files.md)). Derived data records the `model_id` and `prompt_id@version` that produced it.
5. **Light on resources.** One heavy model is loaded at a time, unloaded after the configured idle time. Background work runs at `.utility` or lower.
6. **No slop** ([ADR 0006](docs/decisions/0006-no-slop.md)). AI extracts and computes; it never offers insights, interpretations or advice unasked. Generated labels are marked, editable, and linked to their source.
7. **Dependencies point inward.** `Domain` imports nothing. Only `Engines/*` import ML SDKs. Only `AppComposition` wires engines into protocols.

## Commands

```bash
scripts/check.sh               # the gate: format lint → build → fast tests (run before saying "done")
scripts/check.sh --fix         # same, but auto-format first
scripts/test-integration.sh    # real models on audio fixtures (slow, needs downloaded models)
scripts/run-app.sh             # build, install to ~/Applications/taellmi.app, launch (--build: build only)
scripts/download-model.sh <id> # the one user-started network step: fetch a seed model, verify SHA-256
```

- Where the running app keeps its data: `~/Library/Containers/app.taellmi/Data/Library/Application Support/taellmi/` (`Archive/`, `taellmi.sqlite`, `models/`, `Scratch/`).
- Inspect config or the index with `sqlite3` on `taellmi.sqlite`.

## Tooling facts

- Xcode 26.6, Swift 6.3, macOS 26 target, Apple Silicon only.
- Most code lives in the local package `Packages/TaellmiKit`. The app target in `App/` is a thin shell.
- The Xcode project is **generated** from `project.yml` with XcodeGen. Never edit `.pbxproj`; a hook blocks it.
- Formatter: `swift format`, configured in `.swift-format`.
- Tests: Swift Testing (`@Test`, `#expect`, `#require`, parameterized `arguments:`). Use XCTest only for UI tests.
- Slow tests live in `*IntegrationTests` targets, which the fast gate skips.

## Where work is tracked

- **Actionable work** (features, bugs, research, ideas) lives in **GitHub Issues** at `yungbigos/taellmi` (private).
  - Type labels: `feature`, `bug`, `idea`, `research`.
  - Area labels: `capture`, `explore`, `mcp`, `visuals`, `foundation`.
  - Use `gh issue list -R yungbigos/taellmi`.
  - Close issues from commits with `Closes #n`.
  - New requests from the owner become issues.
- **`docs/plan.md`** is the vision and roadmap, not a to-do list.
- **`docs/decisions/`** holds the decisions.
- **Commits and PRs** carry no Claude attribution: no `Co-Authored-By`, no "Generated with" lines.

## How to work

- Small, verifiable steps: failing test → minimal code → `scripts/check.sh` → refactor.
- For a new feature, use the `add-feature-test-first` skill. For a new model or engine, use `add-model` or `add-engine`.
- After a non-trivial change, have the `code-reviewer` subagent review the diff in a fresh context.
- If something in `docs/` is wrong or missing after your change, update it in the same change.
