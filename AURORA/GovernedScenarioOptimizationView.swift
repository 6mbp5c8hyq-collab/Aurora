import SwiftUI
import SwiftData
import Charts
import QuickLook

struct GovernedScenarioOptimizationView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedProjectID: UUID?
    @State private var scenarioName = "Scenario A"
    @State private var feedTPH: Double = 100
    @State private var targetGrade: Double = 35
    @State private var selectedRunIDs: Set<String> = []
    @State private var comparisons: [GovernedScenarioRun] = []
    @State private var selectedMetricKey: String?
    @State private var isLoadingComparison = false
    @State private var comparisonError: String?
    @State private var previewURL: URL?
    @State private var comparisonExportRequested = false

    private var project: AuroraProject? {
        if let selectedProjectID,
           let project = projects.first(where: { $0.id == selectedProjectID }) { return project }
        return projects.first
    }

    private var comparableMetrics: [GovernedMetricDefinition] {
        var grouped: [String: [KPI]] = [:]
        for run in comparisons {
            for item in run.kpis {
                grouped[GovernedMetricDefinition.key(name: item.name, unit: item.unit), default: []].append(item)
            }
        }
        return grouped.compactMap { key, values in
            guard values.count >= 2, let first = values.first else { return nil }
            return GovernedMetricDefinition(id: key, name: first.name, unit: first.unit, runCount: values.count)
        }.sorted { $0.name < $1.name }
    }

    private var activeMetric: GovernedMetricDefinition? {
        if let selectedMetricKey,
           let metric = comparableMetrics.first(where: { $0.id == selectedMetricKey }) { return metric }
        return comparableMetrics.first
    }

    private var activeMetricPoints: [GovernedScenarioMetricPoint] {
        guard let metric = activeMetric else { return [] }
        return comparisons.compactMap { run in
            guard let kpi = run.kpis.first(where: { GovernedMetricDefinition.key(name: $0.name, unit: $0.unit) == metric.id }) else { return nil }
            return GovernedScenarioMetricPoint(runID: run.id, runLabel: run.shortLabel, metric: metric.name, value: kpi.value, unit: metric.unit)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                scenarioBuilder
                recentRuns
                comparisonSurface
                optimizationAuthority
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .quickLookPreview($previewURL)
        .onAppear { synchronizeScenarioBasis() }
        .onChange(of: selectedProjectID) { _, _ in synchronizeScenarioBasis() }
        .onChange(of: app.lastExportURL) { _, value in
            guard comparisonExportRequested, let value else { return }
            previewURL = value
        }
    }

    private var header: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.16))
                        .frame(width: 68, height: 68)
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2.bold())
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Scenario & Optimization Workspace").font(.largeTitle.bold())
                    Text("Governed variants · like-for-like metrics · explicit feasibility authority")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Scenario runs use the canonical DAG. Comparisons never place different KPI types or unlike units on one numeric axis, and residual values are kept separate from explicit closure status.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.isRunning ? "Scenario running" : "Scenario screening")
            }
        }
    }

    private var scenarioBuilder: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Governed Scenario Builder").font(.headline)
                        Text("Only established project-basis fields are changed at the canonical request boundary.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let project { Text(project.name).font(.caption.bold()).foregroundStyle(AuroraTheme.gold) }
                }

                if projects.isEmpty {
                    ContentUnavailableView("No project available", systemImage: "folder.badge.questionmark", description: Text("Create a project in Input Workflow before defining scenarios."))
                } else {
                    Picker("Base project", selection: Binding<UUID?>(get: { selectedProjectID ?? projects.first?.id }, set: { selectedProjectID = $0 })) {
                        ForEach(projects) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                    Divider().opacity(0.15)
                    HStack(spacing: 12) {
                        scenarioField("Scenario name") { TextField("Scenario A", text: $scenarioName).textFieldStyle(.roundedBorder) }
                        scenarioField("Feed throughput · t/h") {
                            TextField("100", value: $feedTPH, format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        }
                        scenarioField("Target grade · %") {
                            TextField("35", value: $targetGrade, format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        }
                    }
                    if let project {
                        HStack(spacing: 10) {
                            basisChip("Base feed", "\(project.feedTPH.formatted(.number.precision(.fractionLength(0...2)))) t/h")
                            basisChip("Scenario feed", "\(feedTPH.formatted(.number.precision(.fractionLength(0...2)))) t/h")
                            basisChip("Base target", "\(project.targetGrade.formatted(.number.precision(.fractionLength(0...2))))%")
                            basisChip("Scenario target", "\(targetGrade.formatted(.number.precision(.fractionLength(0...2))))%")
                        }
                    }
                    HStack {
                        Label("Execution path: Preflight → canonical DAG → engine fan-out → Result Vault", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            guard let project else { return }
                            app.runScenario(project: project, context: context, name: scenarioName, feedTPH: feedTPH, targetGrade: targetGrade)
                        } label: {
                            if app.isRunning { ProgressView(); Text("Running scenario") }
                            else { Label("RUN SCENARIO", systemImage: "play.fill") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.isRunning || project == nil || feedTPH <= 0)
                    }
                }
            }
        }
    }

    private var recentRuns: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Result Vault · Comparison Set").font(.headline)
                        Text("Select two to four persisted DAG runs. Full result bodies are loaded only when Compare is pressed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await loadComparison() } } label: {
                        if isLoadingComparison { ProgressView(); Text("Loading") }
                        else { Label("COMPARE SELECTED", systemImage: "square.split.2x2") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedRunIDs.count < 2 || selectedRunIDs.count > 4 || isLoadingComparison)
                }

                if app.serverDagRuns.isEmpty {
                    Text("No persisted DAG runs are currently listed by Result Vault.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(app.serverDagRuns.prefix(12).enumerated()), id: \.offset) { _, run in
                        if let id = run.firstString(["run_id", "runId", "id"]), !id.isEmpty {
                            runSelectionRow(run: run, id: id)
                            Divider().opacity(0.12)
                        }
                    }
                }
                if let comparisonError {
                    Label(comparisonError, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(AuroraTheme.warn)
                }
            }
        }
    }

    @ViewBuilder
    private var comparisonSurface: some View {
        if !comparisons.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                comparisonAuthority
                dimensionSafeChart
                comparisonMatrix
                assuranceMatrix
                residualMatrix
                comparisonDeliverables
            }
        }
    }

    private var comparisonAuthority: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "ruler.fill").font(.title2).foregroundStyle(AuroraTheme.good)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dimension-Safe Comparison").font(.headline)
                    Text("The chart below displays exactly one KPI definition at a time. Runs are compared only when both KPI name and declared unit match. Matrix rows may contain different metrics, but each row preserves its own unit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: "\(comparisons.count) governed runs")
            }
        }
    }

    private var dimensionSafeChart: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Like-for-Like KPI Comparison").font(.headline)
                        Text("One metric + one unit per chart")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !comparableMetrics.isEmpty {
                        Picker("Metric", selection: Binding<String>(
                            get: { activeMetric?.id ?? comparableMetrics[0].id },
                            set: { selectedMetricKey = $0 }
                        )) {
                            ForEach(comparableMetrics) { metric in
                                Text(metric.unit.isEmpty ? metric.name : "\(metric.name) · \(metric.unit)").tag(metric.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)
                    }
                }

                if let metric = activeMetric, !activeMetricPoints.isEmpty {
                    Chart(activeMetricPoints) { point in
                        BarMark(
                            x: .value("Run", point.runLabel),
                            y: .value(metric.unit.isEmpty ? metric.name : "\(metric.name) [\(metric.unit)]", point.value)
                        )
                    }
                    .frame(height: 260)
                    Text(metric.unit.isEmpty
                         ? "Metric: \(metric.name). The runtime KPI registry currently provides no explicit unit string for this metric."
                         : "Metric: \(metric.name) · Unit: \(metric.unit). Only matching metric/unit pairs are included.")
                        .font(.caption2).foregroundStyle(metric.unit.isEmpty ? AuroraTheme.warn : .secondary)
                } else {
                    ContentUnavailableView("No like-for-like KPI pair", systemImage: "chart.bar.xaxis", description: Text("The selected runs do not share at least one KPI with the same registered name and unit."))
                        .frame(maxWidth: .infinity, minHeight: 190)
                }
            }
        }
    }

    private var comparisonMatrix: some View {
        let definitions = allMetricDefinitions
        return AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reported KPI Matrix").font(.headline)
                    Spacer()
                    Text("ROW-SCOPED UNITS").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.gold)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                        GridRow {
                            Text("Metric").font(.caption.bold()).frame(width: 155, alignment: .leading)
                            Text("Unit").font(.caption.bold()).frame(width: 85, alignment: .leading)
                            ForEach(comparisons) { run in
                                Text(run.shortLabel).font(.caption.bold()).frame(width: 145, alignment: .trailing)
                            }
                        }
                        Divider()
                        ForEach(definitions) { metric in
                            GridRow {
                                Text(metric.name).font(.caption).foregroundStyle(.secondary)
                                Text(metric.unit.isEmpty ? "unreported" : metric.unit).font(.caption2.monospaced()).foregroundStyle(metric.unit.isEmpty ? AuroraTheme.warn : .secondary)
                                ForEach(comparisons) { run in
                                    Text(kpiValueText(metric, run: run)).font(.caption.monospaced()).frame(width: 145, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var assuranceMatrix: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Assurance & Explicit Closure State").font(.headline)
                    Spacer()
                    Text("NO RESIDUAL→CLOSURE INFERENCE").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 10)], spacing: 10) {
                    ForEach(comparisons) { run in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(run.shortLabel).font(.caption.bold()).lineLimit(1); Spacer(); StatusBadge(text: run.status) }
                            LabeledContent("Claim ceiling", value: run.claimCeiling ?? "not reported")
                            LabeledContent("Closure status", value: run.explicitClosureStatus ?? "not reported")
                            LabeledContent("Stages", value: "\(run.stageCount)")
                            LabeledContent("Validation paths", value: "\(run.validationPathCount)")
                            LabeledContent("Uncertainty paths", value: "\(run.uncertaintyPathCount)")
                            LabeledContent("OOD/applicability", value: "\(run.domainPathCount)")
                        }
                        .font(.caption)
                        .padding(12)
                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 13))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var residualMatrix: some View {
        let any = comparisons.contains { !$0.residuals.isEmpty }
        if any {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Returned Residual Observations").font(.headline)
                    Text("Residual and imbalance values are shown as returned and are not converted into closure status or combined across unlike residual definitions.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(comparisons) { run in
                        if !run.residuals.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(run.shortLabel).font(.subheadline.bold())
                                ForEach(run.residuals.prefix(20)) { residual in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(residual.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                        Spacer(minLength: 10)
                                        Text(residual.value).font(.caption2.monospaced()).textSelection(.enabled)
                                    }
                                }
                            }
                            Divider().opacity(0.1)
                        }
                    }
                }
            }
        }
    }

    private var comparisonDeliverables: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scenario Comparison Deliverables").font(.headline)
                        Text("Exports KPI rows with explicit units, explicit closure status only, residual observations, and screening authority metadata.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Comparison scoped")
                }
                HStack(spacing: 9) {
                    comparisonExportButton("PDF", "pdf", "doc.richtext.fill")
                    comparisonExportButton("EXCEL", "xlsx", "tablecells.fill")
                    comparisonExportButton("WORD", "docx", "doc.text.fill")
                    comparisonExportButton("CSV", "csv", "list.bullet.rectangle.fill")
                }
                if project == nil || comparisons.count < 2 {
                    Text("Export requires a project context and at least two loaded persisted runs.").font(.caption2).foregroundStyle(AuroraTheme.warn)
                }
                if comparisonExportRequested, let url = app.lastExportURL {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AuroraTheme.good)
                        Text(app.lastExportName ?? url.lastPathComponent).font(.caption.monospaced()).lineLimit(1)
                        Spacer()
                        Button("Preview") { previewURL = url }.buttonStyle(.bordered)
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func comparisonExportButton(_ title: String, _ format: String, _ icon: String) -> some View {
        Button {
            guard let project, comparisons.count >= 2 else { return }
            comparisonExportRequested = true
            app.exportScenarioComparison(project: project, comparisons: comparisons, format: format)
        } label: { Label(title, systemImage: icon) }
        .buttonStyle(.bordered)
        .disabled(project == nil || comparisons.count < 2 || app.isExporting)
    }

    private var optimizationAuthority: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(AuroraTheme.gold)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Optimization Authority Boundary").font(.headline)
                    Text("The current mobile contract exposes governed DAG execution and persisted results, but no dedicated optimization endpoint with objective, constraints and feasibility certificate is assumed. This workspace therefore labels parameter variants as scenario screening. It may display an optimization claim only when the runtime result itself returns optimization authority fields.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var allMetricDefinitions: [GovernedMetricDefinition] {
        var map: [String: GovernedMetricDefinition] = [:]
        for run in comparisons {
            for item in run.kpis {
                let id = GovernedMetricDefinition.key(name: item.name, unit: item.unit)
                if map[id] == nil { map[id] = GovernedMetricDefinition(id: id, name: item.name, unit: item.unit, runCount: 1) }
            }
        }
        return map.values.sorted { $0.name < $1.name }
    }

    private func scenarioField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); content() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func basisChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.bold()) }
            .padding(.horizontal, 10).padding(.vertical, 8).background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func runSelectionRow(run: JSONValue, id: String) -> some View {
        let status = ResultTools.status(run)
        let selected = selectedRunIDs.contains(id)
        return HStack(spacing: 10) {
            Button {
                if selected { selectedRunIDs.remove(id) }
                else if selectedRunIDs.count < 4 { selectedRunIDs.insert(id) }
            } label: {
                Image(systemName: selected ? "checkmark.square.fill" : "square").foregroundStyle(selected ? AuroraTheme.accent : .secondary).font(.title3)
            }
            .buttonStyle(.plain)
            StatusBadge(text: status)
            VStack(alignment: .leading, spacing: 2) {
                Text(id).font(.caption.monospaced()).lineLimit(1)
                Text(run.firstString(["current_stage", "active_stage", "stage"]) ?? "Persisted DAG run").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if selected { Text("COMPARE").font(.caption2.bold()).foregroundStyle(AuroraTheme.accent) }
        }
    }

    private func synchronizeScenarioBasis() {
        guard let project else { return }
        feedTPH = project.feedTPH
        targetGrade = project.targetGrade
    }

    private func loadComparison() async {
        isLoadingComparison = true
        comparisonError = nil
        defer { isLoadingComparison = false }
        var loaded: [GovernedScenarioRun] = []
        for id in selectedRunIDs.sorted().prefix(4) {
            do {
                let result = try await app.storedDagRun(id: id)
                loaded.append(GovernedScenarioRun(id: id, result: result))
            } catch {
                comparisonError = "Could not load run \(id.prefix(10)): \(error.localizedDescription)"
            }
        }
        comparisons = loaded
        selectedMetricKey = nil
    }

    private func kpiValueText(_ metric: GovernedMetricDefinition, run: GovernedScenarioRun) -> String {
        guard let item = run.kpis.first(where: { GovernedMetricDefinition.key(name: $0.name, unit: $0.unit) == metric.id }) else { return "—" }
        return item.value.formatted(.number.precision(.fractionLength(0...4)))
    }
}

struct GovernedScenarioRun: Identifiable {
    let id: String
    let label: String
    let status: String
    let claimCeiling: String?
    let explicitClosureStatus: String?
    let stageCount: Int
    let kpis: [KPI]
    let residuals: [GovernedResidual]
    let validationPathCount: Int
    let uncertaintyPathCount: Int
    let domainPathCount: Int

    init(id: String, result: JSONValue) {
        self.id = id
        self.label = Self.scenarioName(result) ?? "Run \(id.prefix(8))"
        self.status = ResultTools.status(result)
        self.claimCeiling = ResultTools.ceiling(result)
        self.explicitClosureStatus = result.firstString(["closure_status", "mass_balance_status", "balance_status", "conservation_status"])
        self.stageCount = ResultTools.stages(result).count
        self.kpis = ResultTools.kpis(result)

        var residuals: [GovernedResidual] = []
        var validation = 0, uncertainty = 0, domain = 0
        for (path, value) in result.flattenedScalars(limit: 10000) {
            let lower = path.lowercased()
            if lower.contains("residual") || lower.contains("imbalance") || lower.contains("closure_error") || lower.contains("balance_error") || lower.contains("mismatch") {
                if residuals.count < 80 { residuals.append(GovernedResidual(path: path, value: value)) }
            }
            if lower.contains("validation") || lower.contains("rmse") || lower.contains("mae") || lower.contains("holdout") { validation += 1 }
            if lower.contains("uncertainty") || lower.contains("confidence_interval") || lower.contains("prediction_interval") || lower.contains("posterior") { uncertainty += 1 }
            if lower.contains("ood") || lower.contains("out_of_domain") || lower.contains("applicability_domain") || lower.contains("extrapolation") { domain += 1 }
        }
        self.residuals = residuals
        self.validationPathCount = validation
        self.uncertaintyPathCount = uncertainty
        self.domainPathCount = domain
    }

    var shortLabel: String { label.count > 18 ? String(label.prefix(18)) + "…" : label }

    private static func scenarioName(_ result: JSONValue) -> String? {
        guard let value = result.recursiveFind("scenario"), case .object(let object) = value else { return nil }
        return object["name"]?.stringValue
    }
}

struct GovernedResidual: Identifiable {
    let id = UUID()
    let path: String
    let value: String
}

private struct GovernedMetricDefinition: Identifiable {
    let id: String
    let name: String
    let unit: String
    let runCount: Int

    static func key(name: String, unit: String) -> String { name.lowercased() + "|" + unit.lowercased() }
}

private struct GovernedScenarioMetricPoint: Identifiable {
    let id = UUID()
    let runID: String
    let runLabel: String
    let metric: String
    let value: Double
    let unit: String
}

extension AppModel {
    func exportScenarioComparison(project: AuroraProject, comparisons: [GovernedScenarioRun], format: String) {
        guard !isExporting, comparisons.count >= 2 else { return }
        isExporting = true
        lastError = nil
        let api = AURORAAPI()

        let runRows = comparisons.map { run in
            JSONValue.object([
                "run_id": .string(run.id),
                "label": .string(run.label),
                "status": .string(run.status),
                "claim_ceiling": run.claimCeiling.map(JSONValue.string) ?? .null,
                "explicit_closure_status": run.explicitClosureStatus.map(JSONValue.string) ?? .null,
                "stage_count": .number(Double(run.stageCount)),
                "validation_path_count": .number(Double(run.validationPathCount)),
                "uncertainty_path_count": .number(Double(run.uncertaintyPathCount)),
                "applicability_ood_path_count": .number(Double(run.domainPathCount)),
                "kpis": .array(run.kpis.map { item in
                    .object([
                        "name": .string(item.name),
                        "value": .number(item.value),
                        "unit": .string(item.unit),
                        "comparison_key": .string(GovernedMetricDefinition.key(name: item.name, unit: item.unit))
                    ])
                }),
                "residual_observations": .array(run.residuals.map { residual in
                    .object(["path": .string(residual.path), "value": .string(residual.value)])
                })
            ])
        }

        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_Scenario_Comparison_" + project.name),
            "project": project.payload,
            "designBasis": .object([
                "export_scope": .string("persisted_scenario_comparison"),
                "authority": .string("returned_persisted_run_values_only"),
                "comparison_rule": .string("like_metric_and_like_unit_only_for_numeric_charting"),
                "closure_rule": .string("explicit_closure_status_only"),
                "residual_rule": .string("reported_separately_not_promoted_to_closure"),
                "optimization_authority": .string("scenario_screening_unless_runtime_explicitly_returns_objective_constraints_and_feasibility"),
                "run_count": .number(Double(comparisons.count))
            ]),
            "analyses": .array([]),
            "flowsheet": .object([:]),
            "diagnostics": .array([]),
            "result": .object(["scenario_runs": .array(runRows)]),
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus),
                "scope": .string("scenario_comparison_workspace")
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
