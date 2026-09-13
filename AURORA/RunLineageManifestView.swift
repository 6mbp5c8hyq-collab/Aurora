import SwiftUI
import SwiftData
import QuickLook

struct RunLineageManifestView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedProjectID: UUID?
    @State private var previewURL: URL?
    @State private var exportRequested = false

    private struct PresenceRow: Identifiable {
        let id: String
        let label: String
        let path: String?
    }

    private struct InputAuthorityCounts {
        var total = 0
        var measured = 0
        var estimated = 0
        var assumed = 0
        var declared = 0
        var unqualified = 0
        var sourceMissing = 0
    }

    private var project: AuroraProject? {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) { return selected }
        return projects.first
    }

    private var active: JSONValue? { app.activeResult }

    private var runReference: String? {
        app.activeJobID
            ?? active?.firstString(["run_id", "runId", "job_id", "jobId", "id"])
    }

    private var persistenceKind: String {
        guard let active else { return "unreported" }
        if active.firstString(["run_id", "runId"]) != nil { return "DAG run reference" }
        if active.firstString(["job_id", "jobId"]) != nil { return "Engine job reference" }
        if active.firstString(["requested_module", "requestedModule", "active_engine"]) != nil { return "Engine-scoped result" }
        return runReference == nil ? "unreported" : "Persisted execution reference"
    }

    private var requestedEngine: String? {
        active?.firstString(["requested_module", "requestedModule", "active_engine"])
    }

    private var executionScope: String {
        if let requestedEngine, !requestedEngine.isEmpty { return "selected_engine" }
        if active != nil { return "canonical_dag_or_loaded_run" }
        return "unreported"
    }

    private var stageCount: Int? {
        guard active != nil else { return nil }
        let rows = ResultTools.stages(active)
        return rows.isEmpty ? nil : rows.count
    }

    private var returnedEngineIDs: [String] {
        guard let active else { return [] }
        return runtimeEngineIDs.filter { id in
            active.recursiveFind(id) != nil
                || active.recursiveFind(id.replacingOccurrences(of: "_", with: "")) != nil
        }
    }

    private var runtimeEngineIDs: [String] {
        if let audit = app.runtimeAudit,
           let engines = audit.recursiveFind("engines"),
           case .object(let object) = engines,
           let declared = object["declared"],
           case .array(let rows) = declared {
            let ids = rows.compactMap { row -> String? in
                if let id = row.stringValue, !id.isEmpty { return id }
                guard case .object(let item) = row else { return nil }
                return item["id"]?.stringValue
                    ?? item["engine"]?.stringValue
                    ?? item["name"]?.stringValue
                    ?? item["key"]?.stringValue
            }
            if !ids.isEmpty { return Array(Set(ids)).sorted() }
        }
        return [
            "ore_intelligence", "resource_model", "comminution", "classification",
            "flotation", "magnetic_gravity", "hydrometallurgy", "thermodynamics",
            "water_circuit", "conservation", "equipment_epc", "economics",
            "tailings", "digital_twin", "hybrid_ai", "diagnostics"
        ]
    }

    private var inputCounts: InputAuthorityCounts? {
        guard let project, case .array(let rows) = project.canonicalAnalyses else { return nil }
        var counts = InputAuthorityCounts()
        for row in rows {
            guard case .object(let object) = row else { continue }
            counts.total += 1
            let status = (object["status"]?.stringValue ?? "UNQUALIFIED").uppercased()
            let source = (object["source"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch status {
            case "MEASURED": counts.measured += 1
            case "ESTIMATED": counts.estimated += 1
            case "ASSUMED": counts.assumed += 1
            case "DECLARED": counts.declared += 1
            default: counts.unqualified += 1
            }
            if source.isEmpty || source == "source_missing" { counts.sourceMissing += 1 }
        }
        return counts
    }

    private var routeUnitCount: Int? {
        guard let project,
              case .object(let flowsheet) = project.canonicalFlowsheet,
              let units = flowsheet["units"], case .array(let rows) = units else { return nil }
        return rows.count
    }

    private var presenceRows: [PresenceRow] {
        guard let active else {
            return [
                PresenceRow(id: "validation", label: "Validation", path: nil),
                PresenceRow(id: "provenance", label: "Provenance / lineage", path: nil),
                PresenceRow(id: "uncertainty", label: "Uncertainty", path: nil),
                PresenceRow(id: "ood", label: "OOD / applicability", path: nil),
                PresenceRow(id: "benchmark", label: "Benchmark", path: nil),
                PresenceRow(id: "balance", label: "Balance / conservation", path: nil),
                PresenceRow(id: "engineering", label: "Engineering artifacts", path: nil)
            ]
        }
        return [
            presence("validation", "Validation", ["validation", "validation_status", "certificate"], active),
            presence("provenance", "Provenance / lineage", ["provenance", "lineage", "evidence"], active),
            presence("uncertainty", "Uncertainty", ["uncertainty", "uq", "confidence_interval", "prediction_interval"], active),
            presence("ood", "OOD / applicability", ["ood", "out_of_domain", "applicability_domain", "applicability"], active),
            presence("benchmark", "Benchmark", ["benchmark", "external_validation", "reference_comparison"], active),
            presence("balance", "Balance / conservation", ["balance", "balances", "conservation", "residual_ledger", "reconciliation"], active),
            presence("engineering", "Engineering artifacts", ["engineering", "artifacts", "deliverables"], active)
        ]
    }

    private var lineageManifest: JSONValue {
        var presenceObject: [String: JSONValue] = [:]
        for row in presenceRows {
            presenceObject[row.id] = .object([
                "present": .bool(row.path != nil),
                "returned_path": row.path.map(JSONValue.string) ?? .null,
                "interpretation": .string("returned_path_presence_only_not_pass_status")
            ])
        }

        let counts = inputCounts
        let projectBasis: JSONValue
        if let project {
            projectBasis = .object([
                "project_id": .string(project.id.uuidString),
                "project_name": .string(project.name),
                "relationship": .string("currently_selected_project_context_not_independent_persisted_run_proof"),
                "feed_tph": .number(project.feedTPH),
                "target_component": .string(project.targetComponent),
                "target_grade": .number(project.targetGrade),
                "runtime_analysis_rows": .number(Double(counts?.total ?? 0)),
                "measured_rows": .number(Double(counts?.measured ?? 0)),
                "estimated_rows": .number(Double(counts?.estimated ?? 0)),
                "assumed_rows": .number(Double(counts?.assumed ?? 0)),
                "declared_rows": .number(Double(counts?.declared ?? 0)),
                "unqualified_rows": .number(Double(counts?.unqualified ?? 0)),
                "source_missing_rows": .number(Double(counts?.sourceMissing ?? 0)),
                "route_unit_count": .number(Double(routeUnitCount ?? 0))
            ])
        } else {
            projectBasis = .object([
                "relationship": .string("project_context_unavailable")
            ])
        }

        return .object([
            "manifest_type": .string("run_lineage_manifest"),
            "authority": .string("execution_identity_and_returned_path_presence_only"),
            "scientific_validation_claim": .string("not_inferred_from_persistence_or_path_presence"),
            "run_reference": runReference.map(JSONValue.string) ?? .null,
            "persistence_kind": .string(persistenceKind),
            "execution_scope": .string(executionScope),
            "requested_engine": requestedEngine.map(JSONValue.string) ?? .null,
            "active_result_origin": .string(app.activeResultOrigin),
            "reported_status": .string(app.runStatus),
            "returned_stage_count": stageCount.map { .number(Double($0)) } ?? .null,
            "returned_engine_count": .number(Double(returnedEngineIDs.count)),
            "returned_engine_ids": .array(returnedEngineIDs.map(JSONValue.string)),
            "returned_path_presence": .object(presenceObject),
            "selected_project_basis": projectBasis
        ])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                projectContext
                executionIdentity
                returnedScope
                evidencePresence
                authorityBoundary
                exportPanel
                rawManifest
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .quickLookPreview($previewURL)
        .onChange(of: app.lastExportURL) { _, value in
            guard exportRequested, let value else { return }
            previewURL = value
        }
        .onAppear {
            if selectedProjectID == nil { selectedProjectID = projects.first?.id }
        }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AuroraTheme.gold.opacity(0.14))
                        .frame(width: 68, height: 68)
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(AuroraTheme.gold)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Run Lineage Manifest").font(.largeTitle.bold())
                    Text("Execution identity · persistence reference · returned-path presence · selected project context")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("This manifest documents what the app can trace about the active execution. It is not a calibration certificate, scientific validation certificate, EPC approval, or proof that every returned resource was consumed by the run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: active == nil ? "No active result" : app.runStatus)
            }
        }
    }

    private var projectContext: some View {
        AuroraCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Selected Project Context").font(.headline)
                    Text("Used only as current export context; it is not silently asserted to be the exact persisted input of a loaded historical run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if projects.isEmpty {
                    StatusBadge(text: "No project context")
                } else {
                    Picker("Project", selection: Binding<UUID?>(
                        get: { selectedProjectID ?? projects.first?.id },
                        set: { selectedProjectID = $0 }
                    )) {
                        ForEach(projects) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                }
            }
        }
    }

    private var executionIdentity: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Execution Identity").font(.headline)
                    Spacer()
                    Text("PRESENCE-BASED").font(.caption2.bold()).foregroundStyle(AuroraTheme.gold)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 9)], spacing: 9) {
                    fact("Run / job reference", runReference ?? "Unreported", "server/device execution reference")
                    fact("Persistence kind", persistenceKind, "derived only from returned run/job identity fields")
                    fact("Execution scope", executionScope, "selected engine only when an engine identifier is returned")
                    fact("Requested engine", requestedEngine ?? "Unreported", "never inferred from source filenames")
                    fact("Reported status", app.runStatus, "runtime/application status text")
                    fact("Result origin", app.activeResultOrigin, "how this app activated the result")
                }
            }
        }
    }

    private var returnedScope: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                Text("Returned Execution Scope").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 9)], spacing: 9) {
                    countTile("Stages returned", stageCount, AuroraTheme.accent)
                    countTile("Engines returned", returnedEngineIDs.isEmpty ? nil : returnedEngineIDs.count, AuroraTheme.accent)
                    countTile("Input rows in selected basis", inputCounts?.total, AuroraTheme.gold)
                    countTile("Source-missing rows", inputCounts?.sourceMissing, (inputCounts?.sourceMissing ?? 0) > 0 ? AuroraTheme.bad : AuroraTheme.good)
                }
                if returnedEngineIDs.isEmpty {
                    Text("No registered engine payload is counted in the active result. No engine execution is inferred from declaration alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(returnedEngineIDs.joined(separator: " · "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var evidencePresence: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Returned Evidence-Path Presence").font(.headline)
                        Text("A check means a matching path exists in the active result; it never means pass/validated by itself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("NO PASS STATUS INFERENCE").font(.caption2.bold()).foregroundStyle(AuroraTheme.warn)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(presenceRows) { row in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: row.path == nil ? "circle.dashed" : "checkmark.circle.fill")
                                .foregroundStyle(row.path == nil ? .secondary : AuroraTheme.good)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label).font(.caption.bold())
                                Text(row.path.map { "returned path: \($0)" } ?? "not returned")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(9)
                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
    }

    private var authorityBoundary: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Lineage Authority Boundary").font(.headline)
                    Spacer()
                    Text("NO QUALITY SCORE").font(.caption2.bold()).foregroundStyle(AuroraTheme.warn)
                }
                rule("Persistence", runReference == nil ? "Unreported" : "Reference returned", "Persistence proves retrievability of a server execution reference, not scientific validation.")
                rule("Scientific validation", "Not inferred", "Validation is reported only through explicit returned validation evidence/status.")
                rule("Input authority", "Selected project context only", "Measured/estimated/declared counts come from the selected project's canonical runtime projection, not from an unrelated historical run.")
                rule("Resource use", "Not inferred", "Platform catalog associations and file presence are not treated as proof that a run consumed a resource.")
                rule("Engineering authority", "Not inferred", "Returned engineering paths/references are not EPC approval, issue-for-construction status, or revision authority.")
            }
        }
    }

    private var exportPanel: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Run Lineage Deliverable").font(.headline)
                        Text("Exports only the lineage manifest and current project-context summary; the scientific result payload is not expanded into this scope.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Lineage scoped")
                }
                HStack(spacing: 9) {
                    exportButton("PDF", "pdf", "doc.richtext.fill")
                    exportButton("EXCEL", "xlsx", "tablecells.fill")
                    exportButton("WORD", "docx", "doc.text.fill")
                    exportButton("CSV", "csv", "list.bullet.rectangle.fill")
                }
                if active == nil || project == nil {
                    Text("A direct lineage export requires an active result and a selected project context. Missing evidence fields remain explicitly unreported.")
                        .font(.caption2)
                        .foregroundStyle(AuroraTheme.warn)
                }
                if exportRequested, let url = app.lastExportURL {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AuroraTheme.good)
                        Text(app.lastExportName ?? url.lastPathComponent)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                        Spacer()
                        Button("Preview") { previewURL = url }.buttonStyle(.bordered)
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var rawManifest: some View {
        AuroraCard {
            DisclosureGroup("Raw lineage manifest JSON") {
                Text(lineageManifest.prettyString())
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func exportButton(_ title: String, _ format: String, _ icon: String) -> some View {
        Button {
            guard let project, active != nil else { return }
            exportRequested = true
            app.exportRunLineageManifest(project: project, manifest: lineageManifest, format: format)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .disabled(project == nil || active == nil || app.isExporting)
    }

    private func presence(_ id: String, _ label: String, _ keys: [String], _ value: JSONValue) -> PresenceRow {
        let matched = keys.first { value.recursiveFind($0) != nil }
        return PresenceRow(id: id, label: label, path: matched)
    }

    private func fact(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold()).lineLimit(2)
            Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func countTile(_ title: String, _ value: Int?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.map(String.init) ?? "—").font(.title3.bold()).foregroundStyle(value == nil ? .secondary : tint)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func rule(_ title: String, _ value: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(AuroraTheme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) · \(value)").font(.caption.bold())
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

extension AppModel {
    func exportRunLineageManifest(project: AuroraProject, manifest: JSONValue, format: String) {
        guard !isExporting else { return }
        guard activeResult != nil else {
            lastError = "No active result is available for a run-lineage export."
            return
        }

        isExporting = true
        lastError = nil
        let api = AURORAAPI()
        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_Run_Lineage_" + project.name),
            "project": project.canonicalProject,
            "designBasis": .object([
                "export_scope": .string("run_lineage_manifest"),
                "authority": .string("execution_identity_and_returned_path_presence_only"),
                "scientific_validation_claim": .string("not_inferred_from_persistence_or_path_presence"),
                "project_context_relationship": .string("currently_selected_project_context")
            ]),
            "analyses": .array([]),
            "flowsheet": .object([:]),
            "diagnostics": .array([]),
            "inputGovernance": project.canonicalInputGovernance,
            "result": .object([
                "run_lineage_manifest": manifest
            ]),
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus),
                "scope": .string("run_lineage_manifest")
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
