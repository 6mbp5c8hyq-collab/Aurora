import SwiftUI
import SwiftData

struct ExecutionControlView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedProjectID: UUID?
    @State private var executionScope: ExecutionScope = .fullDAG
    @AppStorage("aurora.engine.workspace.selected") private var selectedEngineID = "ore_intelligence"

    private enum ExecutionScope: String, CaseIterable, Identifiable {
        case fullDAG = "Full AURORA DAG"
        case selectedEngine = "Selected Engine"
        var id: String { rawValue }
    }

    private struct EngineChoice: Identifiable, Hashable {
        let id: String
        let title: String
    }

    private struct AuthoritySnapshot {
        var total = 0
        var measured = 0
        var estimated = 0
        var assumed = 0
        var declared = 0
        var unqualified = 0
        var sourceMissing = 0
        var sourceTagged = 0
        var routeUnits = 0
    }

    private var project: AuroraProject? {
        if let selectedProjectID, let selected = projects.first(where: { $0.id == selectedProjectID }) { return selected }
        return projects.first
    }

    private var stages: [EngineStage] {
        ResultTools.stages(app.activeResult)
    }

    private var engineChoices: [EngineChoice] {
        if let audit = app.runtimeAudit,
           let engines = audit.recursiveFind("engines"),
           case .object(let engineObject) = engines,
           let declared = engineObject["declared"],
           case .array(let rows) = declared {
            let parsed = rows.compactMap { row -> EngineChoice? in
                if let id = row.stringValue, !id.isEmpty {
                    return EngineChoice(id: id, title: titleForEngine(id))
                }
                guard case .object(let object) = row else { return nil }
                let id = object["id"]?.stringValue
                    ?? object["engine"]?.stringValue
                    ?? object["name"]?.stringValue
                    ?? object["key"]?.stringValue
                guard let id, !id.isEmpty else { return nil }
                let title = object["title"]?.stringValue
                    ?? object["label"]?.stringValue
                    ?? object["name"]?.stringValue
                    ?? titleForEngine(id)
                return EngineChoice(id: id, title: title)
            }
            if !parsed.isEmpty { return parsed }
        }

        return [
            "ore_intelligence", "resource_model", "comminution", "classification",
            "flotation", "magnetic_gravity", "hydrometallurgy", "thermodynamics",
            "water_circuit", "conservation", "equipment_epc", "economics",
            "tailings", "digital_twin", "hybrid_ai", "diagnostics"
        ].map { EngineChoice(id: $0, title: titleForEngine($0)) }
    }

    private var snapshot: AuthoritySnapshot {
        guard let project else { return AuthoritySnapshot() }
        var value = AuthoritySnapshot()

        if case .array(let rows) = project.canonicalAnalyses {
            value.total = rows.count
            for row in rows {
                guard case .object(let object) = row else { continue }
                let status = (object["status"]?.stringValue ?? "").uppercased()
                let source = (object["source"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                switch status {
                case "MEASURED": value.measured += 1
                case "ESTIMATED": value.estimated += 1
                case "ASSUMED": value.assumed += 1
                case "DECLARED": value.declared += 1
                default: value.unqualified += 1
                }
                if source == "source_missing" || source.isEmpty { value.sourceMissing += 1 }
                else { value.sourceTagged += 1 }
            }
        }

        if case .object(let flowsheet) = project.canonicalFlowsheet,
           let units = flowsheet["units"], case .array(let rows) = units {
            value.routeUnits = rows.count
        }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                projectBasis
                payloadAuthority
                preflight
                executionControls
                liveTrace
                resultSummary
                if let error = app.lastError { errorCard(error) }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .onAppear {
            if selectedProjectID == nil { selectedProjectID = projects.first?.id }
            if !engineChoices.contains(where: { $0.id == selectedEngineID }), let first = engineChoices.first {
                selectedEngineID = first.id
            }
        }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AuroraTheme.accent.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Governed Execution Control").font(.largeTitle.bold())
                    Text("Canonical mobile payload → server validation → governed execution → Result Vault")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("The execution screen reports the authority carried by the current payload. It does not upgrade declared, estimated or unqualified inputs to measured evidence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.runStatus)
            }
        }
    }

    private var projectBasis: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Execution Basis").font(.headline)
                    Spacer()
                    if projects.isEmpty { StatusBadge(text: "No project") }
                    else { StatusBadge(text: "Canonical payload") }
                }

                if projects.isEmpty {
                    ContentUnavailableView(
                        "No project available",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a governed project in Input Workflow before running AURORA.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    Picker(
                        "Project",
                        selection: Binding<UUID?>(
                            get: { selectedProjectID ?? projects.first?.id },
                            set: {
                                selectedProjectID = $0
                                app.validationResult = nil
                                app.lastError = nil
                            }
                        )
                    ) {
                        ForEach(projects) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                    .pickerStyle(.menu)

                    if let project {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                            basisTile("Ore family", project.declaredFamily, "mountain.2.fill")
                            basisTile("Feed", "\(project.feedTPH.formatted()) t/h", "arrow.right.circle.fill")
                            basisTile("Target", project.targetComponent, "scope")
                            basisTile("Target grade", "\(project.targetGrade.formatted())%", "gauge.with.dots.needle.50percent")
                        }
                    }
                }
            }
        }
    }

    private var payloadAuthority: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Payload Authority Snapshot").font(.headline)
                        Text("Counts come from the exact runtime-facing canonical analyses array.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("NO AUTHORITY PROMOTION")
                        .font(.caption2.bold())
                        .foregroundStyle(AuroraTheme.gold)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                    authorityTile("Evidence rows", snapshot.total, AuroraTheme.accent)
                    authorityTile("Measured", snapshot.measured, AuroraTheme.good)
                    authorityTile("Estimated", snapshot.estimated, AuroraTheme.warn)
                    authorityTile("Assumed", snapshot.assumed, AuroraTheme.warn)
                    authorityTile("Declared", snapshot.declared, AuroraTheme.accent)
                    authorityTile("Unqualified", snapshot.unqualified, snapshot.unqualified > 0 ? AuroraTheme.bad : AuroraTheme.good)
                    authorityTile("Source tagged", snapshot.sourceTagged, AuroraTheme.accent)
                    authorityTile("Source missing", snapshot.sourceMissing, snapshot.sourceMissing > 0 ? AuroraTheme.bad : AuroraTheme.good)
                    authorityTile("Route units", snapshot.routeUnits, snapshot.routeUnits > 0 ? AuroraTheme.accent : AuroraTheme.warn)
                }

                Divider().opacity(0.12)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 8)], spacing: 8) {
                    authorityRule("Project object", "project.id / name / oreType / feedTph", "canonical runtime contract")
                    authorityRule("Design basis", "user_declared_design_basis", "not measured evidence")
                    authorityRule("Quick measured rule", "source reference required", "otherwise UNQUALIFIED")
                    authorityRule("Process route", routeAuthorityText, "design intent unless runtime states otherwise")
                }
            }
        }
    }

    private var preflight: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Server Preflight Validation").font(.headline)
                        Text("POST /api/validate against the exact canonical runtime payload; no execution is started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if app.isValidating { ProgressView() }
                    else { StatusBadge(text: validationLabel) }
                }

                HStack(alignment: .center, spacing: 12) {
                    Button {
                        guard let project else { return }
                        app.validate(project: project)
                    } label: {
                        Label("VALIDATE CURRENT PAYLOAD", systemImage: "checkmark.shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(project == nil || app.isValidating || app.isRunning)

                    Text(validationGuidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let validation = app.validationResult {
                    let preferredRows = validationSummaryRows(validation)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                        ForEach(Array(preferredRows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 8) {
                                Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text(row.1).font(.caption2.monospaced()).multilineTextAlignment(.trailing)
                            }
                            .padding(8)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
    }

    private var executionControls: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Execution Scope").font(.headline)
                        Text("Both scopes use server-side validation before execution. A client-side badge is not treated as scientific approval.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: executionScope == .fullDAG ? "Canonical DAG" : "Engine scope")
                }

                Picker("Scope", selection: $executionScope) {
                    ForEach(ExecutionScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if executionScope == .selectedEngine {
                    LabeledContent("Registered execution engine") {
                        Picker("Engine", selection: $selectedEngineID) {
                            ForEach(engineChoices) { engine in
                                Text(engine.title).tag(engine.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(executionScope == .fullDAG ? "Full AURORA DAG" : selectedEngineTitle)
                            .font(.headline)
                        Text(executionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        guard let project else { return }
                        if executionScope == .fullDAG {
                            app.run(project: project, context: context)
                        } else {
                            app.run(project: project, context: context, module: selectedEngineID)
                        }
                    } label: {
                        if app.isRunning {
                            ProgressView()
                            Text("RUNNING AURORA")
                        } else {
                            Label(executionScope == .fullDAG ? "RUN FULL AURORA" : "RUN SELECTED ENGINE", systemImage: "bolt.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(project == nil || app.isRunning || app.isValidating)
                }

                Text("Run is not disabled merely because a manual preflight was not pressed: the API validates again as part of execution. A server rejection remains authoritative and is surfaced as an error.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var liveTrace: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Execution Trace").font(.headline)
                        Text(app.activeResultOrigin).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let id = app.activeJobID {
                        Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                if stages.isEmpty {
                    ContentUnavailableView(
                        "No execution trace loaded",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Run AURORA or load a persisted result from Result Vault.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(stageColor(stage.status).opacity(0.15))
                                    .frame(width: 34, height: 34)
                                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(stageColor(stage.status))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stage.name).font(.subheadline.bold())
                                Text(stage.status).font(.caption).foregroundStyle(stageColor(stage.status))
                                if let detail = stage.detail {
                                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        if index < stages.count - 1 { Divider().opacity(0.12) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSummary: some View {
        if let result = app.activeResult {
            AuroraCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Active Result Summary").font(.headline)
                            Text("KPIs are displayed independently in their returned units; no cross-unit aggregate chart is created here.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(text: ResultTools.status(result))
                    }
                    let kpis = ResultTools.kpis(result)
                    if kpis.isEmpty {
                        Text("No recognized KPI fields were returned in the active result.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                            ForEach(kpis) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.caption).foregroundStyle(.secondary)
                                    Text("\(item.value.formatted(.number.precision(.fractionLength(0...3)))) \(item.unit)")
                                        .font(.title3.bold())
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                            }
                        }
                    }
                }
            }
        }
    }

    private var validationLabel: String {
        guard let validation = app.validationResult else { return "Not validated" }
        if let ok = validation.recursiveFind("ok")?.boolValue {
            if ok { return validation.firstString(["status", "validation_status", "state"]) ?? "Input valid" }
            return validation.firstString(["status", "validation_status", "state"]) ?? "Rejected"
        }
        return validation.firstString(["status", "validation_status", "state"]) ?? "Reported"
    }

    private var validationGuidance: String {
        guard let validation = app.validationResult else {
            return "No manual preflight response is loaded for this project selection."
        }
        if validation.recursiveFind("ok")?.boolValue == true {
            return "The server accepted the current payload contract. This is input admission, not proof that every engine result is scientifically validated."
        }
        return "The server did not report a successful input admission. Review the returned status/error before execution."
    }

    private var executionDescription: String {
        if executionScope == .fullDAG {
            return "Canonical input admission → declared DAG stages → engine fan-out where returned → persisted Result Vault record."
        }
        return "Requests only the selected registered engine through the governed job execution path; returned evidence determines what the workspace may claim."
    }

    private var selectedEngineTitle: String {
        engineChoices.first(where: { $0.id == selectedEngineID })?.title ?? titleForEngine(selectedEngineID)
    }

    private var routeAuthorityText: String {
        guard let project,
              case .object(let object) = project.canonicalFlowsheet else { return "unreported" }
        return object["topology_status"]?.stringValue
            ?? object["authority"]?.stringValue
            ?? "unreported"
    }

    private func validationSummaryRows(_ validation: JSONValue) -> [(String, String)] {
        var rows: [(String, String)] = []
        for key in ["ok", "status", "feed_tph", "unit_count", "input_summary", "error"] {
            if let value = validation.recursiveFind(key)?.stringValue {
                rows.append((key, value))
            }
        }
        if let target = validation.recursiveFind("target") {
            for (path, value) in target.flattenedScalars(limit: 12) {
                rows.append(("target.\(path)", value))
            }
        }
        return rows.isEmpty ? validation.flattenedScalars(limit: 40) : rows
    }

    private func basisTile(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(AuroraTheme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.subheadline.bold()).lineLimit(1)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func authorityTile(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func authorityRule(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold())
            Text(value).font(.caption.monospaced()).foregroundStyle(AuroraTheme.accent)
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stageColor(_ status: String) -> Color {
        let lower = status.lowercased()
        if lower.contains("fail") || lower.contains("error") || lower.contains("blocked") { return AuroraTheme.bad }
        if lower.contains("running") || lower.contains("queue") || lower.contains("pending") { return AuroraTheme.warn }
        if lower.contains("complete") || lower.contains("success") || lower.contains("pass") { return AuroraTheme.good }
        return AuroraTheme.accent
    }

    private func titleForEngine(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func errorCard(_ error: String) -> some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Execution / validation error").font(.headline)
                    Text(error).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
