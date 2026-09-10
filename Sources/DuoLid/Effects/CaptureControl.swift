import ScreenCaptureKit

// Keep SCStream lifecycle calls on the same actor that owns its configuration.
// The callback API avoids transferring a non-Sendable stream into the generic
// executor used by the async importer in older SDKs. Only errors cross back.
extension SCStream {
    @MainActor
    func startOnMainActor() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            startCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    @MainActor
    func stopOnMainActor() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stopCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    @MainActor
    func updateOnMainActor(_ configuration: SCStreamConfiguration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            updateConfiguration(configuration) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
