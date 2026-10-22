# website

The marketing site for tällmi: get people to try it or help build it. It is not built yet. This folder holds the design study that comes first. The framework and the real pages follow once a direction is picked.

| Path | What |
|---|---|
| [study/](study/) | The design study: story, word options, three look-and-feel directions (A paper, B night, C space), the call, demo pieces. Pick options; the page collects them for pasting back. |
| [study/b/](study/b/) | The picked direction (B night) as a whole page. The spoken thought flows into a structure of words as you scroll ([flow.js](study/b/flow.js)). |
| [wordmark.js](wordmark.js) | The wordmark as inline SVG, shared by every page. |
| [talli.js](talli.js) | tälli for the web. Painter and behaviour from [docs/brand/prototype.html](../docs/brand/prototype.html), every number from [docs/brand/tokens.json](../docs/brand/tokens.json). |
| [fonts/](fonts/) | Copies of `App/Fonts` (SIL Open Font License), self-hosted so the page loads nothing from anyone else. |
| [serve.ts](serve.ts) | Local preview server on 127.0.0.1, with caching off. TypeScript with no dependencies; Node 23.6+ runs it directly. |

Open the study (from the repo root):

```bash
npm --prefix website run dev
```

Then go to `http://localhost:4173/study/`. The study's scripts are plain JavaScript so the browser runs them without a build step; the real site will be TypeScript.

The brand rules in [docs/brand.md](../docs/brand.md) apply here too: lowercase voice, pink only for the dots, Funnel Display and Funnel Sans, paper first.
