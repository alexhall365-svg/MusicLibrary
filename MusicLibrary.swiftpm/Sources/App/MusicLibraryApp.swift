import SwiftUI
import SwiftData

@main
struct MusicLibraryApp: App {
    private let container: ModelContainer
    @State private var appState = AppState()

    init() {
        container = LibraryDatabase.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .modelContainer(container)
    }
}
