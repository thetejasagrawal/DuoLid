import AppKit
import DuoLidCore
import MetalKit
import ScreenCaptureKit

private final class EffectPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class EffectSurface: NSView {
    override var wantsUpdateLayer: Bool { true }
    override var isOpaque: Bool { true }
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
}

final class StreamReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let frames: CapturedFrame
    // Immutable after initialization; frames synchronizes its own storage.
    let onError: (@Sendable (Error) -> Void)?
    init(frames: CapturedFrame, onError: (@Sendable (Error) -> Void)? = nil) {
        self.frames = frames
        self.onError = onError
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let status = attachments.first?[.status] as? Int,
            status == SCFrameStatus.complete.rawValue,
            let buffer = sampleBuffer.imageBuffer
        else { return }
        frames.set(buffer)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { onError?(error) }
}

@MainActor
final class DesktopEffect {
    var onError: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onCaptureChanged: ((CapturePhase) -> Void)?
    var onGraphicsFailure: (() -> Void)?
    var onPerformanceReport: ((PerformanceReport) -> Void)?
    var onActiveChanged: ((Bool) -> Void)?
    private(set) var isActive = false
    private var stream: SCStream?
    private var receiver: StreamReceiver?
    private var panel: EffectPanel?
    private var view: EffectSurface?
    private var renderLoop: DisplayRenderLoop?
    private var renderer: MetalRenderer?
    private var frames = CapturedFrame()
    private var startTask: Task<Void, Never>?
    private var firstFrameTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var cadenceTask: Task<Void, Never>?
    private var configuration: SCStreamConfiguration?
    private var requestedFPS = 0
    private var requestedAutomatic = true
    private var useLiveAngle = true
    private let liveAngle: LatestLidSample?
    private let defaults: UserDefaults
    private let settingsOnly: Bool
    private(set) var failureLatched = false
    // If the GPU cannot drain, retain its surfaces until process exit. The
    // circuit breaker prevents another session from accumulating resources.
    private var quarantinedSurface: AnyObject?
    private var generation = 0
    private var lastFailure = -Double.infinity
    private var targetAngle = 120.0
    private var settings = DuoSettings()
    private var shouldRun = false
    private var hasPresented = false
    private var frameReady = false
    private var displayWanted = false
    private var captureGate = CaptureGate()
    private var preparationGate = CapturePreparationGate()

    init(liveAngle: LatestLidSample? = nil, defaults: UserDefaults = .standard, settingsOnly: Bool = false) {
        self.liveAngle = liveAngle
        self.defaults = defaults
        self.settingsOnly = settingsOnly
        failureLatched = defaults.bool(forKey: "DuoLid.renderSessionInterrupted")
    }

    @discardableResult
    func acknowledgeFailure() -> Bool {
        guard quarantinedSurface == nil else {
            onError?("Restart DuoLid before trying graphics again.")
            return false
        }
        failureLatched = false
        defaults.set(false, forKey: "DuoLid.renderSessionInterrupted")
        return true
    }

    static var builtInScreen: NSScreen? {
        NSScreen.screens.first {
            guard let id = $0.displayID else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0
                && CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
        }
    }

    func update(angle: Double, settings: DuoSettings, allowed: Bool, useLiveAngle: Bool = true) {
        self.useLiveAngle = useLiveAngle
        self.settings = settings
        targetAngle = angle
        renderer?.update(
            angle: angle, settings: settings,
            reduceMotion: settings.respectReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            useLiveAngle: useLiveAngle)
        let enabled =
            allowed && Self.builtInScreen != nil && !settingsOnly && !failureLatched && settings.enabled
            && settings.blurEnabled
        updateCadence()
        displayWanted = captureGate.update(angle: angle, clearAngle: settings.clearAngle, enabled: enabled)
        let preparing = preparationGate.update(
            angle: angle, startAngle: settings.clearAngle, enabled: enabled,
            at: ProcessInfo.processInfo.systemUptime)
        let wanted = displayWanted || preparing
        shouldRun = wanted
        if displayWanted && frameReady { presentOverlay() }
        if wanted {
            if stream == nil, startTask == nil, cleanupTask == nil,
                ProcessInfo.processInfo.systemUptime - lastFailure > 8
            {
                generation += 1
                let token = generation
                startTask = Task { [weak self] in await self?.start(token: token) }
            }
        } else if stream != nil || startTask != nil {
            stop()
        }
    }

    private func start(token: Int) async {
        defer { if token == generation { startTask = nil } }
        guard let screen = Self.builtInScreen, let displayID = screen.displayID else { return }
        onCaptureChanged?(.preparing)
        do {
            // A retiring stream can still deliver a final frame; isolate each session.
            let frames = CapturedFrame(source: .live)
            self.frames = frames
            let renderer = try MetalRenderer(
                frames: frames, device: CGDirectDisplayCopyCurrentMetalDevice(displayID), liveAngle: liveAngle)
            let panel = EffectPanel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                defer: false)
            panel.title = "DuoLid Effect"
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.sharingType = .none
            panel.isReleasedWhenClosed = false
            panel.alphaValue = 0.001
            let view = EffectSurface(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            guard let layer = view.layer as? CAMetalLayer else { throw RenderError.unavailable }
            layer.device = renderer.device
            layer.pixelFormat = .bgra8Unorm
            layer.framebufferOnly = true
            layer.maximumDrawableCount = 2
            layer.allowsNextDrawableTimeout = true
            layer.displaySyncEnabled = true
            layer.presentsWithTransaction = false
            layer.contentsScale = screen.backingScaleFactor
            layer.drawableSize = CGSize(
                width: screen.frame.width * screen.backingScaleFactor,
                height: screen.frame.height * screen.backingScaleFactor)
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            let fps = settings.frameRateMode.targetFPS(
                maximum: screen.maximumFramesPerSecond,
                lowPower: settings.batterySaver && ProcessInfo.processInfo.isLowPowerModeEnabled)
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            // Make the overlay known to WindowServer before the capture exclusion is constructed.
            panel.orderFrontRegardless()
            self.panel = panel
            self.view = view
            self.renderer = renderer
            renderer.backingScale = screen.backingScaleFactor
            renderer.update(
                angle: targetAngle, settings: settings,
                reduceMotion: settings.respectReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                useLiveAngle: useLiveAngle)
            renderer.onPresent = { [weak self] in
                guard self?.generation == token else { return }
                self?.frameReady = true
                self?.firstFrameTask?.cancel()
                self?.firstFrameTask = nil
                self?.presentOverlay()
            }
            renderer.onFailure = { [weak self] message in
                guard self?.generation == token else { return }
                self?.onGraphicsFailure?()
                self?.fail(message)
            }
            requestedFPS = fps
            requestedAutomatic = settings.frameRateMode == .automatic
            let loop = DisplayRenderLoop(
                renderer: renderer, layer: layer, screen: screen, fps: fps,
                automatic: settings.frameRateMode == .automatic,
                onCadenceChange: { [weak self] rate in
                    guard self?.generation == token else { return }
                    self?.setCaptureCadence(rate)
                })
            renderLoop = loop
            let content = try await CaptureContent.fetch()
            guard token == generation, !Task.isCancelled, shouldRun else { return }
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw NSError(
                    domain: "DuoLid", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The built-in display is unavailable."])
            }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            // Retain the settings window in the image while always excluding all overlays.
            let settingsWindows = content.windows.filter {
                $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier && $0.title == "DuoLid"
            }
            let filter = SCContentFilter(
                display: display, excludingApplications: ownApps, exceptingWindows: settingsWindows)
            if #available(macOS 14.2, *) { filter.includeMenuBar = true }
            let configuration = SCStreamConfiguration()
            // CGDisplayPixelsWide can report logical pixels in a Retina display mode.
            // ScreenCaptureKit's filter describes the actual capture backing scale.
            configuration.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
            configuration.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
            // Two GPU readers, a latest-frame slot, and one capture producer.
            configuration.queueDepth = 4
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            RenderLog.logger.notice("Capture configured: \(configuration.width)×\(configuration.height), \(fps) fps")
            let receiver = StreamReceiver(frames: frames) { [weak self] error in
                Task { @MainActor in
                    guard self?.generation == token else { return }
                    self?.failCapture(error)
                }
            }
            let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
            try stream.addStreamOutput(
                receiver, type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "app.duolid.frames", qos: .userInteractive))
            self.configuration = configuration
            self.receiver = receiver
            self.stream = stream
            try await stream.startOnMainActor()
            guard token == generation, !Task.isCancelled else {
                try? await stream.stopOnMainActor()
                return
            }
            onCaptureChanged?(.capturing)
            defaults.set(true, forKey: "DuoLid.renderSessionInterrupted")
            loop.start()
            healthTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self, self.generation == token else { return }
                    if renderer.statistics.isStalled(at: CACurrentMediaTime()) {
                        self.onGraphicsFailure?()
                        self.fail(
                            "Graphics stopped responding. The effect has been paused. Restart DuoLid before testing again."
                        )
                        return
                    }
                }
            }
            firstFrameTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, !self.frameReady else { return }
                self.fail("The desktop did not provide a frame. Check Screen Recording access and try again.")
            }
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            if error is RenderError { onGraphicsFailure?() }
            failCapture(error)
        }
    }

    private func presentOverlay() {
        guard !hasPresented, shouldRun, displayWanted, frameReady else { return }
        hasPresented = true
        panel?.alphaValue = 1
        RenderLog.logger.notice("First desktop frame presented")
        isActive = true
        firstFrameTask?.cancel()
        firstFrameTask = nil
        onActiveChanged?(true)
    }

    private func failCapture(_ error: Error) {
        let failure = error as NSError
        if failure.domain == SCStreamErrorDomain && failure.code == SCStreamError.Code.userDeclined.rawValue {
            onPermissionDenied?()
        }
        fail(error.localizedDescription)
    }

    private func fail(_ message: String) {
        failureLatched = true
        lastFailure = ProcessInfo.processInfo.systemUptime
        stop()
        onCaptureChanged?(.failed)
        onError?(message)
    }

    private func updateCadence() {
        guard let screen = Self.builtInScreen else { return }
        let rate = settings.frameRateMode.targetFPS(
            maximum: screen.maximumFramesPerSecond,
            lowPower: settings.batterySaver && ProcessInfo.processInfo.isLowPowerModeEnabled)
        let automatic = settings.frameRateMode == .automatic
        guard rate != requestedFPS || automatic != requestedAutomatic else { return }
        requestedFPS = rate
        requestedAutomatic = automatic
        renderLoop?.setFrameRate(rate, automatic: settings.frameRateMode == .automatic)
        setCaptureCadence(rate)
    }

    private func setCaptureCadence(_ rate: Int) {
        guard let stream, let configuration else { return }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(rate))
        let previous = cadenceTask
        let token = generation
        cadenceTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do { try await stream.updateOnMainActor(configuration) } catch {
                if !Task.isCancelled && self?.generation == token {
                    self?.failCapture(error)
                }
            }
        }
    }

    func stop() {
        generation += 1
        shouldRun = false
        let startup = startTask
        startup?.cancel()
        startTask = nil
        firstFrameTask?.cancel()
        firstFrameTask = nil
        healthTask?.cancel()
        healthTask = nil
        let cadence = cadenceTask
        cadence?.cancel()
        cadenceTask = nil
        let oldLoop = renderLoop
        oldLoop?.stop()
        renderLoop = nil
        let oldPanel = panel
        oldPanel?.orderOut(nil)
        let oldStream = stream
        let oldReceiver = receiver
        let oldRenderer = renderer
        let oldFrames = frames
        panel = nil
        view = nil
        renderer = nil
        stream = nil
        receiver = nil
        configuration = nil
        requestedFPS = 0
        if oldPanel != nil || oldStream != nil || startup != nil {
            if !failureLatched { onCaptureChanged?(.stopping) }
            let previousCleanup = cleanupTask
            cleanupTask = Task { [weak self] in
                await previousCleanup?.value
                await startup?.value
                await cadence?.value
                try? await oldStream?.stopOnMainActor()
                let drained = await oldLoop?.stopAndWait() ?? true
                oldFrames.clear()
                withExtendedLifetime(oldReceiver) {}
                if let oldRenderer {
                    self?.onPerformanceReport?(oldRenderer.statistics.snapshot(targetFPS: oldRenderer.targetFPS))
                }
                withExtendedLifetime(oldRenderer) {}
                if drained {
                    oldPanel?.close()
                    if self?.failureLatched == false {
                        self?.defaults.set(false, forKey: "DuoLid.renderSessionInterrupted")
                    }
                } else {
                    self?.failureLatched = true
                    self?.quarantinedSurface = oldPanel
                    self?.onError?("Graphics did not finish shutting down. Restart DuoLid before testing again.")
                }
                self?.cleanupTask = nil
                if self?.failureLatched == false { self?.onCaptureChanged?(.idle) }
            }
        }
        hasPresented = false
        frameReady = false
        displayWanted = false
        captureGate.reset()
        preparationGate.reset()
        if isActive {
            isActive = false
            onActiveChanged?(false)
        }
    }

    func stopAndWait() async {
        stop()
        await cleanupTask?.value
    }

}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
