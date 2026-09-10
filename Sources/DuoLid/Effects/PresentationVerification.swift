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
    private var escapeMonitor: Any?
    private var startedAt = 0.0
    private var finishing = false

    init(arguments args: [String] = CommandLine.arguments) throws {
        guard let screen = DesktopEffect.builtInScreen, let displayID = screen.displayID else {
            throw RenderError.unavailable
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
        renderer = try MetalRenderer(frames: frames, device: CGDirectDisplayCopyCurrentMetalDevice(displayID))
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
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: contentRect.size))
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.maximumDrawableCount = 2
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
        renderer.onFailure = { [weak self] _ in self?.finish(cancelled: true) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.finish(cancelled: true) }
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
                    if !Task.isCancelled { finish(cancelled: false) }
                }
            } catch { finish(cancelled: true) }
        }
    }

    private func startCapture() async throws {
        let content = try await CaptureContent.fetch()
        guard !finishing, !Task.isCancelled else { return }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RenderError.unavailable
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        if #available(macOS 14.2, *) { filter.includeMenuBar = true }
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        configuration.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
        configuration.queueDepth = 4
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        let receiver = StreamReceiver(frames: frames) { [weak self] _ in
            Task { @MainActor in self?.finish(cancelled: true) }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        try stream.addStreamOutput(
            receiver, type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "app.duolid.diagnostic.capture", qos: .userInteractive))
        self.receiver = receiver
        self.stream = stream
        try await stream.startOnMainActor()
    }

    private func finish(cancelled: Bool) {
        guard !finishing else { return }
        finishing = true
        window.orderOut(nil)
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
                let cancelled: Bool
                let drained: Bool
                let timing: PerformanceReport
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(
                RunReport(
                    mode: live ? "live-capture" : "synthetic", cancelled: cancelled, drained: drained, timing: report))
            {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            exit(!cancelled && drained && report.passesCadence ? 0 : 2)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(cancelled: true)
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        finish(cancelled: true)
        return .terminateCancel
    }

    private func update() {
        guard !finishing else { return }
        if renderer.statistics.isStalled(at: CACurrentMediaTime()) {
            finish(cancelled: true)
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
