# Architecture and ownership

`DuoLidCore` contains pure settings, progress/projection math, exact spring integration, capture/preparation gates, latch detection and synthesis, performance evaluation, and update policy. CPU tests exercise these independently of a window server or Metal device.

`AppModel` and all AppKit/SwiftUI state live on the main actor. `LidSensor` owns IOKit on a utility dispatch queue. Input callbacks publish to `LatestLidSample` immediately; main-actor delivery is coalesced, and the visible readout updates at most ten times per second. Rendering reads the latest sample directly, independent of UI redraws.

`DesktopEffect` owns capture-session transitions. Each session has a new generation and frame store. Asynchronous startup and callbacks check that generation; a retiring stream cannot populate a new session. Mode/power changes update capture cadence and the display link without restarting a visible session. Automatic cadence may step down once per fold, then reassesses in the next session.

`DisplayRenderLoop` owns its AppKit screen-bound display link and renderer on a dedicated run loop. Controls cross through a lock and run-loop blocks. `MetalRenderer` owns mutable working textures and kernels on that thread. Pipeline caches are immutable per Metal device; capture uses the device associated with the built-in display. Display changes retire the session so the next one rebuilds size/device-dependent resources.

A latest-only `CapturedFrame` slot prevents stale-frame queues. A two-permit semaphore bounds pending GPU commands. Each command retains its source CVPixelBuffer and CVMetalTexture through completion. A drawable is acquired only when capture data and a permit exist. `command.present(drawable)` schedules presentation with GPU work. The first overlay reveal requires both command success and an actual nonzero presentation timestamp, regardless of callback arrival order.

The main actor can hide the panel immediately. Cleanup cancels startup, stops capture, joins the render owner, and closes the surface after queued GPU work drains. A drain timeout retains the hidden surface until exit and blocks a new session. Shutdown and updater relaunch await cleanup. Sleep, display sleep, inactive sessions, and shutdown are separate interruption reasons; one wake event cannot clear a different reason.

A persistent interrupted-session marker is set during capture/rendering and cleared after clean retirement. Rendering or capture failures latch the effect instead of retrying in a loop. A main-actor watchdog hides and retires a session if GPU or presentation progress stops. These guards reduce exposure; they cannot repair a hung macOS WindowServer or prove that a driver fault is fixed.

Settings-only launch bypasses capture and Metal preview creation without changing user preferences. The sample preview otherwise uses synthetic desktop pixels and the same shader implementation as the live path. No previous frame is blended into the next; dithering is spatial, not temporal.

`UpdaterController` wraps Sparkle's native updater, with an HTTPS signed feed and signed archives verified before extraction. The updater delegate postpones relaunch while the app awaits cleanup. Normal termination also uses AppKit's deferred termination reply. Automatic checking is opt-in; installation is interactive and system profiling is disabled.
