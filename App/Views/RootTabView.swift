import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            DebriefView()
                .tabItem { Label("Debrief", systemImage: "chart.bar.doc.horizontal") }
            BookView()
                .tabItem { Label("Book", systemImage: "list.bullet.rectangle") }
            MessageView()
                .tabItem { Label("Message", systemImage: "bubble.left.and.bubble.right") }
        }
        // Polling lives here, above the tabs, so switching tabs does not stop
        // it and the two read-model tabs cannot fight over one timer.
        .task {
            await store.refreshDebrief()
            store.startPolling()
        }
        .onDisappear { store.stopPolling() }
    }
}
