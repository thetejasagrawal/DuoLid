import Foundation
import ScreenCaptureKit

@MainActor
enum CaptureContent {
    static func fetch() async throws -> SCShareableContent {
        let snapshot = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<ShareableContentTransfer, Error>) in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: ShareableContentTransfer(content))
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "DuoLid.Capture", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "The display list is unavailable. Try again."]))
                }
            }
        }
        return snapshot.value
    }
}

/// ScreenCaptureKit hands back a read-only snapshot. Older SDKs don't annotate
/// it as Sendable. Transfer it once from the callback, then expose it only on
/// the main actor; no capture object is mutated on the callback queue.
private final class ShareableContentTransfer: @unchecked Sendable {
    private let content: SCShareableContent
    init(_ content: SCShareableContent) { self.content = content }
    @MainActor var value: SCShareableContent { content }
}
