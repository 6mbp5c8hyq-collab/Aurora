import SwiftUI
import SwiftData
import Charts

struct EngineWorkspaceNavigatorView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @Binding var selectedEngineID: String
    @State private var selectedProjectID: UUID?
    @State private var resources: [EngineLinkedResource] = []
    @State private var resourceSummary: JSONValue?
    @State private var resourcesLoading = false
    @State private var resourceError: String?
    @State private var outputQuery = ""

    private let resourceAPI = EngineResourceAPI()

    private var engines: [EngineNavigatorDefinition] {
        let runtime = runtimeDeclaredEngines()
        return runtime.isEmpty ? EngineNavigatorDefinition.fallback : runtime
    }

    private var selectedEngine: EngineNavigatorDefinition {
        engines.first(where: { $0.id == selectedEngineID }) ?? engines.first ?? EngineNavigatorDefinition.fallback[0]
    }

    private var activeProject: AuroraProject? {
        if let selectedProjectID,
           let project = projects.first(where: { $0.id == selectedProjectID }) {
            return project
        }
        return projects.first
    }

    private var selectedResult: JSONValue? {
        engineResult(for: selectedEngine.id)
    }

    private var outputRows: [EngineNavigatorOutputRow] {
        guard let selectedResult else { return [] }
        return selectedResult.flattenedScalars(limit: 7000).map {
            EngineNavigatorOutputRow(path: $0.0, value: $0.1)
        }
    }

    private var filteredOutputRows: [EngineNavigatorOutputRow] {
        guard !outputQuery.isEmpty else { return outputRows }
        return outputRows.filter {
            $0.path.localizedCaseInsensitiveContains(outputQuery)
            || $0.value.localizedCaseInsensitiveContains(outputQuery)
        }
    }

    private var performanceRows: [EngineNavigatorOutputRow] {
        outputRows.filter {
            guard $0.numeric != nil else { return false }
            let path = $0.path.lowercased()
            return path.contains("recovery") || path.contains("grade") || path.contains("yield")
                || path.contains("efficien") || path.contains("extraction") || path.contains("mass_pull")
                || path.contains("throughput") || path.contains("power") || path.contains("p80")
        }.prefix(14).map { $0 }
    }

    private var warningRows: [EngineNavigatorOutputRow] {
        outputRows.filter {
            let path = $0.path.lowercased()
            let value = $0.value.lowercased()
            return path.contains("warning") || path.contains("error") || path.contains("risk")
                || path.contains("blocked") || path.contains("limitation") || path.contains("gate")
                || value.contains("warning") || value.contains("failed") || value.contains("blocked")
        }.prefix(40).map { $0 }
    }

    private var uncertaintyRows: [EngineNavigatorOutputRow] {
        outputRows.filter {
            let path = $0.path.lowercased()
            return path.contains("uncert") || path.contains("confidence") || path.contains("interval")
                || path.contains("ood") || path.contains("applicability") || path.contains("calibration")
                || path.contains("rmse") || path.contains("mae") || path.contains("coverage")
        }.prefix(40).map { $0 }
    }

    private var evidenceRows: [EngineNavigatorOutputRow] {
        outputRows.filter {
            let path = $0.path.lowercased()
            return path.contains("evidence") || path.contains("lineage") || path.contains("source")
                || path.contains("validation") || path.contains("benchmark") || path.contains("measured")
                || path.contains("authority") || path.contains("dataset")
        }.prefix(40).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                executionConsole
                liveExecutionMatrix
                selectedWorkspaceHeader
                linkedResources
                if let selectedResult {
                    resultSummary(selectedResult)
                    performanceChart
                    diagnosticsAndAuthority
                    outputExplorer
                    exportStrip
                } else {
                    emptyResult
                }
                if let error = app.lastError { runtimeError(error) }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .task(id: selectedEngineID) {
            await loadResources()
        }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.16))
                        .frame(width: 72, height: 72)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("AURORA Engine Control Matrix").font(.largeTitle.bold())
                    Text("Direct engine navigation · live DAG state · scientific resources · governed outputs")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("The matrix distinguishes returned, running, pending, blocked/error and not-returned states. The client does not mark an engine complete unless the runtime returned engine or stage evidence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: app.isRunning ? app.runStatus : ResultTools.status(app.activeResult))
                    Text("\(engines.count) governed engine domains")
                        .font(.caption.monospaced())
                        .foregroundStyle(AuroraTheme.gold)
                }
            }
        }
    }

    private var executionConsole: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Execution Control").font(.headline)
                        Text("Execute the selected engine independently or launch the canonical full DAG.")
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
                            app.run(project: project, context: context, module: selectedEngine.id)
                        } label: {
                            if app.isRunning {
                                ProgressView()
                                Text("RUNNING")
                            } else {
                                Label("RUN \(selectedEngine.shortTitle.uppercased())", systemImage: "bolt.horizontal.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.isRunning || activeProject == nil)

                        Button {
                            guard let project = activeProject else { return }
                            app.run(project: project, context: context)
                        } label: {
                            Label("RUN FULL DAG", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                        .buttonStyle(.bordered)
                        .disabled(app.isRunning || activeProject == nil)
                    }
                    Spacer()
                    StatusBadge(text: app.isRunning ? app.activeResultOrigin : "Execution idle")
                }
            }
        }
    }

    private var liveExecutionMatrix: some View {
        let states = engines.map { ($0, executionState(for: $0)) }
        let returned = states.filter { $0.1.kind == .returned }.count
        let running = states.filter { $0.1.kind == .running }.count
        let pending = states.filter { $0.1.kind == .pending }.count
        let blocked = states.filter { $0.1.kind == .blocked }.count

        return AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Engine Execution Matrix").font(.headline)
                        Text("State is inferred only from runtime engine payloads, engine-specific stage traces and current execution mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 7) {
                        matrixCount("Returned", returned)
                        matrixCount("Running", running)
                        matrixCount("Pending", pending)
                        matrixCount("Blocked", blocked)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                    ForEach(states, id: \.0.id) { engine, state in
                        Button {
                            withAnimation(.snappy) { selectedEngineID = engine.id }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: engine.icon)
                                    .foregroundStyle(state.color)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(engine.title).font(.caption.bold()).lineLimit(1)
                                    Text(state.label).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Circle().fill(state.color).frame(width: 8, height: 8)
                            }
                            .padding(10)
                            .background(
                                selectedEngineID == engine.id ? AuroraTheme.accent.opacity(0.13) : AuroraTheme.panel2,
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(selectedEngineID == engine.id ? AuroraTheme.accent : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var selectedWorkspaceHeader: some View {
        let state = executionState(for: selectedEngine)
        return AuroraCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selectedEngine.icon)
                    .font(.title.bold())
                    .foregroundStyle(AuroraTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(AuroraTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedEngine.title).font(.title2.bold())
                    Text(selectedEngine.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Text(selectedEngine.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: state.label)
                    Text(selectedEngine.group.uppercased())
                        .font(.caption2.bold()).tracking(1.1).foregroundStyle(AuroraTheme.gold)
                }
            }
        }
    }

    private var linkedResources: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Linked Scientific Resources").font(.headline)
                        Text("Packaged runtime assets associated with \(selectedEngine.title) by the production Platform Catalog.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if resourcesLoading {
                        ProgressView()
                    } else {
                        Text("\(resources.count) loaded")
                            .font(.caption.monospaced())
                            .foregroundStyle(AuroraTheme.gold)
                    }
                }

                if let resourceSummary {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        resourceMetric("Engine assets", scalar(resourceSummary, "count"), "externaldrive.fill")
                        resourceMetric("Platform assets", scalar(resourceSummary, "asset_count"), "server.rack")
                        resourceMetric("Readable", scalar(resourceSummary, "readable_asset_count"), "checkmark.seal.fill")
                        resourceMetric("Direct", scalar(resourceSummary, "direct_asset_count"), "doc.fill")
                        resourceMetric("Archive", scalar(resourceSummary, "archive_asset_count"), "archivebox.fill")
                    }
                }

                if let resourceError {
                    Text(resourceError).font(.caption.monospaced()).foregroundStyle(AuroraTheme.bad)
                } else if resources.isEmpty && !resourcesLoading {
                    Text("No runtime resource association was returned for this engine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let categories = Dictionary(grouping: resources, by: \.category)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories.keys.sorted(), id: \.self) { category in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pretty(category)).font(.caption2.bold())
                                    Text("\(categories[category]?.count ?? 0) assets")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(9)
                                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    ForEach(resources.prefix(12)) { resource in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: resource.icon)
                                .foregroundStyle(resource.readable ? AuroraTheme.good : AuroraTheme.warn)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(resource.name).font(.caption.bold()).lineLimit(2)
                                Text(resource.path).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                                Text("\(pretty(resource.category)) · \(resource.format.uppercased()) · \(resource.validation)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(text: resource.readable ? "Readable" : "Unverified")
                        }
                        .padding(.vertical, 4)
                        Divider().opacity(0.08)
                    }
                    if resources.count > 12 {
                        Text("\(resources.count - 12) additional linked resources remain available in Data & Model Catalog.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Resource association is inventory/semantic linkage; it is not proof that every listed asset was consumed by this specific run.")
                    .font(.caption2)
                    .foregroundStyle(AuroraTheme.warn)
            }
        }
    }

    private func resultSummary(_ result: JSONValue) -> some View {
        let kpis = ResultTools.kpis(result)
        let numeric = outputRows.filter { $0.numeric != nil }
        return AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Returned Engine Results").font(.headline)
                    Spacer()
                    Text("\(outputRows.count) scalar paths · \(numeric.count) numeric")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if !kpis.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                        ForEach(kpis) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.caption).foregroundStyle(.secondary)
                                Text("\(item.value.formatted(.number.precision(.fractionLength(0...4)))) \(item.unit)")
                                    .font(.title3.bold())
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 9)], spacing: 9) {
                        ForEach(numeric.prefix(8)) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(row.value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.65)
                                Text(row.path).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
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

    @ViewBuilder
    private var performanceChart: some View {
        if !performanceRows.isEmpty {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Returned Performance Signals").font(.headline)
                        Spacer()
                        Text("NO CLIENT NORMALIZATION").font(.caption2.bold()).foregroundStyle(AuroraTheme.warn)
                    }
                    Chart(performanceRows) { row in
                        if let numeric = row.numeric {
                            BarMark(x: .value("Metric", row.shortLabel), y: .value("Value", numeric))
                                .annotation(position: .top) {
                                    Text(numeric.formatted(.number.precision(.fractionLength(0...2))))
                                        .font(.system(size: 8, design: .monospaced))
                                }
                        }
                    }
                    .frame(height: 260)
                }
            }
        }
    }

    private var diagnosticsAndAuthority: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
            outputGroup("Warnings / Gates / Risks", rows: warningRows, icon: "exclamationmark.triangle.fill")
            outputGroup("Uncertainty / Applicability", rows: uncertaintyRows, icon: "waveform.path.ecg")
            outputGroup("Evidence / Validation / Lineage", rows: evidenceRows, icon: "checkmark.shield.fill")
        }
    }

    private var outputExplorer: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Engine Output Explorer").font(.headline)
                    Spacer()
                    Text("\(filteredOutputRows.count) visible").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search path or returned value", text: $outputQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(9)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))

                ForEach(filteredOutputRows.prefix(300)) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        Spacer(minLength: 10)
                        Text(row.value).font(.caption2.monospaced()).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                    Divider().opacity(0.08)
                }
                if filteredOutputRows.count > 300 {
                    Text("Showing first 300 matching paths. Narrow the search to inspect the remainder.")
                        .font(.caption2).foregroundStyle(AuroraTheme.warn)
                }
                DisclosureGroup("Raw governed engine response") {
                    Text(selectedResult?.prettyString() ?? "{}")
                        .font(.caption2.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var exportStrip: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Selected Engine Deliverables").font(.headline)
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Ready")
                }
                HStack(spacing: 9) {
                    exportButton("PDF", "pdf", "doc.richtext.fill")
                    exportButton("Excel", "xlsx", "tablecells.fill")
                    exportButton("Word", "docx", "doc.text.fill")
                    exportButton("CSV", "csv", "list.bullet.rectangle.fill")
                    Spacer()
                    if let url = app.lastExportURL {
                        ShareLink(item: url) { Label(app.lastExportName ?? "Share export", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var emptyResult: some View {
        AuroraCard {
            ContentUnavailableView(
                "No governed result returned for \(selectedEngine.title)",
                systemImage: selectedEngine.icon,
                description: Text("Run this engine, execute the full DAG, or restore a compatible result from Result Vault. Linked runtime resources remain inspectable above without fabricating process results.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private func outputGroup(_ title: String, rows: [EngineNavigatorOutputRow], icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                    Text(title).font(.subheadline.bold())
                    Spacer()
                    Text("\(rows.count)").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                }
                if rows.isEmpty {
                    Text("No explicit returned paths in this category.").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(rows.prefix(12)) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.path).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                            Text(row.value).font(.caption2).lineLimit(3)
                        }
                        Divider().opacity(0.08)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        }
    }

    private func matrixCount(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(.caption.bold())
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 8))
    }

    private func resourceMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
            Text(value).font(.subheadline.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func exportButton(_ title: String, _ format: String, _ icon: String) -> some View {
        Button {
            guard let project = activeProject else { return }
            app.exportEngine(project: project, engineID: selectedEngine.id, engineTitle: selectedEngine.title, format: format)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .disabled(selectedResult == nil || activeProject == nil || app.isExporting)
    }

    private func runtimeError(_ text: String) -> some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtime / engine error").font(.headline)
                    Text(text).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func engineResult(for id: String) -> JSONValue? {
        guard let result = app.activeResult else { return nil }
        return result.recursiveFind(id)
            ?? result.recursiveFind(id.replacingOccurrences(of: "_", with: ""))
    }

    private func executionState(for engine: EngineNavigatorDefinition) -> EngineNavigatorExecutionState {
        if let result = engineResult(for: engine.id) {
            let raw = ResultTools.status(result)
            let status = raw == "No result" ? "Returned" : raw
            let lower = status.lowercased()
            if lower.contains("fail") || lower.contains("error") || lower.contains("block") || lower.contains("reject") {
                return .init(kind: .blocked, label: status)
            }
            if lower.contains("run") || lower.contains("progress") || lower.contains("queue") || lower.contains("start") {
                return .init(kind: .running, label: status)
            }
            return .init(kind: .returned, label: status)
        }

        if let stage = matchingStage(for: engine) {
            let lower = stage.status.lowercased()
            if lower.contains("fail") || lower.contains("error") || lower.contains("block") {
                return .init(kind: .blocked, label: stage.status)
            }
            if lower.contains("run") || lower.contains("progress") || lower.contains("queue") || lower.contains("start") {
                return .init(kind: .running, label: stage.status)
            }
            if lower.contains("complete") || lower.contains("success") || lower.contains("pass") || lower.contains("done") || lower.contains("ready") {
                return .init(kind: .returned, label: stage.status)
            }
        }

        if app.isRunning {
            if app.activeResultOrigin.localizedCaseInsensitiveContains("engine") {
                let requested = app.activeResult?.firstString(["requested_module", "requestedModule", "active_engine"])
                if requested == engine.id || (requested == nil && engine.id == selectedEngineID) {
                    return .init(kind: .running, label: "Running")
                }
                return .init(kind: .idle, label: "Not requested")
            }
            if app.activeResultOrigin.localizedCaseInsensitiveContains("dag") {
                return .init(kind: .pending, label: "Pending / not returned")
            }
        }
        return .init(kind: .idle, label: engine.observed ? "Observed historically" : "Not returned")
    }

    private func matchingStage(for engine: EngineNavigatorDefinition) -> EngineStage? {
        let idTokens = engine.id.split(separator: "_").map { String($0).lowercased() }
        return ResultTools.stages(app.activeResult).first { stage in
            let haystack = (stage.name + " " + (stage.detail ?? "")).lowercased()
            if haystack.contains(engine.id.lowercased()) { return true }
            let meaningful = idTokens.filter { $0.count > 3 }
            return !meaningful.isEmpty && meaningful.allSatisfy { haystack.contains($0) }
        }
    }

    private func runtimeDeclaredEngines() -> [EngineNavigatorDefinition] {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let engineObject) = enginesValue,
              let declaredValue = engineObject["declared"],
              case .array(let declared) = declaredValue else { return [] }

        var observed = Set<String>()
        if let observedValue = engineObject["observed_in_completed_jobs"], case .array(let rows) = observedValue {
            observed = Set(rows.compactMap { $0.stringValue })
        }
        return declared.compactMap { row in
            guard case .object(let object) = row,
                  let id = object["id"]?.stringValue, !id.isEmpty else { return nil }
            let label = object["label"]?.stringValue ?? pretty(id)
            return EngineNavigatorDefinition.make(id, label, observed: observed.contains(id))
        }
    }

    private func loadResources() async {
        resourcesLoading = true
        resourceError = nil
        defer { resourcesLoading = false }
        do {
            let response = try await resourceAPI.resources(engine: selectedEngineID)
            resourceSummary = response
            if let value = response.recursiveFind("assets"), case .array(let rows) = value {
                resources = rows.compactMap(EngineLinkedResource.init)
            } else {
                resources = []
            }
        } catch {
            resources = []
            resourceSummary = nil
            resourceError = error.localizedDescription
        }
    }

    private func scalar(_ source: JSONValue?, _ key: String) -> String {
        source?.recursiveFind(key)?.stringValue ?? "—"
    }

    private func pretty(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }
}

private struct EngineNavigatorDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let summary: String
    let group: String
    let observed: Bool

    var shortTitle: String {
        title.count > 22 ? String(title.prefix(20)) : title
    }

    static let fallback: [EngineNavigatorDefinition] = [
        .make("ore_intelligence", "Ore Intelligence"),
        .make("resource_model", "Resource & Mining"),
        .make("comminution", "Comminution"),
        .make("classification", "Classification"),
        .make("flotation", "Flotation"),
        .make("magnetic_gravity", "Magnetic & Gravity"),
        .make("hydrometallurgy", "Hydrometallurgy"),
        .make("thermodynamics", "Thermodynamics"),
        .make("water_circuit", "Water & Recycle"),
        .make("conservation", "Conservation & Reconciliation"),
        .make("equipment_epc", "Equipment & EPC"),
        .make("economics", "Economics"),
        .make("tailings", "Tailings & ESG"),
        .make("digital_twin", "Digital Twin"),
        .make("hybrid_ai", "Hybrid AI & Uncertainty"),
        .make("diagnostics", "Governance & Diagnostics")
    ]

    static func make(_ id: String, _ title: String, observed: Bool = false) -> EngineNavigatorDefinition {
        let meta = metadata(id)
        return .init(id: id, title: title, icon: meta.0, summary: meta.1, group: meta.2, observed: observed)
    }

    private static func metadata(_ id: String) -> (String, String, String) {
        switch id {
        case "ore_intelligence": return ("cube.transparent", "Ore diagnosis, assays, mineralogy, PSD, liberation and evidence quality.", "Diagnosis")
        case "resource_model": return ("map", "Resource classification, geostatistics, mine domains and uncertainty.", "Geoscience & Mining")
        case "comminution": return ("gearshape.2", "Crushing, grinding, breakage, power and particle-size response.", "Process Physics")
        case "classification": return ("line.3.crossed.swirl.circle", "Hydrocyclone, screen, partition and classification response.", "Process Physics")
        case "flotation": return ("bubbles.and.sparkles", "Mineral-by-size-by-liberation flotation, kinetics and reagent response.", "Separation")
        case "magnetic_gravity": return ("magnet", "Magnetic susceptibility and gravity separation response.", "Separation")
        case "hydrometallurgy": return ("drop.triangle", "Leaching, dissolution, precipitation and solution recovery.", "Chemistry")
        case "thermodynamics": return ("flame", "Speciation, activities, equilibrium, redox and precipitation.", "Chemistry")
        case "water_circuit": return ("drop", "Recycle water, ions, scaling, corrosion and bleed control.", "Utilities")
        case "conservation": return ("arrow.triangle.2.circlepath", "Mass, water, mineral, element, species, charge and energy closure.", "Assurance")
        case "equipment_epc": return ("wrench.and.screwdriver", "Equipment sizing, duties, quantities and EPC engineering outputs.", "Engineering")
        case "economics": return ("chart.line.uptrend.xyaxis", "CAPEX, OPEX, cash flow, NPV, IRR and sensitivities.", "Decision")
        case "tailings": return ("exclamationmark.triangle", "Tailings chemistry, residual value, risk, ESG and reprocessing.", "Closure & ESG")
        case "digital_twin": return ("dot.radiowaves.left.and.right", "Operating envelope, optimization, scenario state and controls.", "Operations")
        case "hybrid_ai": return ("brain.head.profile", "Physics-constrained prediction, uncertainty, OOD and applicability.", "Intelligence")
        case "diagnostics": return ("stethoscope", "Root-cause diagnostics, evidence gates, warnings and claim ceiling.", "Governance")
        default: return ("cpu", "Runtime-declared governed AURORA engine.", "Runtime Contract")
        }
    }
}

private struct EngineNavigatorExecutionState {
    enum Kind { case returned, running, pending, blocked, idle }
    let kind: Kind
    let label: String

    var color: Color {
        switch kind {
        case .returned: return AuroraTheme.good
        case .running: return AuroraTheme.accent
        case .pending: return AuroraTheme.gold
        case .blocked: return AuroraTheme.bad
        case .idle: return .secondary
        }
    }
}

private struct EngineNavigatorOutputRow: Identifiable {
    let id = UUID()
    let path: String
    let value: String
    let numeric: Double?

    var label: String {
        let leaf = path.split(separator: ".").last.map(String.init) ?? path
        return leaf.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var shortLabel: String {
        label.count > 20 ? String(label.prefix(18)) + "…" : label
    }

    init(path: String, value: String) {
        self.path = path
        self.value = value
        let clean = value.replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.numeric = Double(clean)
    }
}

private struct EngineLinkedResource: Identifiable {
    let id: String
    let name: String
    let path: String
    let category: String
    let format: String
    let validation: String
    let readable: Bool

    init?(_ value: JSONValue) {
        guard case .object(let object) = value else { return nil }
        let path = object["relative_path"]?.stringValue ?? object["name"]?.stringValue ?? "unknown"
        self.id = object["asset_id"]?.stringValue ?? path
        self.name = object["name"]?.stringValue ?? path
        self.path = path
        self.category = object["category"]?.stringValue ?? "data_resource"
        self.format = object["format"]?.stringValue ?? "unknown"
        self.validation = object["validation"]?.stringValue ?? "not_tested"
        self.readable = object["readable"]?.boolValue ?? false
    }

    var icon: String {
        switch category {
        case "model": return "brain.head.profile"
        case "database": return "cylinder.split.1x2.fill"
        case "thermodynamic_reference": return "flame.fill"
        case "process_reference": return "gearshape.2.fill"
        case "engineering_reference": return "wrench.and.screwdriver.fill"
        case "validation_reference": return "checkmark.shield.fill"
        case "economic_reference": return "chart.line.uptrend.xyaxis"
        case "configuration_registry": return "list.bullet.rectangle.fill"
        default: return "doc.text.fill"
        }
    }
}

private actor EngineResourceAPI {
    enum ResourceError: LocalizedError {
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid AURORA resource inventory response"
            case .http(let code, let body): return "AURORA resource inventory HTTP \(code): \(body)"
            }
        }
    }

    func resources(engine: String) async throws -> JSONValue {
        var components = URLComponents(
            url: AppConfig.backend.appendingPathComponent("api/platform/databases"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [.init(name: "engine", value: engine)]
        guard let url = components.url else { throw ResourceError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ResourceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ResourceError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
