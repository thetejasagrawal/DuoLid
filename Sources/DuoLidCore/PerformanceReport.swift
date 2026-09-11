import Foundation

public struct CaptureTiming: Codable, Sendable {
    public enum Source: String, Codable, Sendable { case synthetic, live }
    public let source: Source
    public let receivedFrames: Int
    public let arrivalFPS: Double
    public let p95IntervalMS: Double
    public let latestFrameAgeMS: Double
    public init(source: Source, receivedFrames: Int, timestamps: [Double], now: Double) {
        self.source = source
        self.receivedFrames = receivedFrames
        let timing = PresentationTiming(timestamps: timestamps, targetFPS: 120, warmup: 0)
        arrivalFPS = timing.framesPerSecond
        p95IntervalMS = timing.p95IntervalMS
        latestFrameAgeMS = max(0, now - (timestamps.max() ?? now)) * 1_000
    }
}

public struct PresentationTiming: Codable, Sendable {
    public let frames: Int
    public let duration: Double
    public let framesPerSecond: Double
    public let medianIntervalMS: Double
    public let p95IntervalMS: Double
    public let missedDeadlineRatio: Double

    /// Presentation callbacks may arrive out of order. Evaluate their timestamps,
    /// never callback arrival order or the number of completed GPU submissions.
    public init(timestamps: [Double], targetFPS: Double, warmup: Double = 0.25) {
        let sorted = Set(timestamps.filter { $0.isFinite && $0 > 0 }).sorted()
        let first = sorted.first ?? 0
        let samples = sorted.filter { $0 >= first + warmup }
        frames = samples.count
        duration = max(0, (samples.last ?? 0) - (samples.first ?? 0))
        framesPerSecond = duration > 0 ? Double(max(0, frames - 1)) / duration : 0
        let intervals = zip(samples.dropFirst(), samples).map { $0 - $1 }.sorted()
        medianIntervalMS = intervals.isEmpty ? 0 : intervals[intervals.count / 2] * 1_000
        p95IntervalMS = intervals.isEmpty ? 0 : intervals[Int(Double(intervals.count - 1) * 0.95)] * 1_000
        let period = 1 / max(1, targetFPS)
        let missed = intervals.reduce(0) { $0 + max(0, Int(($1 / period).rounded()) - 1) }
        missedDeadlineRatio = Double(missed) / Double(max(1, intervals.count + missed))
    }

    public func passes(targetFPS: Double) -> Bool {
        frames >= 15 && framesPerSecond >= targetFPS * 0.98 && missedDeadlineRatio < 0.01
            && p95IntervalMS <= 1_250 / max(1, targetFPS)
    }
}

public struct PerformanceReport: Codable, Sendable {
    public let schemaVersion: Int
    public let targetFPS: Double
    public let completedFrames: Int
    public let skippedSubmissions: Int
    public let gpuMS: Double
    public let cpuMS: Double
    public let gpuQueueMS: Double
    public let captureArrivalAgeMS: Double
    public let presentationLeadMS: Double
    public let presentation: PresentationTiming
    public let capture: CaptureTiming?
    public let preparationMS: Double?
    public var passesCadence: Bool { presentation.passes(targetFPS: targetFPS) }

    public init(
        targetFPS: Double, completedFrames: Int, skippedSubmissions: Int,
        gpuMS: Double, cpuMS: Double, gpuQueueMS: Double,
        captureArrivalAgeMS: Double, presentationLeadMS: Double,
        presentation: PresentationTiming, capture: CaptureTiming? = nil, preparationMS: Double? = nil
    ) {
        schemaVersion = 1
        self.targetFPS = targetFPS
        self.completedFrames = completedFrames
        self.skippedSubmissions = skippedSubmissions
        self.gpuMS = gpuMS
        self.cpuMS = cpuMS
        self.gpuQueueMS = gpuQueueMS
        self.captureArrivalAgeMS = captureArrivalAgeMS
        self.presentationLeadMS = presentationLeadMS
        self.presentation = presentation
        self.capture = capture
        self.preparationMS = preparationMS
    }
}
