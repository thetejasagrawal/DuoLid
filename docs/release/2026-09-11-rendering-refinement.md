# Rendering refinement — September 11, 2026

Source: `b9e5d177900e8c8c4325e7a03ca55ffd180f499b`. Both architectures passed [strict Swift 6 tests and universal development packaging](https://github.com/thetejasagrawal/DuoLid/actions/runs/34570649251). A clean local Developer ID build also passed architecture, macOS 14 target, nested-signature, compiled-shader, updater-policy, and matching-symbol verification.

## What changed

The display pool now has three surfaces while GPU submissions remain limited to two. Continuous frames use `present(_:afterMinimumDuration:)` with the selected cadence; animation still samples the display link's target timestamp. This removed the frequent short/long presentation pairs seen with target-time presentation alone.

Narrow blur was the remaining repeatable expensive section. Earlier native-resolution benchmarks started at 20% progress and missed it. The expanded benchmark covers sigma 0.57 through 57. Before restricting work to the visible sweep, narrow-blur samples took roughly 10–16 ms on this Mac.

Gaussian output is now limited to rows reached by the top-to-bottom sweep, including a bilinear filtering margin. The source and final image stay at native resolution. Halo sampling follows the same sweep and uses the sharp source below it, so it cannot read stale, uncomputed blur rows. Broad blur uses a filtered 2× reduction starting at sigma 4. Both narrow and broad pipelines are prepared offscreen before acquiring the first display surface, with a bounded wait and fenced cleanup on failure.

The diagnostic now reports why it stopped. One earlier long run was explicitly interrupted by window occlusion, which macOS can stop presenting. Timing windows now remain floating and dismissible. Live checks include a moving synthetic text/edge window through ScreenCaptureKit while excluding the rendered diagnostic output. They do not save screen images or recordings.

An automatic cadence callback also checks that its rate is still current before changing capture settings, so a later user or Low Power change takes precedence.

## Visual and GPU checks

- Maximum difference from the full-resolution Gaussian reference: **1/255** across seven positions, including the resolution transition.
- Maximum difference during alternating deep/shallow folds: **1/255**, across all three styles with maximum glow and bleed. The reference computes every row.
- The isolated bright-line test has a maximum adjacent step of **1/255**; the open frame stays unchanged and the bottom remains sharp until reached by the sweep.
- Expanded native 3456×2234 benchmark: **3.67 ms median, 5.16 ms maximum** across 36 measured samples covering narrow and broad blur. These are GPU execution measurements, separate from displayed-frame acceptance.

## Windowed presentation

Current MacBookPro18,1, macOS 26.6.2; native 3456×2234 GPU workload in a 960×620 window. Default Duo style, animated angle reversals, colorful glow enabled. The existing **0.25-second** presentation warmup and acceptance thresholds are unchanged. Frames are counted from actual drawable presentation callbacks, sorted by timestamp. Every recorded run uses an external process timeout and checks awaited GPU retirement.

| Input | Target | Requested run | Presented fps | p95 interval | Missed deadlines | Result |
| --- | --- | --- | --- | --- | --- | --- |
| Synthetic | 60 fps | 30 s | 59.82 | 16.67 ms | 0.44% | Passed |
| Synthetic | 120 fps | 30 s | 119.73 | 8.33 ms | 0.22% | Passed |
| Moving live capture | 60 fps | Pending | — | — | — | Pending |
| Moving live capture | 120 fps | Pending | — | — | — | Pending |

Both synthetic runs completed normally and drained all submitted work, with no GPU failures. GPU work averaged 2.08 ms at 60 fps and 2.00 ms at 120 fps. Compact technical reports are retained for [60 fps](2026-09-11-timing/synthetic-60.json) and [120 fps](2026-09-11-timing/synthetic-120.json). Short five-second checks also passed at both 60 and 120 fps before increasing the duration.

These windowed results do not establish full-screen recovery, the resolution of the earlier pink-screen incident, additional hardware compatibility, or notarized installation/update acceptance. Full-screen testing remains suspended on the owner's working desktop. Earlier failures remain documented in the [initial windowed report](2026-09-11-windowed-checks.md); release status is tracked in [acceptance.json](acceptance.json).

## Distribution

At the owner's request, the landing page and Pages workflow were removed and GitHub Pages was disabled. The repository README now contains the app icon, native screenshots, synthetic demonstration, setup, compatibility, customization, privacy, and release status. Its versioned download button is generated from `updates/release.json` only after verified release assets exist. Sparkle's signed feed will be served directly from the repository's `updates/appcast.xml` over HTTPS.

The `DuoLid-notary` Keychain profile is still required before notarization can proceed. No unsigned or unnotarized binary has been advertised as a verified release, and the installed `/Applications/DuoLid.app` has not been replaced during these checks.
