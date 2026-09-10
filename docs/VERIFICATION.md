# Verification

## Current evidence and incident

CPU behavioral checks pass locally; strict Swift 6 compilation has passed. Consult CI for the committed revision and both runner architectures. These checks do not establish smooth presentation or physical hardware compatibility.

During development on 2026-09-10, the owner reported repeated completely pink screens. macOS recorded WindowServer watchdog timeouts during that testing period. The exact cause is not yet established. A visible diagnostic returned zero GPU completions/presentations with hundreds of skipped submissions. That run **failed**. No raw crash logs or screen contents are included here.

All DuoLid processes were stopped. Full-screen testing is suspended on the owner's working desktop. The implementation now uses an AppKit display link, command-buffer-scheduled presentation, two pending frames, a first-frame completion/presentation barrier, a watchdog, a persistent interrupted-session marker, and awaited surface retirement. These changes have not yet proven the incident resolved. [Acceptance remains blocked](release/acceptance.json).

## Safe source and package checks

```sh
swift test -c release -Xswiftc -warnings-as-errors
bash scripts/build.sh development
python3 scripts/verify-bundle.py dist/development/DuoLid.app development
open dist/development/DuoLid.app --args --settings-only
```

Tests cover sensor decoding, quintic progress, anchored projection, top-to-bottom coverage, spring timing and reversal, preparation expiry, pause, latch hysteresis, sound decoding, settings recovery/migration, capability/cadence policy, callback order, missing presentation, and overlapping interruptions. No test plays sound or creates a desktop overlay.

`--diagnose` reads technical sensor/display/permission/graphics metadata. `--render-check` uses synthetic offscreen GPU content through the production pipeline and writes synthetic artifacts. It is a GPU test, not a presentation or capture benchmark. Visible presentation checks require explicit opt-in and a designated test Mac.

## Required beta gates

| Area | Acceptance |
| --- | --- |
| Presentation | Thirty seconds each synthetic and moving live desktop at 60 and 120 Hz where supported. After warmup, fewer than 1% missed slots and p95 interval within 1.25× frame budget. Sort real presented timestamps; no-presented-frame runs fail. |
| Visual quality | Full-resolution text, bright lines, dark gradients, multiple angles, slow motion/reversals, all styles and glow extremes. No blocks, abrupt blur steps, ghosting, or hard halo boundaries. |
| Ordinary use | Above the start angle after preparation expiry: no overlay, capture stream, or desktop rendering clock. Window dragging/video playback unaffected. |
| Recovery | Repeated folds, pause/Esc, sleep/wake, lock/unlock, Spaces, fullscreen apps, external displays, mirroring, permission revocation, sensor loss, display resolution/device changes. No stuck overlay. |
| Native UI | Keyboard focus/navigation, numeric input, smallest window, VoiceOver labels/order, light/dark, increased contrast, Reduce Motion. |
| Persistence/audio | Existing preferences survive upgrade; invalid individual fields recover. One opening sound per appropriate cycle; respect disabled sound, app volume and system mute. |
| Installation | Browser-downloaded quarantined DMG; Gatekeeper accepted; offline launch with stapled tickets; first screen grant. |
| Updates | Signed beta/stable channel selection; preference and permission identity survive an update. Tampered archive/feed rejection and interrupted-download recovery. |

Record summaries and technical timing JSON under `docs/release/` only after inspecting for private data. Update `acceptance.json` with a tested commit and actual evidence. Do not clear a blocker merely because the app compiles. Stable additionally needs the physical [hardware matrix](COMPATIBILITY.md).

Use Instruments **Metal System Trace** on the designated test machine if presentation deadlines still fail. Compare capture arrival, CPU encoding, GPU queue delay/execution, and actual presentation separately. A short GPU execution time alone does not demonstrate display smoothness.
