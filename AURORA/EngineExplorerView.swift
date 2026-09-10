import SwiftUI

struct EngineExplorerView: View {
    @EnvironmentObject private var app: AppModel
    @State private var selectedEngine: EngineDefinition?
    @State private var query = ""

    private let engines: [EngineDefinition] = [
        .init("Ore Intelligence", "ore_intelligence", "cube.transparent", "Ore diagnosis, assays, mineralogy and evidence quality", "Diagnosis"),
        .init("Resource Model", "resource_model", "map", "Resource classification, domains and uncertainty", "Geoscience"),
        .init("Comminution", "comminution", "gearshape.2", "Crushing, grinding, power and particle-size response", "Process"),
        .init("Classification", "classification", "line.3.crossed.swirl.circle", "Size classification and hydrocyclone response", "Process"),
        .init("Flotation", "flotation", "bubbles.and.sparkles", "Mineral-by-size-by-liberation flotation response", "Separation"),
        .init("Magnetic & Gravity", "magnetic_gravity", "magnet", "Magnetic susceptibility and gravity separation", "Separation"),
        .init("Hydrometallurgy", "hydrometallurgy", "drop.triangle", "Leaching, solution chemistry and recovery", "Chemistry"),
        .init("Thermodynamics", "thermodynamics", "flame", "Speciation, equilibrium, redox and precipitation", "Chemistry"),
        .init("Water Circuit", "water_circuit", "drop", "Recycle water, ions, scaling and bleed", "Utilities"),
        .init("Conservation", "conservation", "arrow.triangle.2.circlepath", "Mass, water, species, charge and energy closure", "Assurance"),
        .init("Equipment & EPC", "equipment_epc", "wrench.and.screwdriver", "Equipment sizing, PFD/P&ID and EPC quantities", "Engineering"),
        .init("Economics", "economics", "chart.line.uptrend.xyaxis", "CAPEX, OPEX, NPV, IRR and sensitivities", "Economics"),
        .init("Tailings", "tailings", "exclamationmark.triangle", "Tailings chemistry, value, risk and reprocessing", "Risk"),
        .init("Digital Twin", "digital_twin", "dot.radiowaves.left.and.right", "Scenario state, optimization and operating envelope", "Operations"),
        .init("Hybrid AI", "hybrid_ai", "brain.head.profile", "Physics-constrained prediction and uncertainty", "Intelligence"),
        .init("Diagnostics", "diagnostics", "stethoscope", "Root-cause, gates, warnings and claim ceiling", "Assurance")
    ]

    private var filteredEngines: [EngineDefinition] {
        guard !query.isEmpty else { return engines }
        return engines.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.group.localizedCaseInsensitiveContains(query) ||
            $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                traceStrip
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
                    Text("One result surface for every AURORA engine")
                        .foregroundStyle(.secondary)
                    Text("Select any engine to inspect its own status, evidence, scalar outputs, diagnostics and downloadable artifacts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.activeResult == nil ? "Awaiting run" : "Result loaded")
            }
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
                    Text("Run AURORA to populate the live trace. The catalog remains available before execution.")
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

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search engine, domain or capability", text: $query)
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
        return result.recursiveFind(engine.key) ?? result.recursiveFind(engine.key.replacingOccurrences(of: "_", with: ""))
    }
}

private struct EngineDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let key: String
    let icon: String
    let summary: String
    let group: String

    init(_ title: String, _ key: String, _ icon: String, _ summary: String, _ group: String) {
        self.id = key
        self.title = title
        self.key = key
        self.icon = icon
        self.summary = summary
        self.group = group
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
                    Text(result == nil ? "No run result" : "Open engine result")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                }
                .foregroundStyle(result == nil ? .secondary : AuroraTheme.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
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
        let text = result == nil ? "waiting" : ResultTools.status(result)
        return Text(text.uppercased())
            .font(.caption2.bold())
            .foregroundStyle(result == nil ? .secondary : AuroraTheme.accent)
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
                        Text(engine.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: result == nil ? "No result" : ResultTools.status(result))
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
                        "No individual engine result yet",
                        systemImage: engine.icon,
                        description: Text("Run the canonical workflow. If the engine is governed or blocked, that state and its reason will appear here.")
                    )
                }
            }
        }
    }
}
