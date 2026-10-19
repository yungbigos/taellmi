# 0006 — No slop: the app extracts and computes, it never interprets unasked

- **Status:** accepted (2026-10-19)

## Allowed

- **Extraction that points back to your words:** Fragments, Concepts, Mentions, and recognising that two Concepts are the same.
- **Computation:** similarity, clusters, counts, timelines, centrality.
- **Short generated labels and paraphrases:** titles for Entries, Fragments and clusters, and condensed statements. These are always marked as generated, always editable, and always linked to their source.

## Forbidden

- Unsolicited insights or interpretations.
- Advice.
- Mood diagnoses.
- "You seem to…".
- Nudging notifications. The one exception is opt-in **invitations** by the Companion:
  - off by default
  - shown only at times you set
  - only fixed texts from config that you can edit (e.g. "Möchtest du etwas festhalten?")
  - never generated content, never references to your Entries
  - (amended 2026-10-19)
- Feedback while capturing, unless you explicitly ask for it.

## When you ask a question

Answers use only your own Fragments, cite them, and say "nothing found" rather than guessing.

## Why

The product is a precise mirror of your own thinking, not a commentator on it. This ADR exists so that no future change "helpfully" adds an insights feature.
