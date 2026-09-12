import SwiftUI
import SwiftData
import Charts

struct OperationsTwinView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedProjectID: UUID?

    private var project: AuroraProject? {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) {
            return selected
        }
        return projects.first
    }

    private var twinResult: JSONValue? {
        guard let active = app.activeResult else { return nil }
        if let twin = active.recursiveFind("digital_twin") { return twin }
        if active.firstString(["active_engine"]) == "digital_twin" {
            return active.recursiveFind("result") ?? active
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                executionControl
                authorityStrip
                performanceSurface
                operatingEnvelope
                controlActions
                connectivitySurface
                rawTwinLedger
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
                        .fill(AuroraTheme.accent.opacity(0.16))
                        .frame(width: 66, height: 66)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2.bold())
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Operations & Digital Twin")
                        .font(.largeTitle.bold())
                    Text("Operating envelope · governed setpoints · diagnostics · telemetry posture")
                        .foregroundStyle(.secondary)
                    Text("This surface does not invent live plant connectivity. It exposes only the state, constraints and recommendations actually returned by AURORA's governed Digital Twin execution.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: twinResult == nil ? "No twin result" : ResultTools.status(twinResult))
            }
        }
    }

    private var executionControl: some View {
        AuroraCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Digital Twin Execution").font(.headline)
                    Text("Runs the official digital_twin engine against the selected project basis using canonical_mobile_execute.")
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
                        guard let project else { return }
                        app.run(project: project, context: context, module: "digital_twin")
                    } label: {
                        if app.isRunning {
                            ProgressView()
                            Text("Running")
                        } else {
                            Label("RUN DIGITAL TWIN", systemImage: "bolt.horizontal.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.isRunning || project == nil)
                }
            }
        }
    }

    private var authorityStrip: some View {
        AuroraCard {
            HStack(spacing: 16) {
                authorityMetric("Contract", digitalTwinDeclared ? "Declared" : "Unresolved", "checkmark.seal")
                authorityMetric("Observed", digitalTwinObserved ? "Observed" : "Awaiting run", "eye")
                authorityMetric("Result origin", app.activeResultOrigin, "point.3.connected.trianglepath.dotted")
                authorityMetric("Persistence", app.vaultStatus == nil ? "Unchecked" : "Result Vault", "externaldrive.fill")
            }
        }
    }

    @ViewBuilder
    private var performanceSurface: some View {
        if let twinResult {
            let kpis = ResultTools.kpis(twinResult)
            if !kpis.isEmpty {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reported Operating KPIs").font(.headline)
                        Chart(kpis) { item in
                            BarMark(
                                x: .value("KPI", item.name),
                                y: .value("Value", item.value)
                            )
                        }
                        .frame(height: 230)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
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
                }
            }
        }
    }

    private var operatingEnvelope: some View {
        reportedSurface(
            title: "Operating Envelope & Constraints",
            subtitle: "Feasible region, operating limits and constraint states reported by the runtime.",
            icon: "scope",
            keys: ["operating_envelope", "operating_limits", "feasible_region", "constraints", "constraint_state"]
        )
    }

    private var controlActions: some View {
        reportedSurface(
            title: "Setpoints & Recommendations",
            subtitle: "Recommended actions remain advisory unless the returned runtime evidence explicitly marks them otherwise.",
            icon: "dial.medium",
            keys: ["setpoints", "recommended_setpoints", "recommendations", "actions", "control_actions", "optimization_result"]
        )
    }

    private var connectivitySurface: some View {
        reportedSurface(
            title: "Industrial Connectivity Posture",
            subtitle: "Live telemetry, historian and plant-system links are shown only when the runtime reports them.",
            icon: "network",
            keys: ["telemetry", "opc_ua", "opcua", "historian", "pi_system", "lims", "fms", "connectivity"]
        )
    }

    @ViewBuilder
    private var rawTwinLedger: some View {
        if let twinResult {
            AuroraCard {
                DisclosureGroup("Digital Twin scalar ledger") {
                    ForEach(Array(twinResult.flattenedScalars(limit: 600).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.0)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(row.1)
                                .font(.caption2.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func reportedSurface(title: String, subtitle: String, icon: String, keys: [String]) -> some View {
        let reported = firstReported(keys)
        return AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: reported == nil ? "Not reported" : "Reported")
                }

                if let reported {
                    let rows = reported.flattenedScalars(limit: 90)
                    if rows.isEmpty, let scalar = reported.stringValue {
                        Text(scalar).font(.caption.monospaced())
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 8)], spacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(row.0)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text(row.1)
                                        .font(.caption2.monospaced())
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(8)
                                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                } else {
                    Text("No value from this category exists in the active Digital Twin result. The application leaves it unresolved rather than synthesizing a plant state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func firstReported(_ keys: [String]) -> JSONValue? {
        guard let twinResult else { return nil }
        for key in keys {
            if let value = twinResult.recursiveFind(key) { return value }
        }
        return nil
    }

    private var digitalTwinDeclared: Bool {
        guard let audit = app.runtimeAudit,
              let declared = audit.recursiveFind("declared"),
              case .array(let entries) = declared else { return false }
        return entries.contains { $0.firstString(["id", "engine_id"]) == "digital_twin" }
    }

    private var digitalTwinObserved: Bool {
        guard let audit = app.runtimeAudit,
              let observed = audit.recursiveFind("observed_in_completed_jobs"),
              case .array(let entries) = observed else { return false }
        return entries.contains { $0.stringValue == "digital_twin" }
    }

    private func authorityMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
            Text(value).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.75)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
