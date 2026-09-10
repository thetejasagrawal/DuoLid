# DuoLid reference study

Studied September 10, 2026.

## References

- [Bendy](https://trybendy.app/): inspected the live site and its visual demo. It combines hinge angle with a live desktop tilt, blur, shade, and an opening click. Its page describes Metal rendering, Screen Recording access, a menu-bar home, and local frame processing.
- [Apple’s iPhone Duo announcement](https://www.apple.com/uk/newsroom/2026/09/apple-unveils-iphone-duo/): Apple describes content responding continuously as the device folds and moves between displays. This is a motion reference, not a claim that macOS exposes the same transition API.
- [Sam Henri Gold’s LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor): primary research into the MacBook HID sensor and report 1. The documented 0x20 sensor page / 0x8A orientation usage and little-endian degree format were verified with this MacBook’s actual hardware. DuoLid has its own implementation; no code or sound assets were copied into the app.
- [Apple: Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos): ScreenCaptureKit streams and content exclusions.
- [Apple: SCContentFilter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter): exclude the overlay’s application, with the settings window included as an exception, to prevent capture feedback.

- [macOS design skill](https://github.com/ceorkm/macos-design-skill): the user’s selected design guidance. Applied semantic system colors, native controls and title bar, keyboard shortcuts, immediate feedback, and progressive disclosure. The app’s small scope uses one tuning workspace instead of a navigation sidebar.
- [Apple: CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink): display-synchronized rendering on a dedicated run loop, presentation deadlines, and variable refresh rate support.

## Design decisions

The reference is the feeling of an interface responding to physical movement. DuoLid translates this into a MacBook-specific effect; it does not claim a pixel-identical implementation of Apple’s proprietary transition.

As requested during development, a feathered blur front travels from the top edge toward the hinge as the lid closes. The lower portion uses the untouched original pixels until the front reaches it. Reopening reverses that exact progression. A quintic curve gives the transition gentle starts and finishes. Dense native Gaussian kernels use 16-bit floating-point intermediates. Broad blur can run after a filtered 2× reduction; the optimized path is checked against a native-resolution reference and an isolated bright-line regression to prevent block patterns. The source and composite stay at full Retina resolution. The desktop plane rotates around the bottom-center hinge, so its top edge visibly descends and narrows. Fold depth and shading are independently adjustable. Behind the moving front, Duo has greater softness toward the top; Frost keeps the screen flat and uses an even blur radius; Quiet lowers the overall visual weight.

The colorful corner glow is optional and off by default, as requested. It uses soft Gaussian light fields, composed with the blurred desktop rather than a hard border. Four palettes, three corner placements, brightness, spread, and edge bleed are adjustable. A pale wash connects the corner lights along the folding edge; a bright core and broad outer halo soften the black background. A sub-level spatial dither prevents banding in the dim falloff. Its progress follows the same hinge curve as the blur, without unrelated looping animation. The start angle defaults to 62° and remains directly editable.

The original opening Foley is synthesized in memory from a damped low impact, filtered noise, a short metallic tail, and a tiny delayed release. An armed state with hysteresis makes one meaningful close-and-open produce one click. Small desk adjustments and ordinary startup do not make a sound.

## Hardware observations

The development machine reports MacBookPro18,1 on macOS 26.6.2. Its AppleSPUHIDDevice has usage page 32, usage 138, product 33028. Both feature and input report 1 returned `[1, 90, 0]` during the initial probe. A feature-report watchdog covers hardware that does not deliver continuous input callbacks. This sensor interface is undocumented and compatibility must be verified per model.

## Scope of verification

Automated tests cover transition continuity, malformed sensor reports, smoothing, sound triggers across sleep-like gaps, settings recovery, and decoding the synthesized audio with AVFoundation. Native UI and shader verification are performed locally. A physical lid cycle and the Screen Recording consent flow require the user’s Mac and consent; those are listed separately in the verification guide.
