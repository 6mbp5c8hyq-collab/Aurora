import SwiftUI

struct ResultVaultBrowserView: View {
    @EnvironmentObject private var app: AppModel
    @State private var tab: VaultTab = .dag
    @State private var query = ""

    enum VaultTab: String, CaseIterable, Identifiable {
        case dag = "DAG Runs"
        case jobs = "Engine Jobs"
        var id: String { rawValue }
    }

    private var dagRuns: [JSONValue] {
        filter(app.serverDagRuns)
    }

    private var jobs: [JSONValue] {
        filter(app.serverJobs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                controls
                activeResultCard
                browser
                if let error = app.lastError { errorCard(error) }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .refreshable {
            await app.refreshServerState()
        }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AuroraTheme.accent.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "externaldrive.fill.badge.checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Result Vault Browser").font(.largeTitle.bold())
                    Text("Persisted DAG runs · governed engine jobs · reproducible result recovery")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Open any persisted server execution and make it the active result for Engine Observatory, Stream & Balance, Engineering Studio and Export Center.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.vaultStatus == nil ? "Vault unavailable" : "Vault connected")
            }
        }
    }

    private var controls: some View {
        AuroraCard {
            HStack(spacing: 14) {
                Picker("Vault collection", selection: $tab) {
                    ForEach(VaultTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search ID, module, operation or status", text: $query)
                        .textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))

                Button {
                    Task { await app.refreshServerState() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var activeResultCard: some View {
        AuroraCard {
            HStack(spacing: 12) {
                Image(systemName: app.activeResult == nil ? "circle.dashed" : "scope")
                    .font(.title3.bold())
                    .foregroundStyle(app.activeResult == nil ? .secondary : AuroraTheme.good)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Active Result").font(.headline)
                    Text(app.activeResultOrigin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let id = app.activeJobID {
                        Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                StatusBadge(text: app.runStatus)
            }
        }
    }

    @ViewBuilder
    private var browser: some View {
        switch tab {
        case .dag:
            vaultCollection(
                title: "Persisted DAG Runs",
                subtitle: "Full project orchestration results",
                rows: dagRuns,
                kind: .dag
            )
        case .jobs:
            vaultCollection(
                title: "Persisted Engine Jobs",
                subtitle: "Individual governed engine executions",
                rows: jobs,
                kind: .job
            )
        }
    }

    private enum RowKind { case dag, job }

    private func vaultCollection(title: String, subtitle: String, rows: [JSONValue], kind: RowKind) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(rows.count) records")
                        .font(.caption.monospaced())
                        .foregroundStyle(AuroraTheme.gold)
                }

                if rows.isEmpty {
                    ContentUnavailableView(
                        "No matching records",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text(query.isEmpty ? "No persisted executions were returned by the server." : "No persisted execution matches the current search.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        vaultRow(row, kind: kind)
                        Divider().opacity(0.12)
                    }
                }
            }
        }
    }

    private func vaultRow(_ row: JSONValue, kind: RowKind) -> some View {
        let id = rowID(row, kind: kind)
        let status = row.firstString(["status", "state", "platform_status"]) ?? "unknown"
        let module = row.firstString(["requested_module", "module", "operation"])
        let currentStage = row.firstString(["current_stage", "active_stage", "stage"])
        let active = app.activeJobID == id

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind == .dag ? "point.3.connected.trianglepath.dotted" : "cpu")
                .font(.title3)
                .foregroundStyle(active ? AuroraTheme.gold : AuroraTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(id).font(.caption.monospaced()).lineLimit(1)
                    if active {
                        Text("ACTIVE")
                            .font(.caption2.bold())
                            .foregroundStyle(AuroraTheme.background)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AuroraTheme.gold, in: Capsule())
                    }
                }
                HStack(spacing: 10) {
                    if let module {
                        Label(module, systemImage: "square.stack.3d.up")
                    }
                    if let currentStage {
                        Label(currentStage.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "arrow.right.circle")
                    }
                    if let date = dateText(row) {
                        Label(date, systemImage: "clock")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()
            StatusBadge(text: status)

            Button {
                if kind == .dag { app.loadStoredDagRun(id: id) }
                else { app.loadStoredJob(id: id) }
            } label: {
                if app.isLoadingStoredRun && !active {
                    ProgressView()
                } else {
                    Label(active ? "Loaded" : "Open", systemImage: active ? "checkmark.circle.fill" : "arrow.down.doc.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(id == "unidentified" || app.isLoadingStoredRun || active)
        }
        .padding(.vertical, 7)
    }

    private func filter(_ source: [JSONValue]) -> [JSONValue] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return source }
        return source.filter { value in
            value.prettyString().localizedCaseInsensitiveContains(clean)
        }
    }

    private func rowID(_ row: JSONValue, kind: RowKind) -> String {
        switch kind {
        case .dag: return row.firstString(["run_id", "runId", "id"]) ?? "unidentified"
        case .job: return row.firstString(["job_id", "jobId", "id"]) ?? "unidentified"
        }
    }

    private func dateText(_ row: JSONValue) -> String? {
        for key in ["finished_at", "updated_at", "created_at", "started_at"] {
            guard let value = row.recursiveFind(key) else { continue }
            switch value {
            case .number(let epoch):
                guard epoch > 1_000_000_000 else { continue }
                return Date(timeIntervalSince1970: epoch).formatted(date: .abbreviated, time: .shortened)
            case .string(let text):
                if let epoch = Double(text), epoch > 1_000_000_000 {
                    return Date(timeIntervalSince1970: epoch).formatted(date: .abbreviated, time: .shortened)
                }
                if !text.isEmpty { return text }
            default:
                continue
            }
        }
        return nil
    }

    private func errorCard(_ error: String) -> some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vault operation error").font(.headline)
                    Text(error).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
