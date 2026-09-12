import Foundation

struct ScenarioMetadata: Codable, Hashable {
    let name: String
    let projectID: String
    let projectName: String
    let feedTPH: Double
    let targetGrade: Double
    let createdAt: Date
}

enum ScenarioMetadataStore {
    private static let key = "aurora.scenario.metadata.v1"

    static func metadata(for runID: String) -> ScenarioMetadata? {
        all()[runID]
    }

    static func save(_ metadata: ScenarioMetadata, for runID: String) {
        guard !runID.isEmpty else { return }
        var values = all()
        values[runID] = metadata
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func all() -> [String: ScenarioMetadata] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ScenarioMetadata].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
