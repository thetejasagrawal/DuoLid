import XCTest
@testable import DuoLidCore

final class RenderCadenceTests: XCTestCase {
    func testSixtyFPSUsesAlternateNativeDisplayOpportunities() {
        var cadence = RenderCadence(maximumFramesPerSecond: 120, framesPerSecond: 60)
        XCTAssertEqual(cadence.clockFramesPerSecond, 120)
        let rendered = (0..<120).filter { cadence.shouldRender(at: 1 + Double($0) / 120) }
        XCTAssertEqual(rendered, Array(stride(from: 0, to: 120, by: 2)))
    }

    func testLateCallbacksDoNotQueueCatchUpFramesOrAcceptInvalidTime() {
        var cadence = RenderCadence(maximumFramesPerSecond: 120, framesPerSecond: 60)
        XCTAssertFalse(cadence.shouldRender(at: .nan))
        XCTAssertFalse(cadence.shouldRender(at: .infinity))
        XCTAssertFalse(cadence.shouldRender(at: 0))
        XCTAssertTrue(cadence.shouldRender(at: 1))
        XCTAssertTrue(cadence.shouldRender(at: 2))
        XCTAssertFalse(cadence.shouldRender(at: 2))
        XCTAssertFalse(cadence.shouldRender(at: 1.5))
        XCTAssertFalse(cadence.shouldRender(at: 2 + 1.0 / 120))
        XCTAssertTrue(cadence.shouldRender(at: 2 + 1.0 / 60))
    }

    func testChangingRateRespectsDisplayCapabilitiesAndLowPower() {
        var cadence = RenderCadence(maximumFramesPerSecond: 60, framesPerSecond: 120)
        XCTAssertEqual(cadence.framesPerSecond, 60)
        XCTAssertEqual(cadence.clockFramesPerSecond, 60)
        XCTAssertTrue(cadence.shouldRender(at: 1))
        cadence.select(30)
        XCTAssertEqual(cadence.framesPerSecond, 30)
        XCTAssertEqual(cadence.clockFramesPerSecond, 30)
        XCTAssertTrue(cadence.shouldRender(at: 1.01))
        XCTAssertFalse(cadence.shouldRender(at: 1.02))
        cadence.select(120)
        XCTAssertEqual(cadence.framesPerSecond, 60)
        XCTAssertTrue(cadence.shouldRender(at: 1.02))
    }
}
