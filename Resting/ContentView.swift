import SwiftUI

struct ContentView: View {
    @Environment(RestSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AmbientBackground()

            Group {
                switch session.state {
                case .idle:
                    WelcomeView()
                        .transition(.opacity)
                case .running, .paused:
                    MeditationView()
                        .transition(.opacity)
                case .completed, .endedEarly:
                    CompletionView()
                        .transition(.opacity)
                }
            }
            .padding(48)
        }
        .frame(minWidth: 640, minHeight: 620)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: screen)
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhase(newPhase)
        }
    }

    /// Changes only when the visible screen changes, not on pause/resume.
    private var screen: Int {
        switch session.state {
        case .idle: 0
        case .running, .paused: 1
        case .completed, .endedEarly: 2
        }
    }
}

/// Deep midnight backdrop with soft, static cyan and lavender light.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.midnight, Palette.navy],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Palette.cyan.opacity(0.22), .clear],
                center: UnitPoint(x: 0.2, y: 0.15),
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [Palette.lavender.opacity(0.2), .clear],
                center: UnitPoint(x: 0.85, y: 0.9),
                startRadius: 0,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

enum Palette {
    static let midnight = Color(red: 0.03, green: 0.05, blue: 0.14)
    static let navy = Color(red: 0.06, green: 0.09, blue: 0.24)
    static let cyan = Color(red: 0.45, green: 0.85, blue: 0.95)
    static let blue = Color(red: 0.36, green: 0.55, blue: 0.98)
    static let lavender = Color(red: 0.68, green: 0.6, blue: 0.98)
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(RestSession())
}
