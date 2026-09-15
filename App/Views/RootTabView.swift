import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            BookView()
                .tabItem { Label("Book", systemImage: "list.bullet.rectangle") }
            MessageView()
                .tabItem { Label("Message", systemImage: "bubble.left.and.bubble.right") }
        }
    }
}
