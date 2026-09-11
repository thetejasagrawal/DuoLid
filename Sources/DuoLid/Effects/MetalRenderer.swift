import AppKit
import CoreVideo
import DuoLidCore
import MetalKit
import MetalPerformanceShaders
import OSLog

enum RenderLog {
    static let logger = Logger(subsystem: "app.duolid.DuoLid", category: "Rendering")
}

/// All callback-produced counters are protected by one lock. Snapshots own copies.
final class RenderStatistics: @unchecked Sendable {
    private let frames: CapturedFrame
    init(frames: CapturedFrame, recordsFrameTimings: Bool = false) {
        self.frames = frames
        timeline = recordsFrameTimings ? RenderFrameTimeline() : nil
    }
    private let lock = NSLock()
    private var timeline: RenderFrameTimeline?
    private var count = 0, skipped = 0
    private var gpuTime = 0.0, arrivalAge = 0.0, cpuTime = 0.0
    private var presentationLead = 0.0, queueWait = 0.0
    private var preparationMS: Double?
    private var renderedDimensions: PixelSize?
    private var timestamps: [Double] = []
    private var writeIndex = 0
    private var pending: [UInt64: Double] = [:]
    private var firstSubmission: Double?
    private var lastPresentation: Double?
    func submitted(_ frame: RenderFrameTiming) {
        lock.withLock {
            pending[frame.id] = frame.submittedAt
            if firstSubmission == nil { firstSubmission = frame.submittedAt }
            timeline?.submitted(frame)
        }
    }
    func completed(id: UInt64, start: Double, end: Double, success: Bool) {
        lock.withLock {
            pending.removeValue(forKey: id)
            timeline?.completed(id: id, start: start, end: end, success: success)
        }
    }
    func frameTimings() -> [RenderFrameTiming] { lock.withLock { timeline?.frames ?? [] } }
    func isStalled(at time: Double) -> Bool {
        lock.withLock {
            if let oldest = pending.values.min(), time - oldest > 0.75 { return true }
            guard let since = lastPresentation ?? firstSubmission else { return false }
            return time - since > 1
        }
    }

    func presented(id: UInt64, at time: Double) {
        guard time.isFinite, time > 0 else { return }
        lock.withLock {
            lastPresentation = max(lastPresentation ?? 0, time)
            if timestamps.count < 8_192 { timestamps.append(time) } else { timestamps[writeIndex % 8_192] = time }
            writeIndex += 1
            timeline?.presented(id: id, at: time)
        }
    }
    func skip() { lock.withLock { skipped += 1 } }
    func prepared(in seconds: Double) { lock.withLock { preparationMS = seconds * 1_000 } }
    func rendered(width: Int, height: Int) {
        lock.withLock { renderedDimensions = PixelSize(width: width, height: height) }
    }
    func record(gpu: Double, age: Double, cpu: Double, lead: Double, wait: Double) {
        lock.withLock {
            count += 1
            gpuTime += max(0, gpu)
            arrivalAge += max(0, age)
            cpuTime += max(0, cpu)
            presentationLead += lead
            queueWait += max(0, wait)
        }
    }
    func snapshot(targetFPS: Double, warmup: Double = 0.25) -> PerformanceReport {
        lock.withLock {
            let scale = 1_000 / Double(max(1, count))
            return PerformanceReport(
                targetFPS: targetFPS, completedFrames: count,
                skippedSubmissions: skipped, gpuMS: gpuTime * scale, cpuMS: cpuTime * scale,
                gpuQueueMS: queueWait * scale, captureArrivalAgeMS: arrivalAge * scale,
                presentationLeadMS: presentationLead * scale,
                presentation: PresentationTiming(timestamps: timestamps, targetFPS: targetFPS, warmup: warmup),
                capture: frames.timing(), preparationMS: preparationMS, renderedDimensions: renderedDimensions)
        }
    }
    func recentTimestamps(since time: Double) -> [Double] {
        lock.withLock { timestamps.filter { $0 >= time } }
    }
    func report(targetFPS: Double) {
        let value = snapshot(targetFPS: targetFPS)
        guard value.completedFrames > 0 else { return }
        RenderLog.logger.notice(
            "Presented: \(value.presentation.framesPerSecond, format: .fixed(precision: 1)) fps, p95 \(value.presentation.p95IntervalMS, format: .fixed(precision: 2)) ms, missed \(value.presentation.missedDeadlineRatio * 100, format: .fixed(precision: 2))%; GPU \(value.gpuMS, format: .fixed(precision: 2)) ms, CPU \(value.cpuMS, format: .fixed(precision: 2)) ms, queue \(value.gpuQueueMS, format: .fixed(precision: 2)) ms"
        )
    }
}

final class CapturedFrame: @unchecked Sendable {
    private let source: CaptureTiming.Source
    private var arrivals: [Double] = []
    private var received = 0
    private var dimensions: PixelSize?
    init(source: CaptureTiming.Source = .synthetic) { self.source = source }
    func timing() -> CaptureTiming {
        lock.withLock {
            CaptureTiming(
                source: source, receivedFrames: received, timestamps: arrivals,
                now: ProcessInfo.processInfo.systemUptime, dimensions: dimensions)
        }
    }
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var timestamp: TimeInterval = 0
    func set(_ buffer: CVPixelBuffer) {
        lock.lock()
        defer { lock.unlock() }
        self.buffer = buffer
        dimensions = PixelSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        timestamp = ProcessInfo.processInfo.systemUptime
        if arrivals.count < 512 { arrivals.append(timestamp) } else { arrivals[received % 512] = timestamp }
        received += 1
    }
    func get() -> (CVPixelBuffer, TimeInterval)? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer else { return nil }
        return (buffer, timestamp)
    }
    func clear() {
        lock.lock()
        buffer = nil
        timestamp = 0
        lock.unlock()
    }
}

struct EffectUniforms {
    var progress: Float
    var perspective: Float
    var shade: Float
    var glow: Float
    var spread: Float
    var aspect: Float
    var corners: Float
    var blurGradient: Float
    var bleed: Float
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    var colorC: SIMD4<Float>
}

/// Shader compilation is shared across capture sessions, never repeated during a fold.
// Metal devices and immutable pipeline states are documented for concurrent use.
// Fully initialized before publication. Metal devices and compiled pipelines
// support concurrent use; older SDKs omit their Sendable annotations. Mutable
// command encoders and working textures belong to each renderer, never this cache.
private final class EffectGPU: @unchecked Sendable {
    private static let cache = Cache()
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var values: [UInt64: EffectGPU] = [:]
    }
    static func get(device: MTLDevice) throws -> EffectGPU {
        try cache.lock.withLock {
            if let existing = cache.values[device.registryID] { return existing }
            let value = try EffectGPU(device: device)
            cache.values[device.registryID] = value
            return value
        }
    }
    let device: MTLDevice
    let composite: MTLRenderPipelineState
    private init(device: MTLDevice) throws {
        self.device = device
        let library: MTLLibrary
        if let url = Bundle.main.url(forResource: "Effects", withExtension: "metallib") {
            library = try device.makeLibrary(URL: url)
        } else {
            #if DUOLID_PACKAGED
                throw RenderError.shaderMissing
            #else
                // Source builds work without Xcode's Metal toolchain. The release
                // packaging script requires and includes the compiled library.
                guard
                    let url = Bundle.main.url(forResource: "Effects", withExtension: "metal")
                        ?? Bundle.module.url(forResource: "Effects", withExtension: "metal")
                else { throw RenderError.shaderMissing }
                library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
            #endif
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fullScreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "duoComposite")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        composite = try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

enum RenderError: LocalizedError {
    case unavailable, shaderMissing
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Metal graphics are unavailable on this Mac."
        case .shaderMissing: return "DuoLid’s effect resources are missing. Rebuild or reinstall the app."
        }
    }
}

final class MetalRenderer: NSObject, @unchecked Sendable {
    // WindowServer can retain the displayed and pending surfaces simultaneously.
    // Leave a third surface available for rendering; GPU submissions stay capped
    // at two by inFlight and always read the latest captured input.
    static let drawableCount = 3
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let compositePipeline: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var softBlur: MTLTexture?
    private var deepBlur: MTLTexture?
    private var reducedSource: MTLTexture?
    private var reducedSoftBlur: MTLTexture?
    private var reducedDeepBlur: MTLTexture?
    private let downsample: MPSImageBilinearScale
    private var softKernel: MPSImageGaussianBlur?
    private var deepKernel: MPSImageGaussianBlur?
    // Never queue old frames behind a busy GPU; the next draw takes the newest capture.
    private let inFlight = DispatchSemaphore(value: 2)
    let frames: CapturedFrame
    private let liveAngle: LatestLidSample?
    private var submissionID: UInt64 = 0
    private var hasCommittedWork = false
    private var didPrepareBlur = false
    private var preparationFailed = false
    private struct State {
        var settings = DuoSettings()
        var progress = 0.0
        var backingScale = 2.0
        var reduceMotion = false
        var targetAngle: Double?
        var useLiveAngle = true
    }
    private let stateLock = NSLock()
    private var state = State()
    private var smoother = AngleSmoother()
    var settings: DuoSettings {
        get { stateLock.withLock { state.settings } }
        set { stateLock.withLock { state.settings = newValue } }
    }
    var progress: Double {
        get { stateLock.withLock { state.progress } }
        set { stateLock.withLock { state.progress = newValue } }
    }
    var backingScale: Double {
        get { stateLock.withLock { state.backingScale } }
        set { stateLock.withLock { state.backingScale = newValue } }
    }
    var reduceMotion: Bool {
        get { stateLock.withLock { state.reduceMotion } }
        set { stateLock.withLock { state.reduceMotion = newValue } }
    }
    var onPresent: (@MainActor @Sendable () -> Void)?
    var onFailure: (@MainActor @Sendable (String) -> Void)?
    private(set) var lastGPUTime = 0.0
    private var scheduledFirstPresentation = false
    let statistics: RenderStatistics
    var targetFPS = 60.0

    static func prepare(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        if let device { _ = try? EffectGPU.get(device: device) }
    }

    init(
        frames: CapturedFrame, device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        liveAngle: LatestLidSample? = nil, recordsFrameTimings: Bool = false
    )
        throws
    {
        guard let device else { throw RenderError.unavailable }
        let gpu = try EffectGPU.get(device: device)
        guard let queue = device.makeCommandQueue() else { throw RenderError.unavailable }
        self.device = device
        commandQueue = queue
        self.frames = frames
        statistics = RenderStatistics(frames: frames, recordsFrameTimings: recordsFrameTimings)
        self.liveAngle = liveAngle
        compositePipeline = gpu.composite
        downsample = MPSImageBilinearScale(device: device)
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    func update(angle: Double, settings: DuoSettings, reduceMotion: Bool, useLiveAngle: Bool = true) {
        stateLock.withLock {
            state.useLiveAngle = useLiveAngle
            state.targetAngle = angle
            state.settings = settings
            state.reduceMotion = reduceMotion
        }
    }

    /// Called only on the dedicated render queue. No AppKit or SwiftUI work runs here.
    func draw(
        to layer: CAMetalLayer, at presentationTime: CFTimeInterval = CACurrentMediaTime(),
        minimumDuration: CFTimeInterval? = nil
    ) {
        guard !preparationFailed, let (buffer, _) = frames.get() else { return }
        if !didPrepareBlur {
            guard let (retainedTexture, source) = sourceTexture(for: buffer),
                prepareBlur(source: source, input: FrameLease(texture: retainedTexture, buffer: buffer))
            else {
                preparationFailed = true
                let failure = onFailure
                Task { @MainActor in failure?("Graphics preparation did not finish. DuoLid has paused the effect.") }
                return
            }
            didPrepareBlur = true
        }
        guard inFlight.wait(timeout: .now()) == .success else {
            statistics.skip()
            return
        }
        let requestedAt = CACurrentMediaTime()
        guard let drawable = layer.nextDrawable() else {
            inFlight.signal()
            return
        }
        draw(drawable: drawable, at: presentationTime, requestedAt: requestedAt, minimumDuration: minimumDuration)
    }

    private func draw(
        drawable: CAMetalDrawable, at presentationTime: CFTimeInterval, requestedAt: CFTimeInterval,
        minimumDuration: CFTimeInterval?
    ) {
        let began = CACurrentMediaTime()
        var committed = false
        defer { if !committed { inFlight.signal() } }
        guard let (pixelBuffer, receivedAt) = frames.get() else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard
            let (retainedTexture, source) = sourceTexture(for: pixelBuffer),
            let command = commandQueue.makeCommandBuffer()
        else { return }
        // Allocate both blur levels while the first captured frame is prepared,
        // including at zero progress, so crossing the blur threshold allocates no textures.
        prepareTextures(width: width, height: height)
        prepareReducedTextures(width: max(1, width / 2), height: max(1, height / 2))
        let input = FrameLease(texture: retainedTexture, buffer: pixelBuffer)
        var snapshot = stateLock.withLock { state }
        if let target = (snapshot.useLiveAngle ? liveAngle?.get() : nil) ?? snapshot.targetAngle {
            let angle = smoother.update(target, at: presentationTime, response: snapshot.settings.response) ?? target
            snapshot.progress = LidMath.progress(angle: angle, clearAngle: snapshot.settings.clearAngle)
        }
        guard encodeEffect(command: command, source: source, target: drawable.texture, state: snapshot) else { return }
        let semaphore = inFlight
        let statistics = statistics
        statistics.rendered(width: drawable.texture.width, height: drawable.texture.height)
        submissionID &+= 1
        let id = submissionID
        drawable.addPresentedHandler { drawable in statistics.presented(id: id, at: drawable.presentedTime) }
        let frameAge = max(0, ProcessInfo.processInfo.systemUptime - receivedAt)
        let submitted = CACurrentMediaTime()
        let failure = onFailure
        let firstFrame = scheduledFirstPresentation ? nil : FirstFrameSignal(action: onPresent)
        scheduledFirstPresentation = true
        statistics.submitted(
            RenderFrameTiming(
                id: id, targetTime: presentationTime, drawableRequestedAt: requestedAt,
                encodingStartedAt: began, submittedAt: submitted))
        command.addCompletedHandler { command in
            // Keep the IOSurface-backed input alive until the GPU has finished reading it.
            withExtendedLifetime(input) {}
            semaphore.signal()
            let success = command.status == .completed && command.error == nil
            statistics.completed(id: id, start: command.gpuStartTime, end: command.gpuEndTime, success: success)
            firstFrame?.completed(success: success)
            statistics.record(
                gpu: command.gpuEndTime - command.gpuStartTime, age: frameAge,
                cpu: submitted - began, lead: presentationTime - submitted,
                wait: max(0, command.gpuStartTime - submitted))
            if let error = command.error {
                let message = error.localizedDescription
                Task { @MainActor in failure?(message) }
            }
        }
        if let firstFrame {
            drawable.addPresentedHandler { firstFrame.presented(at: $0.presentedTime) }
        }
        // Present only once Metal has scheduled the writes to this drawable.
        // Calling drawable.present() immediately after commit can race scheduling
        // and expose an unwritten surface.
        // Base continuous frame pacing on the previous actual presentation. This
        // prevents 8.3/25 ms pairs at a 60 fps target on a 120 Hz compositor.
        // Animation still samples the display link's predicted target time.
        if let minimumDuration, minimumDuration.isFinite, minimumDuration > 0 {
            command.present(drawable, afterMinimumDuration: minimumDuration)
        } else if presentationTime.isFinite, presentationTime > submitted {
            command.present(drawable, atTime: presentationTime)
        } else {
            command.present(drawable)
        }
        hasCommittedWork = true
        command.commit()
        committed = true
    }

    private func sourceTexture(for buffer: CVPixelBuffer) -> (CVMetalTexture, MTLTexture)? {
        guard let cache = textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        guard
            CVMetalTextureCacheCreateTextureFromImage(
                nil, cache, buffer, nil, .bgra8Unorm,
                CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &cvTexture) == kCVReturnSuccess,
            let retainedTexture = cvTexture, let texture = CVMetalTextureGetTexture(retainedTexture)
        else { return nil }
        return (retainedTexture, texture)
    }

    /// Exercise both Gaussian texture formats before the first visible frame.
    /// Metal Performance Shaders specializes its work lazily; crossing from the
    /// broad half-size blur to a narrow native blur must not do that mid-fold.
    /// Runs once on the rendering owner during the brief capture preparation.
    private func prepareBlur(source: MTLTexture, input: FrameLease) -> Bool {
        let began = CACurrentMediaTime()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: source.width, height: source.height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        guard let target = device.makeTexture(descriptor: descriptor),
            let command = commandQueue.makeCommandBuffer()
        else { return false }
        var preparation = State()
        preparation.backingScale = 1
        preparation.settings.intensity = 1
        for sigma in [2.0, 3.875, 24.0] {
            preparation.progress = sigma / preparation.settings.style.radius
            guard encodeEffect(command: command, source: source, target: target, state: preparation) else {
                return false
            }
        }
        let completed = DispatchSemaphore(value: 0)
        command.addCompletedHandler { _ in
            withExtendedLifetime(input) {}
            completed.signal()
        }
        hasCommittedWork = true
        command.commit()
        // Never block the main actor or wait indefinitely on the GPU. A failed
        // preparation follows the same fenced retirement as a visible session.
        guard completed.wait(timeout: .now() + 0.5) == .success,
            command.status == .completed, command.error == nil
        else { return false }
        statistics.prepared(in: CACurrentMediaTime() - began)
        return true
    }

    /// The production renderer and offscreen verification use this same pipeline.
    private func encodeEffect(
        command: MTLCommandBuffer, source: MTLTexture, target: MTLTexture, state: State,
        fullResolutionBlur: Bool = false
    ) -> Bool {
        let settings = state.settings
        let progress = state.progress
        let backingScale = state.backingScale
        let reduceMotion = state.reduceMotion
        let width = source.width
        let height = source.height
        let sigma = Float(settings.style.radius * settings.intensity * progress * backingScale)
        let gradient: Float = settings.style == .frost ? 0 : 1
        var deep: MTLTexture = source
        var soft: MTLTexture = source
        if sigma >= 0.25 {
            let reduced = sigma >= 4 && !fullResolutionBlur
            var blurSource = source
            let workingSigma = sigma * (reduced ? 0.5 : 1)
            if reduced {
                prepareReducedTextures(width: width / 2, height: height / 2)
                guard let reducedSource, let reducedDeepBlur, let reducedSoftBlur else { return false }
                // A 2× box prefilter, dense Gaussian, and bilinear reconstruction.
                // Used only for broad blur; the sharp source remains full Retina.
                downsample.encode(commandBuffer: command, sourceTexture: source, destinationTexture: reducedSource)
                blurSource = reducedSource
                deep = reducedDeepBlur
                soft = reducedSoftBlur
            } else {
                prepareTextures(width: width, height: height)
                guard let deepBlur, let softBlur else { return false }
                deep = deepBlur
                soft = softBlur
            }
            // The blur sweep reaches y = 1.36 * progress. Keep the sharp source
            // full-size, but only compute destination rows that the compositor
            // can sample. Two extra rows cover bilinear filtering at the edge.
            // The reference path deliberately computes the entire image.
            let rows =
                fullResolutionBlur
                ? blurSource.height
                : min(
                    blurSource.height, max(1, Int(ceil(Double(blurSource.height) * 1.36 * progress)) + 2))
            let region = MTLRegionMake2D(0, 0, blurSource.width, rows)
            updateKernel(&deepKernel, sigma: workingSigma)
            deepKernel?.clipRect = region
            deepKernel?.encode(commandBuffer: command, sourceTexture: blurSource, destinationTexture: deep)
            if gradient > 0 {
                updateKernel(&softKernel, sigma: workingSigma * (settings.style == .duo ? 0.28 : 0.64))
                softKernel?.clipRect = region
                softKernel?.encode(commandBuffer: command, sourceTexture: blurSource, destinationTexture: soft)
            }
        }
        let palette = settings.glowPalette.colors.map { SIMD4<Float>(Float($0[0]), Float($0[1]), Float($0[2]), 1) }
        var uniforms = EffectUniforms(
            progress: Float(progress),
            perspective: Float(reduceMotion ? 0 : settings.style.perspective * settings.perspective),
            shade: Float(settings.style.shade * settings.shadow * 2),
            glow: Float(settings.glowEnabled ? settings.glowIntensity : 0), spread: Float(settings.glowSpread),
            aspect: Float(width) / Float(height),
            corners: settings.glowCorners == .all ? 0 : settings.glowCorners == .lower ? 1 : 2,
            blurGradient: gradient,
            bleed: Float(settings.edgeBleed),
            colorA: palette[0], colorB: palette[1], colorC: palette[2]
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(deep, index: 1)
        encoder.setFragmentTexture(gradient > 0 ? soft : source, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    func renderOffscreen(source: MTLTexture, fullResolutionBlur: Bool = false) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: source.width, height: source.height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let target = device.makeTexture(descriptor: descriptor),
            let command = commandQueue.makeCommandBuffer(),
            encodeEffect(
                command: command, source: source, target: target, state: stateLock.withLock { state },
                fullResolutionBlur: fullResolutionBlur)
        else { throw RenderError.unavailable }
        if !device.hasUnifiedMemory, let blit = command.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        lastGPUTime = command.gpuEndTime - command.gpuStartTime
        return target
    }

    private func prepareTextures(width: Int, height: Int) {
        guard deepBlur?.width != width || deepBlur?.height != height else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        softBlur = device.makeTexture(descriptor: descriptor)
        deepBlur = device.makeTexture(descriptor: descriptor)
    }

    private func updateKernel(_ kernel: inout MPSImageGaussianBlur?, sigma: Float) {
        let radius = max(0.5, (sigma * 8).rounded() / 8)
        guard kernel?.sigma != radius else { return }
        kernel = MPSImageGaussianBlur(device: device, sigma: radius)
        kernel?.edgeMode = .clamp
    }

    private func prepareReducedTextures(width: Int, height: Int) {
        guard reducedSource?.width != width || reducedSource?.height != height else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        reducedSource = device.makeTexture(descriptor: descriptor)
        reducedSoftBlur = device.makeTexture(descriptor: descriptor)
        reducedDeepBlur = device.makeTexture(descriptor: descriptor)
    }

    func releaseFrames() {
        statistics.report(targetFPS: targetFPS)
        frames.clear()
        softBlur = nil
        deepBlur = nil
        reducedSource = nil
        reducedSoftBlur = nil
        reducedDeepBlur = nil
        if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) }
    }

    /// Called by the rendering owner after it stops scheduling draws. An empty
    /// command buffer fences earlier submissions without blocking the main actor.
    @discardableResult
    func finishRendering() -> Bool {
        guard hasCommittedWork else {
            releaseFrames()
            return true
        }
        // Failure to create or complete the fence is not evidence that earlier
        // work drained. The caller keeps that surface quarantined until exit.
        guard let fence = commandQueue.makeCommandBuffer() else { return false }
        let finished = DispatchSemaphore(value: 0)
        fence.addCompletedHandler { _ in finished.signal() }
        fence.commit()
        guard finished.wait(timeout: .now() + 2) == .success,
            fence.status == .completed, fence.error == nil
        else { return false }
        releaseFrames()
        return true
    }
}
