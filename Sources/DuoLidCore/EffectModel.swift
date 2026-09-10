import Foundation

public enum EffectStyle: String, Codable, CaseIterable, Sendable {
    case duo, frost, quiet
    public var title: String { rawValue.capitalized }
    public var detail: String {
        switch self {
        case .duo: return "Fluid blur. A gentle fold."
        case .frost: return "Soft, even, beautifully hazy."
        case .quiet: return "Just a hint of softness."
        }
    }
    public var radius: Double {
        switch self { case .duo: return 38; case .frost: return 52; case .quiet: return 22 }
    }
    public var perspective: Double {
        switch self { case .duo: return 78 * .pi / 180; case .frost: return 0; case .quiet: return 38 * .pi / 180 }
    }
    public var shade: Double {
        switch self { case .duo: return 0.17; case .frost: return 0.08; case .quiet: return 0.055 }
    }
}

public enum LatchTone: String, Codable, CaseIterable, Sendable {
    case magnetic, soft, crisp
    public var title: String { rawValue.capitalized }
    public var detail: String {
        switch self {
        case .magnetic: return "A low, tactile snap with a tiny metallic tail."
        case .soft: return "A rounded, understated tap."
        case .crisp: return "A bright, precise little click."
        }
    }
}

public enum GlowPalette: String, Codable, CaseIterable, Sendable {
    case aurora, prism, sunset, ocean
    public var title: String { rawValue.capitalized }
    public var colors: [[Double]] {
        switch self {
        case .aurora: return [[0.48, 0.28, 1], [0.12, 0.82, 0.90], [0.96, 0.40, 0.68]]
        case .prism: return [[0.40, 0.22, 1], [1, 0.33, 0.26], [0.32, 0.78, 1]]
        case .sunset: return [[1, 0.28, 0.45], [1, 0.65, 0.25], [0.71, 0.30, 0.87]]
        case .ocean: return [[0.12, 0.43, 1], [0.08, 0.90, 0.74], [0.34, 0.67, 1]]
        }
    }
}

public enum GlowCorners: String, Codable, CaseIterable, Sendable {
    case all, lower, upper
    public var title: String {
        switch self { case .all: return "All corners"; case .lower: return "Lower corners"; case .upper: return "Upper corners" }
    }
}

public enum FrameRateMode: String, Codable, CaseIterable, Sendable {
    case automatic, sixty, oneTwenty
    public var title: String {
        switch self { case .automatic: return "Automatic"; case .sixty: return "60 fps"; case .oneTwenty: return "120 fps" }
    }
    public func targetFPS(maximum: Int, lowPower: Bool) -> Int {
        let limit = maximum > 0 ? maximum : 60
        if lowPower { return min(30, limit) }
        return min(self == .sixty ? 60 : 120, limit)
    }
}

public struct DuoSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var blurEnabled = true
    public var soundEnabled = true
    public var style: EffectStyle = .duo
    public var intensity = 0.75
    public var clearAngle = 62.0
    public var volume = 0.35
    public var tone: LatchTone = .magnetic
    public var respectReduceMotion = true
    public var batterySaver = true
    public var perspective = 0.9
    public var shadow = 0.5
    public var response = 0.055
    public var glowEnabled = false
    public var glowPalette: GlowPalette = .aurora
    public var glowIntensity = 0.55
    public var glowSpread = 0.55
    public var glowCorners: GlowCorners = .all
    public var edgeBleed = 0.6
    public var frameRateMode: FrameRateMode = .automatic

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, blurEnabled, soundEnabled, style, intensity, clearAngle, volume, tone
        case respectReduceMotion, batterySaver, perspective, shadow, response
        case glowEnabled, glowPalette, glowIntensity, glowSpread, glowCorners, edgeBleed, frameRateMode
    }
    private enum LegacyKeys: String, CodingKey { case frameRate }

    /// New controls take their default without resetting an existing user's choices.
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? values.decodeIfPresent(Bool.self, forKey: .enabled)) ?? enabled
        blurEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .blurEnabled)) ?? blurEnabled
        soundEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .soundEnabled)) ?? soundEnabled
        style = (try? values.decodeIfPresent(EffectStyle.self, forKey: .style)) ?? style
        intensity = (try? values.decodeIfPresent(Double.self, forKey: .intensity)) ?? intensity
        clearAngle = (try? values.decodeIfPresent(Double.self, forKey: .clearAngle)) ?? clearAngle
        volume = (try? values.decodeIfPresent(Double.self, forKey: .volume)) ?? volume
        tone = (try? values.decodeIfPresent(LatchTone.self, forKey: .tone)) ?? tone
        respectReduceMotion = (try? values.decodeIfPresent(Bool.self, forKey: .respectReduceMotion)) ?? respectReduceMotion
        batterySaver = (try? values.decodeIfPresent(Bool.self, forKey: .batterySaver)) ?? batterySaver
        perspective = (try? values.decodeIfPresent(Double.self, forKey: .perspective)) ?? perspective
        shadow = (try? values.decodeIfPresent(Double.self, forKey: .shadow)) ?? shadow
        response = (try? values.decodeIfPresent(Double.self, forKey: .response)) ?? response
        glowEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .glowEnabled)) ?? glowEnabled
        glowPalette = (try? values.decodeIfPresent(GlowPalette.self, forKey: .glowPalette)) ?? glowPalette
        glowIntensity = (try? values.decodeIfPresent(Double.self, forKey: .glowIntensity)) ?? glowIntensity
        glowSpread = (try? values.decodeIfPresent(Double.self, forKey: .glowSpread)) ?? glowSpread
        glowCorners = (try? values.decodeIfPresent(GlowCorners.self, forKey: .glowCorners)) ?? glowCorners
        edgeBleed = (try? values.decodeIfPresent(Double.self, forKey: .edgeBleed)) ?? edgeBleed
        if let mode = try? values.decode(FrameRateMode.self, forKey: .frameRateMode) {
            frameRateMode = mode
        } else if !values.contains(.frameRateMode),
                  let legacy = try? decoder.container(keyedBy: LegacyKeys.self).decode(Int.self, forKey: .frameRate) {
            if legacy == 60 { frameRateMode = .sixty }
            if legacy == 120 { frameRateMode = .oneTwenty }
        }
    }

    public mutating func normalize() {
        intensity = bounded(intensity, 0.15...1, fallback: 0.75)
        clearAngle = bounded(clearAngle, 45...140, fallback: 62)
        volume = bounded(volume, 0...1, fallback: 0.35)
        perspective = bounded(perspective, 0...1, fallback: 0.9)
        shadow = bounded(shadow, 0...1, fallback: 0.5)
        response = bounded(response, 0.025...0.18, fallback: 0.055)
        glowIntensity = bounded(glowIntensity, 0...1, fallback: 0.55)
        glowSpread = bounded(glowSpread, 0.15...1, fallback: 0.55)
        edgeBleed = bounded(edgeBleed, 0...1, fallback: 0.6)
    }

    public static func load(from data: Data?) -> DuoSettings {
        guard let data, var settings = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        settings.normalize()
        return settings
    }
}

public func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    guard value.isFinite else { return fallback }
    return min(range.upperBound, max(range.lowerBound, value))
}

public enum LidMath {
    /// Perspective projection around the bottom-center hinge, normalized to display height.
    public static func projectedPoint(x: Double, y: Double, radians: Double) -> (x: Double, y: Double) {
        let theta = bounded(radians, 0...(78 * .pi / 180), fallback: 0)
        let height = 1 - y
        let depth = 1 + height * sin(theta) / 2.4
        return ((x - 0.5) / depth + 0.5, 1 - height * cos(theta) / depth)
    }

    /// Soft leading edge travels from above the display to below it.
    public static func blurCoverage(y: Double, progress: Double) -> Double {
        guard y.isFinite, progress.isFinite else { return 0 }
        let progress = bounded(progress, 0...1, fallback: 0)
        let front = -0.18 + 1.36 * progress
        let t = bounded((y - (front - 0.18)) / 0.36, 0...1, fallback: 1)
        return 1 - t * t * (3 - 2 * t)
    }

    /// No hard edge at either end; the screen is untouched at normal working angles.
    public static func progress(angle: Double, clearAngle: Double) -> Double {
        guard angle.isFinite, clearAngle.isFinite else { return 0 }
        let clear = bounded(clearAngle, 45...140, fallback: 62)
        let t = bounded((clear - angle) / (clear - 6), 0...1, fallback: 0)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// Feature and input reports share report 1's little-endian angle field.
    public static func decode(report: [UInt8]) -> Double? {
        guard report.count >= 3, report[0] == 1 else { return nil }
        let value = Double(UInt16(report[1]) | (UInt16(report[2]) << 8))
        return (0...180).contains(value) ? value : nil
    }
}

public struct AngleSmoother: Sendable {
    public private(set) var value: Double?
    private var timestamp: Double?
    private var velocity = 0.0
    public init() {}

    public mutating func update(_ angle: Double, at now: Double, response: Double = 0.055) -> Double? {
        guard angle.isFinite, now.isFinite, (0...180).contains(angle) else { return value }
        defer { timestamp = now }
        guard let old = value, let last = timestamp, now > last, now - last < 1 else {
            value = angle
            velocity = 0
            return angle
        }
        // An exact critically damped spring keeps velocity continuous across the
        // sensor's whole-degree readings, without frame-rate-dependent easing.
        let dt = now - last
        let omega = 2 / max(response, 0.001)
        let displacement = old - angle
        let component = velocity + omega * displacement
        let decay = exp(-omega * dt)
        value = bounded(angle + (displacement + component * dt) * decay, 0...180, fallback: angle)
        velocity = (velocity - omega * component * dt) * decay
        if abs(value! - angle) < 0.02 && abs(velocity) < 0.1 { value = angle; velocity = 0 }
        return value
    }
    public mutating func reset() { value = nil; timestamp = nil; velocity = 0 }
}

/// The chosen start angle is well below normal working positions.
/// A sub-degree entry margin prevents noise from starting a capture at the boundary.
public struct CaptureGate: Sendable {
    public private(set) var isEngaged = false
    public init() {}
    public mutating func update(angle: Double, clearAngle: Double, enabled: Bool) -> Bool {
        guard enabled, angle.isFinite, clearAngle.isFinite else { isEngaged = false; return false }
        let margin = isEngaged ? 0.0 : 0.25
        isEngaged = angle < clearAngle - margin
        return isEngaged
    }
    public mutating func reset() { isEngaged = false }
}

/// Prepare capture briefly while approaching the start angle. This never decides
/// overlay visibility; CaptureGate remains the exact visible-effect boundary.
public struct CapturePreparationGate: Sendable {
    private var previousAngle: Double?
    private var lastClosing = -Double.infinity
    public init() {}
    public mutating func update(angle: Double, startAngle: Double, enabled: Bool, at time: Double) -> Bool {
        guard enabled, angle.isFinite, startAngle.isFinite, time.isFinite else { reset(); return false }
        if let previousAngle {
            if angle < previousAngle - 0.05 { lastClosing = time }
            else if angle > previousAngle + 0.05 { lastClosing = -.infinity }
        }
        previousAngle = angle
        return angle >= startAngle && angle < startAngle + 20 && time - lastClosing < 0.25
    }
    public mutating func reset() { previousAngle = nil; lastClosing = -.infinity }
}

public struct LatchDetector: Sendable {
    private var armed = false
    private var lastFire: Double = -.infinity
    public init() {}

    /// A real close arms the sound. Jitter around the clear angle cannot retrigger it.
    public mutating func update(angle: Double, clearAngle: Double, at time: Double) -> Bool {
        guard angle.isFinite, time.isFinite, clearAngle.isFinite, (0...180).contains(angle) else { return false }
        if angle <= min(55, clearAngle - 18) { armed = true }
        guard armed, angle >= clearAngle, time - lastFire > 0.8 else { return false }
        armed = false
        lastFire = time
        return true
    }

    public mutating func lidDidClose() { armed = true }
    public mutating func reset() { armed = false }
}
