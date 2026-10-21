# 0014 — Formatting is Markdown in the Text, styled where it stands; speech adds only paragraphs and numbered lists

- **Status:** accepted (2026-10-20). Builds on ADR 0004 (entries as files), ADR 0006 (no slop), ADR 0011 (passages) and ADR 0013 (importing notes).
- **Issues:** #55 (formatting, also from speech). Shortcuts follow #24 (keyboard-first).

## Context

Thoughts are plain text today. You want bold, italic, underline, strike-through, bullet lists and numbered lists while typing, and a list when you count out loud. Notes imported from Apple Notes already arrive with Markdown in them (`# Titel`, `- `, `**`, `- [ ]`), which is shown raw.

## Decision

### Stored as Markdown, in the Text itself
- **`entry.md` holds the formatting as Markdown.** The app writes `**bold**`, `*italic*`, `<u>underline</u>` (Markdown has none; Obsidian shows this), `~~strike through~~`, `- ` for bullets and `1. ` for numbers, with indented lines for deeper levels.
- **Other spellings look the same and are never rewritten:** `__bold__`, `_italic_`, `* item`, and Apple Notes' `++underline++`. Bear's `~underline~` reads as strike-through until there is a Bear import.
- **Shown when they arrive, but not offered as buttons:** headings (`#`, `##`, `###`), checklists (`- [ ]`, `- [x]`; clicking a box ticks it, as your edit), block quotes and links (⌘-click hands the address to your browser; tällmi itself makes no network call). Tables and code show as their plain text. A missing image from an import (Apple Notes' `Attachments/…`) shows `image not imported`; the link stays in the Text.

### The editor styles the Markdown where it stands
- **What you edit is the file.** There is no rich-text model and no conversion between the screen and `entry.md`. A styling mistake can only look wrong, never change your words, and every position the app keeps (search highlights, passages, concept underlines) stays exact.
- **Markup is hidden.** It reappears only around the formatted words the cursor is in or next to, as in Obsidian. Bullets are drawn as •, and the `- ` shows when the cursor is at the start of that item. Numbers show as typed.
- **Where formatting comes from:**
  - a floating bar over a finished selection: bold · italic · underline · strike through · bullet list · numbered list, with a format that's on shown as on;
  - shortcuts, in config: ⌘B, ⌘I, ⌘U, ⇧⌘X (strike through), ⇧⌘7 (bullets), ⇧⌘9 (numbers), ⌘] / ⌘[ (indent, outdent);
  - ⌘K while a thought is being edited;
  - typing `- `, `1. `, `> ` or `# ` at the start of a line.
  There is no formatting toolbar.
- **Lists:** Tab and ⇧Tab change the level, and numbering restarts on each level. Return starts the next item, Return on an empty item ends the list, and Backspace at an item's start removes its bullet or number. Numbers renumber themselves. ⌘Z undoes formatting like any other edit.
- **One editor wherever you edit a thought:** flow, the open thought, and the new-thought composer, which moves to the same editor. tälli's one-line bubble stays plain.
- **Copy gives Markdown and paste gives plain words**, for now.
- **On a concept word, the concept's underline is drawn** instead of yours; yours stays in the Text.

### Everything else reads only the words
- **A words-only view of the Text** (markup removed, positions mapped back to the Text) feeds search, passages, embeddings, points, summaries and word counts. "sehr wichtig" finds "sehr **wichtig**", and `Ver**mieter**` is still "Vermieter".
- **Formatting never changes whether words count.** Struck-through and ticked words are still found and still read.
- **Passages:** each list item, at any level, is a passage of its own, and a long item is split between its sentences. A heading starts a new passage. The line that introduces a list groups with the text before it.
- **Previews** (stack rows, search results, ⌘K, the menu bar, time, space, related thoughts) show plain words; list items run on, separated by spaces.
- **The MCP server, once built, serves the Markdown.** "Export as plain files" copies `entry.md` as it is.

### Speech adds paragraphs and numbered lists, never words
It runs once, where the spelling corrections run: when a spoken thought's Text is first written. What it did is recorded on the Entry, like `vocabulary_corrections`, and listed in the thought's details next to the spellings. The Transcript stays verbatim.
- **Paragraphs:** a pause longer than a configured length, after the end of a sentence, starts a new paragraph. A pause in the middle of a sentence never does.
- **Numbered lists from counting:** "erstens … zweitens …", "Punkt eins … Punkt zwei …", "Nummer eins …", "first … second …". The counting words per language are config.
  - At least two, in order, starting at one, each opening a sentence or following a colon. "Punkt" without a number never counts.
  - Each item runs up to the next counting word, across several sentences if needed. The last item ends with its sentence.
  - Pauses inside the list add no blank lines, and what follows the list starts a new paragraph.
  - The counting words stay: "1. Erstens müssen wir die Steuer machen."
- **Not from speech:** bold, italic, underline, strike-through, bullet lists, dictation commands ("neuer Absatz", "Spiegelstrich"), and lists you don't count out loud. tälli's live words while you speak stay plain.
- **Only new spoken thoughts.** Existing spoken thoughts stay as they are, and typed and imported Texts are never touched.

## Why

- **Markdown in the file** keeps the Archive readable in any editor and in Obsidian (ADR 0004), and imported notes already bring it.
- **Styling in place rather than a rich-text editor:** macOS 26's rich `TextEditor` has no way back to Markdown. A converter in both directions would sit between you and your words, and every stored position would need translating.
- **Hidden markup** reads cleanly. Showing it at the cursor keeps it editable without a separate mode.
- **Speech:** pauses and counting words are in the Transcript itself, so the rules are deterministic and testable. Stress and tone are not in it, and guessing emphasis or turning a sentence into a list would be interpretation (ADR 0006).
- **Keeping the counting words** keeps German word order intact ("Müssen wir die Steuer machen." without "Erstens" reads as a question), and means speech formatting never changes a word.

## Consequences

- **Build order:**
  1. the editor, the floating bar, shortcuts and the words-only view (this also makes imported notes look right);
  2. paragraphs from pauses;
  3. German test clips with counting (macOS voices plus a few of your own), run through Parakeet in the integration tests;
  4. spoken lists, written against what Parakeet actually writes.
- **Open until step 3:** how Parakeet punctuates "erstens", whether it writes a spoken "Punkt" as ".", and the pause length for a paragraph.
- **Apple Notes' export syntax comes from one hands-on report.** A test export should confirm `++underline++` and how nested lists are indented.
- **The thought editor gains real styling** on top of the display-only search and concept highlights it already draws.

## Built (step 1, 2026-10-21)

- **Reading:** `TextFormatting` (Domain) reads the Markdown line by line; `WordsOnlyText` is the words-only view with positions both ways; `FormattingEdits` holds every action as a pure edit; `TextFormatting.visibility(selection:)` says what is hidden.
- **Details decided while building:**
  - A number at the start of a line starts a list only at 1, or when it continues a list, so "3. Oktober war schön." stays a sentence. A blank line between items keeps the list going.
  - Renumbering only touches the list you are editing: a run of items with no blank line or sentence between them. It keeps that list's first number (1, unless it continues a list above a blank line); a sub-list starts at 1. A list elsewhere in the thought, like "3. Oktober …" after a blank line or an imported list that skips numbers on purpose, is never rewritten.
  - A list item's leading tabs or spaces are always hidden; the level is drawn as an indent of `l` per level. New levels are written as one tab.
  - Shortcuts for letters match the letter typed (⌘B is ⌘B on every layout); digits and brackets match the key, as Apple Notes does (⇧⌘7 is the 7 key, also on a German keyboard).
  - While the mouse is selecting, the markup doesn't change, so text never jumps under the pointer; it updates when the button is released.
  - Search's own index, passages (`passage_splitter@2`, so every thought is split once more), the models' prompts, summary checks, word counts and previews read the words-only view.
- **Not built yet:** steps 2–4 (paragraphs from pauses, the Parakeet test clips, spoken lists).
