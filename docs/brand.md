# tällmi — brand book

Decided with the owner on 2026-10-20. This is the source of truth for how tällmi looks, moves and talks. Agents read it before writing any UI text or visual. Domain terms live in [GLOSSARY.md](../GLOSSARY.md); this file maps them to the words users see.

Visual identity (logo, colour values, type scale, tälli's look and motion) decided on 2026-10-20. The exact numbers live in [brand/tokens.json](brand/tokens.json); the app ships the same file as the seed `Seeds/brand.json` (setting `brand.tokens`, a test keeps both identical) and reads it through config, never from Swift. In the app, views use `.brandStyle(_:)`, `.brandFont("…")`, `.brandForeground(_:)`, `.brandSurface(_:)`, `.brandFill(_:)` and `TalliView(mood:entrance:)`; tälli's behaviour is `TalliMotion`. All of them live in `Features/Components`. A live reference is in [brand/prototype.html](brand/prototype.html).

**Still open, not decided here:**
- German and other translations
- a better name for the list view than "stack"
- sound design (later, opt-in)

## 1. The idea

**ä is the sound of thinking.** In German, "äh" is the "uh" you say while you think. tällmi is built around it:
- You don't need to be precise. Say it the way it comes: unfinished, hesitant, German and English mixed.
- tällmi keeps it and finds it again later.
- **Messy is good and works.**

The promise is **finding and understanding**, never rewriting.
- Your words stay exactly as you said or typed them ([ADR 0006](decisions/0006-no-slop.md), and the rule that the user's Text is sacred).
- A one-sentence summary sits under longer thoughts (ADR 0012). It is only ever an extra next to your thought: made on this Mac, marked as generated, editable, and never replacing the original. Polished versions may come later, made only when you ask.

**Tagline:** `think out loud.`
**The wink:** `äh included.`, always with the explainer in small type: *(äh: german for "uh", the sound of thinking.)*
- Use the tagline for the main line: app icon tooltip, website header, first launch.
- Use the wink for the subline: first launch, website, stickers.

## 2. Names

| Name | What it is | Rules |
|---|---|---|
| **tällmi** | the app | Always lowercase, always with ä, even at the start of a sentence. Never "Tällmi", "Tellmi" or "Taellmi". `taellmi` appears only in identifiers (bundle id, paths). |
| **tälli** | the companion you call with the hotkey | Same rules. tälli is a character, not the app. Never use one name for the other. |

The main window has no name of its own: it is **tällmi**. The menu item is **open tällmi**. The window title shows the current view.

## 3. Logo

- **The mark is the ä with its two dots. The dots are tälli's eyes.** The letter and the dots belong together.
- **Wordmark (decided):** `tällmi` in lowercase on Funnel Display 700, **softened** (a round-joined outline of 6 % of the size, so it matches tälli's body), in ink. The ä dots are larger and a little closer than a normal umlaut, so the a becomes a face; they are pink. The i keeps an ink dot. In animated uses the dots may blink or drift. A crisp version was rejected: it reads like any software company.
- **App icon (decided): "peek".** tälli itself, on a night-blue ground: the softened ä fills the tile and is cut off by the bottom edge, its pink eyes look up at you. No white, no light blue. The Dock icon is still; it may blink once at launch.
- Files: [brand/logo/](brand/logo/).
- **Never:**
  - capitals
  - an "ae" spelling
  - a microphone, speech bubble or waveform as the logo (generic voice-memo clichés)
- Drafts come later as a visual design artifact.

## 4. Avatar (tälli)

The brief for the character work in issue #7:
- **tälli is the living ä** ([ADR 0009](decisions/0009-talli-is-the-living-a.md)): the letter and the creature are one organism with one shape language. Its body is the Funnel Display "a", softened (slightly inflated, rounder ends); its eyes are the two dots.
- no limbs
- **two dot eyes, the same dots as the logo.** The dots do everything: lift, squash, stretch, glance. Rarely, one dot stretches into a short arc for a raised brow.
- **the mouth is the a's lower counter.** It opens only when tälli says something.
- when tälli thinks, the ä grows letters: äh → ähh → ähm → ähmmm, and folds them back when done
- **body: G1 blue with "key + bounce" light**: six gradient steps, a soft tint (never white) from the top left, and light bouncing back into the bottom right so it never sinks into night
- thumbnail-sized, beside the spot where you called it
- no gender, no age: a small creature, not a person and not a pet breed

## 5. Colour

| Token | Role |
|---|---|
| **ink** | deep night blue: dark surfaces, and the wordmark on light backgrounds |
| **blue** | clear mid blue: the app's accent colour (controls, focus, selection) |
| **mist** | pale sky blue: quiet fills, tälli's light side |
| **pink** | **only for the dots**: tälli's eyes, the ä in the logo, the listening pulse. Nothing else is pink. |

Decided values (palette "G1 deep sea"), with contrast against the page:

| Token | Light | Dark | Check |
|---|---|---|---|
| paper | `#FFFFFF` | `#0A1230` (night) | |
| ink | `#0C1638` | `#E7ECF8` | text 17.7 / 15.5 : 1 |
| blue | `#2852D2` | `#7398FF` | text 6.5 / 6.7 : 1. Labels on blue: white in light, night in dark (white on light-blue is only 2.7). |
| mist | `#DCE4F5` | `#1A2850` | fill only; ink on mist 13.9 / 12.1 : 1 |
| pink | `#F0397C` | `#FF6A9C` | dots only, graphic 3.8 / 6.8 : 1 |
| quiet | `#586282` | `#98A3C3` | secondary text 6.0 / 7.3 : 1 |

tälli's body and the icon's night ground are gradients, listed in [brand/tokens.json](brand/tokens.json).

- Everything else follows macOS: light and dark mode, system greys.
- The old peach-pink-indigo orb gradient is retired.
- The values live as config tokens (config first), not in Swift.

## 6. Type

**One family:**
- **Funnel Display** for the wordmark, view titles and big moments.
- **Funnel Sans**, with its italic, for everything else tällmi draws: lists, your thoughts, ⌘K, tälli's bubble, the contents of settings.

Licence and fallback:
- Both are OFL (NORD ID, Kristian Möller; on Google Fonts since 2024), variable weight, and cover Latin-extended.
- Fallback if Funnel disappoints in the real app: **Bricolage Grotesque** (OFL, optical sizes).

Rules:
- Parts that macOS draws stay in SF Pro: menu bar menus, system alerts, file pickers. We don't fight that.
- Text follows the macOS text-size setting. No fixed point sizes: every size is a multiple of the macOS body style (13 pt at default).

| Token | Face | Size × body | Use |
|---|---|---|---|
| display.moment | Display 600 | 4.6 | the one loud thing per screen (a month, a constellation) |
| display.title | Display 600 | 2.0 | view title |
| display.heading | Display 500 | 1.45 | section, constellation name |
| text.thought | Sans 400 | 1.15 (15 pt) | your thought, at reading size |
| text.body | Sans 400 | 1.0 | lists, settings, ⌘K |
| text.label | Sans 500 | 0.85 | date, source |
| text.whisper | Sans 400 italic | 0.77 | the small explainer |

- **One loud thing per screen**, and it is not too loud. Your own text is never animated, rotated or set in display type.
- Fonts are bundled with the app. Nothing loads from the network.

## 7. Style

- **The frame is native macOS 26:** Liquid Glass toolbar and a floating glass bar at the bottom, system controls, generous space, few lines, no custom chrome. There is no sidebar: the bar holds the filters of the view you are in, in glass islands (what to look at · in space, finding concepts · spoken / typed and trash). Search and new thought sit at the top right; search opens ⌘K, and flow and time have a month rail at the side (issues #53, #54).
- **What makes it unusual lives inside the views** (flow, time, space), never in the frame. The look is editorial: big display type, a lot of white space, asymmetry. It grows from calm to wild across the views:
  - **stack**: Apple Notes-clean.
  - **flow**: magazine spreads, asymmetric, a big date or topic.
  - **time**: words laid out along time, big years and months.
  - **space**: you fly through your words in 3D, like a graph made of words. Flat type on planes, with depth (sharp up close, fading and blurring far away), never extruded letters.
  - Wherever you are, a thought you focus turns flat, horizontal, at reading size and searchable.
- Paper first: the light look is the reference, and dark gets equal care.
- **Glass goes on navigation and controls, plus tälli's bubble. It never goes under your thoughts.**
- **See-through, softly.** tällmi's windows and panels let the desktop show through: a macOS material with a thin paper tint on top, so text keeps its contrast. Four surfaces, each a token in `surface`:

  | Surface | Where | How |
  |---|---|---|
  | window | lists, toolbar | material, paper tint 20 % (dark 25 %); toolbar, bottom bar and month rail float as glass |
  | reading | under your thoughts: the open thought, flow, time, the composer | see-through: the blurred desktop with a paper tint (28 % / 32 %), enough for reading; running on under the toolbar and the bottom bar; never the glass-shape effect behind text |
  | panel | menu bar panel, ⌘K, settings, recovery key, unlock | popover material, paper tint 20 % / 25 % |
  | bubble | tälli's bubble | Liquid Glass with a faint paper tint |

  Quiet fills on top (the live transcript box, the highlighted ⌘K row, search matches, marks on the time axis) are named tokens in `fill`; corner radii are in `shape`.
- **Space on a 4 pt grid.** Views use the named steps in `space.scale` (xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32 · xxxl 48), never their own numbers. Your text sits in a reading column of at most 680 pt.
- **flow is where the window opens** (setting `explore.start_view`).
- **stack keeps one line per thought**: what it says and when. The open thought shows only your text under one quiet line (day · time · spoken or typed · length). Its details (recording, transcript, spellings, and later people, places, topics and connections) live in the inspector on the right.
- **Accessibility wins over the look.** With Reduce Transparency every surface becomes solid paper. With Increase Contrast it becomes solid paper with a thin quiet outline, and the fills get stronger. Errors and warnings stay in the macOS red and orange.
- **All lowercase is deliberate.** Apple's guidelines ask for title case in menus and buttons. We chose lowercase, knowingly, for everything we draw.

## 8. Motion

**Alive, like an organism that thinks.** Soft and lifelike: one soft overshoot (about 4 %) is allowed where something arrives, never repeated bounces, wiggles or celebrations.
- tälli breathes slowly when idle and swells gently with your voice.
- **Coming alive:** at the cursor tälli **rises** a little and grows in (0.85 s); when the window launches it **rolls in** from the side and settles upright (1.1 s). In both, the eyes open last. Leaving: the eyes close, then it sinks a little and fades (0.28 s).
- **It sits still and watches you.** tälli appears beside the cursor and stays there; it never follows the cursor. Drag tälli to move it. While you move the cursor its eyes follow it, and they stop once the cursor rests. As the cursor comes close it perks up: a little bigger, eyes a little wider. Click it and it squishes, eyes shut, and springs back; three quick pokes and it squeezes its eyes shut for a moment. With nothing happening for a while (and only when it isn't listening) its lids droop and its breath slows until you move again. Click anywhere in the bubble to type.
- **It reacts to stimuli, even when idle:** it swells with your voice; it thinks visibly while the app works on your thoughts; it is livelier in the morning and slower and sleepier at night (the Mac's clock only, nothing recorded). Camera and device motion come later (#31).
- When tälli is hidden, the organism lives quietly in the menu bar dots and the ä in the window. tälli itself still never appears unasked.
- Slow ambient life inside the views (space and time drift, new connections glow in softly), never under your text.
- **The dots carry status, so words are the exception:**

  | State | What the dots do |
  |---|---|
  | listening | pulse with your voice |
  | you pause | drift slowly and wait, like an "äh" |
  | tälli is thinking | look up and to the side; the ä grows "hmmm" letters |
  | saving | settle into a blink; the mouth opens for "saved." |
  | you move the cursor | follow it; widen as it comes close |
  | you poke tälli | shut while it squishes; squeeze shut after three quick pokes |
  | nothing happens for a while | lids droop, looking down a little |
  | logo / icon | may blink once on hover or launch |

- Saving is a small settle, plus a level-change haptic on the trackpad. No confetti, no wiggle, no celebration. Haptics only for moments you caused.
- Switching views (⌘1–⌘4) is a quick crossfade. Space drifts slowly.
- Reduce Motion makes tälli a still face: entrances become fades, no breathing, swell, drift, blink, watching the cursor or perking up; a poke dims the dots for a moment instead of squishing. Status shows as the dots brightening with your voice and the thinking letters fading in place. Reduce Transparency removes glass.
- Every timing and curve is a named token in [brand/tokens.json](brand/tokens.json).

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
