import SwiftUI

struct ChemistryWorkbenchView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case equilibrium = "Equilibrium / Speciation"
        case saturation = "Saturation Indices"
        case kinetics = "Reaction Kinetics"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .equilibrium: return "atom"
            case .saturation: return "diamond.fill"
            case .kinetics: return "waveform.path.ecg"
            }
        }
    }

    @State private var mode: Mode = .equilibrium
    @State private var payloadText = ChemistryTemplates.weakAcid
    @State private var capabilities: JSONValue?
    @State private var selftest: JSONValue?
    @State private var result: JSONValue?
    @State private var isLoading = false
    @State private var isRunning = false
    @State private var errorText: String?

    private let api = AURORAAPI()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                authorityPanel
                executionPanel
                if let errorText {
                    errorPanel(errorText)
                }
                if let result {
                    resultPanel(result)
                }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .task { await refreshAuthority() }
    }

    private var hero: some View {
        card {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "atom")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Chemistry Authority Workbench")
                        .font(.largeTitle.bold())
                    Text("Governed aqueous equilibrium · activity models · saturation · kinetics")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Every calculation exposes model authority, solver residuals, assumptions and provenance. Unsupported high-fidelity chemistry fails closed rather than silently falling back to a weaker model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    statusBadge(selftest?.recursiveFind("ok")?.boolValue == true ? "SELF-TEST PASS" : "AUTHORITY CHECK")
                    Text("Railway canonical chemistry runtime")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var authorityPanel: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scientific Authority Boundary").font(.headline)
                        Text("Native capabilities are separated from functions requiring validated parameter databases or external thermodynamic delegates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLoading { ProgressView() }
                    Button("Refresh") { Task { await refreshAuthority() } }
                        .buttonStyle(.bordered)
                }

                if let capabilities {
                    let native = capabilityRows(capabilities, key: "native")
                    let delegated = capabilityRows(capabilities, key: "delegate_required")
                    HStack(alignment: .top, spacing: 12) {
                        capabilityColumn(title: "Native / Governed", rows: native, icon: "checkmark.seal.fill", positive: true)
                        capabilityColumn(title: "Delegate Required", rows: delegated, icon: "externaldrive.connected.to.line.below", positive: false)
                    }

                    if let policy = capabilities.recursiveFind("authority_policy")?.stringValue {
                        Text(policy)
                            .font(.caption2.monospaced())
                            .foregroundStyle(AuroraTheme.gold)
                    }
                } else {
                    Text("Chemistry capability contract has not been returned by the runtime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var executionPanel: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Chemistry Execution").font(.headline)
                        Text("Use governed templates or edit the complete scientific payload. Results are rendered as chemistry tables and diagnostics, not as a raw JSON dump.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, newValue in
                    payloadText = ChemistryTemplates.template(for: newValue)
                    result = nil
                    errorText = nil
                }

                HStack(spacing: 8) {
                    Button("Load governed template") {
                        payloadText = ChemistryTemplates.template(for: mode)
                        result = nil
                        errorText = nil
                    }
                    .buttonStyle(.bordered)

                    Button("Run self-test") {
                        Task { await runSelftest() }
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                    Button {
                        Task { await execute() }
                    } label: {
                        if isRunning {
                            ProgressView()
                            Text("RUNNING")
                        } else {
                            Label("RUN CHEMISTRY", systemImage: "bolt.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
                }

                Text("Scientific payload")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextEditor(text: $payloadText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 260)
                    .padding(8)
                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
            }
        }
    }

    @ViewBuilder
    private func resultPanel(_ value: JSONValue) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Returned Chemistry Result").font(.headline)
                        Text(value.firstString(["authority", "status"]) ?? "Governed runtime result")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusBadge(value.recursiveFind("ok")?.boolValue == true ? "CONVERGED" : "CHECK RESULT")
                }

                summaryMetrics(value)

                if let species = speciesRows(value), !species.isEmpty {
                    speciesTable(species)
                }

                if let phases = phaseRows(value), !phases.isEmpty {
                    phaseTable(phases)
                }

                let trajectory = trajectoryRows(value)
                if !trajectory.isEmpty {
                    trajectoryTable(trajectory)
                }

                diagnostics(value)
                provenance(value)
            }
        }
    }

    @ViewBuilder
    private func summaryMetrics(_ value: JSONValue) -> some View {
        let metrics: [(String, String)] = [
            ("pH", scalar(value, "pH")),
            ("Ionic strength", scalar(value, "ionic_strength_molal")),
            ("Charge residual", scalar(value, "charge_balance_eq_per_kg")),
            ("Residual ∞-norm", scalar(value, "residual_inf_norm")),
            ("Activity model", scalar(value, "activity_model")),
            ("Temperature °C", scalar(value, "temperature_c"))
        ].filter { !$0.1.isEmpty }

        if !metrics.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0).font(.caption2).foregroundStyle(.secondary)
                        Text(item.1).font(.headline.monospaced()).lineLimit(1)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func speciesTable(_ rows: [ChemistrySpeciesResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aqueous Species").font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    GridRow {
                        tableHeader("Species")
                        tableHeader("z")
                        tableHeader("Molality")
                        tableHeader("γ")
                        tableHeader("Activity")
                    }
                    Divider().gridCellColumns(5)
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.name).font(.caption.bold())
                            Text(row.charge).font(.caption.monospaced())
                            Text(row.molality).font(.caption.monospaced())
                            Text(row.gamma).font(.caption.monospaced())
                            Text(row.activity).font(.caption.monospaced())
                        }
                    }
                }
                .padding(10)
            }
            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func phaseTable(_ rows: [ChemistryPhaseResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phase Saturation").font(.subheadline.bold())
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(.caption.bold())
                        Text(row.state).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("SI \(row.si)").font(.caption.monospaced())
                }
                .padding(9)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private func trajectoryTable(_ rows: [ChemistryTrajectoryResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kinetic Trajectory").font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(rows.prefix(30)) { row in
                        HStack(spacing: 16) {
                            Text("t = \(row.time) s")
                                .font(.caption.monospaced())
                                .frame(width: 110, alignment: .leading)
                            Text(row.composition)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
            }
            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func diagnostics(_ value: JSONValue) -> some View {
        let rows = value.flattenedScalars(limit: 4000).filter {
            let key = $0.0.lowercased()
            return key.contains("solver") || key.contains("warning") || key.contains("residual") || key.contains("equation_count") || key.contains("unknown_count")
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Solver & Diagnostics").font(.subheadline.bold())
                ForEach(Array(rows.prefix(30).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) {
                        Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.1).font(.caption2.monospaced()).multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(10)
            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func provenance(_ value: JSONValue) -> some View {
        let rows = value.flattenedScalars(limit: 4000).filter {
            let key = $0.0.lowercased()
            return key.contains("provenance") || key.contains("authority") || key.contains("claim_ceiling") || key.contains("revision")
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Authority & Provenance").font(.subheadline.bold())
                ForEach(Array(rows.prefix(30).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).font(.caption2.monospaced()).foregroundStyle(AuroraTheme.gold)
                        Text(row.1).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func capabilityColumn(title: String, rows: [(String, String)], icon: String, positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.bold())
                .foregroundStyle(positive ? AuroraTheme.good : AuroraTheme.gold)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pretty(row.0)).font(.caption.bold())
                    Text(row.1).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func errorPanel(_ text: String) -> some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Chemistry execution blocked", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(AuroraTheme.bad)
                Text(text).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(.secondary)
    }

    private func statusBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AuroraTheme.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(AuroraTheme.accent)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AuroraTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.12)))
    }

    private func refreshAuthority() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let capabilityRequest = api.chemistryCapabilities()
            async let selftestRequest = api.chemistrySelftest()
            capabilities = try await capabilityRequest
            selftest = try await selftestRequest
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runSelftest() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let response = try await api.chemistrySelftest()
            selftest = response
            result = response
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func execute() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            guard let data = payloadText.data(using: .utf8) else {
                throw ChemistryWorkbenchError.invalidUTF8
            }
            let payload = try JSONDecoder().decode(JSONValue.self, from: data)
            let response: JSONValue
            switch mode {
            case .equilibrium:
                response = try await api.chemistryEquilibrate(payload)
            case .saturation:
                response = try await api.chemistrySaturationIndices(payload)
            case .kinetics:
                response = try await api.chemistryKinetics(payload)
            }
            result = response
            errorText = nil
        } catch {
            result = nil
            errorText = error.localizedDescription
        }
    }

    private func capabilityRows(_ value: JSONValue, key: String) -> [(String, String)] {
        guard let found = value.recursiveFind(key), case .object(let object) = found else { return [] }
        return object.keys.sorted().compactMap { key in
            guard let text = object[key]?.stringValue else { return nil }
            return (key, text)
        }
    }

    private func scalar(_ value: JSONValue, _ key: String) -> String {
        value.recursiveFind(key)?.stringValue ?? ""
    }

    private func speciesRows(_ value: JSONValue) -> [ChemistrySpeciesResult]? {
        guard let found = value.recursiveFind("species"), case .array(let rows) = found else { return nil }
        return rows.compactMap { row in
            guard case .object(let object) = row,
                  let name = object["name"]?.stringValue else { return nil }
            return ChemistrySpeciesResult(
                name: name,
                charge: object["charge"]?.stringValue ?? "—",
                molality: scientific(object["molality"]?.doubleValue),
                gamma: scientific(object["activity_coefficient"]?.doubleValue),
                activity: scientific(object["activity"]?.doubleValue)
            )
        }
    }

    private func phaseRows(_ value: JSONValue) -> [ChemistryPhaseResult]? {
        guard let found = value.recursiveFind("phases"), case .array(let rows) = found else { return nil }
        return rows.compactMap { row in
            guard case .object(let object) = row,
                  let name = object["name"]?.stringValue else { return nil }
            return ChemistryPhaseResult(
                name: name,
                si: scientific(object["saturation_index"]?.doubleValue),
                state: object["state"]?.stringValue ?? "—"
            )
        }
    }

    private func trajectoryRows(_ value: JSONValue) -> [ChemistryTrajectoryResult] {
        guard let found = value.recursiveFind("trajectory"), case .array(let rows) = found else { return [] }
        return rows.compactMap { row in
            guard case .object(let object) = row,
                  let time = object["time_s"]?.doubleValue,
                  let molalityValue = object["molality"], case .object(let molality) = molalityValue else { return nil }
            let composition = molality.keys.sorted().map { key in
                "\(key)=\(scientific(molality[key]?.doubleValue))"
            }.joined(separator: "  ")
            return ChemistryTrajectoryResult(time: scientific(time), composition: composition)
        }
    }

    private func scientific(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e4 || magnitude < 1e-3 {
            return String(format: "%.5e", value)
        }
        return String(format: "%.6g", value)
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private enum ChemistryWorkbenchError: LocalizedError {
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .invalidUTF8: return "The chemistry payload is not valid UTF-8."
        }
    }
}

private struct ChemistrySpeciesResult: Identifiable {
    let id = UUID()
    let name: String
    let charge: String
    let molality: String
    let gamma: String
    let activity: String
}

private struct ChemistryPhaseResult: Identifiable {
    let id = UUID()
    let name: String
    let si: String
    let state: String
}

private struct ChemistryTrajectoryResult: Identifiable {
    let id = UUID()
    let time: String
    let composition: String
}

private enum ChemistryTemplates {
    static let weakAcid = """
    {
      "temperature_c": 25.0,
      "pressure_bar": 1.01325,
      "activity_model": "ideal",
      "species": [
        {"name": "HA", "charge": 0, "initial_molality": 0.009},
        {"name": "H+", "charge": 1, "initial_molality": 0.0004},
        {"name": "A-", "charge": -1, "initial_molality": 0.0004}
      ],
      "reactions": [
        {
          "name": "HA_dissociation",
          "logK": -4.756961951,
          "stoichiometry": {"HA": -1, "H+": 1, "A-": 1}
        }
      ],
      "balances": [
        {
          "name": "acid_total",
          "total_molality": 0.01,
          "coefficients": {"HA": 1, "A-": 1}
        }
      ],
      "charge_balance": true
    }
    """

    static let saturation = """
    {
      "activities": {
        "Ca+2": 0.001,
        "CO3-2": 0.0001
      },
      "phases": [
        {
          "name": "Declared carbonate phase",
          "logK": -8.0,
          "ion_activity_product": {"Ca+2": 1, "CO3-2": 1}
        }
      ]
    }
    """

    static let kinetics = """
    {
      "species": [
        {"name": "A", "initial_molality": 1.0},
        {"name": "B", "initial_molality": 0.0}
      ],
      "kinetic_reactions": [
        {
          "name": "A_to_B",
          "rate_constant": 0.01,
          "stoichiometry": {"A": -1, "B": 1},
          "orders": {"A": 1}
        }
      ],
      "time_end_s": 600.0,
      "points": 61
    }
    """

    static func template(for mode: ChemistryWorkbenchView.Mode) -> String {
        switch mode {
        case .equilibrium: return weakAcid
        case .saturation: return saturation
        case .kinetics: return kinetics
        }
    }
}
