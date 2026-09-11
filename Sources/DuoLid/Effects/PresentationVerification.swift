import AppKit
import DuoLidCore
import MetalKit
import ScreenCaptureKit

/// Visible tests are an explicit operator action, never part of normal tests/CI.
@MainActor
enum PresentationVerification {
    static func run() throws {
        guard CommandLine.arguments.contains("--allow-visible-test") else {
            FileHandle.standardError.write(
                Data(
                    "Visible diagnostics are disabled. On a designated test Mac, add --allow-visible-test for a windowed test; --full-screen is a separate opt-in.\n"
                        .utf8))
            exit(64)
        }
        _ = NSApplication.shared
        let session = try PresentationSession()
        NSApp.setActivationPolicy(.regular)
        NSApp.delegate = session
        withExtendedLifetime(session) { NSApp.run() }
    }
}

@MainActor
private final class PresentationSession: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum StopReason: String, Encodable {
        case completed, escape, windowClosed, applicationQuit, windowOccluded
        case graphicsStall, graphicsFailure, captureFailure, startupFailure
    }
    private let renderer: MetalRenderer
    private let window: NSWindow
    private let loop: DisplayRenderLoop
    private let frames: CapturedFrame
    private let fps: Int
    private let duration: Double
    private let live: Bool
    private let displayID: CGDirectDisplayID
    private var timer: Timer?
    private var timeoutTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var stream: SCStream?
    private var receiver: StreamReceiver?
    private var fixture: PresentationFixture?
    private var captureExclusion: CaptureExclusion?
    private var requestedCaptureDimensions: PixelSize?
    private var escapeMonitor: Any?
    private var startedAt = 0.0
    private var finishing = false

    init(arguments args: [String] = CommandLine.arguments) throws {
        guard let screen = DesktopEffect.builtInScreen, let displayID = screen.displayID else {
            throw NSError(
                domain: "DuoLid.Verification", code: 75,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The built-in display is inactive or mirrored. Open and wake it, with display mirroring turned off, before running this check."
                ])
        }
        self.displayID = displayID
        func argument(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        let requested = Int(argument("--fps") ?? "60") ?? 60
        guard [30, 60, 120].contains(requested) else {
            throw NSError(
                domain: "DuoLid.Verification", code: 64,
                userInfo: [NSLocalizedDescriptionKey: "Use --fps 30, 60, or 120."])
        }
        fps = min(requested, max(1, screen.maximumFramesPerSecond))
        duration = bounded(Double(argument("--duration") ?? "30") ?? 30, 2...120, fallback: 30)
        live = args.contains("--live-capture")
        let width = Int(screen.frame.width * screen.backingScaleFactor)
        let height = Int(screen.frame.height * screen.backingScaleFactor)
        frames = CapturedFrame(source: live ? .live : .synthetic)
        if !live { frames.set(try Self.syntheticBuffer(width: width, height: height)) }
        renderer = try MetalRenderer(
            frames: frames, device: CGDirectDisplayCopyCurrentMetalDevice(displayID), recordsFrameTimings: true)
        renderer.backingScale = screen.backingScaleFactor
        let fullScreen = args.contains("--full-screen")
        let contentRect =
            fullScreen
            ? screen.frame
            : CGRect(
                x: screen.visibleFrame.midX - 480,
                y: screen.visibleFrame.midY - 310, width: 960, height: 620)
        window = NSWindow(
            contentRect: contentRect, styleMask: fullScreen ? .borderless : [.titled, .closable], backing: .buffered,
            defer: false)
        window.title = "DuoLid \(live ? "Live capture" : "Synthetic") test · Esc to stop"
        // A covered window is intentionally not presented by WindowServer.
        // Keep this bounded, dismissible test visible without using an overlay.
        window.level = .floating
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: contentRect.size))
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.maximumDrawableCount = MetalRenderer.drawableCount
        layer.framebufferOnly = true
        layer.allowsNextDrawableTimeout = true
        layer.presentsWithTransaction = false
        layer.displaySyncEnabled = true
        layer.contentsScale = screen.backingScaleFactor
        // Keep full native GPU workload even when the diagnostic window is small.
        layer.drawableSize = CGSize(width: width, height: height)
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.layer = layer
        view.wantsLayer = true
        window.contentView = view
        loop = DisplayRenderLoop(renderer: renderer, layer: layer, screen: screen, fps: fps)
        super.init()
        window.delegate = self
        renderer.onFailure = { [weak self] _ in self?.finish(reason: .graphicsFailure) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if live, let screen = window.screen {
            let fixture = PresentationFixture(screen: screen)
            fixture.window.delegate = self
            fixture.show()
            self.fixture = fixture
        }
        window.makeKeyAndOrderFront(nil)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.finish(reason: .escape) }
                return nil
            }
            return event
        }
        startupTask = Task { [self] in
            do {
                if live { try await startCapture() }
                guard !finishing, !Task.isCancelled else { return }
                startedAt = CACurrentMediaTime()
                update()
                loop.start()
                let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                }
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
                timeoutTask = Task { [self] in
                    try? await Task.sleep(for: .seconds(duration))
                    if !Task.isCancelled { finish(reason: .completed) }
                }
            } catch { finish(reason: .startupFailure) }
        }
    }

    private func startCapture() async throws {
        let content = try await CaptureContent.fetch()
        guard !finishing, !Task.isCancelled else { return }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RenderError.unavailable
        }
        let fixtureWindows = content.windows.filter { Int($0.windowID) == fixture?.window.windowNumber }
        guard fixtureWindows.count == 1 else { throw RenderError.unavailable }
        let (filter, exclusion) = try CaptureFilter.make(
            content: content, display: display, outputWindowNumber: window.windowNumber,
            includingOwnWindows: fixtureWindows)
        captureExclusion = exclusion
        let configuration = CaptureConfiguration.make(filter: filter, framesPerSecond: fps)
        requestedCaptureDimensions = PixelSize(width: configuration.width, height: configuration.height)
        let receiver = StreamReceiver(frames: frames) { [weak self] _ in
            Task { @MainActor in self?.finish(reason: .captureFailure) }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        try stream.addStreamOutput(
            receiver, type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "app.duolid.diagnostic.capture", qos: .userInteractive))
        self.receiver = receiver
        self.stream = stream
        try await stream.startOnMainActor()
    }

    private func finish(reason: StopReason) {
        guard !finishing else { return }
        finishing = true
        let cancelled = reason != .completed
        let visibleAtStop = window.occlusionState.contains(.visible)
        let elapsed = startedAt > 0 ? CACurrentMediaTime() - startedAt : 0
        window.orderOut(nil)
        fixture?.close()
        timer?.invalidate()
        timer = nil
        timeoutTask?.cancel()
        let startup = startupTask
        startup?.cancel()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        loop.stop()
        Task { [self] in
            await startup?.value
            try? await stream?.stopOnMainActor()
            let drained = await loop.stopAndWait()
            if drained { window.close() }
            try? await Task.sleep(for: .milliseconds(150))
            let report = renderer.statistics.snapshot(targetFPS: Double(fps))
            struct RunReport: Encodable {
                let mode: String
                let movingCaptureFixture: Bool
                let displayLinkFramesPerSecond: Int
                let captureExclusion: CaptureExclusion?
                let requestedCaptureDimensions: PixelSize?
                let cancelled: Bool
                let stopReason: StopReason
                let windowVisibleAtStop: Bool
                let requestedDuration: Double
                let elapsedDuration: Double
                let drained: Bool
                let timing: PerformanceReport
                let frameTimings: [RenderFrameTiming]
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(
                RunReport(
                    mode: live ? "live-capture" : "synthetic", movingCaptureFixture: live,
                    displayLinkFramesPerSecond: loop.displayLinkFramesPerSecond,
                    captureExclusion: captureExclusion,
                    requestedCaptureDimensions: requestedCaptureDimensions,
                    cancelled: cancelled,
                    stopReason: reason, windowVisibleAtStop: visibleAtStop,
                    requestedDuration: duration, elapsedDuration: elapsed,
                    drained: drained, timing: report,
                    frameTimings: renderer.statistics.frameTimings()))
            {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            exit(!cancelled && drained && report.passesCadence ? 0 : 2)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(reason: .windowClosed)
        return false
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        // WindowServer may stop presenting completely covered windows. That is
        // an interrupted measurement, not evidence of a failing GPU or cadence.
        guard notification.object as? NSWindow === window,
            startedAt > 0, !window.occlusionState.contains(.visible)
        else { return }
        finish(reason: .windowOccluded)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        finish(reason: .applicationQuit)
        return .terminateCancel
    }

    private func update() {
        guard !finishing else { return }
        if renderer.statistics.isStalled(at: CACurrentMediaTime()) {
            finish(reason: window.occlusionState.contains(.visible) ? .graphicsStall : .windowOccluded)
            return
        }
        var settings = DuoSettings()
        settings.glowEnabled = true
        let elapsed = CACurrentMediaTime() - startedAt
        renderer.update(angle: 34 + sin(elapsed * 2.4) * 18, settings: settings, reduceMotion: false)
    }

    private static func syntheticBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        guard
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
                == kCVReturnSuccess,
            let buffer
        else { throw RenderError.unavailable }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let data = CVPixelBufferGetBaseAddress(buffer) else { throw RenderError.unavailable }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * stride + x * 4
                bytes[i] = UInt8(170 + x * 65 / width)
                bytes[i + 1] = UInt8(100 + y * 110 / height)
                bytes[i + 2] = UInt8(120 + x * 90 / width)
                bytes[i + 3] = 255
            }
        }
        return buffer
    }
}
