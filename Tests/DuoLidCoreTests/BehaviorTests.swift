import XCTest
import AVFoundation
@testable import DuoLidCore

final class BehaviorTests: XCTestCase {
    func testCapturePreparationOnlyRunsBrieflyWhenClosingNearTheStart() {
        var gate = CapturePreparationGate()
        XCTAssertFalse(gate.update(angle: 110, startAngle: 62, enabled: true, at: 0))
        XCTAssertFalse(gate.update(angle: 105, startAngle: 62, enabled: true, at: 0.1))
        XCTAssertTrue(gate.update(angle: 80, startAngle: 62, enabled: true, at: 0.2))
        XCTAssertTrue(gate.update(angle: 80, startAngle: 62, enabled: true, at: 0.3))
        XCTAssertFalse(gate.update(angle: 80, startAngle: 62, enabled: true, at: 0.6))
        XCTAssertTrue(gate.update(angle: 70, startAngle: 62, enabled: true, at: 0.7))
        XCTAssertFalse(gate.update(angle: 71, startAngle: 62, enabled: true, at: 0.8))
        XCTAssertFalse(gate.update(angle: 60, startAngle: 62, enabled: true, at: 0.9))
        XCTAssertFalse(gate.update(angle: 70, startAngle: 62, enabled: false, at: 1))
        XCTAssertFalse(gate.update(angle: .nan, startAngle: 62, enabled: true, at: 1.1))
    }

    func testWorkingAngleJitterNeverStartsCaptureAndReopeningStopsIt() {
        XCTAssertEqual(DuoSettings().clearAngle, 62)
        var gate = CaptureGate()
        for angle in [114.0, 112, 110, 109, 90, 80, 63, 62, 61.9] {
            XCTAssertFalse(gate.update(angle: angle, clearAngle: 62, enabled: true))
        }
        XCTAssertTrue(gate.update(angle: 61, clearAngle: 62, enabled: true))
        XCTAssertTrue(gate.update(angle: 61.9, clearAngle: 62, enabled: true))
        XCTAssertFalse(gate.update(angle: 62, clearAngle: 62, enabled: true))
        XCTAssertFalse(gate.update(angle: 61.9, clearAngle: 62, enabled: true))
        XCTAssertTrue(gate.update(angle: 40, clearAngle: 62, enabled: true))
        XCTAssertFalse(gate.update(angle: 40, clearAngle: 62, enabled: false))
        XCTAssertFalse(gate.update(angle: .nan, clearAngle: 62, enabled: true))
    }
    func testFoldKeepsHingeAnchoredWhileTopEdgeDescendsAndNarrows() {
        var lastTop = 0.0
        for degrees in stride(from: 0.0, through: 78, by: 0.5) {
            let theta = degrees * .pi / 180
            let hinge = LidMath.projectedPoint(x: 0.5, y: 1, radians: theta)
            XCTAssertEqual(hinge.x, 0.5, accuracy: 1e-12)
            XCTAssertEqual(hinge.y, 1, accuracy: 1e-12)
            let top = LidMath.projectedPoint(x: 0, y: 0, radians: theta)
            XCTAssertGreaterThanOrEqual(top.y, lastTop)
            XCTAssertGreaterThanOrEqual(top.x, 0)
            XCTAssertLessThan(top.x, 0.5)
            lastTop = top.y
        }
        XCTAssertGreaterThan(lastTop, 0.8)
    }

    func testBlurFrontTravelsFromTopToBottomAndReversesContinuously() {
        for y in stride(from: 0.0, through: 1, by: 0.01) {
            XCTAssertEqual(LidMath.blurCoverage(y: y, progress: 0), 0, accuracy: 1e-12)
            XCTAssertEqual(LidMath.blurCoverage(y: y, progress: 1), 1, accuracy: 1e-12)
            var last = 0.0
            for p in stride(from: 0.0, through: 1, by: 0.01) {
                let coverage = LidMath.blurCoverage(y: y, progress: p)
                XCTAssertGreaterThanOrEqual(coverage, last - 1e-12)
                XCTAssertLessThanOrEqual(coverage - last, 0.06)
                last = coverage
            }
        }
        XCTAssertEqual(LidMath.blurCoverage(y: 0.1, progress: 0.4), 1, accuracy: 1e-12)
        XCTAssertEqual(LidMath.blurCoverage(y: 0.8, progress: 0.4), 0, accuracy: 1e-12)
        XCTAssertGreaterThan(LidMath.blurCoverage(y: 0.7, progress: 0.7), LidMath.blurCoverage(y: 0.7, progress: 0.5))
    }

    func testNormalWorkingAnglesLeaveTheScreenUnchanged() {
        for angle in stride(from: 88.0, through: 180, by: 0.5) {
            XCTAssertEqual(LidMath.progress(angle: angle, clearAngle: 88), 0)
        }
        XCTAssertEqual(LidMath.progress(angle: 0, clearAngle: 88), 1)
    }

    func testClosingIsContinuousAndMonotonicAcrossAllSupportedClearAngles() {
        for threshold in stride(from: 45.0, through: 140, by: 5) {
            var previous = 0.0
            for angle in stride(from: 180.0, through: 0, by: -0.25) {
                let progress = LidMath.progress(angle: angle, clearAngle: threshold)
                XCTAssertGreaterThanOrEqual(progress, previous - 1e-12)
                XCTAssertLessThan(progress - previous, 0.025)
                XCTAssertTrue((0...1).contains(progress))
                previous = progress
            }
        }
    }

    func testMalformedSensorDataFailsOpen() {
        XCTAssertEqual(LidMath.progress(angle: .nan, clearAngle: 90), 0)
        XCTAssertEqual(LidMath.progress(angle: 45, clearAngle: .infinity), 0)
        XCTAssertNil(LidMath.decode(report: []))
        XCTAssertNil(LidMath.decode(report: [1, 90]))
        XCTAssertNil(LidMath.decode(report: [2, 90, 0]))
        XCTAssertNil(LidMath.decode(report: [1, 255, 255]))
        XCTAssertNil(LidMath.decode(report: [1, 0, 1]))
        XCTAssertEqual(LidMath.decode(report: [1, 90, 0, 0, 0, 0, 0, 0]), 90)
        XCTAssertEqual(LidMath.decode(report: [1, 0, 0]), 0)
    }

    func testSoundNeverPlaysJustBecauseTheAppStartedOpen() {
        var latch = LatchDetector()
        for time in 0..<100 { XCTAssertFalse(latch.update(angle: 112, clearAngle: 100, at: Double(time))) }
    }

    func testSoundFiresOncePerMeaningfulCloseAndOpen() {
        var latch = LatchDetector()
        var events = 0
        for (index, angle) in [112.0, 93, 70, 30, 6, 20, 56, 89, 99, 101, 99, 101, 100, 112].enumerated() {
            if latch.update(angle: angle, clearAngle: 100, at: Double(index)) { events += 1 }
        }
        XCTAssertEqual(events, 1)
        XCTAssertFalse(latch.update(angle: 20, clearAngle: 100, at: 20))
        XCTAssertTrue(latch.update(angle: 105, clearAngle: 100, at: 22))
    }

    func testSmallDeskAdjustmentsDoNotArmTheLatch() {
        var latch = LatchDetector()
        for (index, angle) in [105.0, 98, 83, 71, 98, 101, 99, 103].enumerated() {
            XCTAssertFalse(latch.update(angle: angle, clearAngle: 100, at: Double(index)))
        }
    }

    func testClosedLidWakeSurvivesMissingIntermediateSamples() {
        var latch = LatchDetector()
        latch.lidDidClose()
        XCTAssertTrue(latch.update(angle: 110, clearAngle: 100, at: 100))
        XCTAssertFalse(latch.update(angle: 111, clearAngle: 100, at: 101))
    }

    func testPauseClearsTheArmedSound() {
        var latch = LatchDetector()
        latch.lidDidClose()
        latch.reset()
        XCTAssertFalse(latch.update(angle: 110, clearAngle: 100, at: 100))
    }

    func testSmoothingIsFrameRateIndependent() {
        var low = AngleSmoother(), high = AngleSmoother()
        _ = low.update(100, at: 0); _ = high.update(100, at: 0)
        for frame in 1...30 { _ = low.update(40, at: Double(frame) / 30) }
        for frame in 1...120 { _ = high.update(40, at: Double(frame) / 120) }
        XCTAssertEqual(low.value!, high.value!, accuracy: 0.02)
    }

    func testMotionEasesIntoSensorStepsWithoutOvershoot() {
        var smoother = AngleSmoother()
        _ = smoother.update(70, at: 0)
        let first = smoother.update(40, at: 1.0 / 120)!
        XCTAssertGreaterThan(first, 68, "A new sensor step should ease in, rather than jerk immediately.")
        var last = first
        for frame in 2...90 {
            let value = smoother.update(40, at: Double(frame) / 120)!
            XCTAssertLessThanOrEqual(value, last)
            XCTAssertGreaterThanOrEqual(value, 40)
            last = value
        }
        XCTAssertEqual(last, 40, accuracy: 0.02)
    }

    func testStaleAndInvalidSamplesDoNotProduceANonfiniteEffect() {
        var smoother = AngleSmoother()
        XCTAssertEqual(smoother.update(90, at: 0), 90)
        XCTAssertEqual(smoother.update(.nan, at: 0.1), 90)
        XCTAssertEqual(smoother.update(400, at: 0.2), 90)
        XCTAssertEqual(smoother.update(15, at: 20), 15)
    }

    func testSavedPreferencesRoundTripAndCorruptDataRecovers() throws {
        var settings = DuoSettings()
        settings.glowEnabled = true
        settings.glowPalette = .sunset
        settings.tone = .soft
        settings.clearAngle = 86
        settings.frameRateMode = .oneTwenty
        XCTAssertEqual(DuoSettings.load(from: try JSONEncoder().encode(settings)), settings)
        XCTAssertEqual(DuoSettings.load(from: Data("broken".utf8)), DuoSettings())
    }

    func testPreferencesClampUnsafeOrInvalidValues() {
        var settings = DuoSettings()
        settings.clearAngle = 0; settings.volume = 9; settings.intensity = .nan
        settings.glowSpread = -1; settings.glowIntensity = .infinity
        settings.edgeBleed = .nan
        settings.normalize()
        XCTAssertEqual(settings.clearAngle, 45)
        XCTAssertEqual(settings.volume, 1)
        XCTAssertEqual(settings.intensity, 0.75)
        XCTAssertEqual(settings.glowSpread, 0.15)
        XCTAssertTrue(settings.glowIntensity.isFinite)
        XCTAssertEqual(settings.edgeBleed, 0.6)
    }

    func testNewBleedControlPreservesOlderSavedPreferences() throws {
        var settings = DuoSettings()
        settings.clearAngle = 87
        settings.glowEnabled = true
        settings.glowPalette = .prism
        settings.volume = 0.85
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        stored.removeValue(forKey: "edgeBleed")
        let restored = DuoSettings.load(from: try JSONSerialization.data(withJSONObject: stored))
        XCTAssertEqual(restored, settings)
    }

    func testGlowIsOptionalByDefault() { XCTAssertFalse(DuoSettings().glowEnabled) }

    func testAllOriginalSoundsDecodeAndHaveBoundedPeaksAndQuietTails() throws {
        for tone in LatchTone.allCases {
            let samples = LatchSynthesis.samples(tone: tone)
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.9 })
            XCTAssertLessThan(samples.suffix(100).map { abs($0) }.max()!, 0.0001)
            let player = try AVAudioPlayer(data: LatchSynthesis.waveData(tone: tone))
            XCTAssertEqual(player.duration, 0.22, accuracy: 0.001)
            XCTAssertEqual(player.numberOfChannels, 1)
        }
    }
}
