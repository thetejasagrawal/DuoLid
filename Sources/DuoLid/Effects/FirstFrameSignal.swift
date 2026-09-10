import DuoLidCore
import Foundation

final class FirstFrameSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var readiness = FirstFrameReadiness()
    private let action: (@MainActor @Sendable () -> Void)?
    init(action: (@MainActor @Sendable () -> Void)?) { self.action = action }
    func completed(success: Bool) {
        if lock.withLock({ readiness.gpuCompleted(success: success) }) { notify() }
    }
    func presented(at time: Double) {
        if lock.withLock({ readiness.didPresent(at: time) }) { notify() }
    }
    private func notify() {
        let action = action
        Task { @MainActor in action?() }
    }
}
