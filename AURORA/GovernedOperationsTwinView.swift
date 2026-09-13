import SwiftUI
import SwiftData
import QuickLook

struct GovernedOperationsTwinView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedProjectID: UUID?
    @State private var previewURL: URL?
    @State private var exportRequested = false

    private var project: AuroraProject? {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) { return selected }
        return projects.first
    }

    private var twinResult: JSONValue? {
        guard let active = app.activeResult else { return nil }
        if let twin = active.recursiveFind("digital_twin") { return twin }
        if active.firstString(["active_engine"]) == "digital_twin" { return active.recursiveFind("result") ?? active }
        return nil
    }

    private var twinEvidence: TwinEvidenceSet { TwinEvidenceSet.scan(twinResult) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                executionControl
                authorityLadder
                kpiSurface
                operatingEnvelope
                recommendations
                connectivityEvidence
                controlAuthority
                deliverables
                rawTwinLedger
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .quickLookPreview($previewURL)
        .onChange(of: app.lastExportURL) { _, value in
            guard exportRequested, let value else { return }
            previewURL = value
        }
    }

    private var header: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle().fill(AuroraTheme.accent.opacity(0.16)).frame(width: 70, height: 70)
                    Image(systemName: "dot.radiowaves.left.and.right").font(.title2.bold()).foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Operations & Digital Twin").font(.largeTitle.bold())
                    Text("Runtime state · operating envelope · connectivity evidence · control authority")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("The iOS client does not infer live plant connectivity or actuation. Closed-loop authority is shown only when explicit control fields are returned by the runtime, and even then external plant-side verification remains separate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(text: twinResult == nil ? "No twin payload" : ResultTools.status(twinResult))
                    Text(app.activeResultOrigin).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var executionControl: some View {
        AuroraCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Digital Twin Execution").font(.headline)
                    Text("Runs the registered digital_twin engine against the selected project through the canonical mobile execution path.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if projects.isEmpty {
                    StatusBadge(text: "Create project first")
                } else {
                    Picker("Project", selection: Binding<UUID?>(get: { selectedProjectID ?? projects.first?.id }, set: { selectedProjectID = $0 })) {
                        ForEach(projects) { project in Text(project.name).tag(Optional(project.id)) }
                    }
                    .labelsHidden().frame(maxWidth: 260)
                    Button {
                        guard let project else { return }
                        app.run(project: project, context: context, module: "digital_twin")
                    } label: {
                        if app.isRunning { ProgressView(); Text("Running") }
                        else { Label("RUN DIGITAL TWIN", systemImage: "bolt.horizontal.fill") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.isRunning || project == nil)
                }
            }
        }
    }

    private var authorityLadder: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Digital Twin Authority Ladder").font(.headline)
                    Spacer()
                    Text("NO IMPLIED CONTROL AUTHORITY").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 9)], spacing: 9) {
                    authorityStep("Registered engine", digitalTwinDeclared, digitalTwinDeclared ? "engines.declared" : "not resolved", "checkmark.seal.fill")
                    authorityStep("Observed completed job", digitalTwinObserved, digitalTwinObserved ? "audit observed" : "not observed", "eye.fill")
                    authorityStep("Active twin payload", twinResult != nil, twinResult == nil ? "not returned" : "returned", "arrow.down.doc.fill")
                    authorityStep("Connectivity paths", !twinEvidence.connectivity.isEmpty, "\(twinEvidence.connectivity.count) returned", "network")
                    authorityStep("Control authority fields", !twinEvidence.controlAuthority.isEmpty, "\(twinEvidence.controlAuthority.count) returned", "switch.2")
                    authorityStep("Actuation-capable state", twinEvidence.hasEnabledLikeControlAuthority, twinEvidence.hasEnabledLikeControlAuthority ? "runtime-reported only" : "unproven", "bolt.horizontal.circle.fill")
                }
                if twinEvidence.hasEnabledLikeControlAuthority {
                    Text("An enabled-like control state is reported by the runtime. This is not independent proof that a PLC/DCS/OPC write path is live, commissioned, interlocked or authorized at the plant.")
                        .font(.caption2).foregroundStyle(AuroraTheme.warn)
                }
            }
        }
    }

    @ViewBuilder
    private var kpiSurface: some View {
        if let twinResult {
            let kpis = ResultTools.kpis(twinResult)
            if !kpis.isEmpty {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Text("Reported Operating KPIs").font(.headline)
                            Spacer()
                            Text("NO CROSS-UNIT CHART").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 9)], spacing: 9) {
                            ForEach(kpis) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(.caption).foregroundStyle(.secondary)
                                    Text(item.value.formatted(.number.precision(.fractionLength(0...4))))
                                        .font(.title3.bold()).textSelection(.enabled)
                                    Text(item.unit.isEmpty ? "unit not registered" : item.unit)
                                        .font(.caption2.monospaced()).foregroundStyle(item.unit.isEmpty ? AuroraTheme.warn : .secondary)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        Text("Each KPI remains an independent returned quantity because throughput, grade, recovery, power, water and economics are dimensionally different.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var operatingEnvelope: some View {
        evidenceSurface(title: "Operating Envelope & Constraints", subtitle: "Returned feasible-region, operating-limit and constraint fields only.", icon: "scope", rows: twinEvidence.envelope)
    }

    private var recommendations: some View {
        evidenceSurface(title: "Setpoints & Recommendations", subtitle: "Returned recommendations are advisory unless separate explicit control-authority fields state otherwise.", icon: "dial.medium", rows: twinEvidence.recommendations)
    }

    private var connectivityEvidence: some View {
        evidenceSurface(title: "Industrial Connectivity Evidence", subtitle: "Telemetry, OPC-UA, historian, LIMS and related paths are shown as returned-path evidence only.", icon: "network", rows: twinEvidence.connectivity)
    }

    private var controlAuthority: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Explicit Control Authority Fields").font(.headline)
                        Text("Only fields whose returned paths explicitly reference control/actuation authority are included.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: twinEvidence.controlPosture)
                }
                if twinEvidence.controlAuthority.isEmpty {
                    Text("No explicit closed-loop, write-authority, actuation-enabled, autonomous-control or controller-mode field is present in the active twin payload. Recommendations remain advisory/unproven for actuation.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(twinEvidence.controlAuthority) { row in evidenceRow(row) }
                }
            }
        }
    }

    private func evidenceSurface(title: String, subtitle: String, icon: String, rows: [TwinEvidenceRow]) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: rows.isEmpty ? "Not reported" : "\(rows.count) returned")
                }
                if rows.isEmpty {
                    Text("No recognized returned path from this category exists in the active Digital Twin payload.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(rows.prefix(120)) { row in evidenceRow(row) }
                    if rows.count > 120 {
                        Text("Showing 120 of \(rows.count) returned paths.").font(.caption2).foregroundStyle(AuroraTheme.warn)
                    }
                }
            }
        }
    }

    private func evidenceRow(_ row: TwinEvidenceRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(row.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer(minLength: 12)
            Text(row.value).font(.caption2.monospaced()).multilineTextAlignment(.trailing).textSelection(.enabled).frame(maxWidth: 390, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private var deliverables: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Digital Twin Evidence Deliverables").font(.headline)
                        Text("Exports the returned twin payload evidence with explicit connectivity/control authority rules.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Twin scoped")
                }
                HStack(spacing: 9) {
                    exportButton("PDF", "pdf", "doc.richtext.fill")
                    exportButton("EXCEL", "xlsx", "tablecells.fill")
                    exportButton("WORD", "docx", "doc.text.fill")
                    exportButton("CSV", "csv", "list.bullet.rectangle.fill")
                }
                if project == nil || twinResult == nil {
                    Text("Export requires a project context and an active returned Digital Twin payload.").font(.caption2).foregroundStyle(AuroraTheme.warn)
                }
                if exportRequested, let url = app.lastExportURL {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AuroraTheme.good)
                        Text(app.lastExportName ?? url.lastPathComponent).font(.caption.monospaced()).lineLimit(1)
                        Spacer()
                        Button("Preview") { previewURL = url }.buttonStyle(.bordered)
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func exportButton(_ title: String, _ format: String, _ icon: String) -> some View {
        Button {
            guard let project, let twinResult else { return }
            exportRequested = true
            app.exportDigitalTwinEvidence(project: project, twinResult: twinResult, evidence: twinEvidence, format: format)
        } label: { Label(title, systemImage: icon) }
        .buttonStyle(.bordered)
        .disabled(project == nil || twinResult == nil || app.isExporting)
    }

    @ViewBuilder
    private var rawTwinLedger: some View {
        if let twinResult {
            AuroraCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Complete Digital Twin Payload").font(.headline)
                    Text("Raw payload is retained for traceability; the categorized surfaces above make no additional plant-state claims.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Open Digital Twin scalar ledger") {
                        ForEach(Array(twinResult.flattenedScalars(limit: 1200).enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 12) {
                                Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                Spacer(minLength: 12)
                                Text(row.1).font(.caption2.monospaced()).multilineTextAlignment(.trailing).textSelection(.enabled)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private var digitalTwinDeclared: Bool {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let engineObject) = enginesValue,
              let declaredValue = engineObject["declared"],
              case .array(let entries) = declaredValue else { return false }
        return entries.contains { row in
            if case .object(let object) = row { return object["id"]?.stringValue == "digital_twin" }
            return row.stringValue == "digital_twin"
        }
    }

    private var digitalTwinObserved: Bool {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let engineObject) = enginesValue,
              let observedValue = engineObject["observed_in_completed_jobs"],
              case .array(let entries) = observedValue else { return false }
        return entries.contains { $0.stringValue == "digital_twin" }
    }

    private func authorityStep(_ title: String, _ present: Bool, _ detail: String, _ icon: String) -> some View {
        HStack(spacing: 9) {
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
        .padding(9).background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TwinEvidenceRow: Identifiable {
    let id = UUID()
    let path: String
    let value: String
}

struct TwinEvidenceSet {
    let envelope: [TwinEvidenceRow]
    let recommendations: [TwinEvidenceRow]
    let connectivity: [TwinEvidenceRow]
    let controlAuthority: [TwinEvidenceRow]

    var hasEnabledLikeControlAuthority: Bool {
        controlAuthority.contains { row in
            let value = row.value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return ["true", "enabled", "active", "automatic", "auto", "closed_loop", "closed-loop", "write", "writable"].contains(value)
        }
    }

    var controlPosture: String {
        if controlAuthority.isEmpty { return "Advisory / unproven" }
        if hasEnabledLikeControlAuthority { return "Actuation-capable state reported" }
        let disabledLike = controlAuthority.contains { row in
            let value = row.value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return ["false", "disabled", "inactive", "advisory", "read_only", "read-only", "off", "manual"].contains(value)
        }
        return disabledLike ? "Non-actuating state reported" : "Authority fields reported"
    }

    static func scan(_ result: JSONValue?) -> TwinEvidenceSet {
        guard let result else { return TwinEvidenceSet(envelope: [], recommendations: [], connectivity: [], controlAuthority: []) }
        var envelope: [TwinEvidenceRow] = []
        var recommendations: [TwinEvidenceRow] = []
        var connectivity: [TwinEvidenceRow] = []
        var control: [TwinEvidenceRow] = []
        var seen = Set<String>()

        for (path, value) in result.flattenedScalars(limit: 10000) {
            let lower = path.lowercased()
            let fingerprint = path + "|" + value
            guard seen.insert(fingerprint).inserted else { continue }
            let row = TwinEvidenceRow(path: path, value: value)

            if has(lower, ["operating_envelope", "operating_limit", "feasible_region", "constraint", "limit_state", "safe_envelope"]) { envelope.append(row) }
            if has(lower, ["setpoint", "recommendation", "recommended_action", "control_action", "optimization_result", "advisory_action"]) { recommendations.append(row) }
            if has(lower, ["telemetry", "opc_ua", "opcua", "historian", "pi_system", "lims", "fms", "connectivity", "plc", "dcs", "scada"]) { connectivity.append(row) }
            if has(lower, ["control_authority", "write_authority", "actuation_enabled", "closed_loop", "autonomous_control", "controller_mode", "control_mode", "write_enabled"]) { control.append(row) }
        }
        return TwinEvidenceSet(envelope: envelope, recommendations: recommendations, connectivity: connectivity, controlAuthority: control)
    }

    private static func has(_ text: String, _ needles: [String]) -> Bool { needles.contains { text.contains($0) } }
}

extension AppModel {
    func exportDigitalTwinEvidence(project: AuroraProject, twinResult: JSONValue, evidence: TwinEvidenceSet, format: String) {
        guard !isExporting else { return }
        isExporting = true
        lastError = nil
        let api = AURORAAPI()

        func rows(_ values: [TwinEvidenceRow]) -> JSONValue {
            .array(values.map { .object(["path": .string($0.path), "value": .string($0.value)]) })
        }

        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_Digital_Twin_Evidence_" + project.name),
            "project": project.payload,
            "designBasis": .object([
                "export_scope": .string("returned_digital_twin_payload_evidence"),
                "authority": .string("active_result_returned_values_only"),
                "connectivity_rule": .string("reported_path_presence_only"),
                "control_authority_rule": .string("explicit_returned_control_fields_only"),
                "actuation_verification": .string("not_performed_by_ios_client"),
                "control_posture": .string(evidence.controlPosture)
            ]),
            "analyses": .array([]),
            "flowsheet": .object([:]),
            "diagnostics": .array([]),
            "result": .object([
                "operating_envelope": rows(evidence.envelope),
                "recommendations": rows(evidence.recommendations),
                "connectivity_evidence": rows(evidence.connectivity),
                "control_authority_fields": rows(evidence.controlAuthority),
                "raw_twin_payload": twinResult
            ]),
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus),
                "scope": .string("digital_twin_authority_workspace")
            ])
        ])

        Task {
            do {
                let file = try await api.export(body, format: format)
                lastExportURL = file.url
                lastExportName = file.name
            } catch {
                lastError = error.localizedDescription
            }
            isExporting = false
        }
    }
}
