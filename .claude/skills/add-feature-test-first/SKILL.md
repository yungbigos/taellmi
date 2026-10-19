---
name: add-feature-test-first
description: Build a new feature or fix a bug in tällmi test-first. Use for any behaviour change in the Swift code.
---
# Add a feature or fix a bug, test first

1. **Pin down the behaviour.** Write 1–5 bullets of observable behaviour, in user terms. If something is ambiguous, ask the owner before coding.
2. **Find the module.** Use `docs/architecture/overview.md`. Logic goes in `Domain`, `Pipeline`, `Search`, `Config` or `Persistence`, never in views. If a tunable, prompt or model choice is involved, it goes in the config seeds.
3. **Write failing tests.** Add them to the module's `Tests/<Module>Tests`, using fakes from `TestSupport`. Run `scripts/check.sh` and **confirm they fail for the right reason**.
4. **Implement the minimum** to make them pass. Run `scripts/check.sh`.
5. **Refactor** while green.
6. **UI.** If UI changed, add or extend the view-model tests (and snapshot tests for key screens). Then run the app with `scripts/run-app.sh` and check the change by looking at it.
7. **Review.** Ask the `code-reviewer` subagent to review the diff and fix what it finds.
8. **Docs.** Update `docs/` if behaviour, schema or config changed. Add an ADR if a principle or stack choice changed.
9. **Report to the owner** in plain language: what they can now do, what was tested, and anything not verified.
