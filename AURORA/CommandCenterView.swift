import SwiftUI
import SwiftData
import Charts

struct CommandCenterView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @Query(sort: \RunRecord.updatedAt, order: .reverse) private var localRuns: [RunRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metricGrid
                runtimeSpine
                latestResult
                serverRuns
                localHistory
            }
            .padding(22)
        }
        .refreshable {
            app.checkHealth()
            await app.refreshServerState(recoverLatest: false)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Industrial Command Center")
                    .font(.largeTitle.bold())
                Text("Canonical runtime, governed execution, engineering outputs and persisted evidence")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            connectionBadge
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
            metric("Projects", "\(projects.count)", "folder.fill")
            metric("Local Runs", "\(localRuns.count)", "iphone")
            metric("Server DAG Runs", "\(app.serverDagRuns.count)", "point.3.connected.trianglepath.dotted")
            metric("Active State", app.runStatus, "waveform.path.ecg")
        }
    }

    private var runtimeSpine: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Industrial Runtime Spine").font(.headline)
                        Text("Railway runtime + DAG Orchestrator + Result Vault")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    vaultBadge
                }

                HStack(spacing: 0) {
                    spineNode("Runtime", runtimeOnline, "server.rack")
                    connector
                    spineNode("DAG", !app.serverDagRuns.isEmpty || app.activeResult != nil, "point.3.connected.trianglepath.dotted")
                    connector
                    spineNode("Vault", app.vaultStatus != nil, "externaldrive.fill.badge.checkmark")
                    connector
                    spineNode("Native UI", true, "iphone")
                }

                if let vault = app.vaultStatus {
                    let rows = vault.flattenedScalars(limit: 14)
                    if !rows.isEmpty {
                        Divider().opacity(0.15)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(row.0)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(row.1)
                                        .font(.caption2.monospaced())
                                        .multilineTextAlignment(.trailing)
                                        .lineLimit(2)
                                }
                                .padding(8)
                                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var latestResult: some View {
        if let result = app.activeResult {
            AuroraCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Latest Governed Result").font(.headline)
                            if let id = app.activeJobID {
                                Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        StatusBadge(text: ResultTools.status(result))
                    }

                    if let ceiling = ResultTools.ceiling(result) {
                        LabeledContent("Claim ceiling", value: ceiling)
                            .font(.caption)
                    }

                    let kpis = ResultTools.kpis(result)
                    if !kpis.isEmpty {
                        Chart(kpis) { item in
                            BarMark(
                                x: .value("KPI", item.name),
                                y: .value("Value", item.value)
                            )
                        }
                        .frame(height: 220)
                    }

                    let stages = ResultTools.stages(result)
                    if !stages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(stages) { stage in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(stage.name).font(.caption.bold()).lineLimit(1)
                                        Text(stage.status).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .frame(width: 155, alignment: .leading)
                                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                }
            }
        } else {
            AuroraCard {
                ContentUnavailableView(
                    "No governed result loaded",
                    systemImage: "waveform.path.ecg",
                    description: Text("Run a project or pull to refresh persisted server state.")
                )
            }
        }
    }

    private var serverRuns: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Result Vault · Recent DAG Runs").font(.headline)
                    Spacer()
                    Text("Server persisted").font(.caption).foregroundStyle(AuroraTheme.gold)
                }

                if app.serverDagRuns.isEmpty {
                    Text("No persisted DAG runs were returned by the server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(app.serverDagRuns.prefix(8).enumerated()), id: \.offset) { _, run in
                        serverRunRow(run)
                        Divider().opacity(0.12)
                    }
                }
            }
        }
    }

    private var localHistory: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Device Execution Ledger").font(.headline)
                    Spacer()
                    Text("SwiftData").font(.caption).foregroundStyle(.secondary)
                }
                if localRuns.isEmpty {
                    Text("No device-side runs yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(localRuns.prefix(8)) { run in
                        HStack(spacing: 10) {
                            StatusBadge(text: run.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                if let id = run.jobID {
                                    Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if run.errorText != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AuroraTheme.warn)
                            }
                        }
                    }
                }
            }
        }
    }

    private var runtimeOnline: Bool {
        if case .online = app.connection { return true }
        return false
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch app.connection {
        case .unknown: StatusBadge(text: "Runtime unknown")
        case .checking: StatusBadge(text: "Checking runtime")
        case .online: StatusBadge(text: "Runtime online")
        case .offline: StatusBadge(text: "Runtime offline")
        }
    }

    private var vaultBadge: some View {
        StatusBadge(text: app.vaultStatus == nil ? "Vault unchecked" : "Vault connected")
    }

    private var connector: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
    }

    private func spineNode(_ title: String, _ ready: Bool, _ icon: String) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill((ready ? AuroraTheme.good : AuroraTheme.warn).opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .foregroundStyle(ready ? AuroraTheme.good : AuroraTheme.warn)
            }
            Text(title).font(.caption.bold()).lineLimit(1)
            Text(ready ? "READY" : "WAIT")
                .font(.caption2.bold())
                .foregroundStyle(ready ? AuroraTheme.good : AuroraTheme.warn)
        }
        .frame(width: 92)
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func serverRunRow(_ run: JSONValue) -> some View {
        let status = run.firstString(["status", "state"]) ?? "unknown"
        let id = run.firstString(["run_id", "runId", "id"]) ?? "unidentified"
        let stage = run.firstString(["current_stage", "stage", "active_stage"])
        return HStack(spacing: 10) {
            StatusBadge(text: status)
            VStack(alignment: .leading, spacing: 2) {
                Text(id).font(.caption.monospaced()).lineLimit(1)
                if let stage {
                    Text(stage.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "externaldrive.badge.checkmark")
                .foregroundStyle(AuroraTheme.accent)
        }
    }
}
