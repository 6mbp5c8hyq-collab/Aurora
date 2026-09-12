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
    @Published var activeResultOrigin = "No active result"
    @Published var runStatus = "Idle"
    @Published var isRunning = false
    @Published var isLoadingStoredRun = false
    @Published var validationResult: JSONValue?
    @Published var isValidating = false
    @Published var lastError: String?
    @Published var isExporting = false
    @Published var lastExportURL: URL?
    @Published var lastExportName: String?
    @Published var vaultStatus: JSONValue?
    @Published var runtimeAudit: JSONValue?
    @Published var serverDagRuns: [JSONValue] = []
    @Published var serverJobs: [JSONValue] = []

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
        async let vaultTask = try? api.vaultStatus()
        async let auditTask = try? api.audit()
        async let dagTask = try? api.recentDagRuns()
        async let jobsTask = try? api.recentJobs()

        vaultStatus = await vaultTask
        runtimeAudit = await auditTask

        if let recent = await dagTask,
           let runsValue = recent.recursiveFind("runs"), case .array(let runs) = runsValue {
            serverDagRuns = runs
        } else {
            serverDagRuns = []
        }

        if let jobs = await jobsTask,
           let jobsValue = jobs.recursiveFind("jobs"), case .array(let rows) = jobsValue {
            serverJobs = rows
        } else {
            serverJobs = []
        }

        if recoverLatest,
           activeResult == nil,
           let first = serverDagRuns.first,
           let id = first.firstString(["run_id", "runId", "id"]),
           !id.isEmpty,
           let latest = try? await api.dagRun(id) {
            activate(latest, id: id, origin: "Restored from Result Vault")
        }
    }

    func validate(project: AuroraProject) {
        guard !isValidating else { return }
        isValidating = true
        lastError = nil
        validationResult = nil
        Task {
            defer { isValidating = false }
            do {
                validationResult = try await api.validate(.object(["payload": project.payload]))
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func loadStoredDagRun(id: String) {
        guard !id.isEmpty, !isLoadingStoredRun else { return }
        isLoadingStoredRun = true
        lastError = nil
        Task {
            defer { isLoadingStoredRun = false }
            do {
                let stored = try await api.dagRun(id)
                activate(stored, id: id, origin: "Result Vault · DAG run")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func loadStoredJob(id: String) {
        guard !id.isEmpty, !isLoadingStoredRun else { return }
        isLoadingStoredRun = true
        lastError = nil
        Task {
            defer { isLoadingStoredRun = false }
            do {
                let stored = try await api.job(id)
                activate(stored, id: id, origin: "Result Vault · engine job")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func run(project: AuroraProject, context: ModelContext, module: String? = nil) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        activeResultOrigin = module == nil ? "Live canonical DAG" : "Live governed engine"
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

    private func activate(_ value: JSONValue, id: String, origin: String) {
        let display = normalized(value)
        activeResult = display
        activeJobID = id
        activeResultOrigin = origin
        runStatus = ResultTools.status(display)
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

        if let result = object["result"],
           object["requested_module"] == nil,
           case .object(let resultObject) = result {
            for (key, child) in resultObject where object[key] == nil {
                object[key] = child
            }
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
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus)
            ])
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
