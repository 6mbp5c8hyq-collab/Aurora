import SwiftUI

struct RuntimeDiagnosticsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var backendText = AppConfig.backend.absoluteString
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                endpointCard
                readinessCard
                vaultCard
                recentJobsCard
                rawAuditCard
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .refreshable {
            app.checkHealth()
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
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Runtime Diagnostics").font(.largeTitle.bold())
                    Text("Health · dependency gates · canonical authority · Result Vault")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Direct view of the backend health/audit contracts used by the native application.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                connectionBadge
            }
        }
    }

    private var endpointCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Backend Endpoint").font(.headline)
                    Spacer()
                    Text("HTTPS REQUIRED").font(.caption2.bold()).foregroundStyle(AuroraTheme.gold)
                }
                TextField("https://…", text: $backendText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        do {
                            try AppConfig.saveBackend(backendText)
                            backendText = AppConfig.backend.absoluteString
                            saveMessage = "Backend saved."
                            app.checkHealth()
                        } catch {
                            saveMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Save & Reconnect", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        backendText = AppConfig.defaultBackend.absoluteString
                    } label: {
                        Label("Use default", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                    if let saveMessage {
                        Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var readinessCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Canonical Runtime Readiness").font(.headline)
                        Text("Fields are read directly from /api/audit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: readinessLabel)
                }

                let priorities = [
                    "source_ok", "scientific_ready", "direct_ready", "canonical_entrypoint",
                    "dependency_gate.core_engine_native_ready", "dependency_gate.all_direct_dependencies_exact",
                    "runtime_state", "payload_integrity", "registry_drift", "active_duplicate_authority"
                ]
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 9)], spacing: 9) {
                    ForEach(priorities, id: \.self) { key in
                        diagnosticTile(key: key, value: findAuditValue(key))
                    }
                }
            }
        }
    }

    private var vaultCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Result Vault").font(.headline)
                        Text("Persistent runtime evidence and run storage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.vaultStatus == nil ? "Unavailable" : "Connected")
                }

                if let vault = app.vaultStatus {
                    let rows = vault.flattenedScalars(limit: 30)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 8)], spacing: 8) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            diagnosticTile(key: row.0, value: row.1)
                        }
                    }
                } else {
                    Text("No vault status was returned by the backend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recentJobsCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Canonical Jobs").font(.headline)
                    Spacer()
                    Text("\(app.serverJobs.count) stored")
                        .font(.caption.monospaced())
                        .foregroundStyle(AuroraTheme.gold)
                }

                if app.serverJobs.isEmpty {
                    Text("No recent jobs were returned by /api/jobs/recent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(app.serverJobs.prefix(12).enumerated()), id: \.offset) { _, job in
                        HStack(spacing: 10) {
                            StatusBadge(text: job.firstString(["status", "state"]) ?? "unknown")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.firstString(["requested_module", "operation"]) ?? "AURORA job")
                                    .font(.caption.bold())
                                Text(job.firstString(["job_id", "id"]) ?? "no id")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(job.firstString(["operation"]) ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Divider().opacity(0.12)
                    }
                }
            }
        }
    }

    private var rawAuditCard: some View {
        AuroraCard {
            DisclosureGroup("Full runtime audit ledger") {
                if let audit = app.runtimeAudit {
                    ForEach(Array(audit.flattenedScalars(limit: 400).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(row.1).font(.caption2.monospaced()).multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 3)
                    }
                } else {
                    Text("Audit not available.").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch app.connection {
        case .unknown: StatusBadge(text: "Unknown")
        case .checking: StatusBadge(text: "Checking")
        case .online: StatusBadge(text: "Runtime online")
        case .offline: StatusBadge(text: "Runtime offline")
        }
    }

    private var readinessLabel: String {
        guard let audit = app.runtimeAudit else { return "Audit unavailable" }
        let direct = audit.firstString(["direct_ready", "all_direct_dependencies_exact"])
        let scientific = audit.firstString(["scientific_ready", "core_engine_native_ready"])
        if direct == "true" { return "Direct ready" }
        if scientific == "true" { return "Scientific ready" }
        return audit.firstString(["status", "state"]) ?? "Reported"
    }

    private func findAuditValue(_ path: String) -> String {
        guard let audit = app.runtimeAudit else { return "—" }
        if let direct = audit.recursiveFind(path)?.stringValue { return direct }
        let last = path.split(separator: ".").last.map(String.init) ?? path
        return audit.recursiveFind(last)?.stringValue ?? "—"
    }

    private func diagnosticTile(key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon(value))
                .foregroundStyle(statusColor(value))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(key).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                Text(value).font(.caption.bold()).lineLimit(3)
            }
            Spacer(minLength: 4)
        }
        .padding(9)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusIcon(_ value: String) -> String {
        let lower = value.lowercased()
        if ["true", "ready", "pass", "success", "ok", "0"].contains(where: { lower == $0 || lower.contains($0) }) {
            return "checkmark.circle.fill"
        }
        if lower == "—" || lower.contains("unknown") || lower.contains("unavailable") { return "minus.circle.fill" }
        if lower.contains("false") || lower.contains("fail") || lower.contains("error") || lower.contains("blocked") {
            return "xmark.octagon.fill"
        }
        return "info.circle.fill"
    }

    private func statusColor(_ value: String) -> Color {
        let icon = statusIcon(value)
        if icon == "checkmark.circle.fill" { return AuroraTheme.good }
        if icon == "xmark.octagon.fill" { return AuroraTheme.bad }
        if icon == "minus.circle.fill" { return .secondary }
        return AuroraTheme.warn
    }
}
