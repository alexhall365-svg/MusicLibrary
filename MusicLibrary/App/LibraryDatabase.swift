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
            // CloudKit stays off until there is a paid developer account. The models
            // are already CloudKit-friendly (defaults everywhere, optional relationships).
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
