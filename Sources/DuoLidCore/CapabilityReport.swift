import Foundation

public enum CapabilityStatus: String, Codable, Sendable {
    case checking, available, unavailable, permissionRequired, failed
}

public enum CapturePhase: String, Codable, Sendable {
    case idle, preparing, capturing, stopping, failed
}

/// Shareable support metadata. Never includes user names, device serial numbers,
/// window titles, captured pixels, or audio.
public struct CapabilityReport: Codable, Sendable {
    public var schemaVersion = 1
    public var app = "DuoLid"
    public var version = "development"
    public var build = "development"
    public var system = ""
    public var architecture = ""
    public var model = ""
    public var sensor: CapabilityStatus = .checking
    public var lidAngle: Double?
    public var screenRecording: CapabilityStatus = .permissionRequired
    public var builtInDisplayActive = false
    public var capture: CapturePhase = .idle
    public var graphics: CapabilityStatus = .checking
    public var graphicsError: String?
    public init() {}
}
