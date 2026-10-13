import SwiftUI

@main
struct RestingApp: App {
    @State private var session = RestSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
        .defaultSize(width: 960, height: 760)
        .windowResizability(.contentMinSize)
    }
}
