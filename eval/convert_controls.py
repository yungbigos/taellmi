"""Converts the downloaded control sets into the evaluation format shared with the synthetic journal:
corpus.jsonl  {"id", "text"}
queries.jsonl {"id", "text", "kind", "relevant": [corpus ids]}
Run by scripts/download-eval-data.sh inside its own Python environment (needs pyarrow).
"""
import json, pathlib, sys, hashlib
import pyarrow as pa, pyarrow.ipc as ipc, pyarrow.parquet as pq

raw, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

def arrow(name):
    with open(raw / name, "rb") as f:
        return ipc.open_stream(f).read_all().to_pylist()

def write(folder, corpus, queries):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "corpus.jsonl").write_text("".join(json.dumps(c, ensure_ascii=False) + "\n" for c in corpus), encoding="utf-8")
    (folder / "queries.jsonl").write_text("".join(json.dumps(q, ensure_ascii=False) + "\n" for q in queries), encoding="utf-8")
    print(f"{folder.name}: {len(corpus)} passages, {len(queries)} searches")

# GermanQuAD (MTEB retrieval version): Wikipedia passages, questions, and which passage answers each.
corpus = [{"id": str(r["_id"]), "text": (r.get("title") + "\n\n" if r.get("title") else "") + r["text"]}
          for r in arrow("germanquad-corpus.arrow")]
relevant = {}
for r in arrow("germanquad-qrels.arrow"):
    if r["score"] > 0:
        relevant.setdefault(str(r["query-id"]), []).append(str(r["corpus-id"]))
queries = [{"id": str(r["_id"]), "text": r["text"], "kind": "question", "relevant": relevant[str(r["_id"])]}
           for r in arrow("germanquad-queries.arrow") if str(r["_id"]) in relevant]
write(out / "germanquad", corpus, queries)

# SQuAD v1.1 validation: same shape in English. Each distinct paragraph is a passage.
rows = pq.read_table(raw / "squad-validation.parquet").to_pylist()
ids, corpus, queries = {}, [], []
for r in rows:
    key = r["context"]
    if key not in ids:
        ids[key] = "s" + hashlib.sha256(key.encode()).hexdigest()[:12]
        corpus.append({"id": ids[key], "text": r["title"].replace("_", " ") + "\n\n" + key})
    queries.append({"id": r["id"], "text": r["question"], "kind": "question", "relevant": [ids[key]]})
write(out / "squad", corpus, queries)
