# Local checks — September 11, 2026

These are implementation checks, not release acceptance. The WindowServer incident and live presentation path remain unverified.

- Swift 6 release compilation with warnings treated as errors: passed. The final suite has 34 CPU behavioral tests, including regression cases for stale permission hints after both grants and revocation.
- Universal development packaging: arm64 and x86_64, macOS 14 deployment targets, framework paths, bundled resources and nested signatures passed static verification.
- Offscreen production renderer: open pixels unchanged; isolated Gaussian highlight maximum adjacent step 1/255; Gaussian reference difference 1/255 across five positions; twelve style/palette combinations exercised. Native 3456×2234 GPU execution across 15 frames had median 3.43 ms and maximum 7.38 ms. This is GPU execution, **not** displayed frame rate or capture performance.
- Presentation diagnostic without explicit visible-test opt-in: exited 64 and created no window.
- Native UI in graphics-disabled review mode: initial focus stayed on the window; out-of-range angle input clamped; malformed `62..5` input preserved the previous setting; entering a valid angle cleared feedback. The main controls remained reachable at the minimum window size. Toolbar labels for both enabled and paused states fit with balanced outer padding and content-based sizing.
- Website: desktop and 390-pixel mobile views had no horizontal overflow. Images loaded; manual play and pause worked; the browser reported no console errors. The four-second video uses 240 precomputed synthetic frames from the production renderer, with no captured desktop content. It is an appearance demonstration, not a live smoothness measurement.
- Sparkle 2.9.6 generated a signed local development archive/feed. Public-key verification accepted both. An edited feed and a one-byte archive corruption were rejected. These fixtures stayed in ignored local build output and were not published. Actual installation, update relaunch, and interrupted-download recovery remain pending.
- Shell syntax, Python compilation, JavaScript syntax, website asset/link checks, and whitespace checks passed.

No full-screen or visible Metal presentation diagnostic was run after the owner requested stopping disruptive tests. No physical Intel or additional MacBook validation is implied. VoiceOver, increased contrast, system Reduce Motion, sleep/session/display recovery, Gatekeeper/notarization and quarantined installation still require recorded acceptance.

## Committed source and release-build evidence

- Source revision: `a2cc2b33cfa13d13a83f818fdc1bebd5f4f0a4c1`.
- [GitHub source checks](https://github.com/thetejasagrawal/DuoLid/actions/runs/34522480895): both `macos-15` and `macos-15-intel` passed strict tests, universal development packaging, script/site checks, and the visible-diagnostic opt-in guard. Older-SDK capture operations use explicit main-actor callback bridges. No concurrency checks were disabled.
- A clean Developer ID release build of that revision passed signature, hardened runtime, timestamp, architecture, macOS 14 target, compiled shader, Sparkle helper entitlement and resource checks. Matching backtrace dSYMs for both architecture UUIDs remain local. The executable contains no developer home or temporary-directory paths.
- The packaged renderer was checked offscreen at revision `255df54af34e58006dc1c8112f60691b0045420f`, using its compiled Metal library. Blur/reference checks passed again. Native 3456×2234 GPU execution measured median 5.06 ms, maximum 6.44 ms over 15 changing frames. The later change only extends preview failure handling; no shader or blur algorithm changed. These measurements still say nothing about live presentation cadence.
- All ten macOS icon representations were inspected. The website deployed successfully to [GitHub Pages](https://thetejasagrawal.github.io/DuoLid/), with preparation status and no binary download.
- No notarized candidate or GitHub binary release has been published. The `DuoLid-notary` credential profile is still required. The pink-screen incident remains unresolved by live testing.
