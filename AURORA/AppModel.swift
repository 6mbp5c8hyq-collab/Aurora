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
    @Published var vaultStatus: JSONValue?
    @Published var serverDagRuns: [JSONValue] = []

    private let api = AURORAAPI()

    func checkHealth() {
        connection = .checking
        Task {
            do {
                let result = try await api.health()
                connection = .online(result.firstString(["status", "platform_status", "ok"]) ?? "online")
                await refreshServerState(recoverLatest: true)
            } catch {
                connection = .offline(error.localizedDescription)
            }
        }
    }

    func refreshServerState(recoverLatest: Bool = false) async {
        vaultStatus = try? await api.vaultStatus()

        do {
            let recent = try await api.recentDagRuns()
            if let runsValue = recent.recursiveFind("runs"), case .array(let runs) = runsValue {
                serverDagRuns = runs
            } else {
                serverDagRuns = []
            }

            if recoverLatest,
               let first = serverDagRuns.first,
               let id = first.firstString(["run_id", "runId", "id"]),
               !id.isEmpty {
                let latest = try await api.dagRun(id)
                let display = normalized(latest)
                activeResult = display
                activeJobID = id
                runStatus = ResultTools.status(display)
            }
        } catch {
            serverDagRuns = []
        }
    }

    func run(project: AuroraProject, context: ModelContext, module: String? = nil) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        runStatus = module == nil ? "Starting DAG" : "Validating module"

        let record = RunRecord(projectID: project.id)
        context.insert(record)
        try? context.save()

        Task {
            do {
                let final: JSONValue
                if let module {
                    let executionPayload = executionPayload(for: project.payload, module: module)
                    final = try await api.run(executionPayload) { [weak self] update in
                        await MainActor.run {
                            self?.apply(update: update, to: record, context: context)
                        }
                    }
                } else {
                    final = try await api.runProject(project.payload) { [weak self] update in
                        await MainActor.run {
                            self?.apply(update: update, to: record, context: context)
                        }
                    }
                }

                let display = normalized(final)
                activeResult = display
                runStatus = ResultTools.status(display)
                record.status = runStatus
                record.rawResultJSON = display.prettyString()
                record.updatedAt = .now
                try? context.save()
                await refreshServerState()
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

    private func apply(update: JSONValue, to record: RunRecord, context: ModelContext) {
        let display = normalized(update)
        activeResult = display
        runStatus = ResultTools.status(display)
        if let id = update.firstString(["run_id", "runId", "job_id", "jobId", "id"]) {
            activeJobID = id
            record.jobID = id
        }
        record.status = runStatus
        record.updatedAt = .now
        record.rawResultJSON = display.prettyString()
        try? context.save()
    }

    private func normalized(_ value: JSONValue) -> JSONValue {
        guard case .object(var object) = value else { return value }

        let requested = object["requested_module"]?.stringValue
            ?? object["requestedModule"]?.stringValue
            ?? object["payload"]?.firstString(["requested_module", "requestedModule"])

        if let requested, !requested.isEmpty,
           let engineResult = object["result"] {
            object[requested] = engineResult
            object["active_engine"] = .string(requested)
        }

        return .object(object)
    }

    private func executionPayload(for base: JSONValue, module: String) -> JSONValue {
        var payload = base
        if case .object(var fields) = base {
            fields["runMode"] = .string("module")
            fields["requested_module"] = .string(module)
            fields["question"] = .string("Execute the selected governed AURORA engine and return evidence-bound outputs.")
            payload = .object(fields)
        }

        return .object([
            "operation": .string("canonical_mobile_execute"),
            "requested_module": .string(module),
            "payload": payload
        ])
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
