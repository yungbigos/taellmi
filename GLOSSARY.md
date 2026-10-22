# tällmi

A private, local-only journal you talk or write into. Over time it becomes a connected archive of your thoughts that you can search, ask questions about, and explore visually.

These are the domain terms used in code and docs. Users see different words, given as _In the app_; [docs/brand.md](docs/brand.md) has the full mapping and the voice rules.

## Archive

**Entry**:
One act of capture: a single recording, a single written note, or a single imported note. Entries are never appended to; each new capture is a new Entry.
_In the app_: thought
_Avoid_: Note, record, memo, item

**Text**:
The canonical content of an Entry, which you can read and edit. For a voice Entry it starts as a Transcript, and from then on it only changes when you edit it.
_Avoid_: Body, content, cleaned transcript

**Formatting**:
How the words of a Text look and are laid out: bold, italic, underline, strike-through, headings, paragraphs, lists, quotes and links. It never changes whether words count; only you add or change it, except that a spoken Entry's first Text gets paragraphs from long pauses and numbered lists from counting out loud, without changing a word, recorded on the Entry.
_In the app_: no umbrella word; bold, italic, underline, strike through, bullet list, numbered list
_Avoid_: Markup, styling, rich text

**Transcript**:
The verbatim output of a speech-to-text model for one Recording, with timings. It seeds the Text and maps words to moments in the audio. It is kept alongside the Recording and expires with it under Retention.
_In the app_: transcript
_Avoid_: Text (when meaning model output)

**Recording**:
The audio captured for a voice Entry.
_In the app_: recording
_Avoid_: Audio note, voice memo, take

**Source**:
Where an Entry came from: spoken, typed, or the app it was imported from (e.g. Apple Notes, WhatsApp, Obsidian, Bear). An imported Entry keeps the date it was originally created. From WhatsApp, each message is an Entry of its own (ADR 0015).
_In the app_: spoken, typed, or the app's name
_Avoid_: Input mode, origin, type

**Import fingerprint**:
The SHA-256 of the file an imported Entry came from, kept in its `entry.md` (`import_fingerprint`). Importing the same file again finds it and skips it (ADR 0013). For a WhatsApp message it is the SHA-256 of its time and words, so a later export of the same chat adds only new messages (ADR 0015).
_In the app_: (not shown; the import report says "already here")
_Avoid_: Hash, checksum

**Archive**:
The folder holding every Entry. It is encrypted by default, lives in the app's Library folder by default, or in a folder you choose.
_In the app_: not shown; the window is just tällmi
_Avoid_: Vault, library, database

**Folder**:
A collection of Entries you make by hand. An Entry lives in at most one Folder; one in none is loose. Folders are Curation: they live in the Archive and never change by themselves.
_In the app_: folder; "loose thoughts" for those in none
_Avoid_: Notebook, collection, tag, album

**Retention**:
How long Recordings are kept before they are deleted or moved elsewhere. The Text is kept forever.
_In the app_: "keep recordings for …"
_Avoid_: Expiry, cleanup policy

**Trash**:
The app's own holding area for deleted Entries. A later cleanup moves them to the macOS Trash.
_In the app_: trash
_Avoid_: Bin, deleted items

**Recovery Key**:
A one-time secret shown at setup. It is the only way to read the encrypted Archive on another Mac or after losing the Keychain.
_In the app_: recovery key
_Avoid_: Backup password, master key

## Meaning

**Fragment**:
A contiguous part of an Entry's Text that is about one thing. An Entry has one or more Fragments. Each list item, at any level, is a Fragment of its own, and a heading starts a new one.
_In the app_: passage
_Avoid_: Chunk, segment, section, block

**Atom**:
One self-contained statement within a Fragment. It is a short generated paraphrase, always linked to the exact words it came from, and editable. It is the smallest unit of meaning.
_In the app_: point
_Avoid_: Sentence, thought, idea, proposition, claim

**Mention**:
The exact words in an Entry's Text that refer to a Concept, such as "Mutti" referring to the Concept *Mutter*.
_In the app_: mention
_Avoid_: Occurrence, reference, tag

**Concept**:
A thing that recurs across the Archive: a topic, person, place, emotion, or another configured kind. A Concept is a single entity across the whole system, however many different words refer to it.
_In the app_: no umbrella word; shown by kind (people, places, topics, feelings)
_Avoid_: Tag, keyword, entity, topic (as the general term)

**Link**:
A connection between two things that you made by hand. Links are permanent. When an endpoint disappears, the Link is shown as broken, never silently removed.
_In the app_: connection
_Avoid_: Relation, edge (in conversation)

**Curation**:
Everything you decide by hand that shapes the Archive's meaning: Links; merging, renaming and hiding Concepts; edited Atoms; your Vocabulary; and weights that give certain Concepts or Atoms more or less focus. Curation is never recomputed; recomputation respects it.
_Avoid_: Manual edits, overrides, annotations

**Summary**:
One generated sentence about what a longer Entry says, shown next to it. Marked as generated. Once you edit it, it is yours (part of Curation) and never regenerated.
_In the app_: summary
_Avoid_: Insight, takeaway, abstract

**Vocabulary**:
The words the app should spell exactly your way, mostly names (e.g. "Kim"). It comes from your own list (part of Curation) and, if you opt in, your contacts. The Text of a new voice Entry is corrected towards it, and each correction is recorded on the Entry.
_In the app_: spellings
_Avoid_: Dictionary, custom words, glossary

**Cluster**:
A group of Concepts or Fragments found automatically because they belong together.
_In the app_: constellation
_Avoid_: Topic, category, group

**Concept kind**:
The category of a Concept, such as person, place, topic or emotion. The list of kinds is configurable.
_Avoid_: Type, label

## Modes

**Capture**:
The mode for getting thoughts in, by speaking, writing or importing.
_In the app_: not shown
_Avoid_: Record mode, input

**Explore**:
The mode for viewing, searching and asking questions about the Archive: Concepts, Fragments, clusters and visualizations.
_In the app_: not shown; the window is just tällmi
_Avoid_: Browse, library view

**Companion**:
The small animated presence that appears next to the cursor for Capture and stays there, watching the cursor, called **tälli** in the app. It appears when you call it (hotkey or click). It never appears unasked, unless you turned on invitations at times you set.
_In the app_: tälli
_Avoid_: Assistant, advisor, avatar, Clippy (in code and docs; "tälli" is the name users see)

**Thinking**:
What the Companion visibly does while the app works on Entries in the background: transcribing, finding Fragments, Concepts and Links. Thoughts (Entries) belong only to the user; tälli thinks about them.
_In the app_: thinking ("tälli is thinking")
_Avoid_: Mulling, pondering, processing (in the app)

**Command**:
Any action in the app (new Entry, delete, switch view, search, …), identified by a fixed id, with a shortcut you can change. ⌘K opens the command palette, which finds Commands and Entries.
_Avoid_: Action, shortcut (for the action itself), hotkey

## Models and config

**Role**:
A job the app needs a model for, such as transcription, titling, or embedding.
_Avoid_: Task, purpose

**Model**:
A specific set of weights that can fill one or more Roles, pinned to an exact version.
_Avoid_: Engine (a different thing)

**Engine**:
The code that knows how to run a family of Models, such as Parakeet via FluidAudio or LLMs via MLX.
_Avoid_: Runtime, backend, adapter (in conversation)

**Assignment**:
The rule saying which Model fills a Role, and with what priority. Lower-priority Assignments act as fallbacks.
_Avoid_: Mapping, binding

**Seed**:
A default config row shipped with the app. Seeds never overwrite something you changed.
_Avoid_: Default (when meaning the shipped row)
