import SwiftUI

/// The central calming visual. `expansion` (0...1) is supplied by the session so
/// the orb is always in step with the displayed breathing instruction.
struct BreathingOrb: View {
    /// 0 = fully exhaled, 1 = fully inhaled. Ignored when not guided.
    var expansion: Double
    var isGuided: Bool
    var isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: Double { isGuided ? expansion : 0.5 }

    private var scale: Double {
        if !isGuided { return 0.82 }
        // With Reduce Motion the orb barely changes size; brightness carries the rhythm.
        return reduceMotion ? 0.8 + 0.04 * level : 0.66 + 0.34 * level
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.cyan.opacity(0.35 + 0.25 * level), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 210
                    )
                )
                .blur(radius: 30)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Palette.cyan, Palette.blue, Palette.lavender],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.55 + 0.3 * level)
                .overlay {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.45), .clear],
                                center: UnitPoint(x: 0.35, y: 0.3),
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                }
                .padding(70)
                .shadow(color: Palette.blue.opacity(0.45), radius: 30)
        }
        .scaleEffect(scale)
        .saturation(isPaused ? 0.6 : 1)
        .frame(width: 320, height: 320)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        BreathingOrb(expansion: 0, isGuided: true, isPaused: false)
        BreathingOrb(expansion: 1, isGuided: true, isPaused: false)
        BreathingOrb(expansion: 0, isGuided: false, isPaused: false)
    }
    .padding()
    .background(Palette.midnight)
}
