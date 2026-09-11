import AppKit
import DuoLidCore
import MetalKit
import SwiftUI

struct PreviewWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var renderingError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preview").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(model.followLid ? "Following your lid" : "Sample desktop")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            VStack(spacing: 0) {
                ZStack {
                    if let preview = model.documentationPreview {
                        Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit)
                    } else if !model.previewRenderingAllowed {
                        PreviewDesktop()
                            .overlay(alignment: .top) {
                                Text("Graphics are paused. Open Settings to review.").font(.caption).padding(10)
                                    .background(.regularMaterial).padding(12)
                            }
                    } else {
                        EffectPreview(
                            angle: model.displayAngle, settings: model.settings,
                            reduceMotion: reduceMotion,
                            onFailure: {
                                renderingError = $0
                                model.previewFailed($0)
                            },
                            registerCleanup: { model.stopPreviewRendering = $0 })
                    }
                    if let renderingError {
                        Text(renderingError).font(.callout).foregroundStyle(.white).padding(24)
                    }
                }
                .aspectRatio(768.0 / 496, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(5)
                .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(.gray.opacity(0.6), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.16), radius: 16, y: 9)
                Capsule().fill(.gray.opacity(0.35)).frame(width: 64, height: 3).padding(.top, 5)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Desktop preview at \(Int(model.displayAngle)) degrees, \(Int(model.previewProgress * 100)) percent effect"
            )
            .padding(.vertical, 16)
            VStack(spacing: 12) {
                HStack {
                    Text("Preview angle").font(.system(size: 12))
                    Spacer()
                    Text("\(Int(model.displayAngle))°").font(.system(size: 12).monospacedDigit()).foregroundStyle(
                        .secondary)
                }
                Slider(
                    value: $model.previewAngle, in: 8...145,
                    onEditingChanged: { editing in
                        if editing {
                            model.stopPreview()
                            model.followLid = false
                        }
                    }
                ).disabled(model.followLid || model.desktopPreview)
                    .accessibilityLabel("Preview angle")
                HStack(spacing: 8) {
                    Button("Closed") { inspect(angle: 8) }
                    Button("Mid-fold") { model.inspectFold() }
                    Button("Open") { inspect(angle: max(112, model.settings.clearAngle + 5)) }
                    Spacer()
                    Toggle(
                        "Follow lid",
                        isOn: Binding(
                            get: { model.followLid },
                            set: { value in
                                model.stopPreview()
                                model.followLid = value
                            })
                    ).toggleStyle(.checkbox).disabled(!model.sensorConnected || model.previewPlaying)
                }.controlSize(.small).font(.system(size: 11))
            }
            .disabled(!model.previewRenderingAllowed)
            .help(
                !model.previewRenderingAllowed
                    ? "Preview controls are unavailable while graphics are stopped."
                    : "Inspect the effect at any lid angle.")
            Spacer(minLength: 22)
            Divider().padding(.bottom, 18)
            HStack(spacing: 10) {
                Button {
                    model.playPreview()
                } label: {
                    Label(
                        model.previewPlaying && !model.desktopPreview ? "Stop animation" : "Animate preview",
                        systemImage: model.previewPlaying && !model.desktopPreview ? "stop.fill" : "play.fill")
                }.disabled(!model.previewRenderingAllowed || model.desktopPreview).help("Animate this preview (⌥⌘P)")
                Spacer(minLength: 0)
                Button {
                    model.playPreview(onDesktop: true)
                } label: {
                    Label(
                        model.desktopPreview ? "Stop test" : "Test on desktop",
                        systemImage: model.desktopPreview ? "stop.fill" : "display")
                }.disabled(
                    !model.previewRenderingAllowed || (model.previewPlaying && !model.desktopPreview)
                        || !model.settings.enabled
                        || !model.settings.blurEnabled
                )
                .help("Test on your real desktop (⌘P)")
            }.controlSize(.large)
            Text(
                !model.previewRenderingAllowed
                    ? "Graphics are stopped. This sample stays still while you adjust settings."
                    : model.desktopPreview
                        ? "Press Esc to pause the desktop effect at any time."
                        : !model.settings.enabled
                            ? "DuoLid is paused. You can still tune the preview."
                            : "Adjust the preview angle to inspect the fold. Changes apply instantly."
            )
            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 10)
            .frame(height: 30, alignment: .topLeading)
        }.padding(28)
            .onChange(of: model.graphicsFailed) { _, failed in
                if !failed { renderingError = nil }
            }
    }

    private func inspect(angle: Double) {
        model.stopPreview()
        model.followLid = false
        model.previewAngle = angle
    }
}

/// Uses synthetic content and the production renderer. No screen access is needed.
private struct EffectPreview: NSViewRepresentable {
    let angle: Double
    let settings: DuoSettings
    let reduceMotion: Bool
    let onFailure: @MainActor @Sendable (String) -> Void
    let registerCleanup: (@escaping @MainActor @Sendable () async -> Void) -> Void

    func makeNSView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.prepare(onFailure: onFailure)
        registerCleanup { [weak view] in await view?.stopRendering() }
        return view
    }
    func updateNSView(_ view: PreviewSurface, context: Context) {
        view.update(angle: angle, settings: settings, reduceMotion: reduceMotion)
    }
}

private final class PreviewSurface: NSView {
    @MainActor private static var quarantinedSurface: PreviewSurface?
    private var renderer: MetalRenderer?
    private var onFailure: (@MainActor @Sendable (String) -> Void)?
    private let renderQueue = DispatchQueue(label: "app.duolid.preview", qos: .userInteractive)
    private var pendingDraw: DispatchWorkItem?
    private var isStopping = false
    private var stopTask: Task<Void, Never>?
    private var lastSettings: DuoSettings?
    private var lastProgress = -1.0
    private var lastReduceMotion = false
    override var wantsUpdateLayer: Bool { true }
    override var isOpaque: Bool { true }
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }

    @MainActor func prepare(onFailure: @escaping @MainActor @Sendable (String) -> Void) {
        self.onFailure = onFailure
        guard Self.quarantinedSurface == nil else {
            DispatchQueue.main.async { onFailure("Restart DuoLid before trying graphics again.") }
            return
        }
        wantsLayer = true
        do {
            let frames = CapturedFrame()
            let renderer = try MetalRenderer(frames: frames)
            guard let layer = layer as? CAMetalLayer else { throw RenderError.unavailable }
            layer.device = renderer.device
            layer.pixelFormat = .bgra8Unorm
            layer.framebufferOnly = true
            layer.maximumDrawableCount = MetalRenderer.drawableCount
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.presentsWithTransaction = false
            layer.displaySyncEnabled = true
            let imageRenderer = ImageRenderer(
                content: PreviewDesktop().frame(width: 384, height: 248).environment(\.colorScheme, .light))
            imageRenderer.scale = 4
            guard let image = imageRenderer.cgImage else { throw RenderError.unavailable }
            var buffer: CVPixelBuffer?
            let attributes: [String: Any] = [
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            guard
                CVPixelBufferCreate(
                    nil, image.width, image.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
                    == kCVReturnSuccess,
                let buffer
            else { throw RenderError.unavailable }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
            guard
                let graphics = CGContext(
                    data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmap.rawValue)
            else { throw RenderError.unavailable }
            graphics.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            frames.set(buffer)
            // Match blur's size relative to the real screen, at the preview's resolution.
            renderer.backingScale = Double(image.height) / Double(DesktopEffect.builtInScreen?.frame.height ?? 1117)
            renderer.onFailure = onFailure
            self.renderer = renderer
        } catch {
            DispatchQueue.main.async { onFailure(error.localizedDescription) }
        }
    }

    func update(angle: Double, settings: DuoSettings, reduceMotion: Bool) {
        let progress = settings.blurEnabled ? LidMath.progress(angle: angle, clearAngle: settings.clearAngle) : 0
        guard settings != lastSettings || progress != lastProgress || reduceMotion != lastReduceMotion else { return }
        lastSettings = settings
        lastProgress = progress
        lastReduceMotion = reduceMotion
        renderer?.settings = settings
        renderer?.progress = progress
        renderer?.reduceMotion = reduceMotion && settings.respectReduceMotion
        requestRender()
    }

    override func layout() {
        super.layout()
        resizeDrawable()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resizeDrawable()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resizeDrawable()
    }

    private func resizeDrawable() {
        guard let layer = layer as? CAMetalLayer else { return }
        let scale = window?.backingScaleFactor ?? 2
        layer.contentsScale = scale
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        if layer.drawableSize != size {
            layer.drawableSize = size
            requestRender()
        }
    }

    private func requestRender() {
        guard !isStopping, let renderer, let layer = layer as? CAMetalLayer, window?.isVisible == true else { return }
        pendingDraw?.cancel()
        // Coalesce slider updates, and keep all GPU work off the UI thread.
        let draw = DispatchWorkItem { autoreleasepool { renderer.draw(to: layer) } }
        pendingDraw = draw
        renderQueue.asyncAfter(deadline: .now() + .milliseconds(8), execute: draw)
    }

    func stopRendering() async {
        if let stopTask {
            await stopTask.value
            return
        }
        isStopping = true
        pendingDraw?.cancel()
        pendingDraw = nil
        let renderer = renderer
        let queue = renderQueue
        let task = Task { @MainActor [self] in
            let drained = await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: renderer?.finishRendering() ?? true)
                }
            }
            if drained {
                self.renderer = nil
            } else {
                Self.quarantinedSurface = self
                onFailure?("Preview graphics did not finish safely. Restart DuoLid before trying again.")
            }
        }
        stopTask = task
        await task.value
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { Task { await stopRendering() } }
        super.viewWillMove(toWindow: newWindow)
    }
}
