import SwiftUI
import Foundation
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
    @Published var isExporting = false
    @Published var lastExportURL: URL?
    @Published var lastExportName: String?

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

    func run(project: AuroraProject, context: ModelContext, module: String? = nil) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        runStatus = "Validating"

        let record = RunRecord(projectID: project.id)
        context.insert(record)
        try? context.save()

        let executionPayload = executionPayload(for: project.payload, module: module)

        Task {
            do {
                let final = try await api.run(executionPayload) { [weak self] update in
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
    private func executionPayload(for base: JSONValue, module: String?) -> JSONValue {
        guard let module, case .object(var fields) = base else { return base }
        fields["runMode"] = .string("module")
        fields["requested_module"] = .string(module)
        fields["question"] = .string("Execute the selected governed AURORA engine and return evidence-bound outputs.")
        return .object(fields)
    }

    func export(project: AuroraProject, format: String) {
        guard !isExporting else { return }
        isExporting = true
        lastError = nil
        let analyses = (try? JSONDecoder().decode(JSONValue.self, from: Data(project.analysesJSON.utf8))) ?? .object([:])
        let flowsheet = (try? JSONDecoder().decode(JSONValue.self, from: Data(project.flowsheetJSON.utf8))) ?? .object(["units": .array([])])
        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_" + project.name),
            "project": project.payload,
            "designBasis": .object([
                "target_component": .string(project.targetComponent),
                "target_grade": .number(project.targetGrade)
            ]),
            "analyses": analyses,
            "flowsheet": flowsheet,
            "diagnostics": .array([]),
            "result": activeResult ?? .object([:]),
            "run": .object([:])
        ])

        Task {
            do {
                let file = try await api.export(body, format: format)
                lastExportURL = file.url
                lastExportName = file.name
            } catch {
                lastError = error.localizedDescription
            }
            isExporting = false
        }
    }

}
