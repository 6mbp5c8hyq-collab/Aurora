import SwiftUI

struct ResultVaultBrowserView: View {
    @EnvironmentObject private var app: AppModel
    @State private var tab: VaultTab = .dag
    @State private var query = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var selectedRecordID: String?
    @State private var showRawSelected = false

    enum VaultTab: String, CaseIterable, Identifiable {
        case dag = "DAG Runs"
        case jobs = "Engine Jobs"
        var id: String { rawValue }
    }

    private enum RowKind: String {
        case dag = "Canonical DAG"
        case job = "Selected Engine"
    }

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All states"
        case terminal = "Terminal"
        case active = "Running / queued"
        case failed = "Failed / blocked"
        var id: String { rawValue }
    }

    private struct PresenceFact: Identifiable {
        let id: String
        let label: String
        let present: Bool
        let note: String
    }

    private var dagRuns: [JSONValue] {
        filter(app.serverDagRuns, kind: .dag)
    }

    private var jobs: [JSONValue] {
        filter(app.serverJobs, kind: .job)
    }

    private var displayedRows: [JSONValue] {
        tab == .dag ? dagRuns : jobs
    }

    private var displayedKind: RowKind {
        tab == .dag ? .dag : .job
    }

    private var selectedRecord: JSONValue? {
        guard let selectedRecordID else { return nil }
        return displayedRows.first { rowID($0, kind: displayedKind) == selectedRecordID }
            ?? sourceRows(kind: displayedKind).first { rowID($0, kind: displayedKind) == selectedRecordID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                controls
                activeResultCard
                lineageAuthorityNote
                browser
                if let selectedRecord { lineageInspector(selectedRecord, kind: displayedKind) }
                if let error = app.lastError { errorCard(error) }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .refreshable {
            await app.refreshServerState()
        }
        .onChange(of: tab) { _, _ in
            selectedRecordID = nil
            showRawSelected = false
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
                    Text("Result Vault & Run Lineage").font(.largeTitle.bold())
                    Text("Persisted execution references · scope identity · evidence-presence lineage")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("A listed record proves that the server persistence API returned that execution reference. It does not by itself prove scientific validation, calibration, or industrial authority.")
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
            VStack(alignment: .leading, spacing: 12) {
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
                        TextField("Search ID, engine, stage, project or status", text: $query)
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

                Picker("State", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var activeResultCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
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

                if let result = app.activeResult {
                    let facts = activePresenceFacts(result)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                        ForEach(facts) { fact in
                            presenceTile(fact)
                        }
                    }
                } else {
                    Text("No persisted or live result is currently active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var lineageAuthorityNote: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .foregroundStyle(AuroraTheme.gold)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lineage interpretation").font(.headline)
                    Text("Fields below are presence- and contract-based. “Canonical input present” is shown only when a record actually contains the nested project/feedTph and analyses-array structure. Missing listing detail is shown as unreported, not inferred from another run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var browser: some View {
        switch tab {
        case .dag:
            vaultCollection(
                title: "Persisted DAG Runs",
                subtitle: "Canonical project orchestration references returned by the server",
                rows: dagRuns,
                kind: .dag
            )
        case .jobs:
            vaultCollection(
                title: "Persisted Engine Jobs",
                subtitle: "Selected-engine execution references returned by the server",
                rows: jobs,
                kind: .job
            )
        }
    }

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
                        description: Text(query.isEmpty ? "No persisted executions match the current state filter." : "No persisted execution matches the current search and state filter.")
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
        let module = requestedEngine(row)
        let currentStage = row.firstString(["current_stage", "active_stage", "stage"])
        let active = app.activeJobID == id
        let canonical = hasCanonicalInputContract(row)
        let stageCount = returnedStageCount(row)
        let engineCount = returnedEngineCount(row)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind == .dag ? "point.3.connected.trianglepath.dotted" : "cpu")
                .font(.title3)
                .foregroundStyle(active ? AuroraTheme.gold : AuroraTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
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
                    Text(kind.rawValue.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(AuroraTheme.accent)
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

                HStack(spacing: 8) {
                    lineageChip(canonical ? "Canonical input present" : "Input contract unreported", tint: canonical ? AuroraTheme.good : .secondary)
                    if let stageCount { lineageChip("\(stageCount) stages returned", tint: AuroraTheme.accent) }
                    if let engineCount { lineageChip("\(engineCount) engines returned", tint: AuroraTheme.accent) }
                }
            }

            Spacer()
            StatusBadge(text: status)

            Button {
                selectedRecordID = id
                showRawSelected = false
            } label: {
                Label(selectedRecordID == id ? "Inspecting" : "Lineage", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .buttonStyle(.bordered)
            .disabled(id == "unidentified")

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

    private func lineageInspector(_ row: JSONValue, kind: RowKind) -> some View {
        let id = rowID(row, kind: kind)
        let canonical = hasCanonicalInputContract(row)
        let authority = evidenceAuthorityCounts(row)
        let stageCount = returnedStageCount(row)
        let engineCount = returnedEngineCount(row)
        let module = requestedEngine(row)
        let projectName = projectNameFrom(row)
        let projectID = projectIDFrom(row)
        let scenario = row.firstString(["scenario_name", "scenario", "name"])

        return AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Run Lineage Inspector").font(.headline)
                        Text(id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: row.firstString(["status", "state", "platform_status"]) ?? "unreported")
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 9)], spacing: 9) {
                    lineageFact("Execution scope", kind.rawValue, "server collection")
                    lineageFact("Persistence reference", "Returned by server listing", "not a scientific validation claim")
                    lineageFact("Input contract", canonical ? "Canonical mobile contract present" : "Unreported in listing", canonical ? "project/feedTph + analyses[] detected" : "load the full result for deeper evidence")
                    lineageFact("Requested engine", module ?? (kind == .dag ? "Full DAG" : "Unreported"), "no engine inferred from filenames")
                    lineageFact("Project", projectName ?? "Unreported", projectID ?? "project id not returned")
                    lineageFact("Scenario", scenario ?? "Unreported", "shown only if returned")
                    lineageFact("Stages returned", stageCount.map(String.init) ?? "Unreported", "count of returned stage structures only")
                    lineageFact("Engines returned", engineCount.map(String.init) ?? "Unreported", "count of returned engine payloads only")
                    lineageFact("Export reference", id == "unidentified" ? "Unavailable" : "Reference available", "file readiness is checked by Export Center")
                }

                if let authority {
                    Divider().opacity(0.12)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Returned Input Authority").font(.subheadline.bold())
                        Text("Counts are derived only from an analyses array present in this listed record.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                            authorityCountTile("Rows", authority.total, AuroraTheme.accent)
                            authorityCountTile("Measured", authority.measured, AuroraTheme.good)
                            authorityCountTile("Estimated", authority.estimated, AuroraTheme.warn)
                            authorityCountTile("Declared", authority.declared, AuroraTheme.accent)
                            authorityCountTile("Unqualified", authority.unqualified, authority.unqualified > 0 ? AuroraTheme.bad : AuroraTheme.good)
                        }
                    }
                } else {
                    Text("Input evidence rows are not included in this listing record. No authority distribution is inferred from another execution.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.12)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidence-path presence in this record").font(.subheadline.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                        ForEach(lineagePresenceFacts(row)) { fact in presenceTile(fact) }
                    }
                }

                HStack {
                    Button(showRawSelected ? "Hide listing metadata" : "Show listing metadata") {
                        withAnimation { showRawSelected.toggle() }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button {
                        if kind == .dag { app.loadStoredDagRun(id: id) }
                        else { app.loadStoredJob(id: id) }
                    } label: {
                        Label("Open as Active Result", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(id == "unidentified" || app.isLoadingStoredRun || app.activeJobID == id)
                }

                if showRawSelected {
                    ScrollView(.horizontal) {
                        Text(row.prettyString())
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private struct AuthorityCounts {
        var total = 0
        var measured = 0
        var estimated = 0
        var declared = 0
        var unqualified = 0
    }

    private func evidenceAuthorityCounts(_ value: JSONValue) -> AuthorityCounts? {
        guard let analyses = canonicalAnalysesArray(in: value) else { return nil }
        var counts = AuthorityCounts()
        for row in analyses {
            guard case .object(let object) = row else { continue }
            counts.total += 1
            let status = (object["status"]?.stringValue ?? "UNQUALIFIED").uppercased()
            switch status {
            case "MEASURED": counts.measured += 1
            case "ESTIMATED", "ASSUMED": counts.estimated += 1
            case "DECLARED": counts.declared += 1
            default: counts.unqualified += 1
            }
        }
        return counts
    }

    private func canonicalAnalysesArray(in value: JSONValue) -> [JSONValue]? {
        if case .object(let object) = value {
            if let analyses = object["analyses"], case .array(let rows) = analyses { return rows }
            if let payload = object["payload"] { return canonicalAnalysesArray(in: payload) }
            if let request = object["request"] { return canonicalAnalysesArray(in: request) }
            if let input = object["input"] { return canonicalAnalysesArray(in: input) }
        }
        return nil
    }

    private func hasCanonicalInputContract(_ value: JSONValue) -> Bool {
        func inspect(_ candidate: JSONValue) -> Bool {
            guard case .object(let object) = candidate,
                  let project = object["project"], case .object(let projectObject) = project,
                  projectObject["feedTph"]?.doubleValue != nil,
                  let analyses = object["analyses"], case .array = analyses else { return false }
            return true
        }

        if inspect(value) { return true }
        if case .object(let object) = value {
            for key in ["payload", "request", "input"] {
                if let nested = object[key], inspect(nested) { return true }
                if let nested = object[key], hasCanonicalInputContract(nested) { return true }
            }
        }
        return false
    }

    private func requestedEngine(_ row: JSONValue) -> String? {
        row.firstString(["requested_module", "requestedModule", "engine_id", "engine", "module"])
    }

    private func projectNameFrom(_ value: JSONValue) -> String? {
        if case .object(let object) = value {
            if let project = object["project"], case .object(let p) = project,
               let name = p["name"]?.stringValue, !name.isEmpty { return name }
            for key in ["payload", "request", "input"] {
                if let nested = object[key], let name = projectNameFrom(nested) { return name }
            }
        }
        return value.firstString(["project_name"])
    }

    private func projectIDFrom(_ value: JSONValue) -> String? {
        if case .object(let object) = value {
            if let project = object["project"], case .object(let p) = project,
               let id = p["id"]?.stringValue, !id.isEmpty { return id }
            for key in ["payload", "request", "input"] {
                if let nested = object[key], let id = projectIDFrom(nested) { return id }
            }
        }
        return value.firstString(["project_id"])
    }

    private func returnedStageCount(_ value: JSONValue) -> Int? {
        for key in ["stages", "stage_trace", "dag_stages", "trace"] {
            guard let found = value.recursiveFind(key) else { continue }
            if case .array(let rows) = found { return rows.count }
        }
        return nil
    }

    private func returnedEngineCount(_ value: JSONValue) -> Int? {
        if let engines = value.recursiveFind("engines") {
            switch engines {
            case .object(let object):
                let reserved = Set(["declared", "observed_in_completed_jobs", "registered", "available"])
                let payloadKeys = object.keys.filter { !reserved.contains($0) }
                if !payloadKeys.isEmpty { return payloadKeys.count }
            case .array(let rows):
                return rows.count
            default:
                break
            }
        }

        let known = [
            "ore_intelligence", "resource_model", "comminution", "classification",
            "flotation", "magnetic_gravity", "hydrometallurgy", "thermodynamics",
            "water_circuit", "conservation", "equipment_epc", "economics",
            "tailings", "digital_twin", "hybrid_ai", "diagnostics"
        ]
        guard case .object(let object) = value else { return nil }
        let count = known.filter { object[$0] != nil }.count
        return count > 0 ? count : nil
    }

    private func lineagePresenceFacts(_ value: JSONValue) -> [PresenceFact] {
        [
            presenceFact("validation", label: "Validation path", keys: ["validation", "validation_status", "certificate"], in: value),
            presenceFact("provenance", label: "Provenance / lineage", keys: ["provenance", "lineage", "evidence"], in: value),
            presenceFact("uncertainty", label: "Uncertainty", keys: ["uncertainty", "uq", "confidence_interval"], in: value),
            presenceFact("ood", label: "OOD / applicability", keys: ["ood", "applicability_domain", "applicability"], in: value),
            presenceFact("benchmark", label: "Benchmark", keys: ["benchmark", "external_validation", "reference_comparison"], in: value),
            presenceFact("balance", label: "Balance / conservation", keys: ["balance", "balances", "conservation", "residual_ledger"], in: value),
            presenceFact("engineering", label: "Engineering artifacts", keys: ["engineering", "artifacts", "deliverables"], in: value)
        ]
    }

    private func activePresenceFacts(_ result: JSONValue) -> [PresenceFact] {
        var facts = lineagePresenceFacts(result)
        facts.insert(
            PresenceFact(
                id: "stages",
                label: "Returned stage trace",
                present: returnedStageCount(result) != nil,
                note: returnedStageCount(result).map { "\($0) returned structures" } ?? "not returned"
            ),
            at: 0
        )
        facts.insert(
            PresenceFact(
                id: "engines",
                label: "Returned engine payloads",
                present: returnedEngineCount(result) != nil,
                note: returnedEngineCount(result).map { "\($0) returned payloads" } ?? "not returned"
            ),
            at: 1
        )
        return facts
    }

    private func presenceFact(_ id: String, label: String, keys: [String], in value: JSONValue) -> PresenceFact {
        let matched = keys.first { value.recursiveFind($0) != nil }
        return PresenceFact(
            id: id,
            label: label,
            present: matched != nil,
            note: matched.map { "returned path: \($0)" } ?? "not returned in this record"
        )
    }

    private func presenceTile(_ fact: PresenceFact) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: fact.present ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(fact.present ? AuroraTheme.good : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.label).font(.caption.bold())
                Text(fact.note).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(9)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
    }

    private func lineageFact(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold()).lineLimit(2)
            Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func authorityCountTile(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)").font(.title3.bold()).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
    }

    private func lineageChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
    }

    private func sourceRows(kind: RowKind) -> [JSONValue] {
        kind == .dag ? app.serverDagRuns : app.serverJobs
    }

    private func filter(_ source: [JSONValue], kind: RowKind) -> [JSONValue] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.filter { value in
            let queryMatches = clean.isEmpty || value.prettyString().localizedCaseInsensitiveContains(clean)
            guard queryMatches else { return false }
            let status = (value.firstString(["status", "state", "platform_status"]) ?? "").lowercased()
            switch statusFilter {
            case .all:
                return true
            case .terminal:
                return isTerminal(status)
            case .active:
                return status.contains("running") || status.contains("queued") || status.contains("pending") || status.contains("start")
            case .failed:
                return status.contains("fail") || status.contains("error") || status.contains("blocked") || status.contains("cancel")
            }
        }
    }

    private func isTerminal(_ status: String) -> Bool {
        ["completed", "success", "succeeded", "failed", "error", "blocked", "cancelled"]
            .contains { status.contains($0) }
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
