import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @State private var section: Section = .dashboard
    @AppStorage("aurora.engine.workspace.selected") private var selectedEngineID = "ore_intelligence"

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Command Center"
        case projects = "Input Workflow"
        case execution = "Run AURORA"
        case scenarios = "Scenarios & Optimization"
        case operations = "Operations & Digital Twin"
        case vault = "Result Vault"
        case engines = "Engine Observatory"
        case catalog = "Data & Model Catalog"
        case results = "Results Explorer"
        case balances = "Stream & Balance"
        case evidence = "Evidence & QA"
        case engineering = "Engineering Studio"
        case deliverables = "Export Center"
        case settings = "Runtime Diagnostics"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2.fill"
            case .projects: return "folder.badge.gearshape"
            case .execution: return "play.circle.fill"
            case .scenarios: return "slider.horizontal.3"
            case .operations: return "dot.radiowaves.left.and.right"
            case .vault: return "externaldrive.fill.badge.checkmark"
            case .engines: return "square.stack.3d.up.fill"
            case .catalog: return "server.rack"
            case .results: return "magnifyingglass.circle.fill"
            case .balances: return "arrow.left.arrow.right.square.fill"
            case .evidence: return "checkmark.shield.fill"
            case .engineering: return "drafting compass"
            case .deliverables: return "archivebox.fill"
            case .settings: return "gearshape.2.fill"
            }
        }

        var description: String {
            switch self {
            case .dashboard: return "Live runtime and vault posture"
            case .projects: return "Ore evidence and process route"
            case .execution: return "Preflight and canonical governed run"
            case .scenarios: return "Governed variants and run comparison"
            case .operations: return "Envelope, controls and twin state"
            case .vault: return "Recover persisted DAG and engine runs"
            case .engines: return "Live matrix and per-engine workspaces"
            case .catalog: return "Runtime databases, models and references"
            case .results: return "Search every governed output path"
            case .balances: return "Streams, conservation and closure"
            case .evidence: return "Provenance, validation and uncertainty"
            case .engineering: return "PFD, P&ID and drawings"
            case .deliverables: return "PDF, Word, Excel and bundle"
            case .settings: return "Audit, gates and backend health"
            }
        }
    }

    private var sidebarEngines: [SidebarEngineItem] {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let engineObject) = enginesValue,
              let declaredValue = engineObject["declared"],
              case .array(let declared) = declaredValue,
              !declared.isEmpty else {
            return SidebarEngineItem.fallback
        }

        var observed = Set<String>()
        if let observedValue = engineObject["observed_in_completed_jobs"], case .array(let rows) = observedValue {
            observed = Set(rows.compactMap { $0.stringValue })
        }

        let parsed = declared.compactMap { row -> SidebarEngineItem? in
            guard case .object(let object) = row,
                  let id = object["id"]?.stringValue,
                  !id.isEmpty else { return nil }
            let label = object["label"]?.stringValue
                ?? id.replacingOccurrences(of: "_", with: " ").capitalized
            return .init(id: id, title: label, observed: observed.contains(id))
        }
        return parsed.isEmpty ? SidebarEngineItem.fallback : parsed
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch section {
                case .dashboard: CommandCenterView()
                case .projects: InputWorkflowView()
                case .execution: ExecutionControlView()
                case .scenarios: ScenarioOptimizationView()
                case .operations: OperationsTwinView()
                case .vault: ResultVaultBrowserView()
                case .engines: EngineWorkspaceNavigatorView(selectedEngineID: $selectedEngineID)
                case .catalog: PlatformCatalogView()
                case .results: ResultsExplorerView()
                case .balances: ProcessBalanceView()
                case .evidence: EvidenceCenterView()
                case .engineering: EngineeringStudioView()
                case .deliverables: DeliverablesCenterView()
                case .settings: RuntimeDiagnosticsView()
                }
            }
            .background(AuroraTheme.background.ignoresSafeArea())
            .navigationTitle(section == .engines ? engineNavigationTitle : section.rawValue)
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(AuroraTheme.accent)
        .task { app.checkHealth() }
    }

    private var engineNavigationTitle: String {
        sidebarEngines.first(where: { $0.id == selectedEngineID })?.title ?? Section.engines.rawValue
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.title2)
                        .foregroundStyle(AuroraTheme.accent)
                    Text("AURORA")
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .tracking(5)
                }
                Text("MINING · PROCESS · EPC INTELLIGENCE")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                StatusBadge(text: app.connectionLabel)
            }
            .padding(18)

            List {
                SwiftUI.Section("WORKSPACE") {
                    ForEach([
                        Section.dashboard,
                        Section.projects,
                        Section.execution,
                        Section.scenarios,
                        Section.operations,
                        Section.vault,
                        Section.engines,
                        Section.catalog,
                        Section.results,
                        Section.balances,
                        Section.evidence,
                        Section.engineering,
                        Section.deliverables
                    ], id: \.id) { item in
                        navigationRow(item)
                    }
                }

                SwiftUI.Section("ENGINE WORKSPACES") {
                    ForEach(sidebarEngines) { engine in
                        engineNavigationRow(engine)
                    }
                }

                SwiftUI.Section("SYSTEM") {
                    navigationRow(.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 280)
        .background(AuroraTheme.background)
    }

    private func navigationRow(_ item: Section) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { section = item }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .frame(width: 24)
                    .foregroundStyle(section == item ? AuroraTheme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.rawValue)
                        .font(.subheadline.weight(section == item ? .semibold : .regular))
                    Text(item.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if section == item {
                    Circle().fill(AuroraTheme.accent).frame(width: 7, height: 7)
                }
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .listRowBackground(section == item ? AuroraTheme.accent.opacity(0.12) : Color.clear)
    }

    private func engineNavigationRow(_ engine: SidebarEngineItem) -> some View {
        let selected = section == .engines && selectedEngineID == engine.id
        return Button {
            selectedEngineID = engine.id
            withAnimation(.easeInOut(duration: 0.18)) { section = .engines }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: engine.icon)
                    .frame(width: 21)
                    .foregroundStyle(selected ? AuroraTheme.accent : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.title)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                    Text(engine.id)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(engine.observed ? AuroraTheme.good : (selected ? AuroraTheme.accent : Color.secondary.opacity(0.45)))
                    .frame(width: 6, height: 6)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? AuroraTheme.accent.opacity(0.12) : Color.clear)
    }
}

private struct SidebarEngineItem: Identifiable {
    let id: String
    let title: String
    let observed: Bool

    var icon: String {
        switch id {
        case "ore_intelligence": return "cube.transparent"
        case "resource_model": return "map"
        case "comminution": return "gearshape.2"
        case "classification": return "line.3.crossed.swirl.circle"
        case "flotation": return "bubbles.and.sparkles"
        case "magnetic_gravity": return "magnet"
        case "hydrometallurgy": return "drop.triangle"
        case "thermodynamics": return "flame"
        case "water_circuit": return "drop"
        case "conservation": return "arrow.triangle.2.circlepath"
        case "equipment_epc": return "wrench.and.screwdriver"
        case "economics": return "chart.line.uptrend.xyaxis"
        case "tailings": return "exclamationmark.triangle"
        case "digital_twin": return "dot.radiowaves.left.and.right"
        case "hybrid_ai": return "brain.head.profile"
        case "diagnostics": return "stethoscope"
        default: return "cpu"
        }
    }

    static let fallback: [SidebarEngineItem] = [
        .init(id: "ore_intelligence", title: "Ore Intelligence", observed: false),
        .init(id: "resource_model", title: "Resource & Mining", observed: false),
        .init(id: "comminution", title: "Comminution", observed: false),
        .init(id: "classification", title: "Classification", observed: false),
        .init(id: "flotation", title: "Flotation", observed: false),
        .init(id: "magnetic_gravity", title: "Magnetic & Gravity", observed: false),
        .init(id: "hydrometallurgy", title: "Hydrometallurgy", observed: false),
        .init(id: "thermodynamics", title: "Thermodynamics", observed: false),
        .init(id: "water_circuit", title: "Water & Recycle", observed: false),
        .init(id: "conservation", title: "Conservation & Reconciliation", observed: false),
        .init(id: "equipment_epc", title: "Equipment & EPC", observed: false),
        .init(id: "economics", title: "Economics", observed: false),
        .init(id: "tailings", title: "Tailings & ESG", observed: false),
        .init(id: "digital_twin", title: "Digital Twin", observed: false),
        .init(id: "hybrid_ai", title: "Hybrid AI & Uncertainty", observed: false),
        .init(id: "diagnostics", title: "Governance & Diagnostics", observed: false)
    ]
}

private extension AppModel {
    var connectionLabel: String {
        switch connection {
        case .unknown: return "Runtime unknown"
        case .checking: return "Runtime checking"
        case .online(_): return "Runtime online"
        case .offline(_): return "Runtime offline"
        }
    }
}
