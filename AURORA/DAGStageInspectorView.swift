import SwiftUI
import SwiftData
import QuickLook

struct DAGStageInspectorView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @Binding var selectedStageID: String
    @State private var selectedProjectID: UUID?
    @State private var query = ""
    @State private var previewURL: URL?
    @State private var stageExportRequested = false

    private var stages: [DAGStageDescriptor] {
        let runtime = runtimeDeclaredStages()
        return runtime.isEmpty ? DAGStageDescriptor.fallback : runtime
    }

    private var selectedStage: DAGStageDescriptor {
        stages.first(where: { $0.id == selectedStageID }) ?? stages.first ?? DAGStageDescriptor.fallback[0]
    }

    private var activeProject: AuroraProject? {
        if let selectedProjectID,
           let project = projects.first(where: { $0.id == selectedProjectID }) {
            return project
        }
        return projects.first
    }

    private var liveStages: [EngineStage] {
        ResultTools.stages(app.activeResult)
    }

    private var selectedLiveStage: EngineStage? {
        matchingLiveStage(for: selectedStage)
    }

    private var selectedStageResult: JSONValue? {
        guard let result = app.activeResult else { return nil }
        return result.recursiveFind(selectedStage.id)
            ?? result.recursiveFind(selectedStage.id.replacingOccurrences(of: "_", with: ""))
    }

    private var stageRows: [DAGStageOutputRow] {
        guard let selectedStageResult else { return [] }
        return selectedStageResult.flattenedScalars(limit: 5000).map {
            DAGStageOutputRow(path: $0.0, value: $0.1)
        }
    }

    private var filteredRows: [DAGStageOutputRow] {
        guard !query.isEmpty else { return stageRows }
        return stageRows.filter {
            $0.path.localizedCaseInsensitiveContains(query)
            || $0.value.localizedCaseInsensitiveContains(query)
        }
    }

    private var returnedEngineIDs: [String] {
        guard let result = app.activeResult else { return [] }
        return runtimeEngineIDs().filter {
            result.recursiveFind($0) != nil
                || result.recursiveFind($0.replacingOccurrences(of: "_", with: "")) != nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                executionControl
                pipelineTrace
                stageHeader
                stageAuthority
                if let selectedStageResult {
                    returnedStageOutput(selectedStageResult)
                    stageDeliverables(selectedStageResult)
                } else {
                    noStagePayload
                }
                if selectedStage.id == "engine_fanout" || selectedStage.title.localizedCaseInsensitiveContains("engine") {
                    engineFanoutCard
                }
                rawRunContext
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .quickLookPreview($previewURL)
        .onChange(of: selectedStageID) { _, _ in
            stageExportRequested = false
            previewURL = nil
        }
        .onChange(of: app.lastExportURL) { _, newValue in
            guard stageExportRequested, let newValue else { return }
            previewURL = newValue
        }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AuroraTheme.gold.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AuroraTheme.gold)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Canonical DAG Observatory").font(.largeTitle.bold())
                    Text("Declared orchestration · live stage trace · returned stage payloads")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("A stage is shown as completed only when the active runtime response or live trace reports completion. Declaration alone is never treated as execution proof.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: app.isRunning ? app.runStatus : ResultTools.status(app.activeResult))
                    Text("\(stages.count) declared stages · \(liveStages.count) live-reported")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var executionControl: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Canonical DAG Execution").font(.headline)
                        Text("Stages are observed within the canonical full DAG. No independent stage-run endpoint is assumed by the iOS client.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let id = app.activeJobID {
                        Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 10) {
                    if projects.isEmpty {
                        StatusBadge(text: "Create project first")
                    } else {
                        Picker(
                            "Project",
                            selection: Binding<UUID?>(
                                get: { selectedProjectID ?? projects.first?.id },
                                set: { selectedProjectID = $0 }
                            )
                        ) {
                            ForEach(projects) { project in
                                Text(project.name).tag(Optional(project.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 280)

                        Button {
                            guard let project = activeProject else { return }
                            app.run(project: project, context: context)
                        } label: {
                            if app.isRunning {
                                ProgressView()
                                Text("DAG RUNNING")
                            } else {
                                Label("RUN CANONICAL DAG", systemImage: "play.circle.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.isRunning || activeProject == nil)
                    }
                    Spacer()
                    StatusBadge(text: app.activeResultOrigin)
                }
            }
        }
    }

    private var pipelineTrace: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DAG Stage Matrix").font(.headline)
                        Text("Select any declared stage to inspect its runtime evidence and returned data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(stages.filter { state(for: $0).kind == .completed }.count) completed evidence")
                        .font(.caption.monospaced())
                        .foregroundStyle(AuroraTheme.good)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 10)], spacing: 10) {
                    ForEach(stages) { stage in
                        let state = state(for: stage)
                        Button {
                            withAnimation(.snappy) { selectedStageID = stage.id }
                        } label: {
                            HStack(spacing: 9) {
                                ZStack {
                                    Circle().fill(state.color.opacity(0.15)).frame(width: 31, height: 31)
                                    Image(systemName: stage.icon).font(.caption.bold()).foregroundStyle(state.color)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stage.title).font(.caption.bold()).lineLimit(1)
                                    Text(state.label).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Circle().fill(state.color).frame(width: 8, height: 8)
                            }
                            .padding(10)
                            .background(
                                selectedStageID == stage.id ? AuroraTheme.gold.opacity(0.12) : AuroraTheme.panel2,
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(selectedStageID == stage.id ? AuroraTheme.gold : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var stageHeader: some View {
        let state = state(for: selectedStage)
        return AuroraCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selectedStage.icon)
                    .font(.title.bold())
                    .foregroundStyle(AuroraTheme.gold)
                    .frame(width: 50, height: 50)
                    .background(AuroraTheme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedStage.title).font(.title2.bold())
                    Text(selectedStage.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Text(selectedStage.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(text: state.label)
                    Text(selectedStage.source.uppercased())
                        .font(.caption2.bold()).tracking(1.0).foregroundStyle(AuroraTheme.accent)
                }
            }
        }
    }

    private var stageAuthority: some View {
        let state = state(for: selectedStage)
        return AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stage Authority").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 8)], spacing: 8) {
                    authorityMetric("Declared", "Yes", "list.bullet.rectangle.fill")
                    authorityMetric("Live trace", selectedLiveStage == nil ? "Not reported" : "Reported", "waveform.path.ecg")
                    authorityMetric("Stage payload", selectedStageResult == nil ? "Not returned" : "Returned", "arrow.down.doc.fill")
                    authorityMetric("State", state.label, "checkmark.shield.fill")
                }
                if let live = selectedLiveStage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(AuroraTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(live.name).font(.caption.bold())
                            Text(live.status).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            if let detail = live.detail, !detail.isEmpty {
                                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }
                Text("Declared means the stage belongs to the runtime orchestration contract; it does not prove that the stage executed in the active run.")
                    .font(.caption2)
                    .foregroundStyle(AuroraTheme.warn)
            }
        }
    }

    private func returnedStageOutput(_ result: JSONValue) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Returned Stage Payload").font(.headline)
                    Spacer()
                    Text("\(filteredRows.count) scalar paths").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search returned stage path or value", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(9)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))

                ForEach(filteredRows.prefix(350)) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        Spacer(minLength: 10)
                        Text(row.value).font(.caption2.monospaced()).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                    Divider().opacity(0.08)
                }
                if filteredRows.count > 350 {
                    Text("Showing the first 350 matching scalar paths. Narrow the search for deeper inspection.")
                        .font(.caption2).foregroundStyle(AuroraTheme.warn)
                }
                DisclosureGroup("Raw returned stage JSON") {
                    Text(result.prettyString())
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func stageDeliverables(_ result: JSONValue) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Stage Deliverables").font(.headline)
                        Text("Exports contain only the returned payload for this selected DAG stage and are explicitly marked stage-scoped.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Payload verified")
                }

                HStack(spacing: 9) {
                    stageExportButton("STAGE PDF", "pdf", "doc.richtext.fill", result)
                    stageExportButton("STAGE EXCEL", "xlsx", "tablecells.fill", result)
                    stageExportButton("STAGE WORD", "docx", "doc.text.fill", result)
                    stageExportButton("STAGE CSV", "csv", "list.bullet.rectangle.fill", result)
                }

                Text("Export is unavailable when the selected stage is only declared/live-reported without an independently returned stage payload.")
                    .font(.caption2)
                    .foregroundStyle(AuroraTheme.warn)

                if stageExportRequested, let url = app.lastExportURL {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AuroraTheme.good)
                        Text(app.lastExportName ?? url.lastPathComponent).font(.caption.monospaced()).lineLimit(1)
                        Spacer()
                        Button("Preview") { previewURL = url }.buttonStyle(.bordered)
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func stageExportButton(_ title: String, _ format: String, _ icon: String, _ result: JSONValue) -> some View {
        Button {
            guard let project = activeProject else { return }
            stageExportRequested = true
            app.exportStage(
                project: project,
                stageID: selectedStage.id,
                stageTitle: selectedStage.title,
                stageResult: result,
                format: format
            )
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .disabled(activeProject == nil || app.isExporting)
    }

    private var noStagePayload: some View {
        AuroraCard {
            ContentUnavailableView(
                "No stage-specific payload returned",
                systemImage: selectedStage.icon,
                description: Text(selectedLiveStage == nil
                    ? "The stage is declared in the orchestration contract, but the active result does not currently expose a matching stage payload or live trace entry."
                    : "A live trace entry exists for this stage, but no independent stage payload was exposed in the active result.")
            )
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private var engineFanoutCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Engine Fan-out Evidence").font(.headline)
                    Spacer()
                    Text("\(returnedEngineIDs.count) engine payloads returned")
                        .font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                }
                Text("These engine IDs are counted only when the active result contains a matching governed engine payload.")
                    .font(.caption).foregroundStyle(.secondary)
                if returnedEngineIDs.isEmpty {
                    Text("No engine-specific payloads are visible in the active result.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                        ForEach(returnedEngineIDs, id: \.self) { engine in
                            HStack {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(AuroraTheme.good)
                                Text(pretty(engine)).font(.caption.bold()).lineLimit(1)
                                Spacer()
                            }
                            .padding(9)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private var rawRunContext: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Active Run Context").font(.headline)
                    Spacer()
                    StatusBadge(text: app.activeResultOrigin)
                }
                HStack(spacing: 18) {
                    contextField("Run status", app.runStatus)
                    contextField("Job / run ID", app.activeJobID ?? "—")
                    contextField("Reported stages", "\(liveStages.count)")
                    contextField("Returned engines", "\(returnedEngineIDs.count)")
                }
                if let activeResult = app.activeResult {
                    DisclosureGroup("Open complete active run response") {
                        Text(activeResult.prettyString())
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func authorityMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
            Text(value).font(.subheadline.bold()).lineLimit(2)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func contextField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func state(for stage: DAGStageDescriptor) -> DAGStageState {
        if let result = app.activeResult?.recursiveFind(stage.id)
            ?? app.activeResult?.recursiveFind(stage.id.replacingOccurrences(of: "_", with: "")) {
            let status = ResultTools.status(result)
            return classify(status == "No result" ? "Returned" : status, defaultKind: .completed)
        }
        if let live = matchingLiveStage(for: stage) {
            return classify(live.status, defaultKind: .reported)
        }
        if app.isRunning && app.activeResultOrigin.localizedCaseInsensitiveContains("dag") {
            return .init(kind: .pending, label: "Pending / not returned")
        }
        return .init(kind: .declared, label: "Declared / not returned")
    }

    private func classify(_ status: String, defaultKind: DAGStageState.Kind) -> DAGStageState {
        let lower = status.lowercased()
        if lower.contains("fail") || lower.contains("error") || lower.contains("block") || lower.contains("reject") {
            return .init(kind: .blocked, label: status)
        }
        if lower.contains("run") || lower.contains("progress") || lower.contains("queue") || lower.contains("start") {
            return .init(kind: .running, label: status)
        }
        if lower.contains("complete") || lower.contains("success") || lower.contains("pass") || lower.contains("done") || lower.contains("ready") || lower == "returned" {
            return .init(kind: .completed, label: status)
        }
        return .init(kind: defaultKind, label: status)
    }

    private func matchingLiveStage(for stage: DAGStageDescriptor) -> EngineStage? {
        let stageID = normalized(stage.id)
        let title = normalized(stage.title)
        return liveStages.first { live in
            let liveName = normalized(live.name)
            if liveName == stageID || liveName == title || liveName.contains(stageID) || stageID.contains(liveName) {
                return true
            }
            let tokens = stage.id.split(separator: "_").map(String.init).filter { $0.count > 3 }
            return !tokens.isEmpty && tokens.allSatisfy { liveName.contains($0.lowercased()) }
        }
    }

    private func runtimeDeclaredStages() -> [DAGStageDescriptor] {
        guard let audit = app.runtimeAudit,
              let dagValue = audit.recursiveFind("dag"),
              case .object(let dagObject) = dagValue,
              let declaredValue = dagObject["declared"],
              case .array(let declared) = declaredValue else { return [] }

        return declared.compactMap { row in
            switch row {
            case .string(let id):
                return DAGStageDescriptor.make(id: id, title: pretty(id), source: "runtime contract")
            case .object(let object):
                let id = object["id"]?.stringValue
                    ?? object["stage"]?.stringValue
                    ?? object["name"]?.stringValue
                    ?? object["key"]?.stringValue
                guard let id, !id.isEmpty else { return nil }
                let title = object["label"]?.stringValue
                    ?? object["title"]?.stringValue
                    ?? object["name"]?.stringValue
                    ?? pretty(id)
                let summary = object["description"]?.stringValue
                    ?? object["summary"]?.stringValue
                    ?? DAGStageDescriptor.summary(for: id)
                return .init(id: id, title: title, summary: summary, icon: DAGStageDescriptor.icon(for: id), source: "runtime contract")
            default:
                return nil
            }
        }
    }

    private func runtimeEngineIDs() -> [String] {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let object) = enginesValue,
              let declaredValue = object["declared"],
              case .array(let rows) = declaredValue else { return DAGStageDescriptor.engineFallback }
        let ids = rows.compactMap { row -> String? in
            if case .object(let object) = row { return object["id"]?.stringValue }
            return row.stringValue
        }
        return ids.isEmpty ? DAGStageDescriptor.engineFallback : ids
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct DAGStageDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let icon: String
    let source: String

    static let fallback: [DAGStageDescriptor] = [
        make(id: "input_admission", title: "Input Admission", source: "native fallback"),
        make(id: "ore_diagnosis", title: "Ore Diagnosis", source: "native fallback"),
        make(id: "process_graph", title: "Process Graph", source: "native fallback"),
        make(id: "engine_fanout", title: "Engine Fan-out", source: "native fallback"),
        make(id: "result_vault", title: "Result Vault", source: "native fallback")
    ]

    static let engineFallback = [
        "ore_intelligence", "resource_model", "comminution", "classification", "flotation",
        "magnetic_gravity", "hydrometallurgy", "thermodynamics", "water_circuit", "conservation",
        "equipment_epc", "economics", "tailings", "digital_twin", "hybrid_ai", "diagnostics"
    ]

    static func make(id: String, title: String, source: String) -> DAGStageDescriptor {
        .init(id: id, title: title, summary: summary(for: id), icon: icon(for: id), source: source)
    }

    static func icon(for id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("input") || lower.contains("admission") { return "tray.and.arrow.down.fill" }
        if lower.contains("ore") || lower.contains("diagnos") { return "cube.transparent" }
        if lower.contains("graph") || lower.contains("flow") { return "point.3.connected.trianglepath.dotted" }
        if lower.contains("engine") || lower.contains("fan") { return "square.stack.3d.up.fill" }
        if lower.contains("vault") || lower.contains("persist") || lower.contains("result") { return "externaldrive.fill.badge.checkmark" }
        if lower.contains("valid") || lower.contains("gate") { return "checkmark.shield.fill" }
        return "circle.hexagongrid.fill"
    }

    static func summary(for id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("input") || lower.contains("admission") { return "Admit and validate the project payload and evidence basis before execution." }
        if lower.contains("ore") || lower.contains("diagnos") { return "Establish ore diagnosis and material evidence required by downstream engines." }
        if lower.contains("graph") || lower.contains("flow") { return "Construct or resolve the governed process topology and execution graph." }
        if lower.contains("engine") || lower.contains("fan") { return "Dispatch governed scientific and engineering engine domains and collect their returned payloads." }
        if lower.contains("vault") || lower.contains("persist") || lower.contains("result") { return "Persist the governed run result and execution trace to the Result Vault." }
        return "Runtime-declared canonical AURORA orchestration stage."
    }
}

private struct DAGStageState {
    enum Kind { case completed, running, pending, blocked, reported, declared }
    let kind: Kind
    let label: String

    var color: Color {
        switch kind {
        case .completed: return AuroraTheme.good
        case .running: return AuroraTheme.accent
        case .pending: return AuroraTheme.gold
        case .blocked: return AuroraTheme.bad
        case .reported: return AuroraTheme.accent
        case .declared: return .secondary
        }
    }
}

private struct DAGStageOutputRow: Identifiable {
    let id = UUID()
    let path: String
    let value: String
}

extension AppModel {
    func exportStage(project: AuroraProject, stageID: String, stageTitle: String, stageResult: JSONValue, format: String) {
        guard !isExporting else { return }
        isExporting = true
        lastError = nil

        let api = AURORAAPI()
        let safeStage = stageID.replacingOccurrences(of: " ", with: "_")
        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_DAG_" + safeStage + "_" + project.name),
            "project": project.payload,
            "designBasis": .object([
                "stage_id": .string(stageID),
                "stage_title": .string(stageTitle),
                "export_scope": .string("single_returned_dag_stage"),
                "authority": .string("returned_stage_payload_only")
            ]),
            "analyses": .array([]),
            "flowsheet": .object([:]),
            "diagnostics": .array([]),
            "result": .object([
                "stage_id": .string(stageID),
                "stage_title": .string(stageTitle),
                "stage_scope": .string("returned_payload"),
                stageID: stageResult
            ]),
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus),
                "scope": .string("dag_stage_deliverable")
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
