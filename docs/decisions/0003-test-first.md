# 0003 — Test first, enforced by tooling

- **Status:** accepted (2026-10-19)
- **Context:** Agents write all code, and the owner can't review Swift. Tests are how we know nothing broke.
- **Decision:**
  - Every behaviour change starts with a failing Swift Testing test.
  - `scripts/check.sh` (format lint → build → fast tests) is the single gate. It runs from the git pre-commit hook and from the Claude Code Stop hook.
  - ML adapters are tested against fakes in unit tests and against real tiny fixtures in tagged integration suites.
  - UI is covered by view-model tests, plus snapshot tests for key screens.
- **Consequences:**
  - The fast suite must stay fast (target: under 30 s).
  - Anything slow goes into an `…IntegrationTests` target, which runs on demand and before releases.
