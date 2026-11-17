import Foundation
import SwiftData

enum LibraryDatabase {
    static let schema = Schema([Score.self, Setlist.self, SetlistEntry.self])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        do {
            if inMemory {
                let configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: configuration)
            }
            let paths = LibraryPaths.shared
            try paths.ensureDirectories()
            // SwiftData's own CloudKit mirroring stays off: it can't share with a
            // choir. `CloudSync` syncs this store with CKSyncEngine instead.
            let configuration = ModelConfiguration(
                schema: schema,
                url: paths.databaseURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the library database: \(error)")
        }
    }
}
