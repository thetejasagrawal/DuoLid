# DuoLid

A native macOS menu-bar app that gives your MacBook a softer landing: progressive desktop blur as the lid closes, a bottom-anchored folding frame, soft edge bleed, an original magnetic opening click, and optional colorful corner glow.

**Status: beta in preparation.** The first planned release is **0.9.0-beta.1**. No production download is published yet. A reported pink-screen/WindowServer interruption is an open release blocker; the new presentation path still needs controlled live validation. See [release acceptance](docs/release/acceptance.json). A successful source build is not evidence that those gates passed.

[Website](https://thetejasagrawal.github.io/DuoLid/) · [Compatibility](docs/COMPATIBILITY.md) · [Contributing](CONTRIBUTING.md) · [Verification](docs/VERIFICATION.md)

## Use DuoLid

Requires **macOS 14+**. The app builds for both Apple silicon and Intel. Automatic effects require a compatible lid-angle sensor; unsupported hardware receives a sample preview and a clear sensor status. A universal binary does not imply every MacBook exposes that sensor.

When a verified release is available, move DuoLid to Applications and allow Screen Recording in Settings. If macOS requests it, quit and reopen the app. The sample preview requires no screen access. Close the settings window to leave DuoLid in the menu bar.

The effect starts below **62°** by default. The start-angle slider, degree field, stepper, and **Use 62°** reset stay in the main workspace. At or above your chosen angle, the visible effect is removed. Capture prepares briefly while a closing lid approaches that angle, then stops if you reopen or hold above it.

- **Lid effect:** Duo, Frost, or Quiet; blur strength and start angle.
- **Colorful glow:** optional and off by default; Aurora, Prism, Sunset, or Ocean palettes. Brightness controls color; Edge bleed controls soft light spilling into black and works independently of colorful glow.
- **Opening sound:** Magnetic, Soft, or Crisp; separate toggle, volume, and Listen button.
- **More tuning:** fold depth, shadow, smoothing, Automatic / 60 / 120 fps, glow spread and corners. Automatic targets the display's refresh rate up to 120 fps and can step down to 60 for a busy fold. Low Power Mode can use 30 fps.
- **Settings:** sensor, Screen Recording, capture and graphics status, launch at login, appearance, Reduce Motion, update preferences, and technical diagnostics.
- **Preview:** choose an angle or animate synthetic content. Desktop testing is separate and needs screen access.
- **Pause:** the title-bar switch, menu bar, **Control–Option–Command–D**, or **Esc** during a visible desktop effect.

Changes save automatically. Updates preserve the production identifier `app.duolid.DuoLid` and existing settings, including individually disabled sound and glow.

## Build and test

Use Xcode with the Swift 6 toolchain. Sparkle **2.9.6** is the only third-party package and is pinned in `Package.resolved`.

```sh
swift test -c release -Xswiftc -warnings-as-errors
bash scripts/build.sh development
# Safe configuration inspection: no Metal preview, desktop capture, or overlay.
open dist/development/DuoLid.app --args --settings-only
```

Open `Package.swift` in Xcode to develop the app. Development packaging creates an ad-hoc signed universal app with the separate identifier `app.duolid.DuoLid.Development`. It never overwrites an installed copy or changes the production app's permission record.

`bash scripts/build.sh release` requires a clean commit, the intended Developer ID identity, and Xcode's Metal Toolchain. It precompiles the shaders, signs every embedded helper, and checks both architecture slices and the macOS 14 target. [Release instructions](docs/RELEASING.md) cover notarization, installation testing, appcast signing, and the separate publication gate. Private signing assets never enter GitHub Actions.

Visible presentation diagnostics require an explicit `--allow-visible-test` flag. Do not run them on a working desktop while investigating the reported graphics interruption. CPU behavior tests and static bundle checks do not launch DuoLid.

To export the icon:

```sh
swift scripts/make-icon.swift
iconutil -c icns .build/DuoLid.iconset -o Resources/DuoLid.icns
```

## How it works

IOKit reads the built-in hinge sensor nonexclusively. Its latest sample goes directly to synchronized render state; SwiftUI angle readouts are throttled. A display-driven, critically damped spring interpolates sensor steps and reversals.

ScreenCaptureKit captures the active, non-mirrored built-in display at its Retina backing size. DuoLid excludes its own overlay from capture. Metal Performance Shaders apply a dense Gaussian blur with floating-point intermediates. Small blur uses native resolution; broad blur uses filtered 2× reduction and reconstruction. Sharp content and final output stay at native resolution. A feathered blur front travels from top to bottom while the desktop rotates around its bottom edge.

An AppKit display link owns a dedicated render loop. Two pending GPU frames are the limit; captured inputs remain retained until completion. The app waits for both valid GPU completion and an actual presentation callback before revealing the effect. A stalled session trips a circuit breaker. Reopening, pausing, sensor loss, display changes, sleep, and an inactive session hide the overlay and retire capture. See [architecture](docs/ARCHITECTURE.md) for ownership and recovery details.

## Privacy and limits

Screen content stays on the Mac and is not saved, uploaded, or included in diagnostics. DuoLid captures no microphone or system audio. Its short opening sounds are synthesized locally. No analytics, account, or advertising SDK is included.

Sparkle contacts GitHub when you check for updates or opt into automatic checking. Downloads may use GitHub's asset CDN. GitHub receives ordinary network metadata such as IP address and user-agent. System profiling and silent installation default off; installation requires user interaction. Diagnostics contain technical capability and aggregate timing data only.

Lid sensing relies on an undocumented Apple HID interface and can vary with hardware and OS updates. Protected video and the lock screen may not be capturable. DuoLid is an aesthetic effect, not a privacy lock, and does not change macOS sleep behavior. External-only and mirrored display configurations are excluded. This beta uses SDR/sRGB capture; HDR highlights may look different during the effect.

See the [reference study](docs/REFERENCE-STUDY.md), [third-party notices](THIRD_PARTY_NOTICES.md), and [MIT license](LICENSE).
