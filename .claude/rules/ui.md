---
paths:
  - "**/Sources/Features/**"
  - "App/**"
---
# UI rules (SwiftUI)

- Features use default MainActor isolation.
- **Reusable building blocks, one place each.** Anything that appears in more than one place is one component in `Sources/Features/Components/`.
  - **tälli is only ever drawn through `TalliView(mood:)`.** Never draw the character elsewhere. A new look or skin changes `TalliView` only.
  - Brand values (colours, type, motion timings) come from shared tokens, not literals in views. Once the design work lands they live in config.
  - Before writing a new view, look for an existing component to reuse or extend.
- Views are thin. Logic lives in `@Observable` view models, which get their dependencies via `init`.
- View models are unit-tested with fakes. Key screens get snapshot tests (swift-snapshot-testing) with a pinned scale and appearance.
- **Performance:**
  - No work in `body`.
  - Use `LazyVStack`/`List` for long lists.
  - Use `Canvas` or Metal for anything with hundreds of drawn elements.
  - Use `TimelineView` for animation.
- **Never block the main actor** on database, file or ML work.
- **Text:** user-facing strings go in a String Catalog. German first, then English.
- **Accessibility:** every control has a label. Respect Reduce Motion for animated graphics.
