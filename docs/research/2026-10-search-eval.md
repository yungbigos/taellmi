# Search evaluation, October 2026

How well search finds thoughts, measured with the real embedding model (Qwen3-Embedding-0.6B 8-bit, 512 dimensions) on three sets. The full tables are in [2026-10-search-eval/](2026-10-search-eval/). Reproduce with `scripts/eval-search.sh`.

## Sets

| Set | Language | Passages | Searches | Right answers per search |
|---|---|---|---|---|
| Synthetic journal ([eval/](../../eval/README.md)) | German with English mixed in, voice-memo style | 1,000 thoughts | 182, including 30 with no answer | median 65 |
| GermanQuAD (control) | German, Wikipedia | 474 | 1,000 (sampled) | 1 |
| SQuAD (control) | English, Wikipedia | 2,067 | 1,000 (sampled) | 1 |

## Scores

- **P@10:** share of the top 10 that are right.
- **R@5:** share of the right answers in the top 5. It is meaningless for the journal, where a search has dozens of right answers.
- **MRR@10:** 1 ÷ the position of the first right answer.
- **False matches:** share of no-answer searches that still return something.

## Findings

### 1. Meaning search is the big win
On the journal, the current settings take P@10 from 27% (words only) to 77%, and MRR from 39% to 97%. The first result is almost always right.

| Kind of search | MRR@10, words only | MRR@10, with meaning |
|---|---|---|
| exact words | 86% | 97% |
| part of a compound | 69% | 100% |
| German paraphrase | 23% | 95% |
| English | 5% | 95% |
| question | 0% | 100% |
| two topics combined | 40% | 100% |

On the Wikipedia controls, words only find almost nothing: a thought must contain every word of a whole question. Meaning reaches R@5 97% (German) and 91% (English).

### 2. The embedding model cannot say "nothing relevant"
Similarity of the closest passage:

| Searches | Median | 10th–90th percentile |
|---|---|---|
| with an answer | 0.64 | 0.57–0.71 |
| without an answer | 0.50 | 0.47–0.56 (max 0.59) |

- **The two ranges overlap,** so every fixed cut-off trades correct results for silence:

  | Cut-off | P@10 | False matches |
  |---|---|---|
  | 0.50 | 74% | 60% |
  | 0.55 | 63% | 30% |
  | 0.60 | 46% | 3% |

- **How far the best hit stands out from the next 20 doesn't separate them either:** median 0.07 with an answer, 0.05 without.
- **A small calibration on six short sentences had suggested 0.35 cleanly separates them.** With 1,000 thoughts, almost every search finds *something* around 0.5.

**Decision (owner, 2026-10-20):** meaning matches are *related*, never answers. Thoughts containing the search words come first, ordered by words and meaning together. Thoughts found only by meaning follow, marked as related. "Nothing found" refers to words. This order costs nothing: P@10 77%, MRR 97%, the same as before. A reranker could later make "no answer" decidable; it remains an option.

### 3. Passage length: keep 600 characters
- **Shorter passages (250) help on long encyclopaedia articles:** SQuAD MRR 84% vs 79%.
- **They hurt on journal thoughts:** MRR 93% vs 97%.

The journal is what tällmi is for.

### 4. A relative cut-off doesn't help
Dropping matches more than 0.10 below the best one lowers journal P@10 from 77% to 72%. The setting `search.relative_similarity_window` stays at 0 (off).

### 5. Memory
- **Unbounded at first:** MLX's buffer cache grew without limit in long runs, reaching about 26 GB in one evaluation.
- **Now capped:** the embedding model's config carries `cache_limit_mb` (256) and `memory_limit_mb` (2048). Every run since peaked at about 2.0 GB.
- **The app gets the same caps.**

## Caveats
- **Journal answers come from topic tags.** A thought that mentions a topic only in passing may be found but counted as wrong. Scores compare variants; they aren't absolute truth.
- **The journal was written by language models from a fixed catalogue.** Real thoughts are messier. Your own archive is the final test.
- **30 no-answer searches** is enough to see the overlap, not to fine-tune a cut-off.
