import AppKit
import DuoLidCore
import Foundation
import QuartzCore

/// Owns its display link and renderer on one dedicated run loop. Cross-thread
/// control uses the lock and CFRunLoopPerformBlock; shutdown has an awaitable end.
final class DisplayRenderLoop: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    private let renderer: MetalRenderer
    private let layer: CAMetalLayer
    private let lock = NSLock()
    private var fps: Float
    private var runLoop: CFRunLoop?
    private var started = false
    private var stopped = false
    private var finished = false
    private var drained = true
    private var completions: [CheckedContinuation<Bool, Never>] = []
    // Accessed only by the display thread.
    private var link: CAMetalDisplayLink?
    private var adaptive: AdaptiveCadence
    private var automatic: Bool
    private let onCadenceChange: (@MainActor @Sendable (Int) -> Void)?
    private var lastCadenceCheck = 0.0
    var framesPerSecond: Int { lock.withLock { Int(fps) } }

    @MainActor
    init(
        renderer: MetalRenderer, layer: CAMetalLayer, screen: NSScreen, fps: Int,
        automatic: Bool = false, onCadenceChange: (@MainActor @Sendable (Int) -> Void)? = nil
    ) {
        self.renderer = renderer
        self.layer = layer
        self.fps = Float(min(fps, max(1, screen.maximumFramesPerSecond)))
        self.automatic = automatic
        self.onCadenceChange = onCadenceChange
        adaptive = AdaptiveCadence(framesPerSecond: fps)
        super.init()
    }

    func start() {
        guard
            lock.withLock({
                if started || stopped { return false }
                started = true
                return true
            })
        else { return }
        let thread = Thread { [self] in
            autoreleasepool {
                let loop = CFRunLoopGetCurrent()!
                let shouldStart = lock.withLock { () -> Bool in
                    guard !stopped else { return false }
                    runLoop = loop
                    return true
                }
                defer {
                    self.link?.invalidate()
                    self.link = nil
                    let didDrain = renderer.finishRendering()
                    let pending = lock.withLock {
                        finished = true
                        drained = didDrain
                        runLoop = nil
                        let pending = completions
                        completions.removeAll()
                        return pending
                    }
                    pending.forEach { $0.resume(returning: didDrain) }
                }
                guard shouldStart else { return }
                // A display link may install only observers before its first tick.
                // Keep an input source alive so CFRunLoopRun cannot exit early.
                var context = CFRunLoopSourceContext()
                context.perform = { _ in }
                let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)!
                CFRunLoopAddSource(loop, keepAlive, .defaultMode)
                // Prepare before asking Core Animation for display surfaces.
                // A stream can return from startCapture before its first frame.
                // This short-lived timer belongs to the render run loop; it
                // never blocks AppKit while waiting for capture or GPU warm-up.
                let preparation = Timer(timeInterval: 1.0 / 120, repeats: true) { [self] timer in
                    guard !lock.withLock({ stopped }), renderer.frames.hasFrame else { return }
                    timer.invalidate()
                    guard renderer.prepareForDisplay() else {
                        stop()
                        return
                    }
                    guard !lock.withLock({ stopped }) else { return }
                    let link = CAMetalDisplayLink(metalLayer: layer)
                    link.delegate = self
                    link.preferredFrameLatency = 1
                    self.link = link
                    applyCadence()
                    link.add(to: .current, forMode: .default)
                }
                RunLoop.current.add(preparation, forMode: .default)
                CFRunLoopRun()
                preparation.invalidate()
                self.link?.invalidate()
                self.link = nil
                CFRunLoopRemoveSource(loop, keepAlive, .defaultMode)
            }
        }
        thread.name = "DuoLid Display"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func setFrameRate(_ rate: Int, automatic: Bool) {
        let loop = lock.withLock {
            fps = Float(rate)
            self.automatic = automatic
            return runLoop
        }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in applyCadence() }
            CFRunLoopWakeUp(loop)
        }
    }

    private func applyCadence() {
        let rate = lock.withLock { fps }
        renderer.targetFPS = Double(rate)
        adaptive = AdaptiveCadence(framesPerSecond: Int(rate))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }

    func stop() {
        let loop = lock.withLock { () -> CFRunLoop? in
            stopped = true
            if !started {
                link?.invalidate()
                link = nil
                finished = true
            }
            return runLoop
        }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        }
    }

    @discardableResult
    func stopAndWait() async -> Bool {
        stop()
        return await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if finished || !started { return true }
                completions.append(continuation)
                return false
            }
            if resumeNow { continuation.resume(returning: lock.withLock { drained }) }
        }
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard !lock.withLock({ stopped }) else { return }
        autoreleasepool {
            // Core Animation supplies an available drawable and its own timing.
            // Waiting for nextDrawable() on a separate clock couples capture's
            // compositor work to the animation and can produce late 8/25 ms pairs.
            renderer.draw(update: update)
            let now = CACurrentMediaTime()
            if now - lastCadenceCheck >= 0.25 {
                lastCadenceCheck = now
                if let rate = adaptive.evaluate(
                    timestamps: renderer.statistics.recentTimestamps(since: now - 1),
                    now: now, automatic: lock.withLock { automatic })
                {
                    lock.withLock { fps = Float(rate) }
                    renderer.targetFPS = Double(rate)
                    link.preferredFrameRateRange = CAFrameRateRange(
                        minimum: Float(rate), maximum: Float(rate), preferred: Float(rate))
                    let notify = onCadenceChange
                    Task { @MainActor in notify?(rate) }
                }
            }
        }
    }
}
