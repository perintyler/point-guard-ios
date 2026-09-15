import SwiftUI

@main
struct PointGuardApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}
