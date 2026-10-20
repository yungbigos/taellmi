# Search evaluation

Model: `qwen3-embedding-0.6b-8bit` (512 dims). Scores in %, higher is better, except false matches (share of searches with no right answer that still returned something).

## germanquad: 474 documents, 1000 searches

| variant | passages | P@10 | R@5 | R@10 | MRR@10 | nDCG@10 | false matches | results/search | ms/search |
|---|---|---|---|---|---|---|---|---|---|
| F: passages 600, min 0.50 | 2380 | 9.5 | 94.5 | 94.8 | 90.7 | 91.7 | – | 4.3 | 21 |
| G: passages 600, min 0.55 | 2380 | 9.0 | 89.7 | 89.7 | 86.7 | 87.5 | – | 2.1 | 4 |
| H: passages 600, min 0.60 | 2380 | 8.0 | 80.2 | 80.2 | 78.0 | 78.6 | – | 1.2 | 4 |
| words only | 2380 | 0.0 | 0.2 | 0.2 | 0.2 | 0.2 | – | 0.0 | 2 |
| A: passages 600, min 0.35 (current) | 2380 | 9.9 | 97.2 | 98.6 | 92.5 | 94.0 | – | 30.3 | 6 |
| B: passages 250, min 0.35 | 5258 | 9.9 | 98.7 | 99.4 | 93.8 | 95.2 | – | 27.1 | 8 |
| C: passages 600, min 0.45 | 2380 | 9.7 | 96.6 | 97.4 | 92.2 | 93.5 | – | 10.3 | 5 |
| D: passages 600, min 0.35, window 0.10 | 2380 | 9.8 | 96.7 | 97.7 | 92.3 | 93.6 | – | 3.8 | 4 |
| E: passages 250, min 0.35, window 0.10 | 5258 | 9.9 | 98.3 | 98.8 | 93.7 | 95.0 | – | 3.2 | 6 |

## squad: 2067 documents, 1000 searches

| variant | passages | P@10 | R@5 | R@10 | MRR@10 | nDCG@10 | false matches | results/search | ms/search |
|---|---|---|---|---|---|---|---|---|---|
| F: passages 600, min 0.50 | 5904 | 9.0 | 88.2 | 89.6 | 77.6 | 80.6 | – | 21.6 | 29 |
| G: passages 600, min 0.55 | 5904 | 8.5 | 83.4 | 84.6 | 74.2 | 76.8 | – | 14.4 | 12 |
| H: passages 600, min 0.60 | 5904 | 7.4 | 73.5 | 74.1 | 66.1 | 68.1 | – | 7.1 | 11 |
| words only | 5904 | 0.0 | 0.2 | 0.2 | 0.2 | 0.2 | – | 0.0 | 7 |
| A: passages 600, min 0.35 (current) | 5904 | 9.3 | 91.0 | 93.1 | 79.3 | 82.8 | – | 39.5 | 14 |
| B: passages 250, min 0.35 | 10367 | 9.6 | 92.8 | 95.6 | 83.5 | 86.5 | – | 35.9 | 17 |
| C: passages 600, min 0.45 | 5904 | 9.2 | 90.2 | 91.9 | 78.8 | 82.1 | – | 29.5 | 14 |
| D: passages 600, min 0.35, window 0.10 | 5904 | 9.2 | 90.0 | 91.7 | 79.0 | 82.1 | – | 11.0 | 12 |
| E: passages 250, min 0.35, window 0.10 | 10367 | 9.4 | 91.9 | 93.8 | 83.1 | 85.7 | – | 8.9 | 15 |
