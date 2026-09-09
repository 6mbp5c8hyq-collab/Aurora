import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @State private var section: Section = .dashboard

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case projects = "Projects"
        case execution = "Execution"
        case engineering = "Engineering"
        case deliverables = "Deliverables"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .projects: return "folder"
            case .execution: return "bolt.horizontal.circle"
            case .engineering: return "wrench.and.screwdriver"
            case .deliverables: return "doc.richtext"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AURORA")
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .tracking(6)
                    Text("MINING · PROCESS · EPC INTELLIGENCE")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(18)

                List {
                    ForEach(Section.allCases) { item in
                        Button {
                            section = item
                        } label: {
                            Label(item.rawValue, systemImage: item.icon)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(AuroraTheme.background)
        } detail: {
            Group {
                switch section {
                case .dashboard: DashboardView()
                case .projects: ProjectsView()
                case .execution: ExecutionView()
                case .engineering: EngineeringView()
                case .deliverables: DeliverablesView()
                case .settings: SettingsView()
                }
            }
            .background(AuroraTheme.background.ignoresSafeArea())
        }
        .tint(AuroraTheme.accent)
        .task { app.checkHealth() }
    }
}
