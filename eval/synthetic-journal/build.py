"""Builds the synthetic-journal evaluation set (corpus.jsonl + queries.jsonl) from parts/*.jsonl and
queries.jsonl. A search's right answers are the thoughts tagged with all of its topics."""
import json, pathlib, sys, collections

here = pathlib.Path(__file__).parent
out = pathlib.Path(sys.argv[1]) / "synthetic-journal"
out.mkdir(parents=True, exist_ok=True)
catalogue = json.loads((here / "catalogue.json").read_text(encoding="utf-8"))
known = set(catalogue["topics"])

entries = []
for part in sorted((here / "parts").glob("part-*.jsonl")):
    for line in part.read_text(encoding="utf-8").splitlines():
        if line.strip():
            entries.append(json.loads(line))
from datetime import datetime
for e in entries:  # some writers left out the seconds; store one exact format
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"):
        try:
            e["date"] = datetime.strptime(e["date"], fmt).strftime("%Y-%m-%dT%H:%M:%S")
            break
        except ValueError:
            pass
    else:
        raise SystemExit(f"{e['id']}: unreadable date {e['date']}")
ids = [e["id"] for e in entries]
assert len(ids) == len(set(ids)), "duplicate ids"
for e in entries:
    unknown = set(e["topics"]) - known
    assert not unknown, f"{e['id']}: unknown topics {unknown}"

# A second, uncapped tagging pass (retag/*.jsonl), made by reading each thought again, replaces the first
# one: it adds what the four-topic cap left out and removes the few wrong tags.
retagged = {}
for part in sorted((here / "retag").glob("retag-*.jsonl")):
    for line in part.read_text(encoding="utf-8").splitlines():
        if line.strip():
            row = json.loads(line)
            retagged[row["id"]] = row["topics"]
for e in entries:
    if e["id"] in retagged:
        unknown = set(retagged[e["id"]]) - known
        assert not unknown, f"{e['id']}: unknown topics {unknown}"
        e["topics"] = list(retagged[e["id"]])
print(f"second tagging pass used for {len(retagged)} thoughts")

# The writers capped tags at four per thought, so a named person was sometimes left untagged. Names are
# distinctive (misspellings included), so person tags are completed from the text.
import re
PEOPLE = {
    "person:lea": r"\b(Lea|Lia|Leah)\b",
    "person:anna": r"\b(Annas?|Ana)\b",
    "person:mama": r"\b(Mama|Mutti|Mutter|meiner Mum|my mom)\b",
    "person:oma": r"\b(Oma|Gerti|Großmutter|grandma)\b",
    "person:tobi": r"\b(Tobi|Toby|Tobis)\b",
    "person:sven": r"\b(Sven|Svens|Swen)\b",
    "person:dr-weber": r"\b(Weber|Wäber|Weeber)\b",
}
added = 0
for e in entries:
    for topic, pattern in PEOPLE.items():
        if topic not in e["topics"] and re.search(pattern, e["text"]):
            e["topics"].append(topic)
            added += 1
print(f"completed {added} person tags from names in the text")

tagged = collections.defaultdict(set)
for e in entries:
    for t in e["topics"]:
        tagged[t].add(e["id"])

queries = []
for line in (here / "queries.jsonl").read_text(encoding="utf-8").splitlines():
    q = json.loads(line)
    relevant = set.intersection(*(tagged[t] for t in q["all_topics"])) if q["all_topics"] else set()
    if q["all_topics"] and not relevant:
        print(f"skipped {q['id']} ({q['text']}): no thought has all of {q['all_topics']}")
        continue
    queries.append({"id": q["id"], "text": q["text"], "kind": q["kind"], "relevant": sorted(relevant)})

(out / "corpus.jsonl").write_text(
    "".join(json.dumps({"id": e["id"], "text": e["text"], "date": e["date"]}, ensure_ascii=False) + "\n" for e in entries),
    encoding="utf-8")
(out / "queries.jsonl").write_text("".join(json.dumps(q, ensure_ascii=False) + "\n" for q in queries), encoding="utf-8")
print(f"synthetic-journal: {len(entries)} thoughts, {len(queries)} searches")
