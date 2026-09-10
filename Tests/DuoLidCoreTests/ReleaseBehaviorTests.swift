import XCTest

@testable import DuoLidCore

final class ReleaseBehaviorTests: XCTestCase {
    func testUpdateChannelsKeepStableAvailableAndRespectOptIn() {
        XCTAssertEqual(UpdatePolicy.allowedChannels(version: "0.9.0-beta.1", betaPreference: nil), ["beta"])
        XCTAssertTrue(UpdatePolicy.allowedChannels(version: "1.0.0", betaPreference: nil).isEmpty)
        XCTAssertEqual(UpdatePolicy.allowedChannels(version: "1.0.0", betaPreference: true), ["beta"])
        XCTAssertTrue(UpdatePolicy.allowedChannels(version: "0.9.0-beta.1", betaPreference: false).isEmpty)
        XCTAssertFalse(UpdatePolicy.validPublicKey("placeholder"))
        XCTAssertFalse(UpdatePolicy.validPublicKey(nil))
        XCTAssertTrue(UpdatePolicy.validPublicKey(Data(repeating: 1, count: 32).base64EncodedString()))
    }

    func testPresentationOrderAndDuplicatesDoNotCorruptCadence() {
        let samples = (0..<1_801).map { 1 + Double($0) / 60 }
        let timing = PresentationTiming(
            timestamps: samples.reversed() + [samples[99], .nan, .infinity, 0], targetFPS: 60)
        XCTAssertTrue(timing.passes(targetFPS: 60))
        XCTAssertEqual(timing.framesPerSecond, 60, accuracy: 0.001)
        XCTAssertEqual(timing.missedDeadlineRatio, 0)
    }

    func testEmptyPresentationAndGPUOnlyWorkNeverPass() {
        let timing = PresentationTiming(timestamps: [], targetFPS: 120)
        XCTAssertFalse(timing.passes(targetFPS: 120))
        let report = PerformanceReport(
            targetFPS: 120, completedFrames: 3_600, skippedSubmissions: 0,
            gpuMS: 3, cpuMS: 1, gpuQueueMS: 0, captureArrivalAgeMS: 2, presentationLeadMS: 5, presentation: timing)
        XCTAssertFalse(report.passesCadence)
    }

    func testFrameTimelineCorrelatesOutOfOrderCallbacks() {
        var timeline = RenderFrameTimeline()
        for id in UInt64(1)...2 {
            timeline.submitted(
                RenderFrameTiming(
                    id: id, targetTime: 2, drawableRequestedAt: 1,
                    encodingStartedAt: 1.01, submittedAt: 1.02))
        }
        timeline.presented(id: 2, at: 2.01)
        timeline.completed(id: 1, start: 1.03, end: 1.04, success: true)
        timeline.presented(id: 1, at: 2)
        timeline.completed(id: 2, start: 1.05, end: 1.06, success: true)
        XCTAssertEqual(timeline.frames.map(\.id), [1, 2])
        XCTAssertEqual(timeline.frames.map(\.presentedAt), [2, 2.01])
        XCTAssertEqual(timeline.frames.map(\.gpuEndedAt), [1.04, 1.06])
        XCTAssertTrue(timeline.frames.allSatisfy { $0.gpuSucceeded == true })
    }

    func testFrameTimelineNeverRestoresEvictedOrUnknownFrames() {
        var timeline = RenderFrameTimeline(capacity: 2)
        for id in UInt64(1)...3 {
            timeline.submitted(
                RenderFrameTiming(
                    id: id, targetTime: 2, drawableRequestedAt: 1,
                    encodingStartedAt: 1.01, submittedAt: 1.02))
        }
        timeline.presented(id: 1, at: 2)
        timeline.completed(id: 1, start: 1.03, end: 1.04, success: true)
        timeline.presented(id: 99, at: 2)
        XCTAssertEqual(timeline.frames.map(\.id), [2, 3])
    }

    func testFrameTimelineRetainsFailureWithoutInventingPresentation() throws {
        var timeline = RenderFrameTimeline()
        timeline.submitted(
            RenderFrameTiming(
                id: 1, targetTime: 2, drawableRequestedAt: 1,
                encodingStartedAt: 1.01, submittedAt: 1.02))
        timeline.completed(id: 1, start: 0, end: .nan, success: false)
        timeline.presented(id: 1, at: .infinity)
        timeline.presented(id: 1, at: 0)
        let frame = try XCTUnwrap(timeline.frames.first)
        XCTAssertEqual(frame.gpuSucceeded, false)
        XCTAssertNil(frame.gpuStartedAt)
        XCTAssertNil(frame.gpuEndedAt)
        XCTAssertNil(frame.presentedAt)
        XCTAssertNoThrow(try JSONEncoder().encode(timeline.frames))
    }

    func testMissedDisplaySlotsFailTheReleaseGate() {
        let samples = (0..<1_800).filter { $0 % 20 != 0 }.map { 1 + Double($0) / 60 }
        let timing = PresentationTiming(timestamps: samples, targetFPS: 60)
        XCTAssertGreaterThan(timing.missedDeadlineRatio, 0.04)
        XCTAssertFalse(timing.passes(targetFPS: 60))
    }

    func testAutomaticStepsDownOnlyOnceAfterWarmup() {
        var cadence = AdaptiveCadence(framesPerSecond: 120)
        XCTAssertNil(cadence.evaluate(timestamps: [], now: 1, automatic: true))
        let late = (0...60).map { 2 + Double($0) / 60 }
        XCTAssertNil(cadence.evaluate(timestamps: late, now: 2, automatic: true))
        XCTAssertEqual(cadence.evaluate(timestamps: late, now: 3, automatic: true), 60)
        XCTAssertNil(cadence.evaluate(timestamps: late, now: 4, automatic: true))
        XCTAssertTrue(cadence.hasSteppedDown)
    }

    func testFixedCadenceAndHealthyAutomaticDoNotStepDown() {
        var fixed = AdaptiveCadence(framesPerSecond: 120)
        XCTAssertNil(fixed.evaluate(timestamps: [], now: 10, automatic: false))
        var automatic = AdaptiveCadence(framesPerSecond: 120)
        XCTAssertNil(automatic.evaluate(timestamps: [], now: 1, automatic: true))
        let healthy = (0...120).map { 2 + Double($0) / 120 }
        XCTAssertNil(automatic.evaluate(timestamps: healthy, now: 3, automatic: true))
        XCTAssertEqual(automatic.framesPerSecond, 120)
    }

    func testFrameRatesRespectDisplayAndLowPowerLimits() {
        XCTAssertEqual(FrameRateMode.automatic.targetFPS(maximum: 120, lowPower: false), 120)
        XCTAssertEqual(FrameRateMode.oneTwenty.targetFPS(maximum: 60, lowPower: false), 60)
        XCTAssertEqual(FrameRateMode.sixty.targetFPS(maximum: 120, lowPower: false), 60)
        XCTAssertEqual(FrameRateMode.automatic.targetFPS(maximum: 120, lowPower: true), 30)
        XCTAssertEqual(FrameRateMode.automatic.targetFPS(maximum: 0, lowPower: false), 60)
    }

    func testLegacyCadenceMigrationPreservesIndividuallyDisabledEffects() throws {
        for (legacy, expected) in [(60, FrameRateMode.sixty), (120, .oneTwenty), (999, .automatic)] {
            let json =
                "{\"frameRate\":\(legacy),\"soundEnabled\":false,\"glowEnabled\":false,\"clearAngle\":75,\"edgeBleed\":0.87}"
            let settings = DuoSettings.load(from: Data(json.utf8))
            XCTAssertEqual(settings.frameRateMode, expected)
            XCTAssertFalse(settings.soundEnabled)
            XCTAssertFalse(settings.glowEnabled)
            XCTAssertEqual(settings.clearAngle, 75)
            XCTAssertEqual(settings.edgeBleed, 0.87)
            let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
            XCTAssertNil(saved["frameRate"])
            XCTAssertEqual(saved["frameRateMode"] as? String, expected.rawValue)
        }
    }

    func testMalformedPreferenceOnlyRecoversItsOwnField() {
        let settings = DuoSettings.load(
            from: Data(
                "{\"style\":\"future-style\",\"frameRateMode\":\"future-mode\",\"intensity\":\"bad\",\"soundEnabled\":false,\"glowEnabled\":false,\"clearAngle\":79}"
                    .utf8))
        XCTAssertEqual(settings.style, .duo)
        XCTAssertEqual(settings.frameRateMode, .automatic)
        XCTAssertEqual(settings.clearAngle, 79)
        XCTAssertFalse(settings.soundEnabled)
        XCTAssertFalse(settings.glowEnabled)
    }

    func testOverlayWaitsForBothCallbacksInEitherOrder() {
        var first = FirstFrameReadiness()
        XCTAssertFalse(first.didPresent(at: 10))
        XCTAssertTrue(first.gpuCompleted(success: true))
        XCTAssertFalse(first.didPresent(at: 11))
        var second = FirstFrameReadiness()
        XCTAssertFalse(second.gpuCompleted(success: true))
        XCTAssertTrue(second.didPresent(at: 10))
        XCTAssertFalse(second.gpuCompleted(success: true))
    }

    func testFailedGPUAndInvalidPresentationNeverRevealAnOverlay() {
        var failed = FirstFrameReadiness()
        XCTAssertFalse(failed.gpuCompleted(success: false))
        XCTAssertFalse(failed.didPresent(at: 1))
        XCTAssertFalse(failed.gpuCompleted(success: true))
        var invalid = FirstFrameReadiness()
        XCTAssertFalse(invalid.gpuCompleted(success: true))
        XCTAssertFalse(invalid.didPresent(at: 0))
        XCTAssertFalse(invalid.didPresent(at: .nan))
    }

    func testDisplayWakeDoesNotResumeALockedOrSleepingSession() {
        var state = InterruptionState()
        state.begin(.sleeping)
        state.begin(.inactiveSession)
        state.begin(.displaySleeping)
        state.end(.displaySleeping)
        XCTAssertTrue(state.isSuspended)
        state.end(.sleeping)
        XCTAssertTrue(state.isSuspended)
        state.end(.inactiveSession)
        XCTAssertFalse(state.isSuspended)
        state.begin(.shutdown)
        state.end(.sleeping)
        XCTAssertTrue(state.isSuspended)
    }

    func testVerifiedScreenAccessSurvivesStaleNegativeHints() {
        var access = ScreenAccessState(preflightHint: false)
        XCTAssertFalse(access.hasAccess)
        access.confirm(true)
        access.observePreflight(false)
        XCTAssertTrue(access.hasAccess)
    }

    func testPermissionRevocationSurvivesStalePositiveHintsUntilReverified() {
        var access = ScreenAccessState(preflightHint: true)
        access.confirm(true)
        access.confirm(false)
        access.observePreflight(true)
        XCTAssertFalse(access.hasAccess)
        access.confirm(true)
        XCTAssertTrue(access.hasAccess)
    }
}
