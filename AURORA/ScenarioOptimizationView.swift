import SwiftUI
import SwiftData
import Charts

struct ScenarioOptimizationView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedProjectID: UUID?
    @State private var scenarioName = "Scenario A"
    @State private var feedTPH: Double = 100
    @State private var targetGrade: Double = 35
    @State private var selectedRunIDs: Set<String> = []
    @State private var comparisons: [ScenarioComparison] = []
    @State private var isLoadingComparison = false
    @State private var comparisonError: String?

    private var project: AuroraProject? {
        if let selectedProjectID,
           let project = projects.first(where: { $0.id == selectedProjectID }) {
            return project
        }
        return projects.first
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
        .onAppear { synchronizeScenarioBasis() }
        .onChange(of: selectedProjectID) { _, _ in synchronizeScenarioBasis() }
    }

    private var header: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.16))
                        .frame(width: 66, height: 66)
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2.bold())
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Scenario & Optimization Workspace")
                        .font(.largeTitle.bold())
                    Text("Governed parameter variants · canonical DAG · Result Vault comparison")
                        .foregroundStyle(.secondary)
                    Text("Run controlled variants through the same AURORA runtime, compare their reported KPIs and closure, and keep optimization claims separated from scenario screening.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.isRunning ? "Scenario running" : "Ready")
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let project {
                        Text(project.name)
                            .font(.caption.bold())
                            .foregroundStyle(AuroraTheme.gold)
                    }
                }

                if projects.isEmpty {
                    ContentUnavailableView(
                        "No project available",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Create a project in Input Workflow before defining scenarios.")
                    )
                } else {
                    Picker(
                        "Base project",
                        selection: Binding<UUID?>(
                            get: { selectedProjectID ?? projects.first?.id },
                            set: { selectedProjectID = $0 }
                        )
                    ) {
                        ForEach(projects) { item in
                            Text(item.name).tag(Optional(item.id))
                        }
                    }

                    Divider().opacity(0.15)

                    HStack(spacing: 12) {
                        scenarioField("Scenario name") {
                            TextField("Scenario A", text: $scenarioName)
                                .textFieldStyle(.roundedBorder)
                        }
                        scenarioField("Feed throughput · t/h") {
                            TextField("100", value: $feedTPH, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        scenarioField("Target grade · %") {
                            TextField("35", value: $targetGrade, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            guard let project else { return }
                            app.runScenario(
                                project: project,
                                context: context,
                                name: scenarioName,
                                feedTPH: feedTPH,
                                targetGrade: targetGrade
                            )
                        } label: {
                            if app.isRunning {
                                ProgressView()
                                Text("Running scenario")
                            } else {
                                Label("RUN SCENARIO", systemImage: "play.fill")
                            }
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
                        Text("Select up to four persisted DAG runs. Full result bodies are loaded only when Compare is pressed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await loadComparison() }
                    } label: {
                        if isLoadingComparison {
                            ProgressView()
                            Text("Loading")
                        } else {
                            Label("COMPARE SELECTED", systemImage: "square.split.2x2")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedRunIDs.count < 2 || selectedRunIDs.count > 4 || isLoadingComparison)
                }

                if app.serverDagRuns.isEmpty {
                    Text("No persisted DAG runs are currently listed by Result Vault.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(app.serverDagRuns.prefix(12).enumerated()), id: \.offset) { _, run in
                        if let id = run.firstString(["run_id", "runId", "id"]), !id.isEmpty {
                            runSelectionRow(run: run, id: id)
                            Divider().opacity(0.12)
                        }
                    }
                }

                if let comparisonError {
                    Label(comparisonError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AuroraTheme.warn)
                }
            }
        }
    }

    @ViewBuilder
    private var comparisonSurface: some View {
        if !comparisons.isEmpty {
            AuroraCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Scenario Comparison").font(.headline)
                        Spacer()
                        Text("\(comparisons.count) governed runs")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    comparisonChart
                    comparisonMatrix
                    assuranceMatrix
                }
            }
        }
    }

    private var comparisonChart: some View {
        let points = comparisons.flatMap { run in
            run.kpis.map { ScenarioKPI(runID: run.id, runLabel: run.label, metric: $0.name, value: $0.value, unit: $0.unit) }
        }
        return Group {
            if points.isEmpty {
                Text("No common numeric KPIs were reported in the selected results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Metric", point.metric),
                        y: .value("Value", point.value)
                    )
                    .position(by: .value("Run", point.runLabel))
                    .foregroundStyle(by: .value("Run", point.runLabel))
                }
                .frame(height: 270)
            }
        }
    }

    private var comparisonMatrix: some View {
        let names = Array(Set(comparisons.flatMap { $0.kpis.map(\.name) })).sorted()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Reported KPI Matrix").font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                    GridRow {
                        Text("Metric").font(.caption.bold()).frame(width: 130, alignment: .leading)
                        ForEach(comparisons) { run in
                            Text(run.shortLabel).font(.caption.bold()).frame(width: 145, alignment: .trailing)
                        }
                    }
                    Divider()
                    ForEach(names, id: \.self) { name in
                        GridRow {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                            ForEach(comparisons) { run in
                                Text(kpiText(name, run: run))
                                    .font(.caption.monospaced())
                                    .frame(width: 145, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var assuranceMatrix: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assurance & Closure").font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                ForEach(comparisons) { run in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(run.shortLabel).font(.caption.bold()).lineLimit(1)
                            Spacer()
                            StatusBadge(text: run.status)
                        }
                        LabeledContent("Claim ceiling", value: run.claimCeiling ?? "not reported")
                        LabeledContent("Closure", value: run.closure ?? "not reported")
                        LabeledContent("Stages", value: "\(run.stageCount)")
                    }
                    .font(.caption)
                    .padding(12)
                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 13))
                }
            }
        }
    }

    private var optimizationAuthority: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(AuroraTheme.gold)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Optimization Authority Boundary").font(.headline)
                    Text("The current mobile API exposes governed DAG execution and the Digital Twin engine, but no dedicated optimizer endpoint was found. Therefore this screen treats parameter sweeps as scenario screening. A result is only labelled optimized when the runtime itself returns an optimization result, objective, constraints and feasibility state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scenarioField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func basisChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func runSelectionRow(run: JSONValue, id: String) -> some View {
        let status = ResultTools.status(run)
        let selected = selectedRunIDs.contains(id)
        return HStack(spacing: 10) {
            Button {
                if selected {
                    selectedRunIDs.remove(id)
                } else if selectedRunIDs.count < 4 {
                    selectedRunIDs.insert(id)
                }
            } label: {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? AuroraTheme.accent : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            StatusBadge(text: status)
            VStack(alignment: .leading, spacing: 2) {
                Text(id).font(.caption.monospaced()).lineLimit(1)
                Text(run.firstString(["current_stage", "active_stage", "stage"]) ?? "Persisted DAG run")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Text("COMPARE")
                    .font(.caption2.bold())
                    .foregroundStyle(AuroraTheme.accent)
            }
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

        var loaded: [ScenarioComparison] = []
        for id in selectedRunIDs.sorted().prefix(4) {
            do {
                let result = try await app.storedDagRun(id: id)
                loaded.append(ScenarioComparison(id: id, result: result))
            } catch {
                comparisonError = "Could not load run \(id.prefix(10)): \(error.localizedDescription)"
            }
        }
        comparisons = loaded
    }

    private func kpiText(_ name: String, run: ScenarioComparison) -> String {
        guard let item = run.kpis.first(where: { $0.name == name }) else { return "—" }
        return "\(item.value.formatted(.number.precision(.fractionLength(0...3)))) \(item.unit)"
    }
}

private struct ScenarioComparison: Identifiable {
    let id: String
    let label: String
    let status: String
    let claimCeiling: String?
    let closure: String?
    let stageCount: Int
    let kpis: [KPI]

    init(id: String, result: JSONValue) {
        self.id = id
        self.label = Self.scenarioName(result) ?? "Run \(id.prefix(8))"
        self.status = ResultTools.status(result)
        self.claimCeiling = ResultTools.ceiling(result)
        self.closure = result.firstString([
            "closure_error_pct",
            "mass_balance_error_pct",
            "balance_residual_pct",
            "max_residual"
        ])
        self.stageCount = ResultTools.stages(result).count
        self.kpis = ResultTools.kpis(result)
    }

    var shortLabel: String {
        label.count > 18 ? String(label.prefix(18)) + "…" : label
    }

    private static func scenarioName(_ result: JSONValue) -> String? {
        guard let value = result.recursiveFind("scenario"),
              case .object(let object) = value else { return nil }
        return object["name"]?.stringValue
    }
}

private struct ScenarioKPI: Identifiable {
    let id = UUID()
    let runID: String
    let runLabel: String
    let metric: String
    let value: Double
    let unit: String
}
