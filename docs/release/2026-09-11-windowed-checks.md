# Controlled windowed checks — September 11, 2026

The owner authorized controlled windowed checks, starting at five seconds. Full-screen testing remains suspended. Both checks used the native 3456×2234 rendering workload in a 960×620 window on the current MacBook Pro, macOS 26.6.2, with synthetic input and a 60 fps target. Neither check captured the desktop.

| Source revision | Duration requested | GPU completions | Presented frames after warmup | Presented fps | p95 interval | Missed deadlines | Cleanup | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `a2cc2b3` | 5 s | 304 | 285 | 60.00 | 16.67 ms | 4.70% | Drained | Failed |
| `3645cb9` | 5 s | 301 | 283 | 58.65 | 25.00 ms | 8.14% | Drained | Failed |

The first run used immediate command-buffer presentation. The second scheduled presentation for the display link's animation target and added per-frame timing correlation. The scheduling change alone did not satisfy the release gate. These brief runs under changing desktop load do not establish a causal performance improvement or regression.

In the second run, every submitted GPU command completed successfully. The journal contains 296 actual presentation callbacks; five submitted frames lacked presentation callbacks, including the final two after the window was hidden. The gate excludes the initial 0.25 seconds of presented frames.

Detailed timings after an additional 0.5-second submission warmup:

| Stage | Median | p95 | Maximum |
| --- | --- | --- | --- |
| Drawable acquisition | 0.04 ms | 1.10 ms | 74.55 ms |
| CPU encoding | 0.18 ms | 0.67 ms | 2.21 ms |
| GPU queue wait | 0.21 ms | 0.52 ms | 64.92 ms |
| GPU execution | 5.11 ms | 8.67 ms | 10.61 ms |

Presentation intervals included 8.33 ms and 25 ms pairs as well as longer gaps. Several late presentations occurred even when GPU execution completed before the requested presentation time. The evidence identifies queue, drawable, and delivery delays; it does not yet establish their cause. Average fps or successful GPU execution cannot substitute for the failed presentation gate.

Both processes exited on their own with diagnostic status 2, within seven seconds, and left no DuoLid process running. The external process watchdog did not activate. No new WindowServer diagnostic report appeared during either check; the newest report remained the one from September 10 at 23:16. That observation does not establish that the previously reported pink-screen incident is resolved.

Longer, 120 fps, live-capture, and full-screen checks were not attempted. No smoothness or pink-screen acceptance flag was enabled. Raw technical timing journals remain in ignored local build output; no private screen contents or crash reports are published.

The timing journal is bounded and disabled during ordinary app use. Regression tests cover out-of-order callbacks, evicted entries, and failed GPU work without invented presentation timestamps. Both Apple silicon and Intel CI runners passed all 37 behavioral tests, strict Swift 6 compilation, universal development packaging, and source checks for `3645cb9`: [CI run](https://github.com/thetejasagrawal/DuoLid/actions/runs/34525493984).

## Offscreen profiling and cleanup

A subsequent Metal System Trace attempt targeted only the synthetic offscreen renderer, using a uniquely named local profiling copy to avoid an Instruments application-name ambiguity. It created no diagnostic window or desktop capture. The recorder reached its five-second limit but did not finish saving before the external 30-second timeout. The recorder was terminated and its remaining suspended probe process was removed. Exporting the incomplete trace failed with a missing-template error. This produced **no usable profiling evidence**; no graphics tests followed it.

Cleanup review found a separate conservative-retirement gap: an unavailable or failed Metal fence must return an undrained result. The renderer now releases its working resources only after a successfully completed fence; otherwise the existing surface-quarantine path retains them until process exit. This handles a failure case without claiming to explain the pink-screen incident.
