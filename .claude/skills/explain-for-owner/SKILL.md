---
name: explain-for-owner
description: Explain the current diff, a module, or a technical decision to the tällmi owner, who does not read Swift. Use when the owner asks what changed or how something works.
---
# Explain for the owner

The owner is technical (product and web background) but does not read Swift. Explain:

1. **What changed for the user:** what they can do now, and what looks or behaves differently.
2. **Where it lives**, at module level (see `docs/architecture/overview.md`), with links to files.
3. **What protects it:** which tests cover it, and what was run and passed.
4. **What is configurable:** which seed rows or settings control it, and how to change them.
5. **Risks or open points**, stated plainly.

No Swift syntax unless asked. Use short paragraphs or a small table. Never claim something was verified unless it was run.
