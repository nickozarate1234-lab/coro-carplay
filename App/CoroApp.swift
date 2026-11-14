import SwiftUI

@main
@MainActor
struct CoroApp: App {
    @StateObject private var auth: SpotifyAuth
    @StateObject private var session: SessionController

    init() {
        let access = SpotifyAuth()
        _auth = StateObject(wrappedValue: access)
        _session = StateObject(wrappedValue: SessionController(auth: access))
    }

    var body: some Scene {
        WindowGroup {
            MainView(session: session, auth: auth)
                .preferredColorScheme(.dark)
                .tint(CoroStyle.accent)
        }
    }
}
