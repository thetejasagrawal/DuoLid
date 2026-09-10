import AppKit

// Export the approved artwork with a macOS icon margin and a real alpha channel.
// The generated artwork remains unchanged in Resources/IconArtwork.png.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/DuoLid.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
guard let image = NSImage(contentsOf: root.appendingPathComponent("Resources/IconArtwork.png")) else {
    fatalError("Resources/IconArtwork.png is missing")
}

func export(_ size: Int) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { fatalError("Icon bitmap unavailable") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    let cg = context.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: size, height: size))
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = CGRect(x: 51.2, y: 51.2, width: 921.6, height: 921.6)
    let mask = CGPath(roundedRect: tile, cornerWidth: 184.3, cornerHeight: 184.3, transform: nil)
    cg.addPath(mask)
    cg.clip()
    context.imageInterpolation = .high
    image.draw(in: tile, from: .zero, operation: .copy, fraction: 1)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG export failed") }
    return data
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try export(size * scale).write(to: iconset.appendingPathComponent(filename))
    }
}
try export(1024).write(to: root.appendingPathComponent("Resources/DuoLid.png"))
print("Exported ten icon representations and the 1024 px master.")
