# DuoLid

A native macOS menu-bar app that gives your MacBook a softer landing: progressive live desktop blur as the lid closes, an original magnetic opening click, and an optional colorful corner glow.

## Run

The built app is at `dist/DuoLid.app`. Move it to Applications if you want to keep it installed. Open **Settings** in the title bar and allow **Screen Recording** to enable the live desktop effect. If macOS requests a restart, quit and reopen DuoLid. The sample desktop preview works without screen access and uses the same renderer as the real effect.

DuoLid starts below **62°** by default. The start-angle slider, degree field, stepper, and **Use 62°** reset are always visible. Existing choices are preserved across updates. At or above the selected angle, the visible effect is removed. Capture can prepare briefly as a closing lid approaches that angle; it stops when you reopen or hold above the threshold. Close the window to leave DuoLid in the menu bar.

The tuning workspace keeps the preview and everyday controls together:

- **Lid effect:** Duo, Frost, or Quiet; blur strength and start angle.
- **Colorful glow:** optional, off by default; pale Aurora, Prism, Sunset, or Ocean palettes. **Brightness** controls the color on the screen; **Edge bleed** controls the soft light spilling into the black background.
- **Opening sound:** Magnetic, Soft, or Crisp; independent toggle, volume, and **Listen** button.
- **More tuning:** fold depth, shadow, smoothing, glow spread and corners, plus a reversible blur/glow reset.
- **Settings:** Screen Recording status, sensor status, login launch, System/Light/Dark appearance, Reduce Motion, Low Power Mode, and shortcuts.
- **Preview:** drag the angle or choose Closed / Mid-fold / Open. **Animate preview** (Option–Command–P) runs a sample cycle; **Test on desktop** (Command–P) tests your real display. Editing blur or glow reveals a partly closed preview. Changes save automatically.
- **Pause:** the title-bar switch, menu bar, Control–Option–Command–D, or Esc during a visible desktop effect.

## Build and test

Requires macOS 14 or newer, Apple’s Swift toolchain / Xcode, and a MacBook with an exposed lid-angle sensor for automatic effects. No third-party dependencies.

```sh
swift test
bash scripts/build.sh
dist/DuoLid.app/Contents/MacOS/DuoLid --diagnose
dist/DuoLid.app/Contents/MacOS/DuoLid --render-check
```

Open `Package.swift` in Xcode to work on the app. `bash scripts/build.sh debug` creates a debug app bundle. The build script uses your Developer ID Application identity when exactly one is available, giving the app a stable permission identity across updates. Set `DUOLID_SIGNING_IDENTITY` explicitly to choose a certificate, or `-` for ad-hoc signing. If no unambiguous identity exists, it falls back to ad-hoc signing, which may require Screen Recording consent again after a rebuild. Public distribution additionally needs notarization.

To rebuild the icon:

```sh
swift scripts/make-icon.swift
iconutil -c icns .build/DuoLid.iconset -o Resources/DuoLid.icns
```

## How it works

- IOKit reads the built-in hinge sensor using nonexclusive device access. Input callbacks are preferred. The fallback polls every 16 ms during motion and an active effect, returning to an 80 ms watchdog when idle. A critically damped spring interpolates the whole-degree readings without abrupt velocity changes.
- ScreenCaptureKit captures only the active, non-mirrored built-in display, using its actual Retina backing scale. The effect’s own windows are excluded to prevent feedback. External monitors are untouched.
- Native Metal Performance Shaders apply a dense Gaussian blur with floating-point intermediates. Small blur uses native resolution; broad blur uses a filtered 2× reduction and reconstruction, validated against a full-resolution reference. The sharp source and final composite remain at full Retina resolution. A feathered front moves from top to bottom. The desktop plane rotates about its bottom-center hinge; the top edge descends and narrows. A gentle light spill softens the edge against the dark background.
- CAMetalDisplayLink schedules a dedicated rendering thread against the display’s presentation times, targeting up to 120 Hz separately from SwiftUI and window dragging. Only the newest captured frame is used; old frames are never blended over the original desktop. The overlay is removed at the selected open angle. A short, invisible preparation window while closing reduces capture startup delay. Capture and rendering stop on reopening, pause, sleep, an inactive session, or after holding above the threshold. Low Power Mode can use 30 fps.
- The overlay ignores mouse events. It closes immediately on pause, sleep, sensor loss, or capture/renderer errors. It does not change macOS sleep or lock behavior.
- Original short Foley sounds are generated in memory and played with AVFoundation. Volume follows the app’s setting and the system output.
- Settings are stored in UserDefaults under `app.duolid.DuoLid`. No analytics, account, network calls, stored screen frames, or captured microphone/system audio. Local macOS logs contain capture dimensions and aggregate render timing, never screen content.

## Practical limits

Lid-angle sensing uses an undocumented Apple HID interface, so support varies by hardware and can change with macOS updates. DuoLid shows the sensor’s actual status and offers a labeled preview on unsupported hardware. Protected video and the lock screen may not be capturable; DuoLid is an aesthetic effect, not a privacy lock. Mirrored and external-only display configurations are intentionally excluded. Live capture currently uses SDR/sRGB, so HDR highlights can look different during the effect.

See [the reference study](docs/REFERENCE-STUDY.md) and [verification guide](docs/VERIFICATION.md).
