import SwiftUI
import SwiftData
import QuickLook

struct EvidenceAuthorityWorkspaceView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedEngineID = "__all__"
    @State private var selectedDimension = "__all__"
    @State private var query = ""
    @State private var previewURL: URL?
    @State private var exportRequested = false

    private var engineIDs: [String] {
        guard let audit = app.runtimeAudit,
              let engines = audit.recursiveFind("engines"),
              case .object(let object) = engines,
              let declared = object["declared"],
              case .array(let rows) = declared else { return EvidencePath.engineFallback }
        let values = rows.compactMap { row -> String? in
            if case .object(let object) = row { return object["id"]?.stringValue }
            return row.stringValue
        }
        return values.isEmpty ? EvidencePath.engineFallback : values
    }

    private var paths: [EvidencePath] {
        EvidenceAuthorityParser.paths(from: app.activeResult, engineIDs: engineIDs)
    }

    private var filteredPaths: [EvidencePath] {
        paths.filter { path in
            let engineMatch = selectedEngineID == "__all__" || path.engineID == selectedEngineID
            let dimensionMatch = selectedDimension == "__all__" || path.dimension == selectedDimension
            let queryMatch = query.isEmpty
                || path.path.localizedCaseInsensitiveContains(query)
                || path.value.localizedCaseInsensitiveContains(query)
            return engineMatch && dimensionMatch && queryMatch
        }
    }

    private var observedEngines: [String] {
        let observed = Set(paths.compactMap(\.engineID))
        return engineIDs.filter { observed.contains($0) }
    }

    private var engineCoverage: [EngineEvidenceCoverage] {
        engineIDs.map { engine in
            EngineEvidenceCoverage(engineID: engine, paths: paths.filter { $0.engineID == engine })
        }
    }

    private var globalPaths: [EvidencePath] { paths.filter { $0.engineID == nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                posture
                filterPanel
                authorityRule
                coverageMatrix
                evidenceLedger
                deliverables
                rawAudit
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

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AuroraTheme.gold.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AuroraTheme.gold)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Evidence Authority Workspace").font(.largeTitle.bold())
                    Text("Provenance · validation · uncertainty · applicability · benchmark · governance")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Coverage means a recognized returned path exists. It does not mean the evidence passed, was externally validated, or authorizes an industrial claim unless the returned status explicitly says so.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(text: app.activeResult == nil ? "No active result" : "Result linked")
                    Text("\(paths.count) evidence-like paths").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var posture: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 11)], spacing: 11) {
            metric("Claim ceiling", ResultTools.ceiling(app.activeResult) ?? "Not reported", "gauge.with.dots.needle.67percent")
            metric("Evidence paths", "\(paths.count)", "books.vertical.fill")
            metric("Engine-scoped", "\(paths.filter { $0.engineID != nil }.count)", "cpu.fill")
            metric("Global / unscoped", "\(globalPaths.count)", "globe")
            metric("Engines evidenced", "\(observedEngines.count)/\(engineIDs.count)", "square.stack.3d.up.fill")
            metric("Dimensions present", "\(Set(paths.map(\.dimension)).count)/\(EvidencePath.dimensionOrder.count)", "square.grid.3x3.fill")
        }
    }

    private var filterPanel: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search evidence path or returned value", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(9)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ENGINE SCOPE").font(.caption2.bold()).foregroundStyle(.secondary)
                        Picker("Engine", selection: $selectedEngineID) {
                            Text("All evidence scopes").tag("__all__")
                            ForEach(engineIDs, id: \.self) { Text(pretty($0)).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EVIDENCE DIMENSION").font(.caption2.bold()).foregroundStyle(.secondary)
                        Picker("Dimension", selection: $selectedDimension) {
                            Text("All dimensions").tag("__all__")
                            ForEach(EvidencePath.dimensionOrder, id: \.self) { Text(pretty($0)).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu)
                    }
                    Spacer()
                    Text("\(filteredPaths.count) visible").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var authorityRule: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill").font(.title2).foregroundStyle(AuroraTheme.warn)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Evidence Interpretation Rule").font(.headline)
                    Text("Engine linkage is assigned only when a registered engine ID appears in the returned path hierarchy. Unscoped evidence stays global. Status is never upgraded from path presence: 'validation.rmse' means validation evidence exists, not that validation passed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var coverageMatrix: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Engine Evidence Coverage Matrix").font(.headline)
                        Text("Presence of returned engine-scoped evidence paths by dimension")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("PRESENCE ≠ PASS").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 5) {
                            matrixCell("Engine", width: 190, header: true)
                            ForEach(EvidencePath.dimensionOrder, id: \.self) { dimension in
                                matrixCell(shortLabel(dimension), width: 100, header: true)
                            }
                        }
                        Divider().opacity(0.2)
                        ForEach(engineCoverage) { coverage in
                            HStack(spacing: 5) {
                                matrixCell(pretty(coverage.engineID), width: 190, emphasis: true)
                                ForEach(EvidencePath.dimensionOrder, id: \.self) { dimension in
                                    let values = coverage.paths.filter { $0.dimension == dimension }
                                    HStack(spacing: 4) {
                                        Image(systemName: values.isEmpty ? "minus.circle" : "checkmark.circle.fill")
                                            .foregroundStyle(values.isEmpty ? .secondary : AuroraTheme.good)
                                        Text(values.isEmpty ? "—" : "\(values.count)")
                                            .font(.caption2.monospaced())
                                    }
                                    .frame(width: 100, alignment: .center)
                                }
                            }
                            .padding(.vertical, 7)
                            Divider().opacity(0.07)
                        }
                    }
                    .frame(minWidth: 900, alignment: .leading)
                }

                if !globalPaths.isEmpty {
                    Text("\(globalPaths.count) recognized evidence paths are global/unscoped and are intentionally not credited to any individual engine.")
                        .font(.caption2).foregroundStyle(AuroraTheme.gold)
                }
            }
        }
    }

    private var evidenceLedger: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Returned Evidence Ledger").font(.headline)
                    Spacer()
                    Text("\(filteredPaths.count) paths").font(.caption.monospaced()).foregroundStyle(.secondary)
                }

                if paths.isEmpty {
                    ContentUnavailableView(
                        "No recognized evidence paths returned",
                        systemImage: "checkmark.shield",
                        description: Text("The active result does not expose recognized provenance, validation, uncertainty, OOD/applicability, benchmark, calibration or governance paths.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 210)
                } else if filteredPaths.isEmpty {
                    ContentUnavailableView("No matching evidence", systemImage: "magnifyingglass", description: Text("Change the evidence filters."))
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    let groups = Dictionary(grouping: filteredPaths, by: \.dimension)
                    ForEach(EvidencePath.dimensionOrder.filter { groups[$0] != nil }, id: \.self) { dimension in
                        if let values = groups[dimension] {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(pretty(dimension)).font(.subheadline.bold())
                                    Spacer()
                                    Text("\(values.count)").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                                }
                                ForEach(values.prefix(250)) { item in
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                            Text(item.engineID.map { pretty($0) } ?? "Global / unscoped")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(item.engineID == nil ? AuroraTheme.gold : AuroraTheme.accent)
                                        }
                                        Spacer(minLength: 10)
                                        Text(item.value).font(.caption2.monospaced()).multilineTextAlignment(.trailing).textSelection(.enabled).frame(maxWidth: 370, alignment: .trailing)
                                    }
                                    .padding(.vertical, 3)
                                    Divider().opacity(0.06)
                                }
                            }
                            Divider().opacity(0.14)
                        }
                    }
                }
            }
        }
    }

    private var deliverables: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Evidence Deliverables").font(.headline)
                        Text("Exports only the visible recognized evidence paths and their returned values; path presence is marked separately from pass/fail authority.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Evidence scoped")
                }
                HStack(spacing: 9) {
                    exportButton("PDF", "pdf", "doc.richtext.fill")
                    exportButton("EXCEL", "xlsx", "tablecells.fill")
                    exportButton("WORD", "docx", "doc.text.fill")
                    exportButton("CSV", "csv", "list.bullet.rectangle.fill")
                }
                if projects.first == nil || filteredPaths.isEmpty {
                    Text("Export requires a project and at least one visible returned evidence path.")
                        .font(.caption2).foregroundStyle(AuroraTheme.warn)
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
            guard let project = projects.first, !filteredPaths.isEmpty else { return }
            exportRequested = true
            app.exportEvidenceSubset(
                project: project,
                paths: filteredPaths,
                engineFilter: selectedEngineID,
                dimensionFilter: selectedDimension,
                query: query,
                format: format
            )
        } label: { Label(title, systemImage: icon) }
        .buttonStyle(.bordered)
        .disabled(projects.first == nil || filteredPaths.isEmpty || app.isExporting)
    }

    @ViewBuilder
    private var rawAudit: some View {
        if let result = app.activeResult {
            AuroraCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Complete Result Audit").font(.headline)
                    Text("The raw response remains available so no evidence field is hidden by the recognized-path projection.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Open complete active result") {
                        Text(result.prettyString()).font(.caption2.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.headline).lineLimit(2).minimumScaleFactor(0.68)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        }
    }

    private func matrixCell(_ value: String, width: CGFloat, header: Bool = false, emphasis: Bool = false) -> some View {
        Text(value)
            .font(header ? .caption2.bold() : emphasis ? .caption.bold() : .caption2.monospaced())
            .foregroundStyle(header ? .secondary : .primary)
            .lineLimit(2)
            .frame(width: width, alignment: .leading)
    }

    private func shortLabel(_ dimension: String) -> String {
        switch dimension {
        case "provenance_lineage": return "PROV"
        case "validation": return "VALID"
        case "uncertainty": return "UQ"
        case "applicability_ood": return "OOD"
        case "benchmark_external": return "BENCH"
        case "calibration": return "CAL"
        case "governance_claims": return "GOV"
        case "warnings_diagnostics": return "WARN"
        default: return dimension.uppercased()
        }
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }
}

struct EvidencePath: Identifiable {
    let id = UUID()
    let path: String
    let value: String
    let dimension: String
    let engineID: String?

    static let dimensionOrder = [
        "provenance_lineage", "validation", "uncertainty", "applicability_ood",
        "benchmark_external", "calibration", "governance_claims", "warnings_diagnostics"
    ]

    static let engineFallback = [
        "ore_intelligence", "resource_model", "comminution", "classification", "flotation",
        "magnetic_gravity", "hydrometallurgy", "thermodynamics", "water_circuit", "conservation",
        "equipment_epc", "economics", "tailings", "digital_twin", "hybrid_ai", "diagnostics"
    ]
}

private struct EngineEvidenceCoverage: Identifiable {
    let engineID: String
    let paths: [EvidencePath]
    var id: String { engineID }
}

private enum EvidenceAuthorityParser {
    static func paths(from result: JSONValue?, engineIDs: [String]) -> [EvidencePath] {
        guard let result else { return [] }
        var output: [EvidencePath] = []
        var seen = Set<String>()

        for (path, value) in result.flattenedScalars(limit: 12000) {
            guard let dimension = dimension(path: path) else { continue }
            let normalized = "." + path.lowercased().replacingOccurrences(of: "[", with: ".").replacingOccurrences(of: "]", with: ".") + "."
            let engine = engineIDs.first { normalized.contains("." + $0.lowercased() + ".") }
            let fingerprint = path + "|" + value
            guard seen.insert(fingerprint).inserted else { continue }
            output.append(EvidencePath(path: path, value: value, dimension: dimension, engineID: engine))
        }
        return output
    }

    private static func dimension(path: String) -> String? {
        let lower = path.lowercased()
        if has(lower, ["provenance", "lineage", "data_source", "source_reference", "source_id", "measured", "measurement", "assay_source"]) { return "provenance_lineage" }
        if has(lower, ["validation", "validated", "validation_certificate", "holdout", "cross_validation", "rmse", "mae", "mape", "r_squared", "r2_score", "validation_error"]) { return "validation" }
        if has(lower, ["uncertainty", "confidence_interval", "prediction_interval", "posterior", "credible_interval", "variance", "standard_error", "std_error", "uq_"]) { return "uncertainty" }
        if has(lower, ["applicability_domain", "ood", "out_of_domain", "in_domain", "domain_status", "extrapolation"]) { return "applicability_ood" }
        if has(lower, ["benchmark", "external_validation", "blind_test", "blind_benchmark", "reference_case", "reference_dataset", "phreeqc", "jksimmet", "metsim", "syscad", "hsc"]) { return "benchmark_external" }
        if has(lower, ["calibration", "calibrated", "calibration_dataset", "fit_parameter", "parameter_fit", "calibration_error"]) { return "calibration" }
        if has(lower, ["claim_ceiling", "claim_authority", "authority", "governance", "evidence_gate", "certificate", "approval_level", "bankability"]) { return "governance_claims" }
        if has(lower, ["warning", "diagnostic", "violation", "error", "failure", "gate", "residual_check"]) { return "warnings_diagnostics" }
        return nil
    }

    private static func has(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

extension AppModel {
    func exportEvidenceSubset(
        project: AuroraProject,
        paths: [EvidencePath],
        engineFilter: String,
        dimensionFilter: String,
        query: String,
        format: String
    ) {
        guard !isExporting, !paths.isEmpty else { return }
        isExporting = true
        lastError = nil
        let api = AURORAAPI()

        let rows = paths.map { path in
            JSONValue.object([
                "path": .string(path.path),
                "value": .string(path.value),
                "dimension": .string(path.dimension),
                "engine_id": path.engineID.map(JSONValue.string) ?? .null,
                "relationship": .string(path.engineID == nil ? "global_unscoped_returned_path" : "engine_id_in_returned_path_hierarchy"),
                "authority": .string("path_presence_only_not_pass_status")
            ])
        }

        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_Evidence_Authority_" + project.name),
            "project": project.payload,
            "designBasis": .object([
                "export_scope": .string("recognized_returned_evidence_paths"),
                "authority": .string("active_result_returned_values_only"),
                "engine_link_rule": .string("registered_engine_id_in_returned_path_hierarchy_only"),
                "coverage_rule": .string("path_presence_not_pass_status"),
                "engine_filter": .string(engineFilter),
                "dimension_filter": .string(dimensionFilter),
                "query_filter": .string(query),
                "visible_path_count": .number(Double(paths.count))
            ]),
            "analyses": .array([]),
            "flowsheet": .object([:]),
            "diagnostics": .array([]),
            "result": .object(["evidence_paths": .array(rows)]),
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus),
                "scope": .string("evidence_authority_workspace")
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
