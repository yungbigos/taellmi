# tälli character: open-source bases and render pipeline

Date: 2026-10-19. Issue: #7. Status: **superseded by [ADR 0009](../decisions/0009-talli-is-the-living-a.md)** (2026-10-20): tälli is the living ä, drawn in 2D from the font. The 3D path below is not pursued for tälli.

Goal: a cute, custom companion character ("tälli") that is "truly ours", shipped as a config-selectable skin, with licences that allow modification and redistribution if the app is open-sourced.

Confidence key: **[V]** checked on the primary page this session. **[S]** secondary source only (blog, guide, forum). **[?]** not verified, check before relying on it.

## 1. Asset sources and licences

| Source | Licence | Commercial / modify / redistribute in an OSS app | Attribution | Rig and animation | Formats | Verdict |
|---|---|---|---|---|---|---|
| [Kenney](https://kenney.nl/support) | CC0 [V] ("public domain licensed (CC0)") | Commercial yes [V]. CC0 itself allows modify and redistribute; Kenney's page does not spell this out [V]. | Not required [V]. Don't use the Kenney logo [V]. | [Blocky Characters](https://opengameart.org/content/blocky-characters): 18 skins, 27 animations [S]. Animated Characters 2: 1 rig, 4 skins, 3 animations [S]. | FBX, OBJ, glTF | Safe. Style is blocky, not "cute round". |
| [Quaternius](https://quaternius.com/faq.html) | FAQ: "All models are under the CC0 License" [V]. Pack pages checked: [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) CC0 [V], [Cute Animated Monsters](https://quaternius.com/packs/cutemonsters.html) CC0 [V]. | Commercial yes, modification "in any way" yes [V]. OSS redistribution is covered by CC0 but the FAQ doesn't mention it [V]. | Not required, appreciated [V]. | UAL: universal humanoid rig, 120+ animations, built for retargeting [V]. Cute Monsters: 21 textured models, each animated, rigging not stated [V]. | FBX, GLB, OBJ, glTF, Blend (source tier) | **Best candidate.** One guide claims a newer "Quaternius Asset Licence (QAL v1.0)" that forbids redistributing the assets themselves [S]. I found no QAL text on quaternius.com, but **check the licence line on each pack at download time** and save a copy of the page. |
| [Poly Pizza](https://poly.pizza/) | Mixed per model: CC0 and CC-BY, some NC [S] | Only CC0 / CC-BY models are fine | CC-BY needs credit | Mostly static [?] | glTF/GLB | Filter to CC0 only. Aggregates Kenney and Quaternius. |
| [Sketchfab](https://help.sketchfab.com/en/articles/16152217) | Per model: CC0, CC-BY, CC-BY-SA, CC-BY-NC, CC-BY-ND [V] | ND forbids edits [V]. NC forbids commercial [V]. SA forces derivatives under the same licence [V]. | Required except CC0 [V] | Varies | glTF/USDZ download | Only CC0 or CC-BY. Skip SA, NC and ND. |
| [OpenGameArt](https://opengameart.org/) | Per item (CC0, CC-BY, CC-BY-SA, GPL, OGA-BY) [S] | Same per-item caveats | Varies | Varies | Varies | Fine for CC0 items, which are often mirrors of the above. |
| [Poly Haven](https://polyhaven.com/) | CC0 [S] | Yes | No | **No characters** (HDRIs, textures, props) | n/a | Not a character source. Useful for HDRIs and textures if we render in 3D. |
| [Mixamo](https://community.adobe.com/questions-696/mixamo-faq-licensing-royalties-ownership-eula-and-tos-589400) | Adobe custom terms | Use in a product is allowed, **redistributing the raw character/animation files is not** [S]. Training ML on it is excluded [S]. Derived-animation status is unclear [S]. | Not required [S] | Auto-rig plus a large animation library | FBX | **Avoid** for an open-source repo. Raw files in git would breach the terms. I found no current Adobe terms page, only 2022 community posts, so [?]. |
| Ready Player Me | n/a | n/a | n/a | n/a | n/a | **Dead.** Netflix acquired it in Dec 2025 and the public service went offline 2026-01-31 [S] ([Avatar SDK write-up](https://avatarsdk.com/blog/2026/08/31/avatar-platforms-2026-whos-alive-whos-gone/), competitor-authored). I did not find its original terms. |
| [VRoid Studio](https://vroid.com/en/studio) / [VRM 1.0](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm-1.0/README.md) | VRM is a glTF extension (`VRMC_vrm`, `.vrm` = renamed GLB) [V]. Licence is per model, in the `meta` block [V]. | Per-model flags (commercial use, modification, redistribution) are in `meta.md`, which I did not read [?]. VRoid's own terms page returned 403 [?]. | Per model | Humanoid bones and expressions (blend shapes), no animation clips [V] | VRM | Anime human avatars. Wrong fit for a small mascot. The expression system is a good model to copy. |
| Blender community rigs | Per rig (CC0, CC-BY, GPL) [?] | Per rig | Per rig | Often good | .blend | Only if CC0 or CC-BY. Not researched in depth. |
| [Blender itself](https://www.blender.org/about/license/) | GPL | "What you create with Blender is your sole property" [V]. GPL applies to Blender and published scripts, not your models [V]. | n/a | n/a | n/a | No licence problem for our output. Our own Blender scripts, if published, must be GPL-compatible [V]. |

**Not found:** I did not find a notable 2025–2026 CC0 cute-mascot generator beyond the sources above. The "2026 free rigged characters" guides ([Cinevva](https://app.cinevva.com/guides/game-assets-guide.html)) mostly list the same Kenney and Quaternius packs [S].

## 2. Render pipeline on macOS

### 3D: RealityKit

- Apple calls SceneKit **soft-deprecated**, in maintenance mode, and recommends RealityKit for new work. There is no plan to hard-deprecate it, and Apple promises notice first ([WWDC25 session 288](https://developer.apple.com/videos/play/wwdc2025/288), [migration guide](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit)) [V via search summary]. Don't build the skin on SceneKit.
- `RealityView` is the SwiftUI entry point. I could not read the page, so the macOS minimum is [?]. tällmi targets macOS 26, which is likely fine.
- Blender USD/USDZ export ([manual](https://docs.blender.org/manual/en/4.1/files/import_export/usd.html)): armatures and animation export. Shape keys export under "Rigging", and RealityKit loads them as `BlendShapeWeightsComponent` ([Apple forums, community answer](https://developer.apple.com/forums/thread/766484)) [S]. Whether skinned skeletal playback survives the round trip cleanly is **[?]**; the sources I found are outdated or unofficial. **Spike needed:** export one rigged Quaternius character to USDZ and play a clip in a `RealityView`.
- Input reaction: set the blend-shape weight or bone pose from the audio level in an update loop, and cross-fade between animation clips for idle, listening and saved. This is custom code either way. RealityKit has no state machine.
- Costs [?]: a transparent, cursor-following `RealityView` in a borderless panel needs measuring for GPU and idle power (non-negotiable 5, light on resources). Needs a prototype.

### 2.5D: Rive

- Rive's Apple runtime is open source under **MIT** (`Copyright (c) 2020 Rive`, [LICENSE](https://github.com/rive-app/rive-ios/blob/main/LICENSE)) [V]. Install via SwiftPM from `rive-app/rive-ios`. macOS 13.1+ [S].
- Two runtimes: the legacy `RiveViewModel` with state-machine inputs, and a **new Swift-first runtime** (`File`/`Worker`/`Rive`, [migration guide](https://rive.app/docs/runtimes/apple/migrating-from-legacy)) [S]. Rive marks state-machine **inputs as legacy and recommends data binding** ([inputs](https://rive.app/docs/runtimes/apple/inputs)) [S].
- Data binding is exactly our need ([docs](https://rive.app/docs/runtimes/apple/data-binding)) [V]: `NumberProperty` for voice level, `BoolProperty` for listening, `TriggerProperty` for saved. Setting values is cheap and applies on the next advance.
- Caveat: the **Rive editor and `.riv` format are Rive's product**. The editor is free to start but has paid plans [?], and Rive's terms on files made in the editor are [?]. Our character would depend on their tooling to edit. The runtime is MIT, so shipping is unaffected.
- `.riv` file size and CPU cost on macOS: not verified [?]. Rive is generally small and vector-based.

### 2.5D: Lottie

- [lottie-ios](https://github.com/airbnb/lottie-ios) is **Apache 2.0** [V]. Authoring is After Effects → Bodymovin, or LottieFiles tools [?].
- Lottie is a timeline player with no state machine. Voice-level reaction means scrubbing progress or swapping clips by hand. Weaker fit than Rive for interactive state.

### Comparison

| | RealityKit + USDZ | Rive | Lottie |
|---|---|---|---|
| Base assets available CC0 | Yes (Quaternius, Kenney) | **No**, 3D assets don't transfer. We draw it ourselves. | No |
| Reacts to voice level | Custom code (blend shapes or bone pose) | Native via data binding | Manual scrubbing |
| State handling | Hand-written | Built-in state machine | None |
| Tooling | Blender, free, GPL, output is ours | Rive editor (proprietary) | After Effects (paid) or LottieFiles |
| Runtime licence | System framework | MIT | Apache 2.0 |
| Cost / risk | Needs a perf spike, skeleton round trip [?] | Editor lock-in [?] | Limited interactivity |

## 3. Recommendation

**Primary path: 3D, Blender → USDZ → RealityKit, starting from a CC0 Quaternius base.** It is the only route where a CC0 base exists, which is what "start from an open-source asset, then adapt it" asks for.

**Candidates**

1. **Quaternius Cute Animated Monsters** (CC0, 21 models, textured and animated): closest to "small cute companion". Risk: the page doesn't say whether it is rigged [V], so we may have to rig it ourselves.
2. **Quaternius Universal Animation Library + Universal Base Characters** (CC0 for the UAL [V]; base-character licence not checked [?]): a clean, retargetable humanoid rig and 120+ clips. Better for animation reuse, wrong silhouette for a mascot, so it would be a source of animation clips for our own rig.
3. **Kenney Blocky Characters** (CC0): safest and simplest, 27 animations [S]. Fallback if the other two don't convert to USDZ cleanly.

**Make it ours, step by step**

1. **Spike, about half a day:** export candidate 1 to USDZ, load it in a `RealityView` in a transparent panel, drive one blend shape from a slider. Measure idle CPU/GPU. This settles the skeleton and performance unknowns above.
2. In Blender: sculpt a new body and head silhouette on top of the base, retopologise to a low poly count (target budget set after the spike), add our own eyes and mouth as shape keys (blink, listening, speaking, happy). Borrow VRM's expression naming for consistency.
3. Retexture from scratch (flat or toon palette), so no base texture survives.
4. Author our own five clips: idle, listening, speaking (driven by level), saved, discard. Don't ship retargeted base clips if we can avoid it.
5. Export USDZ, register it as a skin row in the seed JSON (`Config/Resources/Seeds/`) per the config-first rule. Code only knows the skin kind.
6. Keep the original pack licence file and a provenance note (pack, URL, date, licence text) next to the asset in the repo. CC0 doesn't require it, but it protects us if a pack's licence line changes.

**Backup path: Rive**, if the 3D spike shows poor idle power or a clunky pipeline. We would draw the character from scratch, which is more original but has no asset base. Fits the voice-level and saved states best.

**Avoid**

- Mixamo files in the repo (raw redistribution not allowed [S]).
- Ready Player Me (service is gone [S]).
- Sketchfab / Poly Pizza models under CC-BY-SA (share-alike would pull derivatives under the same licence), CC-BY-ND (no edits) and any NC licence.
- Any pack whose licence line isn't CC0 or CC-BY on the day we download it (see the QAL claim above).
- Building on SceneKit.
- CC-BY assets unless we accept an attribution screen. Workable, but CC0 avoids it.

## Open items

- Confirm the Quaternius QAL claim against quaternius.com (no text found [?]).
- Read the VRM `meta.md` and VRoid terms if VRM is ever used.
- Confirm the RealityView macOS minimum and skeletal USDZ playback in the spike.
- Read Rive's editor terms and plan limits if the backup path is taken.
- Run a "Tellmi" trademark check before release (see the app-name memory), unrelated to licences but relevant to a named mascot.
