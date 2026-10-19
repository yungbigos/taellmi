# 0009 — tälli is the living ä, drawn in 2D from the font, not a 3D character

- **Status:** accepted (2026-10-20). Supersedes the recommendation in [research/2026-10-talli-character.md](../research/2026-10-talli-character.md) (3D, Quaternius base, RealityKit).

## Context

The character research recommended a 3D path: adapt a CC0 Quaternius monster in Blender, export USDZ, render it in RealityKit. While designing the visual identity, the owner decided that everything evolves around the ä and its two dots: the logo, the companion and the app should feel like one organism that thinks.

## Decision

- **tälli is the ä itself.** Its body is the Funnel Display "a", softened by a round-joined outline; its eyes are the two dots of the logo; its mouth is the a's lower counter. When it thinks, letters grow out of it ("ähmmm").
- **It is drawn in 2D from the font's glyph outline** with native drawing (SwiftUI and Core Text), in exactly one reusable component (`TalliView`). Gradients, lighting, sizes and every timing come from the brand tokens in config ([brand/tokens.json](../brand/tokens.json)).
- **No 3D model, no Rive, no Lottie** for tälli. The Quaternius/RealityKit spike is dropped. 3D stays possible for the space view, which is a separate concern.

## Why

- One shape language: the logo, the icon and the companion are the same drawing, so the logo can come alive at any moment.
- It is ours by construction (an OFL font we may modify, plus our own drawing), with no asset licence to track.
- 2D vector drawing is far lighter than a live RealityKit scene next to the cursor (non-negotiable 5), and needs no new dependency.

## Consequences

- The skin is no longer a USDZ file. A "skin" in config is a set of tokens (glyph, material, motion).
- Funnel Display must be bundled with the app, because tälli's body comes from its outlines.
- If Funnel is ever replaced by the fallback (Bricolage Grotesque), tälli's body changes with it.
