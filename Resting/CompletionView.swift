import SwiftUI

/// Shown when a session finishes. A session that reached zero says
/// "Rest Complete"; one ended early says so honestly.
struct CompletionView: View {
    @Environment(RestSession.self) private var session

    private var completed: Bool { session.state == .completed }

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 18) {
                Image(systemName: completed ? "sparkles" : "moon.stars")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Palette.cyan)
                    .accessibilityHidden(true)

                Text(completed ? "Rest Complete" : "Session Ended")
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .accessibilityAddTraits(.isHeader)

                Text(summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
            .frame(maxWidth: 600)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 36, style: .continuous))

            HStack(spacing: 20) {
                Button {
                    session.restAgain()
                } label: {
                    Label("Rest Again", systemImage: "arrow.counterclockwise")
                        .font(.title3.weight(.medium))
                        .frame(minWidth: 170)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.blue)
                .controlSize(.extraLarge)
                .accessibilityHint("Starts another \(session.sessionDuration.spokenTitle) session")

                Button {
                    session.reset()
                } label: {
                    Label("Back to Home", systemImage: "house")
                        .font(.title3)
                        .frame(minWidth: 170)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)
                .accessibilityHint("Returns to the welcome screen")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: String {
        if completed {
            return "You rested for \(session.sessionDuration.spokenTitle). Carry this calm with you."
        }
        if session.restedSeconds == 0 {
            return "You ended the session before it began. Try again whenever you like."
        }
        return "You rested for \(TimeFormatting.spoken(session.restedSeconds)) of \(session.sessionDuration.spokenTitle)."
    }
}

#Preview {
    let session = RestSession()
    session.start()
    session.endEarly()
    return CompletionView()
        .environment(session)
        .padding(40)
}
