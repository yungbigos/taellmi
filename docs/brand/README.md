# brand assets

The rules and decisions are in [../brand.md](../brand.md). This folder holds the files.

| File | What |
|---|---|
| [tokens.json](tokens.json) | Every colour, gradient, type size, motion timing, easing curve and haptic. The app ships an identical copy as `Packages/TaellmiKit/Sources/Config/Resources/Seeds/brand.json`; change both together (a test fails if they differ), and bump `version` so Macs that already have tällmi pick up the change (a test pins each version to its content). |
| [logo/wordmark-light.svg](logo/wordmark-light.svg), [logo/wordmark-dark.svg](logo/wordmark-dark.svg) | The soft eyes wordmark `tällmi`, for light and dark backgrounds. |
| [logo/mark-light.svg](logo/mark-light.svg), [logo/mark-dark.svg](logo/mark-dark.svg) | The ä alone, flat ink with pink dots. |
| [logo/talli.svg](logo/talli.svg) | tälli in its body material (G1, key + bounce light), on a transparent background. |
| [banner/banner-light.svg](banner/banner-light.svg), [banner/banner-dark.svg](banner/banner-dark.svg) | The banner, 1280 × 400: the wordmark and `think out loud.` on mist (light) or the night ground (dark), with tälli peeking up from the bottom edge. |
| [banner/banner.png](banner/banner.png) | The night banner at 2× (2560 × 800), the image at the top of the repo's README. Render it from the SVG with `rsvg-convert -w 2560 -o docs/brand/banner/banner.png docs/brand/banner/banner-dark.svg` (Homebrew `librsvg`). |
| [icon/app-icon.svg](icon/app-icon.svg) | The "peek" app icon, 1024 × 1024, with a preview squircle mask. |
| [icon/app-icon-fullbleed.svg](icon/app-icon-fullbleed.svg) | The same icon without a mask, as the source for Icon Composer, which adds the macOS shape and glass. |
| [prototype.html](prototype.html) | The live reference: tälli's states, entrances, lighting and the icon in motion. Open it in a browser (it loads Funnel from Google Fonts; the app itself never does). |
| [make_svgs.py](make_svgs.py) | Regenerates the SVGs from `tokens.json` and the Funnel Display font. |

All letter shapes are outlined from **Funnel Display 700** (the banner's tagline: 500; SIL Open Font License 1.1, © 2024 The Funnel Project Authors), so the SVGs need no installed font. To regenerate after changing a token:

```bash
python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install fonttools
/tmp/fontenv/bin/python docs/brand/make_svgs.py App/Fonts/FunnelDisplay-Variable.ttf docs/brand docs/brand/tokens.json
```

The font file is the one the app bundles; it comes from `github.com/google/fonts`, folder `ofl/funneldisplay`.
