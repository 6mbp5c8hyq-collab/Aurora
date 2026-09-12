import SwiftUI
import SwiftData

struct ExecutionControlView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedProjectID: UUID?

    private var project: AuroraProject? {
        if let selectedProjectID, let selected = projects.first(where: { $0.id == selectedProjectID }) { return selected }
        return projects.first
    }

    private var stages: [EngineStage] {
        ResultTools.stages(app.activeResult)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                projectBasis
                preflight
                executionControls
                liveTrace
                resultSummary
                if let error = app.lastError { errorCard(error) }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AuroraTheme.accent.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Canonical Execution Control").font(.largeTitle.bold())
                    Text("Preflight validation → governed DAG → persisted result")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Validation blocks remain visible. Full execution uses the canonical AURORA DAG and stores the result through the server-side Result Vault.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.runStatus)
            }
        }
    }

    private var projectBasis: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Execution Basis").font(.headline)
                    Spacer()
                    if projects.isEmpty { StatusBadge(text: "No project") }
                }

                if projects.isEmpty {
                    ContentUnavailableView(
                        "No project available",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a project in Input Workflow before running AURORA.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    Picker(
                        "Project",
                        selection: Binding<UUID?>(
                            get: { selectedProjectID ?? projects.first?.id },
                            set: { selectedProjectID = $0; app.validationResult = nil }
                        )
                    ) {
                        ForEach(projects) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                    .pickerStyle(.menu)

                    if let project {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                            basisTile("Ore family", project.declaredFamily, "mountain.2.fill")
                            basisTile("Feed", "\(project.feedTPH.formatted()) t/h", "arrow.right.circle.fill")
                            basisTile("Target", project.targetComponent, "scope")
                            basisTile("Target grade", "\(project.targetGrade.formatted())%", "gauge.with.dots.needle.50percent")
                        }
                    }
                }
            }
        }
    }

    private var preflight: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Preflight Validation").font(.headline)
                        Text("Server-side validation without starting a run")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if app.isValidating { ProgressView() }
                    else { StatusBadge(text: validationLabel) }
                }

                HStack {
                    Button {
                        guard let project else { return }
                        app.validate(project: project)
                    } label: {
                        Label("VALIDATE PROJECT", systemImage: "checkmark.shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(project == nil || app.isValidating || app.isRunning)

                    Text("Checks canonical runtime readiness, dependency gates and project payload admission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let validation = app.validationResult {
                    let rows = validation.flattenedScalars(limit: 80)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 8)], spacing: 8) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 8) {
                                Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text(row.1).font(.caption2.monospaced()).multilineTextAlignment(.trailing)
                            }
                            .padding(8)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
    }

    private var executionControls: some View {
        AuroraCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full AURORA DAG").font(.headline)
                    Text("Input admission → ore diagnosis → process graph → engine fan-out → Result Vault")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard let project else { return }
                    app.run(project: project, context: context)
                } label: {
                    if app.isRunning {
                        ProgressView()
                        Text("RUNNING AURORA")
                    } else {
                        Label("RUN FULL AURORA", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(project == nil || app.isRunning || app.isValidating)
            }
        }
    }

    private var liveTrace: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live DAG Trace").font(.headline)
                        Text(app.activeResultOrigin).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let id = app.activeJobID {
                        Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                if stages.isEmpty {
                    ContentUnavailableView(
                        "No execution trace loaded",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Run AURORA or load a persisted DAG result from Result Vault.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(stageColor(stage.status).opacity(0.15))
                                    .frame(width: 34, height: 34)
                                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(stageColor(stage.status))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stage.name).font(.subheadline.bold())
                                Text(stage.status).font(.caption).foregroundStyle(stageColor(stage.status))
                                if let detail = stage.detail {
                                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        if index < stages.count - 1 { Divider().opacity(0.12) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSummary: some View {
        if let result = app.activeResult {
            AuroraCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Active Result Summary").font(.headline)
                        Spacer()
                        StatusBadge(text: ResultTools.status(result))
                    }
                    let kpis = ResultTools.kpis(result)
                    if kpis.isEmpty {
                        Text("No recognized KPI fields were returned in the active result.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                            ForEach(kpis) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.caption).foregroundStyle(.secondary)
                                    Text("\(item.value.formatted(.number.precision(.fractionLength(0...3)))) \(item.unit)")
                                        .font(.title3.bold())
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
    }

    private var validationLabel: String {
        guard let validation = app.validationResult else { return "Not validated" }
        return validation.firstString(["status", "validation_status", "state", "ok"]) ?? "Reported"
    }

    private func basisTile(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(AuroraTheme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.subheadline.bold()).lineLimit(1)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stageColor(_ status: String) -> Color {
        let lower = status.lowercased()
        if lower.contains("fail") || lower.contains("error") || lower.contains("blocked") { return AuroraTheme.bad }
        if lower.contains("running") || lower.contains("queue") || lower.contains("pending") { return AuroraTheme.warn }
        if lower.contains("complete") || lower.contains("success") || lower.contains("pass") { return AuroraTheme.good }
        return AuroraTheme.accent
    }

    private func errorCard(_ error: String) -> some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Execution / validation error").font(.headline)
                    Text(error).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
