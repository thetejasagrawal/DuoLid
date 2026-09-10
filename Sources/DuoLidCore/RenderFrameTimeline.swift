import Foundation

/// Technical timing only. No textures, captured pixels, or window information.
public struct RenderFrameTiming: Codable, Sendable {
    public let id: UInt64
    public let targetTime: Double
    public let drawableRequestedAt: Double
    public let encodingStartedAt: Double
    public let submittedAt: Double
    public fileprivate(set) var gpuStartedAt: Double?
    public fileprivate(set) var gpuEndedAt: Double?
    public fileprivate(set) var gpuSucceeded: Bool?
    public fileprivate(set) var presentedAt: Double?

    public init(
        id: UInt64, targetTime: Double, drawableRequestedAt: Double,
        encodingStartedAt: Double, submittedAt: Double
    ) {
        self.id = id
        self.targetTime = targetTime
        self.drawableRequestedAt = drawableRequestedAt
        self.encodingStartedAt = encodingStartedAt
        self.submittedAt = submittedAt
    }
}

/// A bounded diagnostic journal. Its owner supplies synchronization. Completion
/// and presentation can arrive in either order; neither creates an unknown row.
public struct RenderFrameTimeline: Sendable {
    private let capacity: Int
    private var order: [UInt64] = []
    private var rows: [UInt64: RenderFrameTiming] = [:]
    private var writeIndex = 0

    public init(capacity: Int = 8_192) { self.capacity = max(1, capacity) }

    public mutating func submitted(_ frame: RenderFrameTiming) {
        guard rows[frame.id] == nil else { return }
        if order.count < capacity {
            order.append(frame.id)
        } else {
            rows.removeValue(forKey: order[writeIndex])
            order[writeIndex] = frame.id
        }
        writeIndex = (writeIndex + 1) % capacity
        rows[frame.id] = frame
    }

    public mutating func completed(id: UInt64, start: Double, end: Double, success: Bool) {
        guard var frame = rows[id] else { return }
        frame.gpuSucceeded = success
        if start.isFinite, end.isFinite, start > 0, end >= start {
            frame.gpuStartedAt = start
            frame.gpuEndedAt = end
        }
        rows[id] = frame
    }

    public mutating func presented(id: UInt64, at time: Double) {
        guard time.isFinite, time > 0, var frame = rows[id] else { return }
        frame.presentedAt = time
        rows[id] = frame
    }

    public var frames: [RenderFrameTiming] { rows.values.sorted { $0.id < $1.id } }
}
