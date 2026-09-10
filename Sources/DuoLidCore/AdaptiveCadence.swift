import Foundation

/// A fold can step down once, but never hunts between rates while visible.
/// A new instance is created for each capture session.
public struct AdaptiveCadence: Sendable {
    public private(set) var framesPerSecond: Int
    public private(set) var hasSteppedDown = false
    private var eligibleAfter: Double?
    public init(framesPerSecond: Int) { self.framesPerSecond = framesPerSecond }

    public mutating func evaluate(timestamps: [Double], now: Double, automatic: Bool) -> Int? {
        guard automatic, !hasSteppedDown, framesPerSecond > 60, now.isFinite else { return nil }
        if eligibleAfter == nil { eligibleAfter = now + 1.25; return nil }
        guard now >= eligibleAfter! else { return nil }
        let recent = timestamps.filter { $0 >= now - 1 && $0 <= now }
        let timing = PresentationTiming(timestamps: recent, targetFPS: Double(framesPerSecond), warmup: 0)
        guard timing.duration >= 0.85, timing.frames >= 15, timing.missedDeadlineRatio > 0.05 else { return nil }
        framesPerSecond = 60; hasSteppedDown = true
        return 60
    }
}
