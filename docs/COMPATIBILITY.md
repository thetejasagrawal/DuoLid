# Compatibility

The target is macOS 14 or later, with arm64 and x86_64 slices. Automatic effects additionally require a usable lid-angle HID sensor, Metal, an active non-mirrored built-in display, and Screen Recording permission. Hardware support is detected, never inferred from the CPU family alone.

| Configuration | Evidence | Current release status |
| --- | --- | --- |
| MacBookPro18,1, macOS 26.6.2 | Sensor and capture worked in earlier development; display interruptions were reported during testing | Current presentation implementation unverified; release blocked |
| Apple silicon, macOS 14+ | Source target and cross-version availability checks | Physical validation pending |
| Intel, macOS 14+ | x86_64 target builds; this is not an Intel hardware test | Sensor and physical rendering validation pending |
| Additional ProMotion MacBook Pro | None recorded | Unverified |
| Sensor-equipped MacBook Air | None recorded | Unverified |
| Macs with no usable sensor | Preview-only behavior is intentional | No automatic lid effect |
| External-only or mirrored built-in display | Excluded by capture selection | No automatic desktop effect in this configuration |

Some models, including the M1 MacBook Air and M1/M2 Touch Bar MacBook Pro, have been reported without the required angle interface in the reference project. Do not interpret this as a complete support list. Consult the actual sensor status in DuoLid. Reference: https://github.com/samhenrigold/LidAngleSensor

Before stable, record physical results on this Mac, another ProMotion Pro, a sensor-equipped Air, and an Intel Mac with a working sensor, covering macOS 14, 15, and 26. Include display refresh setting, resolution, power mode, and pass/fail for each acceptance area. Keep **tested**, **unsupported**, and **unverified** distinct.

The beta is SDR/sRGB. HDR highlights may tone-map differently while the effect is visible. Protected content can be blank in capture, and lock-screen capture is not supported. DuoLid does not prevent sleep, intercept authentication, or replace a privacy lock.
