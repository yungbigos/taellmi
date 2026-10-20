# Search evaluation

Model: `qwen3-embedding-0.6b-8bit` (512 dims). Scores in %, higher is better, except false matches (share of searches with no right answer that still returned something).

## synthetic-journal: 1000 documents, 182 searches

| variant | passages | P@10 | R@5 | R@10 | MRR@10 | nDCG@10 | false matches | results/search | ms/search |
|---|---|---|---|---|---|---|---|---|---|
| F: passages 600, min 0.50 | 1282 | 74.1 | 8.8 | 15.6 | 96.5 | 78.2 | 60.0 | 32.1 | 15 |
| G: passages 600, min 0.55 | 1282 | 63.2 | 8.0 | 13.2 | 91.4 | 69.0 | 30.0 | 21.6 | 3 |
| H: passages 600, min 0.60 | 1282 | 45.7 | 6.1 | 9.8 | 80.9 | 52.1 | 3.3 | 15.9 | 2 |
| words only | 1282 | 27.2 | 3.6 | 6.1 | 39.0 | 29.2 | 3.3 | 12.7 | 1 |
| A: passages 600, min 0.35 (current) | 1282 | 76.7 | 8.9 | 16.1 | 96.7 | 80.2 | 100.0 | 53.6 | 4 |
| B: passages 250, min 0.35 | 2317 | 75.2 | 9.0 | 15.8 | 93.1 | 78.2 | 100.0 | 52.1 | 5 |
| C: passages 600, min 0.45 | 1282 | 76.5 | 8.9 | 16.1 | 96.7 | 80.0 | 93.3 | 45.2 | 4 |
| D: passages 600, min 0.35, window 0.10 | 1282 | 72.6 | 8.7 | 14.8 | 96.1 | 77.1 | 100.0 | 31.7 | 3 |
| E: passages 250, min 0.35, window 0.10 | 2317 | 71.6 | 8.7 | 14.8 | 93.1 | 75.5 | 100.0 | 32.6 | 4 |

Similarity of the closest passage (10th / 50th / 90th percentile):

| searches | n | p10 | p50 | p90 |
|---|---|---|---|---|
| with an answer | 152 | 0.57 | 0.64 | 0.71 |
| without an answer | 30 | 0.47 | 0.50 | 0.56 |
| margin, with an answer | 152 | 0.04 | 0.07 | 0.11 |
| margin, without an answer | 30 | 0.03 | 0.05 | 0.07 |

Without an answer, sorted: 0.41 0.43 0.45 0.47 0.47 0.47 0.48 0.48 0.48 0.49 0.49 0.49 0.50 0.50 0.50 0.50 0.50 0.51 0.51 0.52 0.53 0.53 0.53 0.54 0.54 0.55 0.55 0.56 0.59 0.59

MRR@10 by kind of search (for `none`: false-match rate):

| variant | combo | english | exact | none | paraphrase | part | question |
|---|---|---|---|---|---|---|---|
| F: passages 600, min 0.50 | 100.0 | 95.4 | 98.7 | 60.0 false | 92.3 | 100.0 | 100.0 |
| G: passages 600, min 0.55 | 100.0 | 87.2 | 93.6 | 30.0 false | 85.9 | 100.0 | 100.0 |
| H: passages 600, min 0.60 | 100.0 | 69.2 | 93.6 | 3.3 false | 67.9 | 87.5 | 100.0 |
| words only | 40.0 | 5.1 | 85.5 | 3.3 false | 23.1 | 68.8 | 0.0 |
| A: passages 600, min 0.35 (current) | 100.0 | 95.4 | 97.0 | 100.0 false | 94.9 | 100.0 | 100.0 |
| B: passages 250, min 0.35 | 90.0 | 92.9 | 94.4 | 100.0 false | 92.4 | 96.9 | 87.0 |
| C: passages 600, min 0.45 | 100.0 | 95.4 | 97.0 | 93.3 false | 94.9 | 100.0 | 100.0 |
| D: passages 600, min 0.35, window 0.10 | 100.0 | 95.4 | 95.7 | 100.0 false | 93.6 | 100.0 | 100.0 |
| E: passages 250, min 0.35, window 0.10 | 90.0 | 92.9 | 94.4 | 100.0 false | 92.4 | 96.9 | 87.0 |
