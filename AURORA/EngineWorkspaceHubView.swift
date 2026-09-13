import SwiftUI
import SwiftData
import Charts
import QuickLook

struct EngineWorkspaceHubView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedEngineID = "ore_intelligence"
    @State private var selectedProjectID: UUID?
    @State private var query = ""
    @State private var previewURL: URL?

    private var engines: [EngineWorkspaceDefinition] {
        let runtime = runtimeDeclaredEngines()
        return runtime.isEmpty ? EngineWorkspaceDefinition.fallback : runtime
    }

    private var selectedEngine: EngineWorkspaceDefinition {
        engines.first(where: { $0.id == selectedEngineID }) ?? engines.first ?? .fallback[0]
    }

    private var activeProject: AuroraProject? {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) {
            return selected
        }
        return projects.first
    }

    private var filteredEngines: [EngineWorkspaceDefinition] {
        guard !query.isEmpty else { return engines }
        return engines.filter {
            $0.title.localizedCaseInsensitiveContains(query)
            || $0.id.localizedCaseInsensitiveContains(query)
            || $0.group.localizedCaseInsensitiveContains(query)
            || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    private var engineResult: JSONValue? {
        guard let result = app.activeResult else { return nil }
        return result.recursiveFind(selectedEngine.id)
            ?? result.recursiveFind(selectedEngine.id.replacingOccurrences(of: "_", with: ""))
    }

    private var workspaceRows: [EngineWorkspaceRow] {
        guard let result = engineResult else { return [] }
        return result.flattenedScalars(limit: 6000).map { EngineWorkspaceRow(path: $0.0, value: $0.1) }
    }

    private var numericRows: [EngineWorkspaceRow] {
        workspaceRows.filter { $0.numeric != nil }
    }

    private var performanceRows: [EngineWorkspaceRow] {
        numericRows.filter {
            let p = $0.path.lowercased()
            return p.contains("recovery") || p.contains("grade") || p.contains("yield")
                || p.contains("efficien") || p.contains("mass_pull") || p.contains("extraction")
        }
        .prefix(16)
        .map { $0 }
    }

    private var issueRows: [EngineWorkspaceRow] {
        workspaceRows.filter {
            let p = $0.path.lowercased()
            let v = $0.value.lowercased()
            return p.contains("warning") || p.contains("error") || p.contains("risk")
                || p.contains("limitation") || p.contains("blocked") || p.contains("gate")
                || v.contains("warning") || v.contains("blocked") || v.contains("failed")
        }
        .prefix(40)
        .map { $0 }
    }

    private var uncertaintyRows: [EngineWorkspaceRow] {
        workspaceRows.filter {
            let p = $0.path.lowercased()
            return p.contains("uncert") || p.contains("confidence") || p.contains("interval")
                || p.contains("ood") || p.contains("applicability") || p.contains("coverage")
                || p.contains("calibration") || p.contains("rmse") || p.contains("mae")
        }
        .prefix(50)
        .map { $0 }
    }

    private var evidenceRows: [EngineWorkspaceRow] {
        workspaceRows.filter {
            let p = $0.path.lowercased()
            return p.contains("evidence") || p.contains("lineage") || p.contains("source")
                || p.contains("measured") || p.contains("laboratory") || p.contains("benchmark")
                || p.contains("validation") || p.contains("authority")
        }
        .prefix(50)
        .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                executionConsole
                engineSelector
                workspaceHeader
                if let engineResult {
                    authorityStrip
                    keyResults(result: engineResult)
                    performanceChart
                    findingsSection
                    uncertaintySection
                    evidenceSection
                    exportSection
                    scalarLedger(result: engineResult)
                } else {
                    emptyWorkspace
                }
                if let error = app.lastError { errorCard(error) }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .quickLookPreview($previewURL)
        .onChange(of: app.lastExportURL) { _, newValue in
            if let newValue { previewURL = newValue }
        }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.16))
                        .frame(width: 72, height: 72)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("AURORA Engine Workspaces").font(.largeTitle.bold())
                    Text("Execute · inspect · validate · visualize · export every governed engine")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Each workspace is bound to the runtime engine contract and reads only values returned by AURORA. Missing results remain explicit; no synthetic KPI values are inserted by the iOS client.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: runtimeContractAvailable ? "Runtime contract" : "Native fallback")
                    Text("\(engines.count) engines")
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
                        Text("Execution Console").font(.headline)
                        Text("Run one governed engine or the complete canonical AURORA DAG against the same project basis.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isRunning ? app.runStatus : "Ready")
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
                                Label("RUN SELECTED ENGINE", systemImage: "bolt.horizontal.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.isRunning || activeProject == nil)

                        Button {
                            guard let project = activeProject else { return }
                            app.run(project: project, context: context)
                        } label: {
                            Label("RUN FULL ENGINE DAG", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                        .buttonStyle(.bordered)
                        .disabled(app.isRunning || activeProject == nil)
                    }

                    Spacer()
                    if let id = app.activeJobID {
                        Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private var engineSelector: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search engine, domain or capability", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filteredEngines) { engine in
                            Button {
                                withAnimation(.snappy) { selectedEngineID = engine.id }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: engine.icon)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(engine.title).font(.caption.bold()).lineLimit(1)
                                        Text(engine.group).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .foregroundStyle(selectedEngineID == engine.id ? AuroraTheme.background : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    selectedEngineID == engine.id ? AuroraTheme.accent : AuroraTheme.panel2,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var workspaceHeader: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selectedEngine.icon)
                    .font(.title.bold())
                    .foregroundStyle(AuroraTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(AuroraTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedEngine.title).font(.title2.bold())
                    Text(selectedEngine.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Text(selectedEngine.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(text: engineResult == nil ? (selectedEngine.observed ? "Observed / no active result" : "Declared / no active result") : ResultTools.status(engineResult))
                    Text(selectedEngine.group.uppercased())
                        .font(.caption2.bold())
                        .tracking(1.1)
                        .foregroundStyle(AuroraTheme.gold)
                }
            }
        }
    }

    private var authorityStrip: some View {
        let measured = workspaceRows.filter { $0.authority == .measured }.count
        let qualified = workspaceRows.filter { $0.authority == .qualified }.count
        let returned = max(0, workspaceRows.count - measured - qualified)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            workspaceMetric("Scalar paths", "\(workspaceRows.count)", "list.number")
            workspaceMetric("Numeric", "\(numericRows.count)", "number.square.fill")
            workspaceMetric("Measured-tagged", "\(measured)", "checkmark.seal.fill")
            workspaceMetric("Qualified-tagged", "\(qualified)", "exclamationmark.shield.fill")
            workspaceMetric("Other returned", "\(returned)", "arrow.down.doc.fill")
            workspaceMetric("Issues", "\(issueRows.count)", "exclamationmark.triangle.fill")
        }
    }

    private func keyResults(result: JSONValue) -> some View {
        let kpis = ResultTools.kpis(result)
        let fallback = numericRows.prefix(8).map { $0 }
        return AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Key Returned Results").font(.headline)
                    Spacer()
                    Text(kpis.isEmpty ? "DIRECT NUMERIC PATHS" : "RECOGNIZED KPI")
                        .font(.caption2.bold())
                        .foregroundStyle(AuroraTheme.gold)
                }
                if !kpis.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(kpis) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.caption).foregroundStyle(.secondary)
                                Text("\(item.value.formatted(.number.precision(.fractionLength(0...4)))) \(item.unit)")
                                    .font(.title3.bold())
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                } else if !fallback.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                        ForEach(fallback) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.parameter).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(row.value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.65)
                                Text(row.path).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                } else {
                    Text("No numeric scientific values were returned under this engine result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        Text("Performance Metrics · As Returned").font(.headline)
                        Spacer()
                        Text("NO CROSS-UNIT NORMALIZATION")
                            .font(.caption2.bold())
                            .foregroundStyle(AuroraTheme.warn)
                    }
                    Text("The chart includes only returned numeric paths whose names indicate recovery, grade, yield, efficiency, mass pull or extraction. Values are not invented or unit-converted by the client.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(performanceRows) { row in
                        if let value = row.numeric {
                            BarMark(
                                x: .value("Metric", row.shortLabel),
                                y: .value("Returned value", value)
                            )
                            .annotation(position: .top) {
                                Text(value.formatted(.number.precision(.fractionLength(0...2))))
                                    .font(.system(size: 8, design: .monospaced))
                            }
                        }
                    }
                    .frame(height: 280)
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine().foregroundStyle(.clear)
                            AxisValueLabel(centered: true) {
                                if let text = value.as(String.self) {
                                    Text(text).font(.system(size: 8)).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var findingsSection: some View {
        ledgerCard(
            title: "Warnings, Gates & Diagnostics",
            subtitle: "Only paths or returned values containing warning/error/risk/limitation/gate semantics",
            rows: issueRows,
            empty: "No warning or gate paths were found in this engine result."
        )
    }

    private var uncertaintySection: some View {
        ledgerCard(
            title: "Uncertainty & Applicability",
            subtitle: "Confidence intervals, OOD/applicability, calibration and error metrics when returned",
            rows: uncertaintyRows,
            empty: "No explicit uncertainty/applicability paths were returned by this engine."
        )
    }

    private var evidenceSection: some View {
        ledgerCard(
            title: "Evidence & Validation Trace",
            subtitle: "Evidence, source, lineage, measured, benchmark and validation paths",
            rows: evidenceRows,
            empty: "No explicit evidence or validation paths were returned under this engine result."
        )
    }

    private var exportSection: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Engine Deliverables").font(.headline)
                        Text("Server-governed exports scoped to the selected engine result, not the whole project response.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Ready")
                }

                HStack(spacing: 10) {
                    exportButton("ENGINE PDF", "pdf", "doc.richtext.fill")
                    exportButton("ENGINE EXCEL", "xlsx", "tablecells.fill")
                    exportButton("ENGINE WORD", "docx", "doc.text.fill")
                    exportButton("ENGINE CSV", "csv", "list.bullet.rectangle.fill")
                }

                if let url = app.lastExportURL {
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

    private func scalarLedger(result: JSONValue) -> some View {
        AuroraCard {
            DisclosureGroup("Complete engine scalar ledger · \(workspaceRows.count) returned paths") {
                ForEach(workspaceRows.prefix(1500)) { row in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(row.authority.rawValue.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(row.authority == .measured ? AuroraTheme.good : row.authority == .qualified ? AuroraTheme.warn : AuroraTheme.accent)
                        }
                        Spacer(minLength: 10)
                        Text(row.value)
                            .font(.caption2.monospaced())
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                            .frame(maxWidth: 360, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.08)
                }
                if workspaceRows.count > 1500 {
                    Text("Showing the first 1,500 scalar paths on-device. Full engine data remains in the governed export/result response.")
                        .font(.caption2)
                        .foregroundStyle(AuroraTheme.warn)
                }
                DisclosureGroup("Raw engine JSON") {
                    Text(result.prettyString())
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var emptyWorkspace: some View {
        AuroraCard {
            ContentUnavailableView(
                "No active result for \(selectedEngine.title)",
                systemImage: selectedEngine.icon,
                description: Text("Run the selected engine, run the full canonical DAG, or restore a matching run from Result Vault. The workspace will not fabricate missing outputs.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    private func ledgerCard(title: String, subtitle: String, rows: [EngineWorkspaceRow], empty: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(rows.count)").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                }
                if rows.isEmpty {
                    Text(empty).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            Spacer(minLength: 10)
                            Text(row.value).font(.caption2.monospaced()).multilineTextAlignment(.trailing).textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                        Divider().opacity(0.08)
                    }
                }
            }
        }
    }

    private func exportButton(_ title: String, _ format: String, _ icon: String) -> some View {
        Button {
            guard let project = activeProject else { return }
            app.exportEngine(project: project, engineID: selectedEngine.id, engineTitle: selectedEngine.title, format: format)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .disabled(engineResult == nil || activeProject == nil || app.isExporting)
    }

    private func workspaceMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        }
    }

    private func errorCard(_ error: String) -> some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Engine workspace error").font(.headline)
                    Text(error).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var runtimeContractAvailable: Bool {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let enginesObject) = enginesValue,
              let declared = enginesObject["declared"],
              case .array(let items) = declared else { return false }
        return !items.isEmpty
    }

    private func runtimeDeclaredEngines() -> [EngineWorkspaceDefinition] {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let enginesObject) = enginesValue,
              let declaredValue = enginesObject["declared"],
              case .array(let declared) = declaredValue else { return [] }

        var observed = Set<String>()
        if let observedValue = enginesObject["observed_in_completed_jobs"], case .array(let ids) = observedValue {
            observed = Set(ids.compactMap { $0.stringValue })
        }

        return declared.compactMap { item in
            guard case .object(let object) = item,
                  let id = object["id"]?.stringValue,
                  !id.isEmpty else { return nil }
            let label = object["label"]?.stringValue ?? id.replacingOccurrences(of: "_", with: " ").capitalized
            return EngineWorkspaceDefinition.make(id, label, observed: observed.contains(id))
        }
    }
}

private struct EngineWorkspaceDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let summary: String
    let group: String
    let observed: Bool

    static let fallback: [EngineWorkspaceDefinition] = [
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

    static func make(_ id: String, _ label: String, observed: Bool = false) -> EngineWorkspaceDefinition {
        let meta = metadata(for: id)
        return .init(id: id, title: label, icon: meta.icon, summary: meta.summary, group: meta.group, observed: observed)
    }

    private static func metadata(for id: String) -> (icon: String, summary: String, group: String) {
        switch id {
        case "ore_intelligence": return ("cube.transparent", "Ore diagnosis, assays, mineralogy, PSD/liberation and evidence quality", "Diagnosis")
        case "resource_model": return ("map", "Resource classification, geostatistics, mine domains and uncertainty", "Geoscience & Mining")
        case "comminution": return ("gearshape.2", "Crushing, grinding, power, breakage and particle-size response", "Process")
        case "classification": return ("line.3.crossed.swirl.circle", "Hydrocyclone/screen partition, cut size and classification response", "Process")
        case "flotation": return ("bubbles.and.sparkles", "Mineral-by-size-by-liberation flotation, kinetics and reagent response", "Separation")
        case "magnetic_gravity": return ("magnet", "Magnetic susceptibility, gravity separation and recovery", "Separation")
        case "hydrometallurgy": return ("drop.triangle", "Leaching, dissolution, precipitation and solution recovery", "Chemistry")
        case "thermodynamics": return ("flame", "Speciation, activities, equilibrium, redox and precipitation", "Chemistry")
        case "water_circuit": return ("drop", "Recycle water, ions, scaling, corrosion, bleed and fresh-water demand", "Utilities")
        case "conservation": return ("arrow.triangle.2.circlepath", "Mass, water, mineral, element, species, charge and energy closure", "Assurance")
        case "equipment_epc": return ("wrench.and.screwdriver", "Equipment sizing, duties, quantities and EPC engineering outputs", "Engineering")
        case "economics": return ("chart.line.uptrend.xyaxis", "CAPEX, OPEX, cash flow, NPV, IRR and sensitivity", "Economics")
        case "tailings": return ("exclamationmark.triangle", "Tailings chemistry, residual value, risk, ESG and reprocessing", "Risk & ESG")
        case "digital_twin": return ("dot.radiowaves.left.and.right", "Operating envelope, scenario state, optimization and control", "Operations")
        case "hybrid_ai": return ("brain.head.profile", "Physics-constrained prediction, uncertainty, OOD and applicability", "Intelligence")
        case "diagnostics": return ("stethoscope", "Root-cause diagnostics, evidence gates, warnings and claim ceiling", "Governance")
        default: return ("cpu", "Runtime-declared governed AURORA engine", "Runtime Contract")
        }
    }
}

private struct EngineWorkspaceRow: Identifiable {
    enum Authority: String { case measured, qualified, returned }

    let id = UUID()
    let path: String
    let value: String
    let numeric: Double?
    let authority: Authority

    var parameter: String {
        let leaf = path.split(separator: ".").last.map(String.init) ?? path
        return leaf.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var shortLabel: String {
        let text = parameter
        return text.count > 20 ? String(text.prefix(18)) + "…" : text
    }

    init(path: String, value: String) {
        self.path = path
        self.value = value
        let clean = value
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.numeric = Double(clean)

        let lower = path.lowercased()
        if lower.contains("measured") || lower.contains("laboratory") || lower.contains("lab_result") {
            self.authority = .measured
        } else if lower.contains("estimated") || lower.contains("heuristic") || lower.contains("assumed")
                    || lower.contains("proxy") || lower.contains("surrogate") || lower.contains("vendor") {
            self.authority = .qualified
        } else {
            self.authority = .returned
        }
    }
}

extension AppModel {
    func exportEngine(project: AuroraProject, engineID: String, engineTitle: String, format: String) {
        guard !isExporting else { return }
        guard let root = activeResult,
              let engineResult = root.recursiveFind(engineID)
                ?? root.recursiveFind(engineID.replacingOccurrences(of: "_", with: "")) else {
            lastError = "No governed result is loaded for \(engineTitle)."
            return
        }

        isExporting = true
        lastError = nil
        let api = AURORAAPI()
        let safeEngine = engineID.replacingOccurrences(of: " ", with: "_")
        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_" + safeEngine + "_" + project.name),
            "project": project.canonicalProject,
            "inputGovernance": project.canonicalInputGovernance,
            "designBasis": .object([
                "target_component": .string(project.targetComponent),
                "target_grade": .number(project.targetGrade),
                "engine_id": .string(engineID),
                "engine_title": .string(engineTitle),
                "export_scope": .string("single_governed_engine")
            ]),
            "analyses": .array([]),
            "flowsheet": .object([:]),
            "diagnostics": .array([]),
            "result": .object([
                "engine_id": .string(engineID),
                "engine_title": .string(engineTitle),
                engineID: engineResult
            ]),
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus),
                "scope": .string("engine_workspace")
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
