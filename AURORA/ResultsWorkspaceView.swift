import SwiftUI
import SwiftData
import QuickLook
import Charts

struct ResultsWorkspaceView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var query = ""
    @State private var numericOnly = false
    @State private var selectedEngineID = "__all__"
    @State private var selectedDomain = "__all__"
    @State private var selectedSemantic = "__all__"
    @State private var previewURL: URL?
    @State private var subsetExportRequested = false

    private var rows: [GovernedResultRow] {
        guard let result = app.activeResult else { return [] }
        return result.flattenedScalars(limit: 8000).map { path, value in
            GovernedResultRow(path: path, value: value, engineIDs: runtimeEngineIDs)
        }
    }

    private var runtimeEngineIDs: [String] {
        guard let audit = app.runtimeAudit,
              let enginesValue = audit.recursiveFind("engines"),
              case .object(let object) = enginesValue,
              let declaredValue = object["declared"],
              case .array(let values) = declaredValue else {
            return GovernedResultRow.engineFallback
        }
        let ids = values.compactMap { value -> String? in
            if case .object(let object) = value { return object["id"]?.stringValue }
            return value.stringValue
        }
        return ids.isEmpty ? GovernedResultRow.engineFallback : ids
    }

    private var engineOptions: [String] {
        let observed = Set(rows.compactMap(\.engineID))
        return runtimeEngineIDs.filter { observed.contains($0) }
    }

    private var domainOptions: [String] {
        Array(Set(rows.map(\.domain))).sorted()
    }

    private var semanticOptions: [String] {
        GovernedResultRow.semanticOrder.filter { semantic in rows.contains(where: { $0.semantic == semantic }) }
    }

    private var filteredRows: [GovernedResultRow] {
        rows.filter { row in
            let queryMatch = query.isEmpty
                || row.path.localizedCaseInsensitiveContains(query)
                || row.value.localizedCaseInsensitiveContains(query)
            let engineMatch = selectedEngineID == "__all__" || row.engineID == selectedEngineID
            let domainMatch = selectedDomain == "__all__" || row.domain == selectedDomain
            let semanticMatch = selectedSemantic == "__all__" || row.semantic == selectedSemantic
            let numericMatch = !numericOnly || row.numericValue != nil
            return queryMatch && engineMatch && domainMatch && semanticMatch && numericMatch
        }
    }

    private var semanticCounts: [SemanticCount] {
        let grouped = Dictionary(grouping: filteredRows, by: \.semantic)
        return GovernedResultRow.semanticOrder.compactMap { key in
            guard let values = grouped[key], !values.isEmpty else { return nil }
            return SemanticCount(name: pretty(key), count: values.count)
        }
    }

    private var activeProject: AuroraProject? { projects.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                filterPanel
                summaryGrid
                semanticDistribution
                authorityBoundary
                subsetDeliverables
                resultLedger
                rawAuthority
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .quickLookPreview($previewURL)
        .onChange(of: app.lastExportURL) { _, newValue in
            guard subsetExportRequested, let newValue else { return }
            previewURL = newValue
        }
        .onChange(of: selectedEngineID) { _, _ in subsetExportRequested = false }
        .onChange(of: selectedDomain) { _, _ in subsetExportRequested = false }
        .onChange(of: selectedSemantic) { _, _ in subsetExportRequested = false }
        .onChange(of: query) { _, _ in subsetExportRequested = false }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Governed Results Workspace").font(.largeTitle.bold())
                    Text("Engine-aware · domain-aware · evidence-preserving output inspection")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Values are displayed exactly as returned by AURORA. Numeric magnitudes from unlike units are never combined into one performance chart.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: app.activeResult == nil ? "No active result" : ResultTools.status(app.activeResult))
                    Text(app.activeResultOrigin).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var filterPanel: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search path or returned value", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Numeric only", isOn: $numericOnly).toggleStyle(.switch).fixedSize()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(9)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                    filterPicker("Execution engine", selection: $selectedEngineID, values: engineOptions, allLabel: "All returned engines")
                    filterPicker("Top-level domain", selection: $selectedDomain, values: domainOptions, allLabel: "All domains")
                    filterPicker("Semantic family", selection: $selectedSemantic, values: semanticOptions, allLabel: "All semantic families")
                }
            }
        }
    }

    private func filterPicker(_ title: String, selection: Binding<String>, values: [String], allLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text(allLabel).tag("__all__")
                ForEach(values, id: \.self) { value in
                    Text(pretty(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 11)], spacing: 11) {
            metric("Returned paths", "\(rows.count)", "point.3.filled.connected.trianglepath.dotted")
            metric("Visible subset", "\(filteredRows.count)", "line.3.horizontal.decrease.circle.fill")
            metric("Numeric", "\(filteredRows.filter { $0.numericValue != nil }.count)", "number.square.fill")
            metric("Engine-tagged", "\(filteredRows.filter { $0.engineID != nil }.count)", "cpu.fill")
            metric("Semantic families", "\(Set(filteredRows.map(\.semantic)).count)", "square.grid.3x3.fill")
            metric("Artifacts", "\(ResultTools.artifacts(app.activeResult).count)", "doc.richtext.fill")
        }
    }

    @ViewBuilder
    private var semanticDistribution: some View {
        if !semanticCounts.isEmpty {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Visible Output Composition").font(.headline)
                        Spacer()
                        Text("COUNT OF RETURNED PATHS · NOT VALUE NORMALIZATION")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AuroraTheme.warn)
                    }
                    Chart(semanticCounts) { item in
                        BarMark(
                            x: .value("Family", item.name),
                            y: .value("Paths", item.count)
                        )
                    }
                    .frame(height: 220)
                    Text("The chart compares only path counts. It never aggregates recovery, grade, energy, chemistry, economics or other values across unlike units.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var authorityBoundary: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(AuroraTheme.good)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Result Authority Boundary").font(.headline)
                    Text("Engine tags are inferred only from registered engine IDs found in the returned path hierarchy. Semantic families are UI classifications for navigation, not additional scientific claims. Exported subsets preserve original paths and returned values.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let ceiling = ResultTools.ceiling(app.activeResult) { StatusBadge(text: ceiling) }
            }
        }
    }

    private var subsetDeliverables: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Filtered Result Deliverables").font(.headline)
                        Text("Exports contain only the currently visible result paths plus explicit filter metadata and original path/value pairs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: app.isExporting ? "Exporting" : "Subset scoped")
                }

                HStack(spacing: 9) {
                    subsetButton("PDF", "pdf", "doc.richtext.fill")
                    subsetButton("EXCEL", "xlsx", "tablecells.fill")
                    subsetButton("WORD", "docx", "doc.text.fill")
                    subsetButton("CSV", "csv", "list.bullet.rectangle.fill")
                }

                if activeProject == nil {
                    Text("Create or load a project to attach project provenance to subset exports.")
                        .font(.caption2)
                        .foregroundStyle(AuroraTheme.warn)
                } else if filteredRows.isEmpty {
                    Text("Export is disabled because the current filter returns no paths.")
                        .font(.caption2)
                        .foregroundStyle(AuroraTheme.warn)
                }

                if subsetExportRequested, let url = app.lastExportURL {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AuroraTheme.good)
                        Text(app.lastExportName ?? url.lastPathComponent).font(.caption.monospaced()).lineLimit(1)
                        Spacer()
                        Button("Preview") { previewURL = url }.buttonStyle(.bordered)
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func subsetButton(_ title: String, _ format: String, _ icon: String) -> some View {
        Button {
            guard let project = activeProject, !filteredRows.isEmpty else { return }
            subsetExportRequested = true
            app.exportResultSubset(
                project: project,
                rows: filteredRows,
                engineID: selectedEngineID,
                domain: selectedDomain,
                semantic: selectedSemantic,
                query: query,
                numericOnly: numericOnly,
                format: format
            )
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .disabled(activeProject == nil || filteredRows.isEmpty || app.isExporting)
    }

    @ViewBuilder
    private var resultLedger: some View {
        if app.activeResult == nil {
            AuroraCard {
                ContentUnavailableView("No active result", systemImage: "waveform.path.ecg", description: Text("Run AURORA or recover a result from Result Vault."))
            }
        } else if filteredRows.isEmpty {
            AuroraCard {
                ContentUnavailableView("No matching output", systemImage: "magnifyingglass", description: Text("Change the active result filters."))
            }
        } else {
            let groups = Dictionary(grouping: filteredRows, by: \.semantic)
            ForEach(GovernedResultRow.semanticOrder.filter { groups[$0] != nil }, id: \.self) { semantic in
                if let group = groups[semantic] {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(pretty(semantic)).font(.headline)
                                Spacer()
                                Text("\(group.count) paths").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            ForEach(group.prefix(300)) { row in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                        HStack(spacing: 5) {
                                            if let engine = row.engineID {
                                                Text(pretty(engine)).font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.accent)
                                            }
                                            Text(pretty(row.domain)).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                                            if row.numericValue != nil {
                                                Text("NUMERIC").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.gold)
                                            }
                                        }
                                    }
                                    Spacer(minLength: 12)
                                    Text(row.value)
                                        .font(.caption.monospaced())
                                        .multilineTextAlignment(.trailing)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: 360, alignment: .trailing)
                                }
                                .padding(.vertical, 3)
                                Divider().opacity(0.07)
                            }
                            if group.count > 300 {
                                Text("Showing 300 of \(group.count) paths in this semantic family. Refine filters to inspect the remainder.")
                                    .font(.caption2)
                                    .foregroundStyle(AuroraTheme.warn)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rawAuthority: some View {
        if let result = app.activeResult {
            AuroraCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Complete Governed Response").font(.headline)
                    Text("Raw JSON is retained as a secondary audit surface; the structured workspace above is the primary inspection interface.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("Open complete active result") {
                        Text(result.prettyString()).font(.caption2.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.65)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        }
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

struct GovernedResultRow: Identifiable {
    let id = UUID()
    let path: String
    let value: String
    let numericValue: Double?
    let domain: String
    let engineID: String?
    let semantic: String

    init(path: String, value: String, engineIDs: [String]) {
        self.path = path
        self.value = value
        let sanitized = value
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.numericValue = Double(sanitized)
        self.domain = path.split(whereSeparator: { $0 == "." || $0 == "[" }).first.map(String.init) ?? "root"

        let normalizedPath = "." + path.lowercased().replacingOccurrences(of: "[", with: ".").replacingOccurrences(of: "]", with: ".") + "."
        self.engineID = engineIDs.first { engine in
            normalizedPath.contains("." + engine.lowercased() + ".")
        }
        self.semantic = GovernedResultRow.classify(path: path)
    }

    static let engineFallback = [
        "ore_intelligence", "resource_model", "comminution", "classification", "flotation",
        "magnetic_gravity", "hydrometallurgy", "thermodynamics", "water_circuit", "conservation",
        "equipment_epc", "economics", "tailings", "digital_twin", "hybrid_ai", "diagnostics"
    ]

    static let semanticOrder = [
        "process_performance", "material_streams", "particle_liberation", "chemistry_geochemistry",
        "water_rheology", "equipment_engineering", "economics", "uncertainty_validation",
        "evidence_governance", "tailings_esg", "mining_resource", "runtime_diagnostics", "other"
    ]

    static func classify(path: String) -> String {
        let lower = path.lowercased()
        if containsAny(lower, ["recovery", "grade", "yield", "mass_pull", "throughput", "efficiency", "extraction"]) { return "process_performance" }
        if containsAny(lower, ["stream", "mass_balance", "water_balance", "species_balance", "flowrate", "flow_rate", "solids_tph"]) { return "material_streams" }
        if containsAny(lower, ["psd", "p80", "p50", "p10", "liberation", "particle", "size_fraction", "breakage", "selection_function"]) { return "particle_liberation" }
        if containsAny(lower, ["thermo", "geochem", "species", "activity", "gibbs", "pitzer", "redox", "orp", "ph", "ionic", "precip", "dissolution", "surface_complex"]) { return "chemistry_geochemistry" }
        if containsAny(lower, ["water", "viscos", "rheolog", "density", "bleed", "recycle", "conductivity", "alkalinity"]) { return "water_rheology" }
        if containsAny(lower, ["equipment", "epc", "pfd", "pid", "p&id", "layout", "drawing", "pump", "mill", "cyclone", "cell", "filter", "thickener"]) { return "equipment_engineering" }
        if containsAny(lower, ["capex", "opex", "npv", "irr", "econom", "cost", "revenue", "margin", "payback"]) { return "economics" }
        if containsAny(lower, ["uncert", "confidence", "ood", "applicability", "calibration", "benchmark", "validation", "rmse", "mae", "r2", "residual"]) { return "uncertainty_validation" }
        if containsAny(lower, ["evidence", "provenance", "lineage", "source", "measured", "assumed", "claim_ceiling", "authority", "governance"]) { return "evidence_governance" }
        if containsAny(lower, ["tailings", "esg", "carbon", "acid_generation", "neutralization", "radioactivity", "closure"]) { return "tailings_esg" }
        if containsAny(lower, ["resource", "block_model", "geostat", "mine", "pit", "stope", "haul", "fleet", "orebody"]) { return "mining_resource" }
        if containsAny(lower, ["diagnostic", "runtime", "engine_trace", "execution", "status", "warning", "error", "gate"]) { return "runtime_diagnostics" }
        return "other"
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

private struct SemanticCount: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

extension AppModel {
    func exportResultSubset(
        project: AuroraProject,
        rows: [GovernedResultRow],
        engineID: String,
        domain: String,
        semantic: String,
        query: String,
        numericOnly: Bool,
        format: String
    ) {
        guard !isExporting, !rows.isEmpty else { return }
        isExporting = true
        lastError = nil

        let api = AURORAAPI()
        let payloadRows = rows.map { row in
            JSONValue.object([
                "path": .string(row.path),
                "value": .string(row.value),
                "domain": .string(row.domain),
                "engine_id": row.engineID.map(JSONValue.string) ?? .null,
                "semantic_family": .string(row.semantic),
                "numeric_value": row.numericValue.map(JSONValue.number) ?? .null
            ])
        }

        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_Filtered_Results_" + project.name),
            "project": project.payload,
            "designBasis": .object([
                "export_scope": .string("filtered_returned_result_paths"),
                "authority": .string("active_result_returned_values_only"),
                "engine_filter": .string(engineID),
                "domain_filter": .string(domain),
                "semantic_filter": .string(semantic),
                "query_filter": .string(query),
                "numeric_only": .bool(numericOnly),
                "visible_path_count": .number(Double(rows.count))
            ]),
            "analyses": .array([]),
            "flowsheet": .object([:]),
            "diagnostics": .array([]),
            "result": .object([
                "scope": .string("filtered_returned_result_paths"),
                "rows": .array(payloadRows)
            ]),
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus),
                "scope": .string("results_workspace_filtered_subset")
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
