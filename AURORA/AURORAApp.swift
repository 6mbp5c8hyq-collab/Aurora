import SwiftUI
import SwiftData

@main
struct AURORAApp: App {
    private let container: ModelContainer = {
        let schema = Schema([AuroraProject.self, RunRecord.self])
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)])
    }()
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model).preferredColorScheme(.dark) }
            .modelContainer(container)
    }
}
