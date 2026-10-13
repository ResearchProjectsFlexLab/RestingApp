import SwiftUI

struct MeditationView: View {
    @Environment(RestSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 28) {
            Text("Resting · \(session.sessionDuration.spokenTitle)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Resting session, \(session.sessionDuration.spokenTitle)")

            Spacer(minLength: 0)

            // Redraws every frame only while a guided session is running; the
            // countdown itself is driven by the session's timer task.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(session.isRunning && session.isGuidedSession))) { _ in
                BreathingOrb(
                    expansion: session.currentBreathingExpansion(),
                    isGuided: session.isGuidedSession,
                    isPaused: session.isPaused
                )
            }

            instruction
                .frame(minHeight: 90)

            Text(TimeFormatting.clock(session.remainingSeconds))
                .font(.system(size: 76, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: session.remainingSeconds)
                .accessibilityLabel("Time remaining")
                .accessibilityValue(TimeFormatting.spoken(session.remainingSeconds))

            Spacer(minLength: 0)

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var instruction: some View {
        VStack(spacing: 8) {
            if session.isPaused {
                Label("Paused", systemImage: "pause.circle")
                    .font(.system(size: 34, weight: .regular, design: .rounded))
                Text(session.state == .paused(.interruption)
                     ? "Your session will continue when you return."
                     : "Resume whenever you're ready.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else if session.isGuidedSession {
                Text(session.breathingPhase.instruction)
                    .font(.system(size: 40, weight: .regular, design: .rounded))
                    .id(session.breathingPhase)
                    .transition(.opacity)
                Text("Slowly and gently.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text("Rest quietly")
                    .font(.system(size: 34, weight: .regular, design: .rounded))
                Text("Let your thoughts settle.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: session.breathingPhase)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button {
                session.togglePause()
            } label: {
                Label(session.isPaused ? "Resume" : "Pause",
                      systemImage: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3.weight(.medium))
                    .frame(minWidth: 160)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.blue)
            .controlSize(.extraLarge)
            .accessibilityHint(session.isPaused ? "Continues the countdown" : "Pauses the countdown")

            Button {
                session.endEarly()
            } label: {
                Label("End Session", systemImage: "xmark")
                    .font(.title3)
                    .frame(minWidth: 160)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.extraLarge)
            .accessibilityHint("Stops this session early")
        }
    }
}

#Preview {
    let session = RestSession()
    session.start()
    return MeditationView()
        .environment(session)
        .padding(40)
}
