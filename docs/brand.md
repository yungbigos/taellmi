# tällmi — brand book

Decided with the owner on 2026-10-20. This is the source of truth for how tällmi looks, moves and talks. Agents read it before writing any UI text or visual. Domain terms live in [GLOSSARY.md](../GLOSSARY.md); this file maps them to the words users see.

**Still open, not decided here:**
- German and other translations
- a better name for the list view than "stack"
- exact colour values
- the logo drawings

## 1. The idea

**ä is the sound of thinking.** In German, "äh" is the "uh" you say while you think. tällmi is built around it:
- You don't need to be precise. Say it the way it comes: unfinished, hesitant, German and English mixed.
- tällmi keeps it and finds it again later.
- **Messy is good and works.**

The promise is **finding and understanding**, never rewriting.
- Your words stay exactly as you said or typed them ([ADR 0006](decisions/0006-no-slop.md), and the rule that the user's Text is sacred).
- Polished versions or summaries may come later. They are only ever extra copies next to your thought: made when you ask, marked as generated, and never replacing the original.

**Tagline:** `think out loud.`
**The wink:** `äh included.`, always with the explainer in small type: *(äh: german for "uh", the sound of thinking.)*
- Use the tagline for the main line: app icon tooltip, website header, first launch.
- Use the wink for the subline: first launch, website, stickers.

## 2. Names

| Name | What it is | Rules |
|---|---|---|
| **tällmi** | the app | Always lowercase, always with ä, even at the start of a sentence. Never "Tällmi", "Tellmi" or "Taellmi". `taellmi` appears only in identifiers (bundle id, paths). |
| **tälli** | the companion at your cursor | Same rules. tälli is a character, not the app. Never use one name for the other. |

The main window has no name of its own: it is **tällmi**. The menu item is **open tällmi**. The window title shows the current view.

## 3. Logo

- **The mark is the ä with its two dots. The dots are tälli's eyes.** The letter and the dots belong together.
- **Wordmark:** `tällmi` in lowercase, drawn by us on top of Funnel Display, so we own the result. In animated uses the dots may blink or drift.
- **App icon:** the ä or tälli's face (two dots) on the brand blues.
- **Never:**
  - capitals
  - an "ae" spelling
  - a microphone, speech bubble or waveform as the logo (generic voice-memo clichés)
- Drafts come later as a visual design artifact.

## 4. Avatar (tälli)

The brief for the character work in issue #7:
- round and soft, with no limbs at first (or tiny ones)
- **two dot eyes, the same dots as the logo**
- a mouth only when it is speaking or reacting
- a blue gradient body
- thumbnail-sized next to the cursor
- no gender, no age: a small creature, not a person and not a pet breed

## 5. Colour

| Token | Role |
|---|---|
| **ink** | deep night blue: dark surfaces, and the wordmark on light backgrounds |
| **blue** | clear mid blue: the app's accent colour (controls, focus, selection) |
| **mist** | pale sky blue: quiet fills, tälli's light side |
| **pink** | **only for the dots**: tälli's eyes, the ä in the logo, the listening pulse. Nothing else is pink. |

- Everything else follows macOS: light and dark mode, system greys.
- The old peach-pink-indigo orb gradient is retired.
- Exact values come with the logo work and live as config tokens (config first), not in Swift.

## 6. Type

**One family:**
- **Funnel Display** for the wordmark, view titles and big moments.
- **Funnel Sans**, with its italic, for everything else tällmi draws: lists, your thoughts, ⌘K, tälli's bubble, the contents of settings.

Licence and fallback:
- Both are OFL (NORD ID, Kristian Möller; on Google Fonts since 2024), variable weight, and cover Latin-extended.
- Fallback if Funnel disappoints in the real app: **Bricolage Grotesque** (OFL, optical sizes).

Rules:
- Parts that macOS draws stay in SF Pro: menu bar menus, system alerts, file pickers. We don't fight that.
- Text follows the macOS text-size setting. No fixed point sizes.
- Fonts are bundled with the app. Nothing loads from the network.

## 7. Style

- **The frame is native macOS 26:** Liquid Glass sidebar and toolbars, system controls, generous space, few lines, no custom chrome.
- **What makes it unusual lives inside the views** (flow, time, space), never in the frame.
- **Glass goes on navigation and controls, plus tälli's bubble. It never goes under your thoughts.**
- **All lowercase is deliberate.** Apple's guidelines ask for title case in menus and buttons. We chose lowercase, knowingly, for everything we draw.

## 8. Motion

**Soft and lifelike, never bouncy.**
- tälli breathes slowly when idle, swells gently with your voice, and fades in and out instead of popping.
- **The dots carry status, so words are the exception:**

  | State | What the dots do |
  |---|---|
  | listening | pulse with your voice |
  | you pause | drift slowly, like an "äh" |
  | saving | settle into a blink |
  | logo / icon | may blink once on hover or launch |

- Saving is a small settle. No confetti, no wiggle, no celebration.
- Switching views (⌘1–⌘4) is a quick crossfade. Space drifts slowly.
- Reduce Motion makes tälli a still face. Reduce Transparency removes glass.

## 9. Voice

**Simple, clean, no over-excitement.** Calm sentences. The playfulness lives in motion and in tälli, not in the words.

### Rules

1. **Lowercase.** Everything tällmi writes is lowercase: buttons, menus we own, commands, tabs, window titles, tälli's lines, errors. Sentences still end with a full stop.

   Three things are never lowercased:
   - your own thoughts, which show exactly as written (the optional "all lowercase" display setting is off by default)
   - proper nouns from outside: Apple Notes, System Settings, people's names
   - what macOS draws itself

2. **English first.** English is the default UI language and the source of every string. Translations come later and follow the same rules. You can speak and write in any language or mix.
3. **du, not Sie**, in German translations.
4. **Who says "i".** Only tälli speaks in the first person. The rest of tällmi speaks neutrally and never says "i".
5. **No slop** ([ADR 0006](decisions/0006-no-slop.md)). tälli never comments on, interprets or advises about what you said.
6. **Never** use "!", emoji, "successfully", "please", "oops", "awesome", "simply" or "just".

### Patterns

| Situation | Pattern | Example |
|---|---|---|
| error | what failed, then what you can do; no apology, no codes | `couldn't save the thought. your text is still here, so try again.` |
| confirmation | past tense, one or two words | `saved.` · `moved to trash.` · `restored.` |
| destructive button | names the action, never "ok" | `delete for good` / `cancel` |
| empty state | one calm line | `no thoughts yet.` |
| command | verb + object | `new thought` · `delete thought` · `show flow` |
| setting | plain phrase, no jargon | `keep recordings for 30 days` |

### tälli's lines

| Moment | Line |
|---|---|
| appears, recording | the dots pulse; `listening …` only where a word is needed |
| typing instead | placeholder `or type …` |
| saved | `saved.` (click to open the thought) |
| Esc | `discarded.` |
| no microphone access | `i can't hear you. allow the microphone in system settings.` |
| invitation (opt-in, editable, ADR 0006) | `anything you want to keep?` |

### Do / don't

| Do | Don't |
|---|---|
| `saved.` | `Your thought was saved successfully!` |
| `couldn't open the thought. try again.` | `Oops! Something went wrong (error 512).` |
| `no thoughts yet.` | `Nothing here. Start journaling today! ✨` |
| `anything you want to keep?` | `You seem stressed today. Want to talk about it?` |
| `open tällmi` | `Open Archive` |

## 10. Terminology

Domain terms stay in code and docs. Users see the UI word. If a term has no UI word, it is never shown.

| Domain term | UI word (EN) | Note |
|---|---|---|
| Entry | **thought** | Dreams and imports are thoughts too ("a thought from apple notes"). |
| Text | (the thought itself) | |
| Transcript | **transcript** | |
| Recording | **recording** | |
| Source | **spoken** · **typed** · **from apple notes** … | shown as a value, not a label |
| Archive | (not shown) | The window is tällmi. Privacy settings say "where your thoughts are stored". |
| Retention | `keep recordings for …` | a setting, not a noun |
| Trash | **trash** | Emptying it moves thoughts on to the macOS Trash. |
| Recovery Key | **recovery key** | |
| Fragment | **passage** | |
| Atom | **point** | |
| Mention | **mention** | |
| Concept | no umbrella word: **people · places · topics · feelings** (by kind) | "theme" only if one word is unavoidable |
| Concept kind | the kind's name | |
| Link | **connection** | |
| Cluster | **constellation** | |
| Vocabulary | **spellings** | |
| Curation, Role, Model, Engine, Assignment, Seed | (not shown) | The voice tab may name a model the user picks. |
| Capture | (not shown) | You just call tälli. |
| Explore | (not shown) | The window is tällmi. |
| Companion | **tälli** | |
| Command | the command's own name | The ⌘K placeholder is `search or run a command …`. |

### Views (⌘1–⌘4)

| Key | View | What it is |
|---|---|---|
| ⌘1 | **stack** (provisional) | the list: find, filter, edit single thoughts |
| ⌘2 | **flow** | every thought as one long-form note you scroll through |
| ⌘3 | **time** | zoomable time axis |
| ⌘4 | **space** | the 3D world of your thoughts and constellations |

A thought exists in space, in time and in a flow.

### Settings tabs

**general · tälli · spellings · shortcuts · privacy · voice · other apps**

| Tab | Holds |
|---|---|
| general | appearance, menu bar icon |
| tälli | hotkey, invitations, look |
| spellings | names, use contacts |
| shortcuts | every command's shortcut |
| privacy | where thoughts are stored, encryption, recovery key, keep recordings |
| voice | speech and language models, downloads |
| other apps | the local MCP server: "let ai apps on this mac read your thoughts" |
