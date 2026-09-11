import Foundation

/// Keep the display clock at the panel's native cadence while limiting expensive
/// rendering to the selected rate. A 60 fps limit on a 120 Hz panel should skip
/// alternate opportunities, without repeatedly changing the panel's clock.
public struct RenderCadence: Sendable {
    public let maximumFramesPerSecond: Int
    public private(set) var framesPerSecond: Int
    private var lastRenderedAt: Double?

    public var clockFramesPerSecond: Int {
        // Low Power remains a genuine lower-cadence request.
        framesPerSecond <= 30 ? framesPerSecond : maximumFramesPerSecond
    }

    public init(maximumFramesPerSecond: Int, framesPerSecond: Int) {
        self.maximumFramesPerSecond = max(1, min(120, maximumFramesPerSecond))
        self.framesPerSecond = max(1, min(self.maximumFramesPerSecond, framesPerSecond))
    }

    public mutating func select(_ rate: Int) {
        framesPerSecond = max(1, min(maximumFramesPerSecond, rate))
        lastRenderedAt = nil
    }

    public mutating func shouldRender(at timestamp: Double) -> Bool {
        guard timestamp.isFinite, timestamp > 0 else { return false }
        if let previous = lastRenderedAt {
            guard timestamp > previous,
                timestamp - previous >= 1 / Double(framesPerSecond) - 0.000_001
            else { return false }
        }
        // After a missed opportunity take the freshest frame once. Never build a
        // catch-up queue or submit several old frames in a burst.
        lastRenderedAt = timestamp
        return true
    }
}
