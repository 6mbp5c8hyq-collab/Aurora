import SwiftUI
import SwiftData

struct EngineExplorerView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedEngine: EngineDefinition?
    @State private var selectedProjectID: UUID?
    @State private var query = ""

    private var engines: [EngineDefinition] {
        let runtime = runtimeDeclaredEngines()
        return runtime.isEmpty ? fallbackEngines : runtime
    }

    private var fallbackEngines: [EngineDefinition] {
        [
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
    }

    private var filteredEngines: [EngineDefinition] {
        guard !query.isEmpty else { return engines }
        return engines.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.key.localizedCaseInsensitiveContains(query) ||
            $0.group.localizedCaseInsensitiveContains(query) ||
            $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    private var activeProject: AuroraProject? {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) {
            return selected
        }
        return projects.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                contractStrip
                traceStrip
                executionBar
                search
                engineGrid
                if let selectedEngine {
                    EngineResultDetail(engine: selectedEngine, result: result(for: selectedEngine))
                }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
    }

    private var header: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AuroraTheme.accent.opacity(0.18))
                        .frame(width: 62, height: 62)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title2.bold())
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Engine Observatory").font(.largeTitle.bold())
                    Text("Backend-governed AURORA engine contract")
                        .foregroundStyle(.secondary)
                    Text("The catalog is read from the runtime audit contract when available; the native fallback mirrors the current canonical contract.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(text: app.activeResult == nil ? "Awaiting run" : "Result loaded")
                    Text("\(engines.count) declared engines")
                        .font(.caption.monospaced())
                        .foregroundStyle(AuroraTheme.gold)
                }
            }
        }
    }

    private var contractStrip: some View {
        let observed = engines.filter(\.observed).count
        let source = runtimeContractAvailable ? "Runtime /api/audit" : "Native canonical fallback"
        return AuroraCard {
            HStack(spacing: 18) {
                Label("\(engines.count) declared", systemImage: "square.stack.3d.up")
                Label("\(observed) observed", systemImage: "checkmark.seal")
                Label(source, systemImage: runtimeContractAvailable ? "server.rack" : "iphone")
                Spacer()
                if runtimeContractAvailable {
                    StatusBadge(text: observed == engines.count ? "Contract observed" : "Contract declared")
                }
            }
            .font(.caption)
        }
    }

    private var traceStrip: some View {
        let stages = ResultTools.stages(app.activeResult)
        return AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("DAG Execution Trace").font(.headline)
                    Spacer()
                    Text("\(stages.count) reported stages").font(.caption).foregroundStyle(.secondary)
                }
                if stages.isEmpty {
                    Text("Run AURORA or restore a DAG result from Result Vault to populate the live trace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(stages) { stage in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stage.name).font(.caption.bold()).lineLimit(1)
                                    Text(stage.status).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(width: 150, alignment: .leading)
                                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }
        }
    }

    private var executionBar: some View {
        AuroraCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Governed Engine Execution").font(.headline)
                    Text("Runs the selected engine through canonical_mobile_execute using the selected project basis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

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
                    .labelsHidden()
                    .frame(maxWidth: 260)

                    Button {
                        guard let engine = selectedEngine, let project = activeProject else { return }
                        app.run(project: project, context: context, module: engine.key)
                    } label: {
                        if app.isRunning {
                            ProgressView()
                            Text("Running")
                        } else {
                            Label(selectedEngine == nil ? "Select Engine" : "RUN ENGINE", systemImage: "bolt.horizontal.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.isRunning || selectedEngine == nil || activeProject == nil)
                }
            }
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search engine, contract id, domain or capability", text: $query)
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(13)
        .background(AuroraTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private var engineGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 12)], spacing: 12) {
            ForEach(filteredEngines) { engine in
                EngineCard(
                    engine: engine,
                    result: result(for: engine),
                    isSelected: selectedEngine?.id == engine.id
                ) {
                    withAnimation(.snappy) { selectedEngine = engine }
                }
            }
        }
    }

    private func result(for engine: EngineDefinition) -> JSONValue? {
        guard let result = app.activeResult else { return nil }
        return result.recursiveFind(engine.key)
            ?? result.recursiveFind(engine.key.replacingOccurrences(of: "_", with: ""))
    }

    private var runtimeContractAvailable: Bool {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let enginesObject) = enginesValue,
              let declared = enginesObject["declared"],
              case .array(let items) = declared else { return false }
        return !items.isEmpty
    }

    private func runtimeDeclaredEngines() -> [EngineDefinition] {
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
                  let id = object["id"]?.stringValue, !id.isEmpty else { return nil }
            let label = object["label"]?.stringValue ?? id.replacingOccurrences(of: "_", with: " ").capitalized
            return EngineDefinition.make(id, label, observed: observed.contains(id))
        }
    }
}

private struct EngineDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let key: String
    let icon: String
    let summary: String
    let group: String
    let observed: Bool

    static func make(_ id: String, _ label: String, observed: Bool = false) -> EngineDefinition {
        let metadata = metadata(for: id)
        return .init(
            id: id,
            title: label,
            key: id,
            icon: metadata.icon,
            summary: metadata.summary,
            group: metadata.group,
            observed: observed
        )
    }

    private static func metadata(for id: String) -> (icon: String, summary: String, group: String) {
        switch id {
        case "ore_intelligence": return ("cube.transparent", "Ore diagnosis, assays, mineralogy and evidence quality", "Diagnosis")
        case "resource_model": return ("map", "Resource classification, mining domains and uncertainty", "Geoscience & Mining")
        case "comminution": return ("gearshape.2", "Crushing, grinding, power and particle-size response", "Process")
        case "classification": return ("line.3.crossed.swirl.circle", "Size classification and hydrocyclone response", "Process")
        case "flotation": return ("bubbles.and.sparkles", "Mineral-by-size-by-liberation flotation response", "Separation")
        case "magnetic_gravity": return ("magnet", "Magnetic susceptibility and gravity separation", "Separation")
        case "hydrometallurgy": return ("drop.triangle", "Leaching, solution chemistry and recovery", "Chemistry")
        case "thermodynamics": return ("flame", "Speciation, equilibrium, redox and precipitation", "Chemistry")
        case "water_circuit": return ("drop", "Recycle water, ions, scaling and bleed", "Utilities")
        case "conservation": return ("arrow.triangle.2.circlepath", "Mass, water, species, charge, energy and reconciliation", "Assurance")
        case "equipment_epc": return ("wrench.and.screwdriver", "Equipment sizing, PFD/P&ID and EPC quantities", "Engineering")
        case "economics": return ("chart.line.uptrend.xyaxis", "CAPEX, OPEX, NPV, IRR and sensitivities", "Economics")
        case "tailings": return ("exclamationmark.triangle", "Tailings chemistry, value, risk, ESG and reprocessing", "Risk & ESG")
        case "digital_twin": return ("dot.radiowaves.left.and.right", "Scenario state, optimization and operating envelope", "Operations")
        case "hybrid_ai": return ("brain.head.profile", "Physics-constrained prediction, applicability and uncertainty", "Intelligence")
        case "diagnostics": return ("stethoscope", "Root-cause, gates, warnings and claim ceiling", "Governance")
        default: return ("cpu", "Runtime-declared governed AURORA engine", "Runtime Contract")
        }
    }
}

private struct EngineCard: View {
    let engine: EngineDefinition
    let result: JSONValue?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: engine.icon)
                        .font(.title3.bold())
                        .foregroundStyle(AuroraTheme.accent)
                    Spacer()
                    status
                }
                Text(engine.title).font(.headline).foregroundStyle(.primary)
                Text(engine.key)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(engine.group.uppercased())
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(AuroraTheme.gold)
                Text(engine.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack {
                    Text(result == nil ? (engine.observed ? "Observed in runtime" : "Declared contract") : "Open engine result")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: result == nil ? "circle.hexagongrid" : "arrow.up.right")
                        .font(.caption.bold())
                }
                .foregroundStyle(result == nil ? .secondary : AuroraTheme.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? AuroraTheme.accent.opacity(0.13) : AuroraTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isSelected ? AuroraTheme.accent : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var status: some View {
        let text: String
        if let result { text = ResultTools.status(result) }
        else { text = engine.observed ? "observed" : "registered" }
        return Text(text.uppercased())
            .font(.caption2.bold())
            .foregroundStyle(result == nil ? (engine.observed ? AuroraTheme.good : .secondary) : AuroraTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AuroraTheme.background, in: Capsule())
    }
}

private struct EngineResultDetail: View {
    let engine: EngineDefinition
    let result: JSONValue?

    var body: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(engine.title).font(.title2.bold())
                        Text(engine.key).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        Text(engine.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: result == nil ? (engine.observed ? "Observed" : "Declared") : ResultTools.status(result))
                }

                if let result {
                    let kpis = ResultTools.kpis(result)
                    if !kpis.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                            ForEach(kpis) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.caption).foregroundStyle(.secondary)
                                    Text("\(item.value.formatted(.number.precision(.fractionLength(0...3)))) \(item.unit)")
                                        .font(.title3.bold())
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    DisclosureGroup("Engine output · scalar ledger") {
                        ForEach(Array(result.flattenedScalars(limit: 500).enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 12) {
                                Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Spacer(minLength: 10)
                                Text(row.1).font(.caption2.monospaced()).multilineTextAlignment(.trailing)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    DisclosureGroup("Engine JSON / diagnostics") {
                        Text(result.prettyString())
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ContentUnavailableView(
                        "No individual engine result loaded",
                        systemImage: engine.icon,
                        description: Text("Select this engine and run it against a project, or restore a matching engine job from Result Vault. Governed/blocked states remain explicit.")
                    )
                }
            }
        }
    }
}
