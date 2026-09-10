import CoreVideo

/// Owns an immutable capture surface until its GPU submission completes.
/// Capture buffers are never locked for writing or modified after publication.
/// Core Video's C objects lack Sendable annotations; only ownership crosses queues.
final class FrameLease: @unchecked Sendable {
    let texture: CVMetalTexture
    let buffer: CVPixelBuffer

    init(texture: CVMetalTexture, buffer: CVPixelBuffer) {
        self.texture = texture
        self.buffer = buffer
    }
}
