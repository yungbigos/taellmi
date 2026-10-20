# tällmi — plan

> Vision and roadmap. Actionable items are tracked as GitHub Issues in `yungbigos/taellmi` (see AGENTS.md).

A Mac app you talk into. It transcribes on the device (German and English), keeps every entry in a personal archive, indexes it for keyword and meaning search, and lets you ask a local LLM questions about your own thoughts. Nothing leaves the machine.

Target machine: M4 Pro, 24 GB RAM, macOS 26.5.

---

## 1. Principles (rules we check every choice against)

1. **Local-only by default.** The app makes no network calls except one: an explicit, user-started download of model weights. That step can be skipped entirely by importing model files by hand. No telemetry, no crash reporting, no cloud sync.
2. **You own the data, as plain files.** Each entry is a folder holding the audio and a Markdown file. The database is an index that can be rebuilt from those files at any time. If the app is deleted, the archive can still be read in any text editor or in Obsidian.
3. **Raw input is never lost.** The original audio and the verbatim transcript are always kept. LLM cleanup, summaries and tags are separate layers on top and can be regenerated.
4. **German first, mixed language expected.** Every component (speech-to-text, embeddings, LLM, full-text tokenizer) has to handle German, German–English code-switching, and German compound nouns.
5. **Capture has to be instant.** Talking into the app must feel as fast as opening a notes app. All heavy work runs afterwards, in the background.

---

## 2. Architecture

```
┌──────────────────────────── taellmi.app (SwiftUI, sandboxed) ────────────────────────────┐
│                                                                                           │
│  Capture            Pipeline (background job queue, resumable)            Use            │
│  ───────            ─────────────────────────────────────────            ───            │
│  hotkey / menu bar → record .m4a → transcribe → clean up → enrich → chunk → embed → index │
│  live preview          (STT)        (LLM)      (LLM)              (embed)   (SQLite)     │
│                                                                                           │
│                                        ┌─────────── Archive (source of truth) ──────────┐│
│  Library / Search / Ask / Map  ◄────── │ ~/Library/…/taellmi/Archive/entries/…/      ││
│                                        │   audio.m4a  transcript.md  (front matter)     ││
│                                        └──────────────────────────────────────────────┬─┘│
│                                        ┌─────────── Index (rebuildable) ──────────────▼─┐│
│                                        │ taellmi.sqlite: entries · segments · chunks     ││
│                                        │   FTS5 (keyword)  ·  sqlite-vec (vectors)       ││
│                                        └────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

Everything runs inside one app process. No Ollama, Docker or Python sidecar is required, which keeps it a single drag-to-Applications app with no open ports.

---

## 3. Technology choices

The research and its sources are in [RESEARCH.md](research/2026-10-stack.md). In short:

| Concern | Choice | Fallback |
|---|---|---|
| App | **Native Swift + SwiftUI**, menu-bar app, App Sandbox with no network entitlement. Graphics native too (see section 5a); a WKWebView only as a fallback | Tauri 2 if Windows ever matters; not Electron |
| Final transcription | **Parakeet TDT 0.6B v3 via FluidAudio** (Neural Engine) + Silero VAD | Whisper large-v3-turbo via WhisperKit; Qwen3-ASR 1.7B via MLX for a high-accuracy pass |
| Live preview | **Apple SpeechTranscriber** (built in) | Nemotron 3.5 streaming 0.6B |
| Small LLM jobs | **Apple Foundation Models** | Qwen3.5-4B |
| Cleanup + "ask" | **Qwen3.5-4B, 4-bit, MLX Swift**, loaded on demand | Qwen3.5-9B / Gemma 4 E4B |
| Embeddings | **Qwen3-Embedding-0.6B @ 512 dims** (MLXEmbedders) | EmbeddingGemma-300M |
| Reranker | Qwen3-Reranker-0.6B (optional) | — |
| Storage + search | **SQLite (GRDB): FTS5 unicode61 + trigram, sqlite-vec, RRF** | USearch if vectors get slow |
| Encryption | FileVault + optional SQLCipher + Touch ID lock | — |

Resource rule: tens of MB at idle, one heavy model at a time, unload after idle, worst case ~4–5 GB while asking a question.

## 4. Data model

Vocabulary: [GLOSSARY.md](../GLOSSARY.md). Decisions: [ADR 0004](decisions/0004-entries-as-files.md) (files, encryption, retention), [ADR 0005](decisions/0005-typed-graph-in-sqlite.md) (graph), [ADR 0006](decisions/0006-no-slop.md) (no slop).

```
Archive (encrypted folder, Library by default or a folder you choose)
└── Entry ── Text (canonical, only you edit it) · Source · date · Recording (retention-limited)
     └── Fragment (contiguous part about one thing)
          └── Atom (one statement: generated paraphrase, linked to its source words)
               └── Mention (your exact words) ──► Concept (person, place, topic, emotion, … kinds are config)

Concept ↔ Concept      co-occurrence (derived)
Fragment ↔ Fragment    similarity (derived, from embeddings)
anything ↔ anything    Link (hand-made, permanent)
Clusters               computed from the graph
```

- **Database:** one SQLite file holds config, the index of Entries, the generic node and edge tables (kinds are config), the vectors for Atoms and Fragments, and the Transcript cache. All of it can be rebuilt from the Archive, except config and your hand-made work (Links, Concept merges, renames and hides). Those are exported into the Archive so they survive a rebuild.
- **Editing Text:** editing an Entry's Text re-extracts its Fragments, Atoms and Mentions. Your Concept edits, Links and edited Atom wording survive.

## 5. Features, in the order we build them

### Phase 0 — Walking skeleton (no benchmarking) ✅ built 2026-10-19
Decisions are locked (see section 3); we fix model choices later if real use shows problems. Built test-first, in this order:
1. Package `TaellmiKit` + thin app shell (XcodeGen), strict compiler settings, `scripts/check.sh` green.
2. Database + migrations + **config layer** (providers, models, assignments, prompts, settings) seeded from JSON, with resolution and fallback tests. See [config.md](architecture/config.md).
3. Entry store: write/read entry folders (audio + Markdown), rebuild index from disk.
4. Menu-bar app, App Sandbox (microphone, no network), global hotkey, recording.
5. Transcription via the engine resolved from config (Parakeet v3), durable job queue.
- **Exit:** you press a key, talk German with English bits, and the entry appears on disk and in the database. Swapping the transcription model is a database edit.
- **Deferred from Phase 0:**
  - choosing the Archive folder
  - encryption and the Recovery Key
  - the app Trash
  - `config.json` / `curation.json` export
  - the live preview (SpeechTranscriber)
  - typed Entries in the UI

### Vocabulary (built 2026-10-19)
- **Your own spelling for names in new voice Entries** (Marlene → Marleen).
  - Matching uses the Kölner Phonetik sound code.
  - Guards stop false corrections: Apple's NaturalLanguage tags names and word classes, so verbs and function words are never touched, and ordinary nouns need high spelling similarity. If two Vocabulary terms sound alike, nothing is replaced.
  - Corrections are recorded in `entry.md` (`vocabulary_corrections`). The Transcript stays verbatim.
- **Where the names come from:**
  - your own list in `curation.json`
  - optionally, macOS Contacts (opt-in in Settings)
  - later, person Concepts
- **Still open:**
  - pass the Vocabulary as contextual strings to the live preview (Phase 1)
  - FluidAudio CTC vocabulary boosting (English-trained; needs a German test)

### Companion "tälli": capture from anywhere (requested 2026-10-19, next)
- **Decided:**
  - technical term **Companion**, user-facing name **tälli**
  - hotkey → tälli fades in next to the cursor, already recording, reacting to your voice, with the live text in a bubble
  - hotkey again → "gespeichert" → it fades out; Esc cancels
  - typing instead of talking makes a typed Entry
  - the look starts as an abstract organic shape (Metal); the exact avatar and animations come later
  - appearing unasked ("invitations") is a setting, off by default:
    - only at times you set
    - only fixed, editable texts from config
    - never generated content (ADR 0006)
  - the menu bar icon stays as a fallback (settings, quit) and can be hidden in Settings
- **A small animated companion appears next to the mouse cursor** when you press the hotkey and stays there, watching the cursor; you can drag it. It lives anywhere on screen, not in the crowded menu bar.
- It shows that it is listening (reacting to your voice), the live preview text, and a short confirmation when the Entry is saved. Then it disappears.
- **Later:** playful physics, e.g. reacting to the Mac's motion or orientation.
- The menu bar stays only as a fallback.

### Context for an Entry (requested 2026-10-19, later)
- **Screenshots:** capture a screenshot (or a region) together with an Entry.
- **Extra context:** a web page, the clipboard, or files, given to tälli by:
  - drag & drop onto tälli
  - a "+" button
  - selecting text in another app, then calling tälli
- **Open questions:** the domain term (likely "Attachment"), how it is stored (files in the Entry folder, encrypted like the rest), what gets indexed, and the permissions needed (Screen Recording for screenshots, Accessibility for reading a selection).

### Character and game-like visuals (requested 2026-10-19, later)
- **A cute, custom character for tälli.** Decided 2026-10-20: tälli is the living ä, drawn in 2D from the Funnel Display glyph, not a 3D model ([ADR 0009](decisions/0009-talli-is-the-living-a.md), look and motion in [brand.md](brand.md)).
  - It replaces the placeholder orb; its look is a set of config tokens ([brand/tokens.json](brand/tokens.json)).
- **A visual, game-like rendering of the thoughts:** Concepts, Fragments and clusters as an explorable world (RealityKit). This connects to the "mind palace" idea in section 5a.

### Explore window (requested 2026-10-19, next)
- **Decided for v1:**
  - **Opening it:** "Archiv öffnen" in the menu bar, its own configurable shortcut (default ⌃⌥A after a clash check), or by clicking an Entry in tälli's confirmation. While it is open, tällmi shows in the Dock and in ⌘Tab.
  - **Functional base:** a list of Entries, filters (time, Source), full-text search, and the Text editable directly with autosave.
    - Search is instant and finds word parts and umlauts.
    - Search by meaning comes with embeddings.
  - **Deleting** moves an Entry to the app's Trash, with ⌘Z. Trash (from the bottom bar or ⌘K) restores or deletes for good.
  - **The "alles klein" style is not applied in Explore** (for now).
- **Design direction: unconventional, to be explored with several prototypes.** These ideas are recorded so they are not lost, not a commitment for v1:
  - **A game-like walk-through:** walking a character through a room. Possibly a gimmick, but worth exploring as a general design concept.
  - **Words in 3D space** that you navigate to.
  - **Clusters as a 3D hive, not a 2D mind map you zoom into ("boring").** You walk through your connected ideas, Atoms and Fragments.

### MCP server (requested 2026-10-19, to be designed early)
- **Goal:** local LLMs and agents (LM Studio, Ollama clients, Claude Desktop, …) can talk to tällmi through the Model Context Protocol: search and read Entries, list Concepts, and possibly add Entries.
- **Config first:** the exposed tools, their descriptions, what each may read or write, per-client permissions and limits are all rows in config (seeded, user-editable, saved in `config.json`). Code only implements the tool *mechanisms* (search, read Entry, list Concepts, …), the same split as engines and models.
- **Decided:**
  - read-only tools first, with a "create Entry" tool that exists in config but is off by default
  - every client is a config row with its own key and granted tools, and everything not granted is denied
  - the first connection asks you in the app
  - Recordings are never exposed
  - Entries written via MCP get Source `mcp:<client>`
- **Transport (decided, [ADR 0007](decisions/0007-local-mcp-server.md)):** Streamable HTTP inside the app on `127.0.0.1`, off by default, with a bearer token per client in the Keychain.
  - First target is LM Studio, then Cherry Studio.
  - A stdio relay helper for Claude Desktop, Jan and goose comes later.
  - Research: [research/2026-10-mcp.md](research/2026-10-mcp.md).

### Phase 1 — Capture and archive (MVP you can use daily)
- Menu-bar app with a global hotkey: press → record → press again → done. Optional push-to-talk.
- Live transcript preview while you talk (SpeechTranscriber, set to de-DE, so English words may look odd in the preview only); the final transcript from Parakeet v3 (automatic language detection, handles German with English mixed in) replaces it in the background.
- Library window: a reverse-chronological list, an entry detail view with an audio player and clickable timestamps, edit transcript, delete.
- Typed entries too, for when speaking isn't possible.
- Archive written as folders + Markdown from day one.
- **Import of your existing notes** (see open questions).

### Meaning layer, slice 1 (built 2026-10-20, [ADR 0011](decisions/0011-meaning-index.md))
- The typed graph (node and edge kinds in config, system kinds protected).
- Every thought is split into passages, and each passage is embedded by the `embed` model.
- Explore search ranks by words and meaning, best match first. It falls back to words while no embedding model can run.
- **Next:**
  - try search by meaning on real thoughts (the MLX embedding engine is built; download the model with `scripts/download-model.sh qwen3-embedding-0.6b-8bit`)
  - extraction of points, mentions and Concepts with Apple's on-device model first, Qwen3.5-4B as fallback (#4)
  - constellations of Concepts

### Phase 2 — Search
- Single search field, hybrid keyword + meaning search, results highlighted, jump to the moment in the audio.
- Filters: date range, tags, people, source.
- "Related entries" panel on every entry (nearest neighbours by vector).

### Phase 3 — Enrichment
- Automatic title, 1–2 sentence summary, tags, people/places, and a rough mood per entry (all local LLM, all editable, all regenerable).
- A cleaned-up, readable version of each transcript (filler words, paragraphs) shown next to the verbatim one.

### Phase 4 — Ask your archive
- Chat view: "What was I worried about in spring?", "How did my thinking on X change?", "Was habe ich über Y gesagt?"
- Retrieval-augmented: hybrid search → top chunks → LLM answers **with citations** that link to entries and timestamps. Answers say "nothing found" instead of inventing.
- Query understanding for time ("letzten Monat", "since I moved") turned into date filters before searching.
- Saved questions you can rerun later.

### Phase 5 — Visualize
- Timeline: entries per day/week, length, mood over time.
- Map of thoughts: every entry as a point in 2D (UMAP on embeddings), clustered into themes the LLM names; click a cluster to read it.
- Theme trends: how often a topic comes up over months.
- People/topic graph from extracted entities.

### 5a. Graphics direction (exploration, after the core works)
Everything native, no web layer, so it runs at full frame rate on the GPU:

| Idea | Native tool |
|---|---|
| Animated avatar that reacts to your voice (level, pauses, mood) | SwiftUI + **Metal shaders** (`.colorEffect` / `.layerEffect`, `TimelineView`), or a Rive state machine with the native Apple runtime (offline) |
| Mind maps, thought graphs (hundreds–thousands of nodes) | SwiftUI **Canvas**; drop to **Metal** if the node count gets large |
| 2D "map of thoughts" (UMAP of embeddings) | Canvas/Metal scatter with zoom/pan; Swift Charts for timelines and trends |
| 3D mind palace, walkable data structures | **RealityKit** (Apple's current 3D engine; SceneKit is being phased out), which also carries over to iPhone/Vision Pro |

The data layer (entries, chunks, embeddings, entities, links) is designed so any of these views can read it without changes. Each experiment is a separate view module that can be thrown away.

### Later, maybe
- iPhone capture app that hands recordings to the Mac over the local network or AirDrop only (no cloud). This needs a decision about sync, which conflicts with "local-only" if done through iCloud.
- Periodic reflections: a weekly local digest of what you talked about.
- Encrypted backup to an external drive.

---

## 6. Privacy checklist (part of the definition of done)

- Sandbox entitlements: microphone, user-selected files; **no** outgoing network except in a separate model-download step the user starts.
- A visible "offline" indicator. Optionally verify with Little Snitch / LuLu during development.
- No analytics or crash-reporting SDKs. No third-party SDK that phones home.
- Model downloads checked against pinned SHA-256 hashes.
- Optional SQLCipher database encryption and Touch ID app lock.
- Excluded from Spotlight indexing if you want (or included — that's a choice, see questions).

---

## 7. Risks and how we handle them

| Risk | Mitigation |
|---|---|
| German/English mixing transcribes poorly | Accepted for now; models sit behind a protocol, so we swap in Whisper turbo or Qwen3-ASR if real use shows problems |
| LLM invents things about your life | Always answer from retrieved chunks with citations; show the sources; prefer "I didn't find that" |
| Too resource-hungry for a Mac also used for work | Load on demand, unload when idle; run pipeline steps one after another rather than in parallel |
| Changing an embedding model later | Store the model id per vector; a background re-embed job |
| Lock-in to our own format | Markdown + audio files are canonical; the index is disposable |
| Sandboxed MLX / sqlite-vec builds are fiddly | Hit early in the walking skeleton |

---

## 8. Open questions for you

1. ~~Which notes app holds your existing entries~~ — answered: Apple Notes, imported from its Markdown export (ADR 0013). The export carries no dates, so imported notes are dated by their files.
2. ~~German/English mixing~~ — answered: mostly German with English words and occasional switches. Parakeet auto-detects; no benchmark for now.
3. **iPhone capture**: needed soon, or Mac-only for now?
4. **Typing vs. talking**: should typed entries be first-class, or is this voice-only?
5. **Spotlight**: should entries show up in macOS Spotlight search, or stay invisible to the rest of the system?
6. **Distribution**: just for you (run from Xcode / unsigned), or eventually signed and notarized for others?

## 9. Proposed first step

Phase 0 walking skeleton: create the Xcode project in this folder and get record → transcribe → save working end to end.

## 10. How we work

You don't write Swift; coding agents do. The setup that keeps that reliable:

- [AGENTS.md](../AGENTS.md): the shared guide every agent reads (CLAUDE.md just imports it).
- `.claude/rules/`: rules that load only when an agent touches matching files (Swift, tests, config, persistence, engines, UI).
- `.claude/skills/`: step-by-step procedures: `add-feature-test-first`, `add-model`, `add-engine`, `explain-for-owner`.
- `.claude/agents/`: a `code-reviewer` that checks every change against the principles in a fresh context, and a `test-writer`.
- Hooks: Swift files are auto-formatted; edits to the generated Xcode project and network entitlements are blocked; an agent **cannot finish** while `scripts/check.sh` fails.
- The git pre-commit hook runs the same `scripts/check.sh`, so nothing broken gets committed.
- Decisions are recorded as ADRs in [decisions/](decisions/).
