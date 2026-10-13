import Foundation

/// A monotonic time source the session uses for all timing decisions.
/// Injected so tests can control time deterministically.
protocol SessionClock: Sendable {
    /// Monotonic time measured from an arbitrary fixed origin.
    func now() -> Duration
    func sleep(for duration: Duration) async throws
}

struct ContinuousSessionClock: SessionClock {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now

    func now() -> Duration {
        origin.duration(to: clock.now)
    }

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}
