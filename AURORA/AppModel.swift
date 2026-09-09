import SwiftUI
import SwiftData

@MainActor
final class AppModel: ObservableObject {
    enum ConnectionState {
        case unknown
        case checking
        case online(String)
        case offline(String)
    }

    @Published var connection: ConnectionState = .unknown
    @Published var activeResult: JSONValue?
    @Published var activeJobID: String?
    @Published var runStatus = "Idle"
    @Published var isRunning = false
    @Published var lastError: String?

    private let api = AURORAAPI()

    func checkHealth() {
        connection = .checking
        Task {
            do {
                let result = try await api.health()
                connection = .online(result.firstString(["status", "platform_status", "ok"]) ?? "online")
            } catch {
                connection = .offline(error.localizedDescription)
            }
        }
    }

    func run(project: AuroraProject, context: ModelContext) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        runStatus = "Validating"

        let record = RunRecord(projectID: project.id)
        context.insert(record)
        try? context.save()

        Task {
            do {
                let final = try await api.run(project.payload) { [weak self] update in
                    await MainActor.run {
                        self?.activeResult = update
                        self?.runStatus = ResultTools.status(update)
                        if let id = update.firstString(["job_id", "jobId", "id"]) {
                            self?.activeJobID = id
                            record.jobID = id
                        }
                        record.status = self?.runStatus ?? "running"
                        record.updatedAt = .now
                        record.rawResultJSON = update.prettyString()
                        try? context.save()
                    }
                }

                activeResult = final
                runStatus = ResultTools.status(final)
                record.status = runStatus
                record.rawResultJSON = final.prettyString()
                record.updatedAt = .now
                try? context.save()
            } catch {
                lastError = error.localizedDescription
                runStatus = "Execution error"
                record.status = "error"
                record.errorText = error.localizedDescription
                record.updatedAt = .now
                try? context.save()
            }
            isRunning = false
        }
    }
}
