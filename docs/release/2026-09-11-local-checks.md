# Local checks — September 11, 2026

These are implementation checks, not release acceptance. The WindowServer incident and live presentation path remain unverified.

- Swift 6 release compilation with warnings treated as errors: passed. All 32 CPU behavioral tests passed.
- Universal development packaging: arm64 and x86_64, macOS 14 deployment targets, framework paths, bundled resources and nested signatures passed static verification.
- Offscreen production renderer: open pixels unchanged; isolated Gaussian highlight maximum adjacent step 1/255; Gaussian reference difference 1/255 across five positions; twelve style/palette combinations exercised. Native 3456×2234 GPU execution across 15 frames had median 3.43 ms and maximum 7.38 ms. This is GPU execution, **not** displayed frame rate or capture performance.
- Presentation diagnostic without explicit visible-test opt-in: exited 64 and created no window.
- Native UI in graphics-disabled review mode: initial focus stayed on the window; out-of-range angle input clamped; malformed `62..5` input preserved the previous setting; entering a valid angle cleared feedback. The main controls remained reachable at the minimum window size. Toolbar labels for both enabled and paused states fit with balanced outer padding and content-based sizing.
- Website: desktop and 390-pixel mobile views had no horizontal overflow. Images loaded; manual play and pause worked; the browser reported no console errors. The four-second video uses 240 precomputed synthetic frames from the production renderer, with no captured desktop content. It is an appearance demonstration, not a live smoothness measurement.
- Sparkle 2.9.6 generated a signed local development archive/feed. Public-key verification accepted both. An edited feed and a one-byte archive corruption were rejected. These fixtures stayed in ignored local build output and were not published. Actual installation, update relaunch, and interrupted-download recovery remain pending.
- Shell syntax, Python compilation, JavaScript syntax, website asset/link checks, and whitespace checks passed.

No full-screen or visible Metal presentation diagnostic was run after the owner requested stopping disruptive tests. No physical Intel or additional MacBook validation is implied. VoiceOver, increased contrast, system Reduce Motion, sleep/session/display recovery, Gatekeeper/notarization and quarantined installation still require recorded acceptance.
