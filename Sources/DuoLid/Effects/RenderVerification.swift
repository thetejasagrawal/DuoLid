import AppKit
import DuoLidCore
import MetalKit

/// Uses synthetic pixels only. This does not request or read the desktop.
@MainActor
enum RenderVerification {
    static func run() throws {
        let renderer = try MetalRenderer(frames: CapturedFrame())
        let width = 768
        let height = 480
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = renderer.device.hasUnifiedMemory ? .shared : .managed
        guard let source = renderer.device.makeTexture(descriptor: descriptor) else { throw RenderError.unavailable }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let cell = ((x / 12) + (y / 12)) % 2 == 0
                pixels[offset] = cell ? 170 : 60
                pixels[offset + 1] = UInt8(45 + y * 120 / height)
                pixels[offset + 2] = cell ? 110 : 35
            }
        }
        source.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        renderer.backingScale = 1
        renderer.progress = 0
        let clear = try read(renderer.renderOffscreen(source: source))
        let maxDelta = zip(clear, pixels).map { abs(Int($0) - Int($1)) }.max()!
        guard maxDelta <= 1 else { throw checkError("Open screen changed by \(maxDelta) levels.") }
        renderer.progress = 0.85
        renderer.settings.perspective = 0
        renderer.settings.shadow = 0
        renderer.progress = 0.4
        let sweep = try read(renderer.renderOffscreen(source: source))
        let unchangedBottom = ((height * 3 / 4)..<height).allSatisfy { y in
            (0..<width).allSatisfy { x in
                let offset = (y * width + x) * 4
                return (0..<3).allSatisfy { abs(Int(sweep[offset + $0]) - Int(pixels[offset + $0])) <= 1 }
            }
        }
        guard unchangedBottom else { throw checkError("The lower screen blurred before the sweep reached it.") }
        renderer.progress = 1
        let blurred = try read(renderer.renderOffscreen(source: source))
        let clearEdges = edgeEnergy(clear, width: width, height: height)
        let blurredEdges = edgeEnergy(blurred, width: width, height: height)
        guard blurredEdges < clearEdges * 0.25 else { throw checkError("Blur did not reduce high-frequency detail.") }
        renderer.settings.glowEnabled = true
        renderer.settings.glowIntensity = 1
        renderer.settings.glowCorners = .lower
        let glow = try read(renderer.renderOffscreen(source: source))
        func luminanceGain(x: Int, y: Int) -> Double {
            let offset = (y * width + x) * 4
            return (0..<3).map { Double(glow[offset + $0]) - Double(blurred[offset + $0]) }.reduce(0, +) / 3
        }
        let lowerGain = luminanceGain(x: 15, y: height - 15)
        let upperGain = luminanceGain(x: 15, y: 15)
        guard lowerGain > 20, upperGain < 2 else {
            throw checkError("Corner selection did not confine the glow: \(lowerGain), \(upperGain).")
        }
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
            "artifacts/render-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try png(clear, width: width, height: height).write(to: output.appendingPathComponent("01-clear.png"))
        try png(blurred, width: width, height: height).write(to: output.appendingPathComponent("02-duo-blur.png"))
        try png(glow, width: width, height: height).write(to: output.appendingPathComponent("03-lower-glow.png"))
        try png(sweep, width: width, height: height).write(to: output.appendingPathComponent("04-top-down-sweep.png"))
        renderer.settings.glowEnabled = false
        renderer.settings.perspective = 0.9
        renderer.progress = 0.8
        let folded = try read(renderer.renderOffscreen(source: source))
        let topSample = (height / 10 * width + width / 2) * 4
        let hingeSample = ((height - 2) * width + width / 2) * 4
        guard folded[topSample] <= 5, folded[topSample + 1] <= 5,
            folded[hingeSample + 1] > 50
        else { throw checkError("The desktop frame did not descend toward the hinge.") }
        try png(folded, width: width, height: height).write(to: output.appendingPathComponent("05-hinged-frame.png"))
        renderer.settings.glowEnabled = true
        renderer.settings.glowCorners = .all
        let bleeding = try read(renderer.renderOffscreen(source: source))
        let topCorner = LidMath.projectedPoint(
            x: 0.08, y: 0,
            radians: renderer.settings.style.perspective * renderer.settings.perspective * renderer.progress)
        let bleedSample = (Int((topCorner.y - 0.04) * Double(height)) * width + Int(topCorner.x * Double(width))) * 4
        let spillGain = (0..<3).map { Int(bleeding[bleedSample + $0]) - Int(folded[bleedSample + $0]) }.max()!
        guard spillGain > 40, bleeding[topSample] <= 5 else {
            throw checkError("The corner light did not bleed softly into the dark background.")
        }
        try png(bleeding, width: width, height: height).write(to: output.appendingPathComponent("07-edge-glow.png"))
        renderer.settings.edgeBleed = 0
        let noBleed = try read(renderer.renderOffscreen(source: source))
        renderer.settings.edgeBleed = 1
        let fullBleed = try read(renderer.renderOffscreen(source: source))
        let fullGain = (0..<3).map { Int(fullBleed[bleedSample + $0]) - Int(bleeding[bleedSample + $0]) }.max()!
        guard (0..<3).allSatisfy({ noBleed[bleedSample + $0] <= 5 }), fullGain > 15 else {
            throw checkError("Edge bleed does not adjust independently from the screen glow.")
        }
        try png(fullBleed, width: width, height: height).write(
            to: output.appendingPathComponent("08-full-edge-bleed.png"))
        renderer.settings.edgeBleed = DuoSettings().edgeBleed
        var variants = 0
        for style in EffectStyle.allCases {
            for palette in GlowPalette.allCases {
                renderer.settings.style = style
                renderer.settings.glowPalette = palette
                renderer.settings.glowCorners = .all
                _ = try renderer.renderOffscreen(source: source)
                variants += 1
            }
        }
        try checkPartialBlur(renderer, source: source)
        try checkBlurSampling(renderer, source: source, width: width, height: height, output: output)
        try benchmarkNativeResolution(renderer)
        print(
            "Metal verification passed: open pixels unchanged; blur edge energy \(String(format: "%.2f", blurredEdges / clearEdges))×; glow confined to selected corners; \(variants) style/palette combinations rendered."
        )
        print("Synthetic render artifacts: \(output.path)")
    }

    private static func benchmarkNativeResolution(_ renderer: MetalRenderer) throws {
        let screen = DesktopEffect.builtInScreen
        let width = screen.map { Int($0.frame.width * $0.backingScaleFactor) } ?? 3456
        let height = screen.map { Int($0.frame.height * $0.backingScaleFactor) } ?? 2234
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = renderer.device.hasUnifiedMemory ? .shared : .managed
        descriptor.usage = .shaderRead
        guard let source = renderer.device.makeTexture(descriptor: descriptor) else { throw RenderError.unavailable }
        let synthetic = [UInt8](repeating: 128, count: width * height * 4)
        source.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: synthetic, bytesPerRow: width * 4)
        renderer.settings = DuoSettings()
        renderer.settings.glowEnabled = true
        renderer.backingScale = 2
        var times: [Double] = []
        for progress in [0.01, 0.02, 0.035, 0.05, 0.065, 0.07, 0.08, 0.12, 0.2, 0.5, 0.8, 1.0] {
            renderer.progress = progress
            var samples: [Double] = []
            for repetition in 0..<4 {
                try autoreleasepool {
                    _ = try renderer.renderOffscreen(source: source)
                    if repetition > 0 { samples.append(renderer.lastGPUTime * 1_000) }
                }
            }
            samples.sort()
            times.append(contentsOf: samples)
            print(
                "Gaussian sigma \(String(format: "%.2f", progress * 57)): median \(String(format: "%.2f", samples[1])) ms, max \(String(format: "%.2f", samples.last!)) ms."
            )
        }
        times.sort()
        print(
            "Native \(width)×\(height) GPU timing, blur + fold + glow: median \(String(format: "%.2f", times[times.count / 2])) ms, maximum \(String(format: "%.2f", times.last!)) ms across \(times.count) samples covering narrow and broad blur."
        )
    }

    private static func checkPartialBlur(_ renderer: MetalRenderer, source: MTLTexture) throws {
        var largestDifference = 0
        // Alternate deep and shallow folds so an accidental read below the
        // freshly computed rows encounters stale pixels from another angle.
        for style in EffectStyle.allCases {
            renderer.settings = DuoSettings()
            renderer.settings.style = style
            renderer.settings.glowEnabled = true
            renderer.settings.glowIntensity = 1
            renderer.settings.edgeBleed = 1
            renderer.backingScale = 2
            for progress in [0.7, 0.02, 0.5, 0.05, 0.2, 0.035, 0.065, 0.1, 0.4] {
                try autoreleasepool {
                    renderer.progress = progress
                    let optimized = try read(renderer.renderOffscreen(source: source))
                    let reference = try read(renderer.renderOffscreen(source: source, fullResolutionBlur: true))
                    largestDifference = max(
                        largestDifference, zip(optimized, reference).map { abs(Int($0) - Int($1)) }.max()!)
                }
            }
        }
        guard largestDifference <= 4 else {
            throw checkError("Partial blur or halo sampled incorrect pixels: difference \(largestDifference)/255.")
        }
        print(
            "Partial blur and reversal reference passed: maximum channel difference \(largestDifference)/255 across all three styles with maximum glow and bleed."
        )
    }

    private static func checkBlurSampling(
        _ renderer: MetalRenderer, source: MTLTexture, width: Int, height: Int, output: URL
    ) throws {
        // A narrow bright line exposes sparse-kernel echoes that broad checkerboards miss.
        var line = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                line[offset + 3] = 255
                if abs(x - width / 2) < 3 {
                    for channel in 0..<3 { line[offset + channel] = 255 }
                }
            }
        }
        source.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: line, bytesPerRow: width * 4)
        renderer.settings = DuoSettings()
        renderer.settings.perspective = 0
        renderer.settings.shadow = 0
        renderer.backingScale = 2
        renderer.progress = 1
        let result = try read(renderer.renderOffscreen(source: source))
        try png(result, width: width, height: height).write(
            to: output.appendingPathComponent("06-smooth-highlight.png"))
        let row = height / 12
        let jumps = ((width / 2 - 200)..<(width / 2 + 200)).map { x in
            abs(Int(result[(row * width + x) * 4]) - Int(result[(row * width + x + 1) * 4]))
        }
        guard jumps.max()! <= 2 else {
            throw checkError(
                "Blur has sparse sampling echoes: adjacent highlight pixels jump by \(jumps.max()!) levels.")
        }
        print("Blur sampling passed: isolated highlight is smooth (maximum adjacent step \(jumps.max()!) levels).")
        var largestDifference = 0
        for progress in [0.065, 0.07, 0.08, 0.15, 0.3, 0.6, 1.0] {
            renderer.progress = progress
            let optimized = try read(renderer.renderOffscreen(source: source))
            let reference = try read(renderer.renderOffscreen(source: source, fullResolutionBlur: true))
            let difference = zip(optimized, reference).map { abs(Int($0) - Int($1)) }.max()!
            largestDifference = max(largestDifference, difference)
        }
        guard largestDifference <= 4 else {
            throw checkError(
                "Optimized Gaussian diverged from the native-resolution reference by \(largestDifference) levels.")
        }
        print(
            "Blur quality reference passed: maximum channel difference \(largestDifference)/255 across seven fold positions, including the blur-resolution transition."
        )
    }

    private static func checkError(_ message: String) -> Error {
        NSError(domain: "DuoLid.RenderVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func read(_ texture: MTLTexture) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &data, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0)
        return data
    }

    private static func edgeEnergy(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        var energy = 0.0
        for y in 5..<(height - 5) {
            for x in 5..<(width - 5) {
                let i = (y * width + x) * 4
                energy += abs(Double(pixels[i]) - Double(pixels[i + 4]))
            }
        }
        return energy / Double(width * height)
    }

    private static func png(_ pixels: [UInt8], width: Int, height: Int) -> Data {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    }
}
