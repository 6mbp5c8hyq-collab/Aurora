import SwiftUI
import SwiftData

struct GovernedCommandCenterView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @Query(sort: \RunRecord.updatedAt, order: .reverse) private var localRuns: [RunRecord]

    private var readiness: CommandReadiness {
        CommandReadiness.scan(result: app.activeResult, engineIDs: declaredEngineIDs)
    }

    private var declaredEngineIDs: [String] {
        guard let audit = app.runtimeAudit,
              let engines = audit.recursiveFind("engines"),
              case .object(let object) = engines,
              let declared = object["declared"],
              case .array(let rows) = declared else { return CommandReadiness.engineFallback }
        let ids = rows.compactMap { row -> String? in
            if case .object(let object) = row { return object["id"]?.stringValue }
            return row.stringValue
        }
        return ids.isEmpty ? CommandReadiness.engineFallback : ids
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metricGrid
                runtimeSpine
                scientificReadiness
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
                Text("Industrial Command Center").font(.largeTitle.bold())
                Text("Canonical runtime · governed execution · evidence posture · engineering outputs")
                    .foregroundStyle(AuroraTheme.accent)
                Text("Readiness indicators below report presence of returned evidence only. They are not a bankability score, validation grade or substitute for external engineering review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            connectionBadge
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
            metric("Projects", "\(projects.count)", "folder.fill")
            metric("Local runs", "\(localRuns.count)", "iphone")
            metric("Server DAG runs", "\(app.serverDagRuns.count)", "point.3.connected.trianglepath.dotted")
            metric("Active state", app.runStatus, "waveform.path.ecg")
            metric("Returned engines", "\(readiness.returnedEngines)/\(declaredEngineIDs.count)", "cpu.fill")
            metric("Claim ceiling", ResultTools.ceiling(app.activeResult) ?? "Not reported", "gauge.with.dots.needle.67percent")
        }
    }

    private var runtimeSpine: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Industrial Runtime Spine").font(.headline)
                        Text("Railway runtime + DAG Orchestrator + Result Vault + Native UI")
                            .font(.caption).foregroundStyle(.secondary)
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
                    let rows = vault.flattenedScalars(limit: 12)
                    if !rows.isEmpty {
                        Divider().opacity(0.15)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(row.1).font(.caption2.monospaced()).multilineTextAlignment(.trailing).lineLimit(2)
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

    private var scientificReadiness: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active Result Evidence Presence").font(.headline)
                        Text("Recognized path presence in the active result; no pass/fail inference from presence alone")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("PRESENCE ≠ AUTHORITY").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 9)], spacing: 9) {
                    readinessCard("Engine payloads", readiness.returnedEngines > 0, "\(readiness.returnedEngines)/\(declaredEngineIDs.count) returned", "cpu.fill")
                    readinessCard("Validation paths", readiness.validationPaths > 0, "\(readiness.validationPaths) returned", "checkmark.seal.fill")
                    readinessCard("Uncertainty paths", readiness.uncertaintyPaths > 0, "\(readiness.uncertaintyPaths) returned", "plusminus.circle.fill")
                    readinessCard("OOD / applicability", readiness.domainPaths > 0, "\(readiness.domainPaths) returned", "scope")
                    readinessCard("Benchmark / external", readiness.benchmarkPaths > 0, "\(readiness.benchmarkPaths) returned", "arrow.triangle.2.circlepath")
                    readinessCard("Provenance / lineage", readiness.provenancePaths > 0, "\(readiness.provenancePaths) returned", "link")
                    readinessCard("Balance objects", readiness.balancePaths > 0, "\(readiness.balancePaths) paths", "scale.3d")
                    readinessCard("Engineering refs", readiness.engineeringReferences > 0, "\(readiness.engineeringReferences) returned", "drafting compass")
                }

                Text("A missing item remains a visible evidence gap. A present item should be inspected in Evidence & QA, Stream & Balance or Engineering Studio before any stronger claim is made.")
                    .font(.caption2).foregroundStyle(.secondary)
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
                            if let id = app.activeJobID { Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        StatusBadge(text: ResultTools.status(result))
                    }

                    let kpis = ResultTools.kpis(result)
                    if !kpis.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Recognized KPIs · as returned").font(.subheadline.bold())
                                Spacer()
                                Text("NO CROSS-UNIT CHART").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                                ForEach(kpis) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                        Text(String(format: "%.6g", item.value)).font(.headline.monospaced()).textSelection(.enabled)
                                    }
                                    .padding(9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            Text("KPIs are intentionally displayed as separate values because their engineering units and physical meaning may differ.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    let stages = ResultTools.stages(result)
                    if !stages.isEmpty {
                        Divider().opacity(0.12)
                        Text("Execution stages").font(.subheadline.bold())
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
                ContentUnavailableView("No governed result loaded", systemImage: "waveform.path.ecg", description: Text("Run a project or recover a persisted result from Result Vault."))
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
                    Text("No persisted DAG runs were returned by the server.").font(.caption).foregroundStyle(.secondary)
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
                                Text(run.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                if let id = run.jobID { Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer()
                            if run.errorText != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.warn) }
                        }
                    }
                }
            }
        }
    }

    private var runtimeOnline: Bool { if case .online = app.connection { return true }; return false }

    @ViewBuilder
    private var connectionBadge: some View {
        switch app.connection {
        case .unknown: StatusBadge(text: "Runtime unknown")
        case .checking: StatusBadge(text: "Checking runtime")
        case .online: StatusBadge(text: "Runtime online")
        case .offline: StatusBadge(text: "Runtime offline")
        }
    }

    private var vaultBadge: some View { StatusBadge(text: app.vaultStatus == nil ? "Vault unchecked" : "Vault connected") }

    private var connector: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
    }

    private func spineNode(_ title: String, _ ready: Bool, _ icon: String) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill((ready ? AuroraTheme.good : AuroraTheme.warn).opacity(0.14)).frame(width: 42, height: 42)
                Image(systemName: icon).foregroundStyle(ready ? AuroraTheme.good : AuroraTheme.warn)
            }
            Text(title).font(.caption.bold()).lineLimit(1)
            Text(ready ? "READY" : "WAIT").font(.caption2.bold()).foregroundStyle(ready ? AuroraTheme.good : AuroraTheme.warn)
        }
        .frame(width: 92)
    }

    private func readinessCard(_ title: String, _ present: Bool, _ detail: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill((present ? AuroraTheme.good : Color.secondary).opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon).foregroundStyle(present ? AuroraTheme.good : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(detail).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: present ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(present ? AuroraTheme.good : .secondary)
        }
        .padding(9)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.66)
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
                if let stage { Text(stage.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "externaldrive.badge.checkmark").foregroundStyle(AuroraTheme.accent)
        }
    }
}

private struct CommandReadiness {
    let returnedEngines: Int
    let validationPaths: Int
    let uncertaintyPaths: Int
    let domainPaths: Int
    let benchmarkPaths: Int
    let provenancePaths: Int
    let balancePaths: Int
    let engineeringReferences: Int

    static let engineFallback = [
        "ore_intelligence", "resource_model", "comminution", "classification", "flotation",
        "magnetic_gravity", "hydrometallurgy", "thermodynamics", "water_circuit", "conservation",
        "equipment_epc", "economics", "tailings", "digital_twin", "hybrid_ai", "diagnostics"
    ]

    static func scan(result: JSONValue?, engineIDs: [String]) -> CommandReadiness {
        guard let result else { return CommandReadiness(returnedEngines: 0, validationPaths: 0, uncertaintyPaths: 0, domainPaths: 0, benchmarkPaths: 0, provenancePaths: 0, balancePaths: 0, engineeringReferences: 0) }
        let rows = result.flattenedScalars(limit: 12000)
        let returned = engineIDs.filter { id in
            result.recursiveFind(id) != nil || result.recursiveFind(id.replacingOccurrences(of: "_", with: "")) != nil
        }.count
        var validation = 0, uncertainty = 0, domain = 0, benchmark = 0, provenance = 0, balance = 0, engineering = 0
        let engineeringExt = [".pdf", ".svg", ".dxf", ".dwg", ".ifc", ".step", ".stp", ".iges", ".igs"]
        for (path, value) in rows {
            let lower = (path + " " + value).lowercased()
            if has(lower, ["validation", "validated", "rmse", "mae", "holdout", "cross_validation"]) { validation += 1 }
            if has(lower, ["uncertainty", "confidence_interval", "prediction_interval", "posterior", "credible_interval"]) { uncertainty += 1 }
            if has(lower, ["ood", "out_of_domain", "applicability_domain", "in_domain", "extrapolation"]) { domain += 1 }
            if has(lower, ["benchmark", "external_validation", "blind_test", "phreeqc", "jksimmet", "metsim", "syscad", "hsc"]) { benchmark += 1 }
            if has(lower, ["provenance", "lineage", "source_reference", "data_source", "measured", "measurement"]) { provenance += 1 }
            if has(lower, ["mass_balance", "water_balance", "species_balance", "charge_balance", "energy_balance", "residual_ledger", "reconciliation"]) { balance += 1 }
            if has(lower, ["pfd", "pid", "p&id", "drawing", "layout", "flowsheet", "cad", "diagram"]) && engineeringExt.contains(where: { lower.contains($0) }) { engineering += 1 }
        }
        return CommandReadiness(returnedEngines: returned, validationPaths: validation, uncertaintyPaths: uncertainty, domainPaths: domain, benchmarkPaths: benchmark, provenancePaths: provenance, balancePaths: balance, engineeringReferences: engineering)
    }

    private static func has(_ text: String, _ needles: [String]) -> Bool { needles.contains { text.contains($0) } }
}
