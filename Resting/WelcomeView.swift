import SwiftUI

struct WelcomeView: View {
    @Environment(RestSession.self) private var session

    var body: some View {
        @Bindable var session = session

        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Image(systemName: "leaf")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Palette.cyan)
                    .accessibilityHidden(true)
                Text("Resting")
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text("Take a quiet moment for yourself.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Duration")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        ForEach(SessionDuration.allCases) { duration in
                            DurationOption(
                                duration: duration,
                                isSelected: session.selectedDuration == duration
                            ) {
                                session.selectedDuration = duration
                            }
                        }
                    }
                }

                Divider()

                Toggle(isOn: $session.isBreathingGuideEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Guided breathing")
                            .font(.title3)
                        Text("Breathe in for 4 seconds, out for 6")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Palette.blue)
                .accessibilityHint("Shows a breathing animation and instructions during your session")
            }
            .padding(32)
            .frame(maxWidth: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            Button {
                session.start()
            } label: {
                Text("Begin Resting")
                    .font(.title2.weight(.medium))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.blue)
            .controlSize(.extraLarge)
            .accessibilityHint("Starts a \(session.selectedDuration.spokenTitle) resting session")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DurationOption: View {
    let duration: SessionDuration
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.cyan : .secondary)
                Text("\(duration.minutes)")
                    .font(.system(size: 34, weight: isSelected ? .semibold : .light, design: .rounded))
                Text(duration.minutes == 1 ? "minute" : "minutes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isSelected ? Palette.blue.opacity(0.35) : Color.white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? Palette.cyan.opacity(0.8) : Color.white.opacity(0.12),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(duration.spokenTitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Selected session length" : "Selects a \(duration.spokenTitle) session")
    }
}

#Preview {
    WelcomeView()
        .environment(RestSession())
        .padding(40)
}
