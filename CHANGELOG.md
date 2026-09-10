# Changelog

## 0.9.0-beta.1 — unreleased

- Top-to-bottom blur and a bottom-anchored folding desktop with independently adjustable soft edge bleed.
- Optional pastel corner glow, original opening sounds, and a configurable 62° start default.
- Native preview-and-controls workspace, localized numeric input, appearance and Reduce Motion settings.
- Automatic / 60 / 120 fps modes and the 30 fps Low Power option; settings migration preserves independent choices.
- Dedicated display-driven rendering, bounded pending work, retained capture surfaces, and explicit asynchronous cleanup.
- First-frame readiness requires both GPU success and actual presentation. Graphics stalls pause the effect; interrupted sessions remain latched until acknowledged.
- Settings-only launch, typed diagnostics, and explicit opt-in visible performance diagnostics.
- Universal macOS 14 build tooling, pinned Sparkle 2.9.6, local signing/notarization tools, and gated GitHub publishing.

**Release withheld:** the reported pink-screen/WindowServer incident and live presentation/installation acceptance remain open. No stable compatibility or smoothness claim is made from compiler tests alone.
