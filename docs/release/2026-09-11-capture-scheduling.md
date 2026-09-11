# Capture scheduling follow-up — September 11, 2026

The retained app source is `d406b9fe8e7d301b932711387183dec7e9e03925`. Rendering and capture match `cd6f9be`; the later changes add an unchanged-pixel capture baseline and improve diagnostic Escape registration. The scheduling experiments described below were reverted because they did not establish an improvement.

**The beta remains withheld.** These are controlled windowed checks on the current working Mac, not full-screen recovery acceptance. No installed application was replaced.

## Presented-frame evidence

MacBookPro18,1, macOS 26.6.2, native **3456×2234** input/output workload in a **960×620-point** window. The existing 0.25-second presentation warmup, fewer-than-1% missed-deadline requirement, and p95 limit of 1.25× the frame budget are unchanged. All rows completed normally, reported zero GPU failures, and drained their work. JSON links contain technical summaries only.

| Check | Source | Duration | Presented fps | p95 | Missed deadlines | Average GPU | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [Live capture, explicit buffer retirement](2026-09-11-timing/live-60-30s.json) | `3074b33` | 30 s | 59.13 | 16.67 ms | 2.668% | 3.27 ms | Failed |
| [Live capture, shared five-surface configuration](2026-09-11-timing/capture-pool-live-60-5s.json) | `cd6f9be` | 5 s | 57.82 | 25.00 ms | 7.000% | 1.82 ms | Failed |
| [Metal display-link experiment](2026-09-11-timing/metal-display-link-live-60-5s.json) | `4315f3f` | 5 s | 59.11 | 25.00 ms | 6.643% | 3.62 ms | Failed; reverted |
| [Higher display-clock request, 60 fps rendering](2026-09-11-timing/native-clock-live-60-5s.json) | `fc8242a` | 5 s | 58.90 | 25.00 ms | 9.968% | 5.28 ms | Failed; reverted |
| [Unchanged-pixel live capture baseline](2026-09-11-timing/capture-baseline-60-5s.json) | `0a4a5ae` | 5 s | 60.00 | 25.00 ms | 5.479% | 0.82 ms | Failed; not an effect qualification |
| [Final synthetic 60 fps](2026-09-11-timing/final-synthetic-60-30s.json) | `d406b9f` | 30 s | 59.88 | 16.67 ms | 0.551% | 3.08 ms | Passed |
| [Final synthetic 120 fps recheck](2026-09-11-timing/final-synthetic-120-5s.json) | `d406b9f` | 5 s | 118.71 | 8.33 ms | 1.071% | 4.74 ms | Failed; not extended |

Earlier 30-second synthetic runs at both rates passed on `b9e5d17`; see the [rendering refinement record](2026-09-11-rendering-refinement.md). That earlier 120 fps pass does not override the failed recheck. The latest acceptance record enables only the current 60 fps synthetic gate and strict source/build checks.

The capture baseline sends unchanged captured pixels through the same renderer and display path at zero effect progress. It removes steady-state Gaussian/folding work. Its failed presentation timing, despite sub-millisecond average GPU work, shows that removing the blur workload alone did not remove the observed jitter. It does **not** identify a specific OS defect or prove that all remaining delay is outside DuoLid. Desktop load and display-policy variation have not been isolated sufficiently to make that claim.

## Metal System Trace

A five-second trace attached to the exact diagnostic PID running `4315f3f`. The diagnostic was windowed and used the moving capture fixture. The recorder reached its time limit but did not finish saving within the external timeout. All child processes were then stopped. The recorded Apple Trace attachment was subsequently imported offline into a usable Metal System Trace document. No second visible run was needed for recovery.

The recovered trace contains GPU intervals, display-vsync events, displayed surfaces, and presented-handler events. Some modeled tables, including the compositor-interval table, were empty, so this is not a complete account of compositor CPU scheduling. An unrelated Location Energy Model warning was reported during import.

Within the inspected portion after 1.65 seconds, successive display-vsync intervals included **8.33 ms, 12.50 ms, and 16.67 ms**. In the unprofiled Metal display-link run, each recorded GPU command completed before its recorded submission deadline, while actual presentation times still varied. These observations motivated the higher-clock experiment; its failure is why it was removed. Profiling itself affected timings, so the profiled run is not used as a performance gate.

Raw traces, process identifiers, and detailed timing journals remain in ignored local build output. No screen recording, captured desktop image, or raw system trace is published.

## Diagnostic safety and source checks

Visible diagnostics still require `--allow-visible-test`; full-screen testing remains a separate opt-in and remains suspended on the working Mac. The diagnostic now reserves Esc before showing a window and refuses to start if registration fails. It also retains focused-window key handling, the close button, a bounded duration, GPU health checks, and awaited retirement.

The UI-driven Escape attempts did not establish cancellation: the timed runs completed before a confirmed Escape cancellation was observed. Global-key delivery and physical recovery therefore remain unverified. They are not marked passed merely because registration and compilation succeeded.

The newest WindowServer report after these checks remained the September 10 report at 23:16. No new report appeared, but absence of a new crash report is not sufficient to resolve the earlier pink-screen incident. DuoLid and profiler processes were stopped after testing.

All **37 behavioral tests** and strict Swift 6 checks passed locally and on both [Apple silicon and Intel CI runners](https://github.com/thetejasagrawal/DuoLid/actions/runs/34578207545). The clean Developer ID build passed universal architecture, macOS 14 deployment target, nested signatures, hardened runtime, compiled shader, updater policy, and matching-symbol checks. It remains local and unnotarized.

## What is still needed

1. Reproduce and resolve live capture pacing on a controlled test machine, keeping capture arrival, rendering, and actual presentation measurements separate. Do not extend a failed run or substitute average fps for the deadline gate.
2. Complete physical fold, emergency pause, sleep/session/display recovery, ordinary desktop use, accessibility, and audio checks. Follow the [hardware matrix](../COMPATIBILITY.md) before stable.
3. Save the `DuoLid-notary` Keychain profile with the local [credential script](../../scripts/notary-credentials.sh), then notarize/staple and complete quarantined installation and signed-update tests.
4. Publish verified release assets before activating the README download button and signed GitHub-hosted appcast. There is no landing page or Pages deployment.
