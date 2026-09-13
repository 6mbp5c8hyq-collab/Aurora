import SwiftUI
import SwiftData
import QuickLook

struct GovernedDeliverablesCenterView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @AppStorage("aurora.engine.workspace.selected") private var selectedEngineID = "ore_intelligence"
    @AppStorage("aurora.dag.stage.selected") private var selectedStageID = "input_admission"

    @State private var selectedProjectID: UUID?
    @State private var previewURL: URL?
    @State private var nativePDF: URL?
    @State private var nativeCSV: URL?
    @State private var lastRequestedScope: String?
    @State private var lastRequestedFormat: String?

    private var project: AuroraProject? {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) { return selected }
        return projects.first
    }

    private var selectedEngineTitle: String {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let enginesObject) = enginesValue,
              let declaredValue = enginesObject["declared"],
              case .array(let rows) = declaredValue else { return pretty(selectedEngineID) }
        for row in rows {
            if case .object(let object) = row,
               object["id"]?.stringValue == selectedEngineID {
                return object["label"]?.stringValue ?? pretty(selectedEngineID)
            }
        }
        return pretty(selectedEngineID)
    }

    private var selectedStageTitle: String {
        guard let audit = app.runtimeAudit,
              let dagValue = audit.recursiveFind("dag"),
              case .object(let dagObject) = dagValue,
              let declaredValue = dagObject["declared"],
              case .array(let rows) = declaredValue else { return pretty(selectedStageID) }
        for row in rows {
            switch row {
            case .string(let id) where id == selectedStageID:
                return pretty(id)
            case .object(let object):
                let id = object["id"]?.stringValue ?? object["stage"]?.stringValue ?? object["name"]?.stringValue ?? object["key"]?.stringValue
                if id == selectedStageID {
                    return object["label"]?.stringValue ?? object["title"]?.stringValue ?? object["name"]?.stringValue ?? pretty(selectedStageID)
                }
            default:
                continue
            }
        }
        return pretty(selectedStageID)
    }

    private var selectedEngineResult: JSONValue? {
        guard let result = app.activeResult else { return nil }
        return result.recursiveFind(selectedEngineID)
            ?? result.recursiveFind(selectedEngineID.replacingOccurrences(of: "_", with: ""))
    }

    private var selectedStageResult: JSONValue? {
        guard let result = app.activeResult else { return nil }
        return result.recursiveFind(selectedStageID)
            ?? result.recursiveFind(selectedStageID.replacingOccurrences(of: "_", with: ""))
    }

    private var twinResult: JSONValue? {
        guard let active = app.activeResult else { return nil }
        if let twin = active.recursiveFind("digital_twin") { return twin }
        if active.firstString(["active_engine"]) == "digital_twin" { return active.recursiveFind("result") ?? active }
        return nil
    }

    private var artifacts: [ArtifactLink] { ResultTools.artifacts(app.activeResult) }

    private var streamBalanceAvailable: Bool {
        guard let result = app.activeResult else { return false }
        return [
            "streams", "process_streams", "stream_table", "material_streams", "stream_ledger",
            "mass_balance", "water_balance", "mineral_balance", "element_balance", "species_balance",
            "charge_balance", "energy_balance", "conservation", "reconciliation", "residual_ledger"
        ].contains { result.recursiveFind($0) != nil }
    }

    private var evidencePathCount: Int {
        guard let result = app.activeResult else { return 0 }
        let terms = [
            "provenance", "lineage", "validation", "validated", "rmse", "mae", "uncertainty",
            "confidence_interval", "prediction_interval", "ood", "out_of_domain", "applicability_domain",
            "benchmark", "external_validation", "calibration", "claim_ceiling", "governance"
        ]
        return result.flattenedScalars(limit: 12000).filter { row in
            let lower = row.0.lowercased()
            return terms.contains { lower.contains($0) }
        }.count
    }

    private var manifest: [DeliverableScopeManifest] {
        [
            .init(
                id: "full_run",
                title: "Full Active Run",
                subtitle: "Project + active governed result + diagnostics",
                source: "Export Center / canonical export route",
                authority: "active result and selected project basis",
                available: project != nil && app.activeResult != nil,
                direct: true,
                detail: app.activeResult == nil ? "No active governed result is loaded." : "Direct export is available from this center.",
                icon: "archivebox.fill"
            ),
            .init(
                id: "selected_engine",
                title: "Selected Engine · \(selectedEngineTitle)",
                subtitle: "Single governed engine payload",
                source: "Engine Observatory",
                authority: "single_governed_engine / returned engine payload only",
                available: project != nil && selectedEngineResult != nil,
                direct: true,
                detail: selectedEngineResult == nil ? "The active result does not expose the selected engine payload." : "Direct export is available for \(selectedEngineID).",
                icon: "cpu.fill"
            ),
            .init(
                id: "selected_stage",
                title: "Selected DAG Stage · \(selectedStageTitle)",
                subtitle: "Single returned DAG-stage payload",
                source: "DAG Observatory",
                authority: "single_returned_dag_stage / returned_stage_payload_only",
                available: project != nil && selectedStageResult != nil,
                direct: true,
                detail: selectedStageResult == nil ? "The selected stage is declared or selected, but no matching stage payload is returned." : "Direct export is available for \(selectedStageID).",
                icon: "point.3.connected.trianglepath.dotted"
            ),
            .init(
                id: "filtered_results",
                title: "Filtered Results Subset",
                subtitle: "Current engine/domain/semantic/search subset",
                source: "Results Explorer",
                authority: "filtered_returned_result_paths / active_result_returned_values_only",
                available: app.activeResult != nil,
                direct: false,
                detail: "Export remains in Results Explorer because its filters are local workspace state and must not be widened silently here.",
                icon: "rectangle.and.text.magnifyingglass"
            ),
            .init(
                id: "stream_balance",
                title: "Stream & Balance Evidence",
                subtitle: "Recognized streams, balances, residuals and explicit closure state",
                source: "Stream & Balance",
                authority: "recognized returned objects / explicit_status_text_only",
                available: project != nil && streamBalanceAvailable,
                direct: false,
                detail: streamBalanceAvailable ? "Available in Stream & Balance with its recognized-object projection preserved." : "No recognized returned stream/balance object is visible.",
                icon: "scale.3d"
            ),
            .init(
                id: "evidence_authority",
                title: "Evidence Authority Subset",
                subtitle: "Provenance, validation, UQ, OOD, benchmarks and governance paths",
                source: "Evidence & QA",
                authority: "path presence only; presence is not pass status",
                available: project != nil && evidencePathCount > 0,
                direct: false,
                detail: evidencePathCount > 0 ? "\(evidencePathCount) recognized evidence-like paths are available for scoped export in Evidence & QA." : "No recognized evidence-like path is returned.",
                icon: "checkmark.shield.fill"
            ),
            .init(
                id: "scenario_comparison",
                title: "Scenario Comparison",
                subtitle: "Two-to-four persisted runs with like-metric/like-unit comparison",
                source: "Scenarios & Optimization",
                authority: "persisted returned runs / explicit closure only / residuals separate",
                available: project != nil && app.serverDagRuns.count >= 2,
                direct: false,
                detail: app.serverDagRuns.count >= 2 ? "Persisted runs exist. Selection remains in the scenario workspace so the comparison set is not guessed here." : "Fewer than two persisted DAG runs are currently listed.",
                icon: "square.split.2x2"
            ),
            .init(
                id: "digital_twin",
                title: "Digital Twin Evidence",
                subtitle: "Twin payload, envelope, recommendations, connectivity and explicit control fields",
                source: "Operations & Digital Twin",
                authority: "returned twin payload; no independent actuation verification",
                available: project != nil && twinResult != nil,
                direct: true,
                detail: twinResult == nil ? "No active Digital Twin payload is returned." : "Direct evidence export is available; control authority remains evidence-bound.",
                icon: "dot.radiowaves.left.and.right"
            ),
            .init(
                id: "runtime_artifacts",
                title: "Runtime Artifact References",
                subtitle: "Files or deliverable references explicitly returned by the active result",
                source: "Active runtime result",
                authority: "reference presence only; not revision/EPC approval proof",
                available: !artifacts.isEmpty,
                direct: false,
                detail: artifacts.isEmpty ? "No artifact reference is reported." : "\(artifacts.count) artifact references are visible in the manifest below.",
                icon: "doc.badge.ellipsis"
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                projectSelector
                scopeManifest
                directExportPanel
                exportReceipt
                artifactManifest
                nativeFallbacks
                authorityNote
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .quickLookPreview($previewURL)
        .onChange(of: app.lastExportURL) { _, value in
            guard let value else { return }
            previewURL = value
        }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Governed Deliverable Manifest").font(.largeTitle.bold())
                    Text("Scope · source · authority rule · availability · export format")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("The center never promotes a local summary, filtered subset or returned file reference into a complete engineering package. Every export scope keeps its originating authority boundary.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(text: app.activeResult == nil ? "No active result" : "Result available")
                    Text("\(manifest.filter(\.available).count)/\(manifest.count) scopes available")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var projectSelector: some View {
        AuroraCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Delivery Basis").font(.headline)
                    Text("Project provenance attached to direct exports from this center")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if projects.isEmpty {
                    StatusBadge(text: "Create project first")
                } else {
                    Picker("Project", selection: Binding<UUID?>(
                        get: { selectedProjectID ?? projects.first?.id },
                        set: { selectedProjectID = $0 }
                    )) {
                        ForEach(projects) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                    .labelsHidden().frame(maxWidth: 300)
                }
            }
        }
    }

    private var scopeManifest: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Deliverable Scope Matrix").font(.headline)
                        Text("Availability is derived from the current shared runtime/project state; workspace-local filter selections are never reconstructed here.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("AUTHORITY-PRESERVING").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.gold)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 10)], spacing: 10) {
                    ForEach(manifest) { scope in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 9) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10).fill((scope.available ? AuroraTheme.good : Color.secondary).opacity(0.11)).frame(width: 40, height: 40)
                                    Image(systemName: scope.icon).foregroundStyle(scope.available ? AuroraTheme.good : .secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scope.title).font(.caption.bold()).lineLimit(2)
                                    Text(scope.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                                }
                                Spacer()
                                Image(systemName: scope.available ? "checkmark.circle.fill" : "minus.circle")
                                    .foregroundStyle(scope.available ? AuroraTheme.good : .secondary)
                            }
                            Divider().opacity(0.08)
                            manifestField("SOURCE", scope.source)
                            manifestField("AUTHORITY", scope.authority)
                            manifestField("DELIVERY", scope.direct ? "Direct from Export Center" : "Preserved in source workspace")
                            Text(scope.detail).font(.caption2).foregroundStyle(scope.available ? .secondary : AuroraTheme.warn)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 13))
                    }
                }
            }
        }
    }

    private var directExportPanel: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Direct Governed Exports").font(.headline)
                        Text("Only scopes whose required inputs are fully resolved from shared application state are exportable here.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Ready")
                }

                directScopeRow(
                    title: "Full Active Run",
                    subtitle: "Canonical project + active result",
                    available: project != nil && app.activeResult != nil,
                    scopeID: "full_run",
                    formats: ["pdf", "xlsx", "docx", "csv", "bundle"]
                )
                Divider().opacity(0.1)
                directScopeRow(
                    title: "Selected Engine · \(selectedEngineTitle)",
                    subtitle: selectedEngineID,
                    available: project != nil && selectedEngineResult != nil,
                    scopeID: "selected_engine",
                    formats: ["pdf", "xlsx", "docx", "csv"]
                )
                Divider().opacity(0.1)
                directScopeRow(
                    title: "Selected DAG Stage · \(selectedStageTitle)",
                    subtitle: selectedStageID,
                    available: project != nil && selectedStageResult != nil,
                    scopeID: "selected_stage",
                    formats: ["pdf", "xlsx", "docx", "csv"]
                )
                Divider().opacity(0.1)
                directScopeRow(
                    title: "Digital Twin Evidence",
                    subtitle: "Returned twin evidence package",
                    available: project != nil && twinResult != nil,
                    scopeID: "digital_twin",
                    formats: ["pdf", "xlsx", "docx", "csv"]
                )
            }
        }
    }

    private func directScopeRow(title: String, subtitle: String, available: Bool, scopeID: String, formats: [String]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if !available {
                StatusBadge(text: "Unavailable")
            } else {
                ForEach(formats, id: \.self) { format in
                    Button(format.uppercased()) { triggerExport(scopeID: scopeID, format: format) }
                        .buttonStyle(.bordered)
                        .disabled(app.isExporting)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var exportReceipt: some View {
        if let error = app.lastError {
            AuroraCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export error").font(.headline)
                        Text(error).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let url = app.lastExportURL {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AuroraTheme.good)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.lastExportName ?? url.lastPathComponent).font(.headline)
                            Text(url.path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button("Preview") { previewURL = url }.buttonStyle(.bordered)
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
                    }
                    HStack(spacing: 16) {
                        receiptField("REQUESTED SCOPE", lastRequestedScope.map(pretty) ?? "unknown / generated elsewhere")
                        receiptField("FORMAT", lastRequestedFormat?.uppercased() ?? "unknown")
                        receiptField("RUN", app.activeJobID ?? "unidentified")
                    }
                    Text("Receipt scope/format are recorded only for exports initiated from this Export Center during the current view session. Exports initiated in other workspaces retain their own embedded metadata but are not relabeled here.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var artifactManifest: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Runtime Artifact References").font(.headline)
                        Text("References explicitly discovered in the active result")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(artifacts.count) refs").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                }
                if artifacts.isEmpty {
                    ContentUnavailableView("No artifact references returned", systemImage: "doc.badge.ellipsis", description: Text("No placeholder or implied deliverable is shown."))
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(artifacts.prefix(60)) { artifact in
                        HStack(alignment: .top, spacing: 10) {
                            Text(artifact.format).font(.caption2.bold()).foregroundStyle(AuroraTheme.background)
                                .padding(.horizontal, 8).padding(.vertical, 5).background(AuroraTheme.gold, in: Capsule())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(artifact.label).font(.caption.bold())
                                Text(artifact.raw).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        Divider().opacity(0.08)
                    }
                }
                Text("Reference presence does not establish document revision, design approval, current-run generation, or EPC issue status.")
                    .font(.caption2).foregroundStyle(AuroraTheme.warn)
            }
        }
    }

    private var nativeFallbacks: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Native Device Summaries").font(.headline)
                        Text("Offline convenience output only; never labeled as governed server deliverables")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("LOCAL · NON-GOVERNED").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                }
                HStack(spacing: 10) {
                    Button {
                        guard let project else { return }
                        nativePDF = NativeReport.makePDF(project: project, result: app.activeResult)
                    } label: { Label("Local PDF summary", systemImage: "doc.fill") }
                        .buttonStyle(.bordered).disabled(project == nil)

                    Button {
                        nativeCSV = NativeReport.makeCSV(result: app.activeResult)
                    } label: { Label("Local CSV", systemImage: "tablecells") }
                        .buttonStyle(.bordered)
                }
                if let nativePDF {
                    HStack {
                        Text(nativePDF.lastPathComponent).font(.caption.monospaced())
                        Spacer()
                        Button("Preview") { previewURL = nativePDF }
                        ShareLink(item: nativePDF) { Image(systemName: "square.and.arrow.up") }
                    }
                }
                if let nativeCSV {
                    HStack {
                        Text(nativeCSV.lastPathComponent).font(.caption.monospaced())
                        Spacer()
                        ShareLink(item: nativeCSV) { Label("Share CSV", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
    }

    private var authorityNote: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.checkered").foregroundStyle(AuroraTheme.gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delivery Authority Rule").font(.headline)
                    Text("A server export is governed only within the scope embedded in its request metadata. A scoped export is not a full industrial/EPC package. A returned artifact reference is not an approval certificate. A local device summary remains local even if it includes values originating from a governed result.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func triggerExport(scopeID: String, format: String) {
        guard let project else { return }
        lastRequestedScope = scopeID
        lastRequestedFormat = format
        switch scopeID {
        case "full_run":
            app.export(project: project, format: format)
        case "selected_engine":
            app.exportEngine(project: project, engineID: selectedEngineID, engineTitle: selectedEngineTitle, format: format)
        case "selected_stage":
            guard let selectedStageResult else { return }
            app.exportStage(project: project, stageID: selectedStageID, stageTitle: selectedStageTitle, stageResult: selectedStageResult, format: format)
        case "digital_twin":
            guard let twinResult else { return }
            app.exportDigitalTwinEvidence(project: project, twinResult: twinResult, evidence: TwinEvidenceSet.scan(twinResult), format: format)
        default:
            break
        }
    }

    private func manifestField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.caption2).foregroundStyle(.primary).lineLimit(3)
        }
    }

    private func receiptField(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.caption2.monospaced()).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }
}

private struct DeliverableScopeManifest: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let source: String
    let authority: String
    let available: Bool
    let direct: Bool
    let detail: String
    let icon: String
}
