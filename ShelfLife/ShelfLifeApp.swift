import SwiftUI
import SwiftData

@main
struct ShelfLifeApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([MediaItem.self])
        // Local-only database stored in the app's private folder on the iPhone.
        // No App Group, no CloudKit, no network sync of any kind.
        let config = ModelConfiguration(
            "ShelfLife",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not open the catalogue database: \(error)")
        }
        BackupExclusion.apply()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
