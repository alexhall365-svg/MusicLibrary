import SwiftUI
import SwiftData

@main
struct MusicLibraryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var appState = AppState()

    init() {
        container = LibraryDatabase.makeContainer()
        CloudSync.shared.configure(modelContainer: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(CloudSync.shared)
                .task {
                    appState.pro.start()
                }
        }
        .modelContainer(container)
    }
}
