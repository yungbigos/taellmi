# 0015 — Importing WhatsApp chats, one thought per message

- **Status:** accepted (2026-10-22). Builds on ADR 0013 (importing notes) and ADR 0004 (entries as files).
- **Issues:** #63.

## Context

Many people keep a chat with themselves in WhatsApp as a notebook: quick notes, links, things to remember. WhatsApp on the iPhone and on the Mac exports a chat ("export chat") as a zip holding `_chat.txt` and, if you include media, the photos, voice messages and documents. Unlike an Apple Notes export, every message carries its date and time. Research on the format, with sources: real exports and the parsers `whatsapp-chat-parser` (Pustur), `WhatsR` and `chat-miner`.

What `_chat.txt` looks like on an iPhone set to German dates:

```
‎[14.08.25, 17:39:08] yannik: tickets.pdf • ‎1 page ‎document omitted
‎[19.08.25, 19:44:41] yannik: ‎audio omitted
[02.09.26, 12:34:31] yannik: Zählerstand ablesen
Zähler-ID: 1ABC0000000000
```

- A message starts with its time in brackets, written in the phone's regional date format, then the sender's name and `: `. Lines without a time continue the message above. A line that only looks like a start (no sender, or a day that doesn't exist) is part of the message above too. WhatsApp ends lines with LF or CRLF; other breaks, like U+2028, are kept as part of the words.
- WhatsApp puts U+200E (an invisible left-to-right mark) before everything it writes itself: attachment placeholders ("audio omitted", "Bild weggelassen", `<attached: …>`), deleted messages, notices, and the "edited" mark at the end of a message. A photo's caption stands before its placeholder (`Lecker ‎Bild weggelassen`); a document's line starts with its file name and page count (`Bauplan.pdf • ‎5 Seiten ‎Dokument weggelassen`). The placeholder words follow WhatsApp's language, the dates the phone's region, and 12- or 24-hour time is a separate setting.
- The export has no message ids and doesn't say which sender is you.

## Decision

- **"import from whatsapp …"** in ⌘K (⌥⌘I) and in settings › privacy opens the system file picker. You pick `_chat.txt`, its unzipped folder, or several. In a folder, only files named `_chat.txt` are read; the photos, voice messages and documents beside them (shared `.txt` files too) are ignored. A `.zip` is reported as "unzip it first". The report names a chat by its folder (`WhatsApp Chat - You/_chat.txt`), since every export's chat has the same name.
- **"import from apple notes …" knows chats too.** A `.txt` that reads as a WhatsApp chat is imported as one, a thought per message, never as a single note. This is checked before the duplicate check, so a chat imported earlier as one note (before this) is split when you import it again; the old single thought stays until you delete it.
- **Each message with words becomes one Entry** with Source `whatsapp`, dated by its timestamp to the second, through `createImportedEntry` like a note. It is encrypted, indexed and analysed like a typed thought.
- **The Text is the message's words** as written, lines and blank lines included, without the time and sender. From the first U+200E on, a line is WhatsApp's and is cut off; the words before it stay, like a caption or an edited message's words. A line whose words end in "•" is a document's name and is left out too. A message with no words left (a photo, voice message, document, deleted message or notice) is not imported; the report counts it. Telling WhatsApp's text apart by U+200E works in every language without a list of phrases.
- **Dates** are read as the phone wrote them: `14.08.25`, `8/14/25 … PM`, `14/08/2025`, `2025-08-14`, with or without seconds. Dots mean day first. For slashes, the chat decides: a first number over 12 is a day, a second one over 12 a month, and else the number that changes more often is the day. Only a chat too short to tell goes by its clock (12-hour means month first). WhatsApp writes no time zone, so times are read in the Mac's.
- **Only a chat with yourself, for now.** If more than one name appears as a sender, the chat is not imported ("a chat with others; only chats with yourself for now"), even if only one of them wrote words or the other only sent photos or the encryption notice. The export doesn't say which name is you, so the words could be the other person's. Other people's words are not your thoughts, and which of them, if any, belong in tällmi is a separate decision.
- **No duplicates, also across exports:** each message's `import_fingerprint` is `whatsapp:` + SHA-256 of its time on the clock and its words. A later export of the same chat, even with another date format or after you renamed yourself, adds only the new messages. A message in the Trash counts as already here.
- **The report** says how many messages were imported, were already here and had no words, and which files failed and why.

## Consequences

- Thoughts show "from whatsapp" and have their own filter in the bar ("only from whatsapp").
- A message you typed that itself contains U+200E (rare, e.g. pasted from right-to-left text) loses the rest of that line. A line of yours ending in "•" is taken for a document's name.
- The same words sent twice in the same second are one thought.
- WhatsApp writes times in the phone's time zone at export. A chat exported again in another time zone (after travelling or moving) shifts every time, so its messages come in a second time. An edited message, exported again, is new content and becomes a new thought, as with an edited note (ADR 0013). So does every message if the rules for cutting off WhatsApp's text change.
- **Next steps, not built:**
  - voice messages from an export with media (`.opus`; macOS 26 decodes Ogg Opus natively, so no new dependency) as spoken thoughts with their recording;
  - reading the `.zip` directly;
  - Android exports (`14.08.25, 17:39 - name: text`, no U+200E marks);
  - conversations with others.
