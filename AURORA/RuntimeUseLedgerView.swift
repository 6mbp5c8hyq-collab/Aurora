import SwiftUI
import Foundation

struct RuntimeUseLedgerView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("aurora.engine.workspace.selected") private var selectedEngineID = "ore_intelligence"

    @State private var snapshot: JSONValue?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var scope: LedgerScope = .recent

    private enum LedgerScope: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case activeRun = "Active Run"
        case selectedEngine = "Selected Engine"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                scopeControls
                authorityBoundary
                summaryGrid
                eventLedger
            }
            .padding(24)
        }
        .background(AuroraTheme.background)
        .task { await refresh() }
        .refreshable { await refresh() }
        .onChange(of: selectedEngineID) { _, _ in
            guard scope == .selectedEngine else { return }
            Task { await refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("RUNTIME USE LEDGER")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .tracking(2.4)
                    Text("Observed runtime dispatch and returned-payload evidence. No semantic component or resource association is promoted to observed use.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let revision = snapshot?.firstString(["revision"]), !revision.isEmpty {
                Text(revision)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(AuroraTheme.bad)
            }
        }
    }

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVIDENCE SCOPE")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Picker("Evidence scope", selection: $scope) {
                ForEach(LedgerScope.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: scope) { _, _ in
                Task { await refresh() }
            }

            HStack(spacing: 10) {
                scopeChip("Active ID", value: app.activeJobID ?? "None")
                scopeChip("Engine", value: selectedEngineID)
                scopeChip("Origin", value: app.activeResultOrigin)
            }
        }
        .padding(16)
        .background(panelBackground)
    }

    private var authorityBoundary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(AuroraTheme.gold)
                Text("EVIDENCE AUTHORITY BOUNDARY")
                    .font(.headline)
            }

            Text(snapshot?.firstString(["claim_ceiling"])
                 ?? "The ledger may prove canonical dispatch and returned-payload observations only. Internal component calls, resource reads, calibration and scientific validation require separate instrumentation/evidence.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                boundaryBadge("Semantic link", value: governanceString("semantic_association_is_use_evidence") ?? "false")
                boundaryBadge("Component trace", value: governanceString("component_use_instrumentation") ?? "not_installed")
                boundaryBadge("Resource trace", value: governanceString("resource_read_instrumentation") ?? "not_installed")
                boundaryBadge("Call graph", value: governanceString("call_graph_inference") ?? "prohibited")
            }
        }
        .padding(16)
        .background(panelBackground)
    }

    private var summaryGrid: some View {
        let summary = summaryObject
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            metric("Ledger events", summaryNumber(summary, "event_count"), "list.bullet.rectangle")
            metric("Observed dispatch", summaryNumber(summary, "observed_dispatch_count"), "arrow.triangle.branch")
            metric("Returned presence", summaryNumber(summary, "returned_payload_presence_count"), "tray.and.arrow.down.fill")
            metric("Component use", summaryNumber(summary, "component_use_count"), "shippingbox")
            metric("Resource use", summaryNumber(summary, "resource_use_count"), "externaldrive")
            metric("Declared withheld", summaryNumber(summary, "declared_engine_records_withheld_from_use_ledger"), "hand.raised.fill")
        }
    }

    private var eventLedger: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OBSERVED EVIDENCE EVENTS")
                    .font(.headline)
                Spacer()
                Text("\(events.count) rows")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if events.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("No use evidence returned for this scope.")
                        .font(.subheadline.weight(.semibold))
                    Text("This does not mean a registered component or scientific asset was used. The ledger intentionally stays empty when runtime proof is absent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panelBackground)
            } else {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    eventCard(event)
                }
            }
        }
    }

    private func eventCard(_ event: JSONValue) -> some View {
        let evidenceClass = field(event, "evidence_class") ?? "unclassified"
        let targetID = field(event, "target_id") ?? "Unknown target"
        let targetType = field(event, "target_type") ?? "unknown"
        let engineID = field(event, "engine_id")
        let runID = field(event, "run_id") ?? "unknown"
        let proof = field(event, "proof_type") ?? "unreported"
        let status = field(event, "status") ?? "unknown"
        let authority = field(event, "authority") ?? "unreported"
        let ceiling = field(event, "claim_ceiling") ?? "No broader claim is authorized."

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(targetID)
                        .font(.subheadline.weight(.semibold))
                        .textSelection(.enabled)
                    Text(targetType.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(evidenceClass.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(evidenceColor(evidenceClass).opacity(0.14))
                    .foregroundStyle(evidenceColor(evidenceClass))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 8) {
                evidenceField("Run", runID)
                evidenceField("Status", status)
                evidenceField("Proof", proof)
                evidenceField("Authority", authority)
                if let engineID, !engineID.isEmpty {
                    evidenceField("Engine", engineID)
                }
            }

            Text(ceiling)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(16)
        .background(panelBackground)
    }

    private func scopeChip(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func boundaryBadge(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(value.lowercased() == "false" || value.lowercased().contains("not") || value.lowercased().contains("prohibit") ? AuroraTheme.gold : AuroraTheme.good)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(AuroraTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold().monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(panelBackground)
    }

    private func evidenceField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private var events: [JSONValue] {
        guard let snapshot,
              let value = snapshot.recursiveFind("events"),
              case .array(let rows) = value else { return [] }
        return rows
    }

    private var summaryObject: [String: JSONValue] {
        guard let snapshot,
              let value = snapshot.recursiveFind("summary"),
              case .object(let object) = value else { return [:] }
        return object
    }

    private func summaryNumber(_ object: [String: JSONValue], _ key: String) -> String {
        object[key]?.stringValue ?? "0"
    }

    private func governanceString(_ key: String) -> String? {
        guard let snapshot,
              let value = snapshot.recursiveFind("governance"),
              case .object(let object) = value else { return nil }
        return object[key]?.stringValue
    }

    private func field(_ value: JSONValue, _ key: String) -> String? {
        guard case .object(let object) = value else { return nil }
        return object[key]?.stringValue
    }

    private func evidenceColor(_ value: String) -> Color {
        switch value.lowercased() {
        case "observed_dispatch": return AuroraTheme.good
        case "returned_payload_presence": return AuroraTheme.accent
        default: return AuroraTheme.gold
        }
    }

    @MainActor
    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let activeID = app.activeJobID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeIsDAG = activeID.map { id in
            app.serverDagRuns.contains { $0.firstString(["run_id", "runId", "id"]) == id }
                || app.activeResultOrigin.lowercased().contains("dag")
        } ?? false

        do {
            switch scope {
            case .recent:
                snapshot = try await RuntimeUseLedgerAPI().fetch()
            case .activeRun:
                guard let activeID, !activeID.isEmpty else {
                    snapshot = nil
                    errorText = "No active persisted run is selected."
                    return
                }
                snapshot = try await RuntimeUseLedgerAPI().fetch(
                    jobID: activeIsDAG ? nil : activeID,
                    runID: activeIsDAG ? activeID : nil
                )
            case .selectedEngine:
                snapshot = try await RuntimeUseLedgerAPI().fetch(engineID: selectedEngineID)
            }
        } catch {
            snapshot = nil
            errorText = error.localizedDescription
        }
    }
}

private actor RuntimeUseLedgerAPI {
    func fetch(jobID: String? = nil, runID: String? = nil, engineID: String? = nil) async throws -> JSONValue {
        guard var components = URLComponents(url: URL(string: "/api/runtime/use-ledger", relativeTo: AppConfig.backend)!, resolvingAgainstBaseURL: true) else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "40")]
        if let jobID, !jobID.isEmpty { queryItems.append(URLQueryItem(name: "job_id", value: jobID)) }
        if let runID, !runID.isEmpty { queryItems.append(URLQueryItem(name: "run_id", value: runID)) }
        if let engineID, !engineID.isEmpty { queryItems.append(URLQueryItem(name: "engine_id", value: engineID)) }
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data, as: UTF8.self)
            throw NSError(domain: "AURORA.RuntimeUseLedger", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
