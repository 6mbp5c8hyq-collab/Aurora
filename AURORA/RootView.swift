import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @State private var section: Section = .dashboard

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Command Center"
        case projects = "Input Workflow"
        case execution = "Run AURORA"
        case vault = "Result Vault"
        case engines = "Engine Observatory"
        case balances = "Stream & Balance"
        case engineering = "Engineering Studio"
        case deliverables = "Export Center"
        case settings = "Runtime Diagnostics"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2.fill"
            case .projects: return "folder.badge.gearshape"
            case .execution: return "play.circle.fill"
            case .vault: return "externaldrive.fill.badge.checkmark"
            case .engines: return "square.stack.3d.up.fill"
            case .balances: return "arrow.left.arrow.right.square.fill"
            case .engineering: return "drafting compass"
            case .deliverables: return "archivebox.fill"
            case .settings: return "gearshape.2.fill"
            }
        }

        var description: String {
            switch self {
            case .dashboard: return "Live runtime and vault posture"
            case .projects: return "Ore evidence and process route"
            case .execution: return "Canonical governed run"
            case .vault: return "Recover persisted DAG and engine runs"
            case .engines: return "Run and inspect every engine"
            case .balances: return "Streams, conservation and closure"
            case .engineering: return "PFD, P&ID and drawings"
            case .deliverables: return "PDF, Word, Excel and bundle"
            case .settings: return "Audit, gates and backend health"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch section {
                case .dashboard: CommandCenterView()
                case .projects: InputWorkflowView()
                case .execution: ExecutionView()
                case .vault: ResultVaultBrowserView()
                case .engines: EngineExplorerView()
                case .balances: ProcessBalanceView()
                case .engineering: EngineeringStudioView()
                case .deliverables: DeliverablesCenterView()
                case .settings: RuntimeDiagnosticsView()
                }
            }
            .background(AuroraTheme.background.ignoresSafeArea())
            .navigationTitle(section.rawValue)
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(AuroraTheme.accent)
        .task { app.checkHealth() }
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
                        Section.vault,
                        Section.engines,
                        Section.balances,
                        Section.engineering,
                        Section.deliverables
                    ], id: \.id) { item in
                        navigationRow(item)
                    }
                }
                SwiftUI.Section("SYSTEM") {
                    navigationRow(.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 260)
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
