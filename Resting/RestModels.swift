import Foundation

/// The session lengths offered on the welcome screen.
enum SessionDuration: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 1
    case threeMinutes = 3
    case fiveMinutes = 5

    static let `default`: SessionDuration = .threeMinutes

    var id: Int { rawValue }

    var minutes: Int { rawValue }

    var duration: Duration { .seconds(rawValue * 60) }

    var shortTitle: String { "\(minutes) min" }

    var spokenTitle: String { minutes == 1 ? "1 minute" : "\(minutes) minutes" }
}

/// Why a session is currently paused. Only interruption pauses resume automatically.
enum PauseReason: Equatable, Sendable {
    case user
    case interruption
}

enum SessionState: Equatable, Sendable {
    /// No session in progress; the welcome screen is shown.
    case idle
    case running
    case paused(PauseReason)
    /// The countdown reached zero.
    case completed
    /// The user ended the session before the countdown reached zero.
    case endedEarly

    var isActive: Bool {
        switch self {
        case .running, .paused: true
        case .idle, .completed, .endedEarly: false
        }
    }

    var isFinished: Bool {
        self == .completed || self == .endedEarly
    }
}

enum BreathingPhase: Equatable, Sendable {
    case inhale
    case exhale

    var instruction: String {
        switch self {
        case .inhale: "Breathe in"
        case .exhale: "Breathe out"
        }
    }
}

/// A repeating inhale/exhale cycle. All values derive from session elapsed time,
/// so pausing the session freezes the breathing guide at the same point.
struct BreathingPattern: Equatable, Sendable {
    var inhale: Duration
    var exhale: Duration

    static let standard = BreathingPattern(inhale: .seconds(4), exhale: .seconds(6))

    var cycle: Duration { inhale + exhale }

    struct Position: Equatable, Sendable {
        var phase: BreathingPhase
        var elapsedInPhase: Duration
        var remainingInPhase: Duration
    }

    func position(at elapsed: Duration) -> Position {
        let cycleSeconds = cycle.seconds
        let inhaleSeconds = inhale.seconds
        let offset = max(0, elapsed.seconds).truncatingRemainder(dividingBy: cycleSeconds)
        if offset < inhaleSeconds {
            return Position(
                phase: .inhale,
                elapsedInPhase: .seconds(offset),
                remainingInPhase: .seconds(inhaleSeconds - offset)
            )
        }
        let exhaleOffset = offset - inhaleSeconds
        return Position(
            phase: .exhale,
            elapsedInPhase: .seconds(exhaleOffset),
            remainingInPhase: .seconds(exhale.seconds - exhaleOffset)
        )
    }

    func phase(at elapsed: Duration) -> BreathingPhase {
        position(at: elapsed).phase
    }

    /// Lung "fullness" from 0 (empty) to 1 (full), eased so the orb starts and
    /// finishes each breath softly.
    func expansion(at elapsed: Duration) -> Double {
        let position = position(at: elapsed)
        switch position.phase {
        case .inhale:
            return Self.ease(position.elapsedInPhase.seconds / inhale.seconds)
        case .exhale:
            return 1 - Self.ease(position.elapsedInPhase.seconds / exhale.seconds)
        }
    }

    private static func ease(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return (1 - cos(.pi * clamped)) / 2
    }
}

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

enum TimeFormatting {
    /// "2:05" style countdown text.
    static func clock(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "2 minutes, 5 seconds" style text for VoiceOver and summaries.
    static func spoken(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutes = seconds / 60
        let remainder = seconds % 60
        let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let secondText = remainder == 1 ? "1 second" : "\(remainder) seconds"
        switch (minutes, remainder) {
        case (0, _): return secondText
        case (_, 0): return minuteText
        default: return "\(minuteText), \(secondText)"
        }
    }
}
