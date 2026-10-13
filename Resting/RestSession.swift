import Foundation
import Observation
import SwiftUI

/// Single source of truth for a resting session: preferences, state, remaining
/// time, and the breathing phase. Owns at most one timer task at any moment.
@MainActor
@Observable
final class RestSession {
    // MARK: Preferences (chosen on the welcome screen)

    var selectedDuration: SessionDuration = .default
    var isBreathingGuideEnabled = true

    // MARK: Observable session state

    private(set) var state: SessionState = .idle
    /// Duration and guide setting captured when the current session started.
    private(set) var sessionDuration: SessionDuration = .default
    private(set) var isGuidedSession = true
    /// Whole seconds left, rounded up, for display. Updated by the timer task.
    private(set) var remainingSeconds: Int = SessionDuration.default.minutes * 60
    private(set) var breathingPhase: BreathingPhase = .inhale
    /// How long the user actually rested; set when a session finishes or ends.
    private(set) var restedSeconds: Int = 0

    // MARK: Timing internals

    @ObservationIgnored private let clock: any SessionClock
    @ObservationIgnored let breathingPattern: BreathingPattern
    @ObservationIgnored private var accumulatedElapsed: Duration = .zero
    @ObservationIgnored private var runningSince: Duration?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    /// Number of timer tasks ever started; lets tests prove no duplicates are created.
    @ObservationIgnored private(set) var timerStartCount = 0

    init(clock: any SessionClock = ContinuousSessionClock(), breathingPattern: BreathingPattern = .standard) {
        self.clock = clock
        self.breathingPattern = breathingPattern
    }

    // MARK: Derived values

    var isRunning: Bool { state == .running }
    var isPaused: Bool { if case .paused = state { true } else { false } }
    var isTimerActive: Bool { timerTask != nil }

    var totalDuration: Duration { sessionDuration.duration }

    /// Precise elapsed session time, read from the monotonic clock.
    var elapsed: Duration {
        let running = runningSince.map { clock.now() - $0 } ?? .zero
        return min(accumulatedElapsed + running, totalDuration)
    }

    var remainingTime: Duration {
        max(.zero, totalDuration - elapsed)
    }

    /// Breathing expansion (0...1) at this instant, for frame-by-frame rendering.
    func currentBreathingExpansion() -> Double {
        breathingPattern.expansion(at: elapsed)
    }

    // MARK: Intents

    /// Starts a new session from the welcome or finished screens. Ignored while a
    /// session is already running or paused, so repeated taps can't stack timers.
    func start() {
        guard !state.isActive else { return }
        stopTimer()
        sessionDuration = selectedDuration
        isGuidedSession = isBreathingGuideEnabled
        accumulatedElapsed = .zero
        restedSeconds = 0
        runningSince = clock.now()
        state = .running
        updateDisplay(elapsed: .zero)
        startTimer()
    }

    func pause() {
        guard state == .running else { return }
        suspend(reason: .user)
    }

    func resume() {
        guard isPaused else { return }
        runningSince = clock.now()
        state = .running
        refresh()
        if state == .running { startTimer() }
    }

    func togglePause() {
        if isRunning { pause() } else if isPaused { resume() }
    }

    /// Ends an active session before the countdown finishes.
    func endEarly() {
        guard state.isActive else { return }
        let finalElapsed = elapsed
        stopTimer()
        freeze(at: finalElapsed)
        restedSeconds = Int(finalElapsed.seconds)
        state = .endedEarly
    }

    /// Clears everything and returns to the welcome screen.
    func reset() {
        stopTimer()
        accumulatedElapsed = .zero
        runningSince = nil
        restedSeconds = 0
        sessionDuration = selectedDuration
        isGuidedSession = isBreathingGuideEnabled
        updateDisplay(elapsed: .zero)
        state = .idle
    }

    /// Starts a fresh session with the same duration and breathing preference.
    func restAgain() {
        let duration = sessionDuration
        let guided = isGuidedSession
        reset()
        selectedDuration = duration
        isBreathingGuideEnabled = guided
        start()
    }

    // MARK: Lifecycle

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active: sceneDidBecomeActive()
        case .inactive, .background: sceneDidBecomeInactive()
        @unknown default: sceneDidBecomeInactive()
        }
    }

    func sceneDidBecomeInactive() {
        guard state == .running else { return }
        suspend(reason: .interruption)
    }

    func sceneDidBecomeActive() {
        guard state == .paused(.interruption) else { return }
        resume()
    }

    // MARK: Timer

    /// Recomputes state from the clock. Called by the timer task at each deadline.
    func refresh() {
        guard state == .running else { return }
        let current = elapsed
        if current >= totalDuration {
            complete()
        } else {
            updateDisplay(elapsed: current)
        }
    }

    private func complete() {
        stopTimer()
        freeze(at: totalDuration)
        updateDisplay(elapsed: totalDuration)
        restedSeconds = sessionDuration.minutes * 60
        state = .completed
    }

    private func suspend(reason: PauseReason) {
        let current = elapsed
        stopTimer()
        freeze(at: current)
        state = .paused(reason)
        updateDisplay(elapsed: current)
    }

    private func freeze(at elapsedTime: Duration) {
        accumulatedElapsed = elapsedTime
        runningSince = nil
    }

    private func updateDisplay(elapsed current: Duration) {
        let remaining = max(.zero, totalDuration - current).seconds
        let seconds = Int(remaining.rounded(.up))
        if remainingSeconds != seconds { remainingSeconds = seconds }
        let phase = breathingPattern.phase(at: current)
        if breathingPhase != phase { breathingPhase = phase }
    }

    private func startTimer() {
        stopTimer()
        timerStartCount += 1
        let clock = clock
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.delayUntilNextEvent() else { return }
                do {
                    try await clock.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.refresh()
                guard self.state == .running else { return }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Time until the next visible change: a countdown second boundary, a
    /// breathing phase change, or the end of the session. Waking slightly after
    /// the boundary avoids rendering a stale value; drift never accumulates
    /// because every wake recomputes from the monotonic clock.
    private func delayUntilNextEvent() -> Duration {
        let current = elapsed
        let remaining = max(.zero, totalDuration - current).seconds
        var untilSecond = remaining - remaining.rounded(.down)
        if untilSecond <= 0 { untilSecond = 1 }
        let untilPhase = breathingPattern.position(at: current).remainingInPhase.seconds
        let next = min(untilSecond, untilPhase, remaining)
        return .seconds(max(next, 0) + 0.005)
    }
}
