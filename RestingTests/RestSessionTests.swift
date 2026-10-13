import SwiftUI
import XCTest
@testable import Resting

/// Time only moves when the test says so. Sleeps wait (cancellably) for real
/// time so the session's timer task never interferes with manual stepping.
final class ManualClock: SessionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .seconds(1_000)

    func now() -> Duration {
        lock.withLock { current }
    }

    func advance(by duration: Duration) {
        lock.withLock { current += duration }
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3_600))
    }
}

/// Every sleep instantly advances time by the requested amount, so the real
/// timer loop can run a full session in milliseconds.
final class AutoAdvancingClock: SessionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero
    private var sleeps = 0

    var sleepCount: Int { lock.withLock { sleeps } }

    func now() -> Duration {
        lock.withLock { current }
    }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        lock.withLock {
            current += duration
            sleeps += 1
        }
        await Task.yield()
        try Task.checkCancellation()
    }
}

@MainActor
final class RestSessionTests: XCTestCase {
    private var clock: ManualClock!
    private var session: RestSession!

    override func setUp() async throws {
        clock = ManualClock()
        session = RestSession(clock: clock)
    }

    override func tearDown() async throws {
        session.reset()
        session = nil
        clock = nil
    }

    private func advance(_ seconds: Double) {
        clock.advance(by: .seconds(seconds))
        session.refresh()
    }

    // 1
    func testDefaultDurationIsThreeMinutes() {
        XCTAssertEqual(SessionDuration.default, .threeMinutes)
        XCTAssertEqual(session.selectedDuration, .threeMinutes)
        XCTAssertEqual(session.selectedDuration.duration, .seconds(180))
        XCTAssertTrue(session.isBreathingGuideEnabled)
    }

    // 2
    func testAllDurationsAreSelectableAndStartWithTheirLength() {
        XCTAssertEqual(SessionDuration.allCases.map(\.minutes), [1, 3, 5])
        for duration in SessionDuration.allCases {
            session.reset()
            session.selectedDuration = duration
            XCTAssertEqual(session.selectedDuration, duration)
            session.start()
            XCTAssertEqual(session.sessionDuration, duration)
            XCTAssertEqual(session.remainingSeconds, duration.minutes * 60)
        }
    }

    // 3
    func testCountdownDoesNotStartOnWelcomeScreen() {
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.isTimerActive)
        advance(30)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.remainingSeconds, 180)
        XCTAssertEqual(session.timerStartCount, 0)

        session.selectedDuration = .fiveMinutes
        session.isBreathingGuideEnabled = false
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.isTimerActive)
    }

    // 4
    func testStartInitializesSelectedDuration() {
        session.selectedDuration = .oneMinute
        session.isBreathingGuideEnabled = false
        session.start()

        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.sessionDuration, .oneMinute)
        XCTAssertFalse(session.isGuidedSession)
        XCTAssertEqual(session.remainingSeconds, 60)
        XCTAssertEqual(session.remainingTime, .seconds(60))
        XCTAssertEqual(session.breathingPhase, .inhale)
        XCTAssertTrue(session.isTimerActive)

        advance(1.5)
        XCTAssertEqual(session.remainingSeconds, 59)
        advance(10)
        XCTAssertEqual(session.remainingSeconds, 49)
        advance(0.5)
        XCTAssertEqual(session.remainingSeconds, 48)
    }

    // 5
    func testPausePreservesRemainingDuration() {
        session.start()
        advance(42)
        session.pause()

        XCTAssertEqual(session.state, .paused(.user))
        XCTAssertFalse(session.isTimerActive)
        XCTAssertEqual(session.remainingTime, .seconds(138))

        advance(300)
        XCTAssertEqual(session.state, .paused(.user))
        XCTAssertEqual(session.remainingTime, .seconds(138))
        XCTAssertEqual(session.remainingSeconds, 138)
    }

    // 6
    func testResumeContinuesFromPreservedDuration() {
        session.start()
        advance(42)
        session.pause()
        advance(120)
        session.resume()

        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(session.isTimerActive)
        XCTAssertEqual(session.remainingTime, .seconds(138))

        advance(8)
        XCTAssertEqual(session.remainingTime, .seconds(130))
        XCTAssertEqual(session.remainingSeconds, 130)
    }

    func testTogglePauseSwitchesBetweenPausedAndRunning() {
        session.start()
        session.togglePause()
        XCTAssertEqual(session.state, .paused(.user))
        session.togglePause()
        XCTAssertEqual(session.state, .running)
    }

    // 7
    func testSessionCompletesAtZero() {
        session.selectedDuration = .oneMinute
        session.start()

        advance(59.5)
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.remainingSeconds, 1)

        advance(0.5)
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.remainingSeconds, 0)
        XCTAssertEqual(session.restedSeconds, 60)
        XCTAssertFalse(session.isTimerActive)
    }

    func testRealTimerTaskCompletesSessionAutomatically() async {
        let autoClock = AutoAdvancingClock()
        let session = RestSession(clock: autoClock)
        session.selectedDuration = .oneMinute
        session.start()

        var iterations = 0
        while session.state == .running, iterations < 10_000 {
            await Task.yield()
            iterations += 1
        }

        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.remainingSeconds, 0)
        XCTAssertFalse(session.isTimerActive)
        XCTAssertEqual(session.timerStartCount, 1)
        // One wake per countdown second plus breathing phase changes; never a busy loop.
        XCTAssertGreaterThanOrEqual(autoClock.sleepCount, 60)
        XCTAssertLessThan(autoClock.sleepCount, 100)

        let sleepsAtCompletion = autoClock.sleepCount
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(autoClock.sleepCount, sleepsAtCompletion, "Timer task kept running after completion")
    }

    // 8
    func testEndingEarlyDoesNotReportCompletion() {
        session.start()
        advance(75)
        session.endEarly()

        XCTAssertEqual(session.state, .endedEarly)
        XCTAssertNotEqual(session.state, .completed)
        XCTAssertEqual(session.restedSeconds, 75)
        XCTAssertFalse(session.isTimerActive)

        advance(500)
        XCTAssertEqual(session.state, .endedEarly)
    }

    func testEndingWhilePausedReportsTimeRestedBeforePause() {
        session.start()
        advance(20)
        session.pause()
        advance(100)
        session.endEarly()
        XCTAssertEqual(session.state, .endedEarly)
        XCTAssertEqual(session.restedSeconds, 20)
    }

    // 9
    func testResetClearsPreviousSessionState() {
        session.selectedDuration = .fiveMinutes
        session.start()
        advance(64)
        session.pause()
        session.reset()

        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.isTimerActive)
        XCTAssertEqual(session.remainingSeconds, 300)
        XCTAssertEqual(session.restedSeconds, 0)
        XCTAssertEqual(session.breathingPhase, .inhale)
        XCTAssertEqual(session.elapsed, .zero)
        XCTAssertEqual(session.selectedDuration, .fiveMinutes, "Preferences survive returning home")
    }

    func testRestAgainStartsFreshSessionWithSamePreferences() {
        session.selectedDuration = .oneMinute
        session.isBreathingGuideEnabled = false
        session.start()
        advance(60)
        XCTAssertEqual(session.state, .completed)

        session.restAgain()
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.sessionDuration, .oneMinute)
        XCTAssertFalse(session.isGuidedSession)
        XCTAssertEqual(session.remainingTime, .seconds(60))
        XCTAssertEqual(session.breathingPhase, .inhale)
        XCTAssertEqual(session.restedSeconds, 0)
        XCTAssertTrue(session.isTimerActive)
        XCTAssertEqual(session.timerStartCount, 2)
    }

    // 10
    func testBreathingPatternAlternatesWithDefinedDurations() {
        let pattern = BreathingPattern.standard
        XCTAssertEqual(pattern.inhale, .seconds(4))
        XCTAssertEqual(pattern.exhale, .seconds(6))

        let expectations: [(Double, BreathingPhase)] = [
            (0, .inhale), (3.99, .inhale), (4, .exhale), (9.99, .exhale),
            (10, .inhale), (13.99, .inhale), (14, .exhale), (20, .inhale),
        ]
        for (seconds, phase) in expectations {
            XCTAssertEqual(pattern.phase(at: .seconds(seconds)), phase, "at \(seconds)s")
        }

        XCTAssertEqual(pattern.expansion(at: .zero), 0, accuracy: 0.0001)
        XCTAssertEqual(pattern.expansion(at: .seconds(4)), 1, accuracy: 0.0001)
        XCTAssertEqual(pattern.expansion(at: .seconds(10)), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(pattern.expansion(at: .seconds(3)), pattern.expansion(at: .seconds(1)))
        XCTAssertLessThan(pattern.expansion(at: .seconds(8)), pattern.expansion(at: .seconds(6)))
    }

    func testSessionBreathingPhaseFollowsElapsedTimeAndFreezesWhenPaused() {
        session.start()
        XCTAssertEqual(session.breathingPhase, .inhale)
        advance(4)
        XCTAssertEqual(session.breathingPhase, .exhale)
        advance(5)
        XCTAssertEqual(session.breathingPhase, .exhale)
        let expansionBeforePause = session.currentBreathingExpansion()

        session.pause()
        advance(1.5)
        XCTAssertEqual(session.breathingPhase, .exhale)
        XCTAssertEqual(session.currentBreathingExpansion(), expansionBeforePause, accuracy: 0.0001)

        session.resume()
        advance(1)
        XCTAssertEqual(session.breathingPhase, .inhale)
    }

    // 11
    func testLifecycleInterruptionPreservesRemainingDurationAndResumes() {
        session.start()
        advance(30)
        advance(1.5)
        let phaseBefore = session.breathingPhase

        session.handleScenePhase(.inactive)
        XCTAssertEqual(session.state, .paused(.interruption))
        XCTAssertFalse(session.isTimerActive)
        session.handleScenePhase(.background)
        advance(600)
        XCTAssertEqual(session.remainingTime, .seconds(148.5))
        XCTAssertEqual(session.breathingPhase, phaseBefore)

        session.handleScenePhase(.active)
        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(session.isTimerActive)
        XCTAssertEqual(session.remainingTime, .seconds(148.5))
        advance(10)
        XCTAssertEqual(session.remainingTime, .seconds(138.5))
    }

    func testLifecycleDoesNotResumeManuallyPausedSession() {
        session.start()
        advance(10)
        session.pause()

        session.handleScenePhase(.background)
        XCTAssertEqual(session.state, .paused(.user))
        session.handleScenePhase(.active)
        XCTAssertEqual(session.state, .paused(.user))
        XCTAssertFalse(session.isTimerActive)
        XCTAssertEqual(session.remainingTime, .seconds(170))
    }

    func testLifecycleChangesDoNothingOutsideActiveSession() {
        session.handleScenePhase(.background)
        session.handleScenePhase(.active)
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.isTimerActive)

        session.start()
        session.endEarly()
        session.handleScenePhase(.inactive)
        session.handleScenePhase(.active)
        XCTAssertEqual(session.state, .endedEarly)
        XCTAssertFalse(session.isTimerActive)
    }

    // 12
    func testMultipleStartAttemptsDoNotCreateDuplicateTimers() {
        session.start()
        advance(5)
        session.start()
        session.start()
        session.resume()
        session.handleScenePhase(.active)

        XCTAssertEqual(session.timerStartCount, 1)
        XCTAssertTrue(session.isTimerActive)
        XCTAssertEqual(session.remainingTime, .seconds(175), "A repeated start must not restart the countdown")

        session.pause()
        session.pause()
        session.resume()
        session.resume()
        XCTAssertEqual(session.timerStartCount, 2)
        XCTAssertTrue(session.isTimerActive)
    }

    func testTimeFormatting() {
        XCTAssertEqual(TimeFormatting.clock(180), "3:00")
        XCTAssertEqual(TimeFormatting.clock(65), "1:05")
        XCTAssertEqual(TimeFormatting.clock(0), "0:00")
        XCTAssertEqual(TimeFormatting.spoken(125), "2 minutes, 5 seconds")
        XCTAssertEqual(TimeFormatting.spoken(60), "1 minute")
        XCTAssertEqual(TimeFormatting.spoken(1), "1 second")
    }
}
