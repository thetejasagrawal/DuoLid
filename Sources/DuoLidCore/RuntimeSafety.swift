import Foundation

/// Multiple system interruptions must all end before automatic effects resume.
public struct InterruptionState: Sendable {
    public enum Reason: Hashable, Sendable { case sleeping, displaySleeping, inactiveSession, shutdown }
    private var reasons: Set<Reason> = []
    public init() {}
    public var isSuspended: Bool { !reasons.isEmpty }
    public mutating func begin(_ reason: Reason) { reasons.insert(reason) }
    public mutating func end(_ reason: Reason) { reasons.remove(reason) }
}

/// Neither a successful GPU command nor a presentation callback alone is enough
/// to reveal a desktop replacement. The two callbacks can arrive in either order.
public struct FirstFrameReadiness: Sendable {
    private var completed = false
    private var presented = false
    private var failed = false
    private var notified = false
    public init() {}
    public mutating func gpuCompleted(success: Bool) -> Bool {
        completed = success; failed = failed || !success
        return takeReady()
    }
    public mutating func didPresent(at time: Double) -> Bool {
        presented = time.isFinite && time > 0
        return takeReady()
    }
    private mutating func takeReady() -> Bool {
        guard completed, presented, !failed, !notified else { return false }
        notified = true
        return true
    }
}
