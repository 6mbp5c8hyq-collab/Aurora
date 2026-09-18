import SwiftUI
import SwiftData

@main
struct AURORAApp: App {
    private let container: ModelContainer = {
        let schema = Schema([AuroraProject.self, RunRecord.self])
        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [persistent])
        } catch {
            // Never crash the application at launch because a device-local SwiftData
            // store is stale or incompatible. Keep AURORA operable and allow the
            // runtime/backend diagnostics to load; persistence can be repaired later.
            assertionFailure("AURORA persistent store unavailable: \(error)")
            let recovery = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [recovery])
            } catch {
                fatalError("AURORA could not initialize even the recovery data store: \(error)")
            }
        }
    }()

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            IndustrialSurfaceView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
