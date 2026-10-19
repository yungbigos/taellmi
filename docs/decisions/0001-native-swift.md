# 0001 — Native Swift/SwiftUI, no cross-platform framework

- **Status:** accepted (2026-10-19)
- **Context:** The app must be local-only, light on resources and fast, and use Apple's on-device ML: the Neural Engine via Core ML, SpeechAnalyzer, Foundation Models and MLX. The owner doesn't write Swift; coding agents do.
- **Decision:** Native Swift 6 + SwiftUI (AppKit where needed). Graphics are native too: Canvas, Metal shaders, RealityKit.
- **Consequences:**
  - Idle memory is in the tens of MB, and Apple APIs are called directly.
  - The App Sandbox can prove the app is offline.
  - The app is Mac and iPhone only.
  - Tauri remains the fallback if Windows ever matters.
  - Details are in [research](../research/2026-10-stack.md).
