# 0013 — Importing notes from Apple Notes as files you choose

- **Status:** accepted (2026-10-20). Builds on ADR 0004 (entries as files) and ADR 0010 (encryption).
- **Issues:** #18 (each note → Entry with Source `apple_notes` and its original date). Formatting is #46.

## Context

Apple Notes on macOS 26 exports a note as Markdown, PDF or Pages. None of them carries the note's creation date, last-edited date or folder. A Markdown export is the title as a `# heading` line followed by the text. Its file dates are the moment of export.

Notes can also hand its notes to another app through Apple Events, with creation date, modification date, folder and a permanent id. That would keep the dates, but it needs a new sandbox exception (controlling Notes) and an HTML-to-Markdown step. The owner chose the Markdown files.

## Decision

- **"import from apple notes …"** in ⌘K (⇧⌘I) and in settings › privacy opens the system file picker. You pick `.md`/`.txt` files or folders; folders are searched with their subfolders, and hidden and other files are ignored. The sandbox lets tällmi read what you picked, so no new entitlement is needed.
- **Each note becomes one Entry** with Source `apple_notes`, written through `EntryFileStore`, so it is encrypted like every other thought. It is then indexed, and the pipeline splits, embeds and analyses it like a typed thought.
- **The Text is the file's content, byte for byte.** The title stays its first line, as Notes wrote it, and `title` stays empty. The file is only read, never moved or changed.
- **Date:** the earlier of the file's creation and modification date. For a fresh Notes export that is the export time, not when you wrote the note.
- **You can change an imported thought's date.** Click its time in flow, or "change date …" in its details in stack: a calendar opens, and "save" writes the new date to `entry.md` and the index. Spoken and typed thoughts keep theirs: those dates are when you said or wrote them.
- **No duplicates:** `entry.md` keeps `import_fingerprint: "sha256:<hex of the file's bytes>"`. A file whose fingerprint is already in the Archive, including the Trash, is reported as already here. A note edited in Notes and exported again is new content, so it becomes a new thought.
- **The report** says how many notes were imported, how many were already here, and which files failed and why (not a note file, couldn't be read, not text, no words in it).
- Which extensions count as notes is config: `import.note_extensions`.

## Consequences

- Imported thoughts show "from apple notes" and have their own filter in the bar ("only from apple notes").
- If the dates matter more later, reading Notes directly through Apple Events is the next step. It can use the same `createImportedEntry` and fingerprint, with Notes' note id as the fingerprint.
