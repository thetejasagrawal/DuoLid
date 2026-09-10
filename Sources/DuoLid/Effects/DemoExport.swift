import AppKit
import DuoLidCore
import MetalKit
import SwiftUI

/// Offline documentation media. No capture, sensor, display link, or visible window.
@MainActor
enum DemoExport {
    static func run() throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
            "artifacts/demo")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let imageRenderer = ImageRenderer(
            content: PreviewDesktop().frame(width: 384, height: 248).environment(\.colorScheme, .light))
        imageRenderer.scale = 3
        guard let image = imageRenderer.cgImage else { throw RenderError.unavailable }
        let renderer = try MetalRenderer(frames: CapturedFrame())
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
        try pixels.withUnsafeMutableBytes { bytes in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmap.rawValue)
            else { throw RenderError.unavailable }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = renderer.device.hasUnifiedMemory ? .shared : .managed
        descriptor.usage = .shaderRead
        guard let source = renderer.device.makeTexture(descriptor: descriptor) else { throw RenderError.unavailable }
        source.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        var settings = DuoSettings()
        settings.glowEnabled = true
        settings.edgeBleed = 0.8
        renderer.settings = settings
        renderer.backingScale = Double(height) / 1117
        renderer.progress = 0.72
        try png(renderer.renderOffscreen(source: source)).write(to: output.appendingPathComponent("fold.png"))
        renderer.settings.glowEnabled = false
        try png(renderer.renderOffscreen(source: source)).write(to: output.appendingPathComponent("neutral-fold.png"))
        renderer.settings.glowEnabled = true
        var smoother = AngleSmoother()
        for index in 0..<240 {
            try autoreleasepool {
                let time = Double(index) / 60
                let target = (110 - 94 * (0.5 - 0.5 * cos(2 * .pi * time / 4))).rounded()
                let angle = smoother.update(target, at: time, response: settings.response) ?? target
                renderer.progress = LidMath.progress(angle: angle, clearAngle: settings.clearAngle)
                let result = try renderer.renderOffscreen(source: source)
                try png(result).write(to: output.appendingPathComponent(String(format: "frame-%04d.png", index)))
            }
        }
        let metadata =
            "{\"source\":\"synthetic PreviewDesktop\",\"renderer\":\"production MetalRenderer\",\"fps\":60,\"frames\":240,\"liveCapture\":false,\"performanceEvidence\":false}\n"
        try Data(metadata.utf8).write(to: output.appendingPathComponent("provenance.json"))
        print("Exported synthetic production-rendered frames to \(output.path). This is not a live performance test.")
    }

    private static func png(_ texture: MTLTexture) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &bytes, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0)
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
            let image = CGImage(
                width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: texture.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmap,
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw RenderError.unavailable }
        return data
    }
}
