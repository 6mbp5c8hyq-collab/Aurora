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
    private static let pendingKey = "aurora.scenario.pending.v1"

    static func metadata(for runID: String) -> ScenarioMetadata? {
        all()[runID]
    }

    static func setPending(_ metadata: ScenarioMetadata) {
        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    static func bindPending(to runID: String) {
        guard !runID.isEmpty,
              let data = UserDefaults.standard.data(forKey: pendingKey),
              let metadata = try? JSONDecoder().decode(ScenarioMetadata.self, from: data) else { return }
        save(metadata, for: runID)
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
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
