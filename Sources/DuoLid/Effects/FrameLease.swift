import CoreVideo
import Foundation

/// Owns an immutable capture surface until its GPU submission completes.
/// Capture buffers are never locked for writing or modified after publication.
/// Core Video's C objects lack Sendable annotations; only ownership crosses queues.
final class FrameLease: @unchecked Sendable {
    private let lock = NSLock()
    private var texture: CVMetalTexture?
    private var buffer: CVPixelBuffer?

    init(texture: CVMetalTexture, buffer: CVPixelBuffer) {
        self.texture = texture
        self.buffer = buffer
    }

    /// Return the capture surface when GPU reads finish, even if Metal retains
    /// the completion handler or command buffer until presentation completes.
    func release() {
        lock.withLock {
            texture = nil
            buffer = nil
        }
    }
}
