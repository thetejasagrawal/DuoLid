/// CoreGraphics preflight can be stale after a permission change. Once a
/// ScreenCaptureKit operation supplies an answer, hints cannot override it.
public struct ScreenAccessState: Sendable {
    private var hint: Bool
    private var confirmed: Bool?

    public init(preflightHint: Bool) { hint = preflightHint }
    public var hasAccess: Bool { confirmed ?? hint }
    public mutating func observePreflight(_ value: Bool) { hint = value }
    public mutating func confirm(_ value: Bool) { confirmed = value }
}
