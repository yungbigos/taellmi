# 0012 — Concepts and summaries from Apple's on-device model

- **Status:** accepted (2026-10-20). Builds on ADR 0005 (typed graph), ADR 0006 (no slop), ADR 0011 (meaning index).
- **Issues:** #49 (concepts, related thoughts and summary per thought), #50 (highlighting in flow), #52 (concepts overview).

## Decision

### The engine
- **Apple Foundation Models** (engine key `apple_foundation`, target `FoundationModelsEngine`) fills the `entities` and `summary` Roles.
  - It runs on this Mac only. macOS owns the weights and their memory, so there is nothing to download, load or unload, and it doesn't count against the one-heavy-model rule.
  - It needs Apple Intelligence turned on. Without it, the step waits and nothing is shown; everything else works as before.
- **The answer shape is config.** Each prompt row carries a JSON Schema (`output_schema`). The engine turns it into a guided-generation schema, so the model can only answer in that shape and the code never parses free text.
- **Every request is a fresh session,** so no thought leaks into the next.

### What is extracted
- **Concepts:** people, places, topics and feelings, the kinds that are children of `concept` in config.
  - The model returns, for each one, the exact words it found (`mention`). A concept whose words aren't in the thought is dropped. Everything shown points back to your words.
  - Feelings only when you named them. The prompt forbids guessing from tone (ADR 0006: no mood diagnosis).
  - The same name (ignoring case) and kind is the same Concept across all thoughts. Merging by hand comes later.
- **Summary:** one sentence, only for thoughts of at least `summary.min_words` words.
  - **It is only shown if every meaningful word in it (noun, name, verb, adjective, adverb) appears in the thought,** in some form (`summary.stem_length` leading letters). This drops summaries that add a reason or a feeling (found in a real run: "weil ich den Vermieter nicht anrufe" for a thought that gave no reason). It can't catch a shifted nuance made of the thought's own words ("eher müde als genervt" → "müde und genervt"); the owner accepted that limit. Joined-up separable verbs ("anrufen" for "rufe … an") make a summary fail the check, which is the cautious side.
  - It is marked as generated wherever it shows.
  - You can edit it. Your version lives in `curation.json` in the Archive, replaces the generated one for good, and survives a rebuilt database.

### Storage
- **A `summary` node per thought** (new system node kind). It stores the Text and prompt versions it came from, so a stale thought is one SQL comparison. It exists even without a summary, to mark the thought as done.
- **Concept nodes span all thoughts.** Their id is the kind plus the lower-cased name.
- **Mentions are `mentions` edges from the passage that contains the words to the Concept,** with the exact UTF-16 ranges as evidence. Deleting or re-splitting a thought removes them through the passage.
- Every derived row records the model and prompts that made it.

### Keeping it current
- **One `understand` step after `embed`.** The sweep (ADR 0011) requeues thoughts whose Text or prompts changed.
- **The sweep only queues while the model is available,** so nothing piles up as failures while Apple Intelligence is off.

### What you see
- **flow:** under each thought, its summary, concept badges and up to `explore.related_count` related thoughts.
  - Related thoughts are the nearest by meaning, using the stored passage vectors. No model runs for this.
  - Concept words in the text are underlined, until you edit the text.
- **space (⌘4):** for now a list of every concept by kind, with counts. Choosing one shows its thoughts and the concepts that appear with it. The 3D version comes later.

## Why
- **Apple's model is already on the Mac** and costs no memory of ours. It handles German and English, and guided generation makes its answers reliable to store.
- **Requiring the exact words** keeps the model from inventing concepts or feelings. This is what ADR 0006 asks of every generated thing.
