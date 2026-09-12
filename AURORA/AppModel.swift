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
                activate(stored, id: id, origin: ScenarioMetadataStore.metadata(for: id) == nil ? "Result Vault · DAG run" : "Result Vault · scenario DAG")
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

    func storedDagRun(id: String) async throws -> JSONValue {
        enriched(normalized(try await api.dagRun(id)), runID: id)
    }

    func run(project: AuroraProject, context: ModelContext, module: String? = nil) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        ScenarioMetadataStore.clearPending()
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

                let display = enriched(normalized(final), runID: activeJobID)
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

    func runScenario(
        project: AuroraProject,
        context: ModelContext,
        name: String,
        feedTPH: Double,
        targetGrade: Double
    ) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scenario" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        activeResultOrigin = "Scenario · \(cleanName)"
        runStatus = "Starting scenario DAG"

        ScenarioMetadataStore.setPending(.init(
            name: cleanName,
            projectID: project.id.uuidString,
            projectName: project.name,
            feedTPH: max(feedTPH, 0),
            targetGrade: max(targetGrade, 0),
            createdAt: .now
        ))

        let record = RunRecord(projectID: project.id)
        context.insert(record)
        try? context.save()

        let payload = scenarioPayload(
            for: project,
            name: cleanName,
            feedTPH: feedTPH,
            targetGrade: targetGrade
        )

        Task {
            do {
                let final = try await api.runProject(payload) { [weak self] update in
                    await MainActor.run {
                        self?.apply(update: update, to: record, context: context)
                    }
                }
                let display = enriched(normalized(final), runID: activeJobID)
                activeResult = display
                runStatus = ResultTools.status(display)
                record.status = runStatus
                record.rawResultJSON = display.prettyString()
                record.updatedAt = .now
                try? context.save()
                await refreshServerState()
            } catch {
                ScenarioMetadataStore.clearPending()
                lastError = error.localizedDescription
                runStatus = "Scenario execution error"
                record.status = "error"
                record.errorText = error.localizedDescription
                record.updatedAt = .now
                try? context.save()
            }
            isRunning = false
        }
    }

    private func scenarioPayload(
        for project: AuroraProject,
        name: String,
        feedTPH: Double,
        targetGrade: Double
    ) -> JSONValue {
        guard case .object(var fields) = project.payload else { return project.payload }
        fields["feed_tph"] = .number(max(feedTPH, 0))
        fields["target_grade"] = .number(max(targetGrade, 0))
        fields["scenario"] = .object([
            "name": .string(name),
            "base_project_id": .string(project.id.uuidString),
            "basis": .string("governed_parameter_variant"),
            "feed_tph": .number(max(feedTPH, 0)),
            "target_grade": .number(max(targetGrade, 0))
        ])
        return .object(fields)
    }

    private func activate(_ value: JSONValue, id: String, origin: String) {
        let display = enriched(normalized(value), runID: id)
        activeResult = display
        activeJobID = id
        activeResultOrigin = origin
        runStatus = ResultTools.status(display)
    }

    private func apply(update: JSONValue, to record: RunRecord, context: ModelContext) {
        let id = update.firstString(["run_id", "runId", "job_id", "jobId", "id"])
        if let id, !id.isEmpty {
            activeJobID = id
            record.jobID = id
            ScenarioMetadataStore.bindPending(to: id)
        }
        let display = enriched(normalized(update), runID: id ?? activeJobID)
        activeResult = display
        runStatus = ResultTools.status(display)
        record.status = runStatus
        record.updatedAt = .now
        record.rawResultJSON = display.prettyString()
        try? context.save()
    }

    private func enriched(_ value: JSONValue, runID: String?) -> JSONValue {
        guard let runID,
              let metadata = ScenarioMetadataStore.metadata(for: runID),
              case .object(var object) = value else { return value }

        if object["scenario"] == nil {
            object["scenario"] = .object([
                "name": .string(metadata.name),
                "base_project_id": .string(metadata.projectID),
                "project_name": .string(metadata.projectName),
                "basis": .string("device_persisted_scenario_metadata"),
                "feed_tph": .number(metadata.feedTPH),
                "target_grade": .number(metadata.targetGrade),
                "created_at": .string(metadata.createdAt.ISO8601Format())
            ])
        }
        return .object(object)
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