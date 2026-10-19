# brand assets

The rules and decisions are in [../brand.md](../brand.md). This folder holds the files.

| File | What |
|---|---|
| [tokens.json](tokens.json) | Every colour, gradient, type size, motion timing, easing curve and haptic. The app must load these through config (seed JSON), not hard-code them. |
| [logo/wordmark-light.svg](logo/wordmark-light.svg), [logo/wordmark-dark.svg](logo/wordmark-dark.svg) | The soft eyes wordmark `tällmi`, for light and dark backgrounds. |
| [logo/mark-light.svg](logo/mark-light.svg), [logo/mark-dark.svg](logo/mark-dark.svg) | The ä alone, flat ink with pink dots. |
| [logo/talli.svg](logo/talli.svg) | tälli in its body material (G1, key + bounce light), on a transparent background. |
| [icon/app-icon.svg](icon/app-icon.svg) | The "peek" app icon, 1024 × 1024, with a preview squircle mask. |
| [icon/app-icon-fullbleed.svg](icon/app-icon-fullbleed.svg) | The same icon without a mask, as the source for Icon Composer, which adds the macOS shape and glass. |
| [prototype.html](prototype.html) | The live reference: tälli's states, entrances, lighting and the icon in motion. Open it in a browser (it loads Funnel from Google Fonts; the app itself never does). |
| [make_svgs.py](make_svgs.py) | Regenerates the SVGs from `tokens.json` and the Funnel Display font. |

All letter shapes are outlined from **Funnel Display 700** (SIL Open Font License 1.1, © 2024 The Funnel Project Authors), so the SVGs need no installed font. To regenerate after changing a token:

```bash
python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install fonttools
/tmp/fontenv/bin/python docs/brand/make_svgs.py path/to/FunnelDisplay[wght].ttf docs/brand docs/brand/tokens.json
```

The font file comes from `github.com/google/fonts`, folder `ofl/funneldisplay`.
