import Foundation

/// The sensor publishes here directly. Drawing never waits for SwiftUI's readout.
final class LatestLidSample: @unchecked Sendable {
    private let lock = NSLock()
    private var angle: Double?
    private var deliveryPending = false
    func set(_ value: Double?) { lock.withLock { angle = value } }
    func scheduleDelivery() -> Bool {
        lock.withLock { if deliveryPending { return false }; deliveryPending = true; return true }
    }
    func takeForDelivery() -> Double? { lock.withLock { deliveryPending = false; return angle } }
    func get() -> Double? { lock.withLock { angle } }
}
