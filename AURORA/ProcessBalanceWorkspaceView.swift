import SwiftUI
import SwiftData
import QuickLook
import Charts

struct ProcessBalanceWorkspaceView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedStreamID: String?
    @State private var selectedBalanceID: String?
    @State private var query = ""
    @State private var previewURL: URL?
    @State private var exportRequested = false

    private var streams: [PBStream] { PBParser.streams(from: app.activeResult) }
    private var balances: [PBBalance] { PBParser.balances(from: app.activeResult) }
    private var selectedStream: PBStream? { streams.first(where: { $0.id == selectedStreamID }) ?? streams.first }
    private var selectedBalance: PBBalance? { balances.first(where: { $0.id == selectedBalanceID }) ?? balances.first }

    private var filteredStreams: [PBStream] {
        guard !query.isEmpty else { return streams }
        return streams.filter { stream in
            stream.name.localizedCaseInsensitiveContains(query)
                || stream.fields.contains { $0.path.localizedCaseInsensitiveContains(query) || $0.displayValue.localizedCaseInsensitiveContains(query) }
        }
    }

    private var evidenceCounts: [PBEvidenceCount] {
        let fields = streams.flatMap(\.fields) + balances.flatMap(\.fields)
        let grouped = Dictionary(grouping: fields, by: \.evidenceClass)
        return PBField.evidenceOrder.compactMap { key in
            guard let values = grouped[key], !values.isEmpty else { return nil }
            return PBEvidenceCount(name: pretty(key), count: values.count)
        }
    }

    private var residualFields: [PBField] { balances.flatMap(\.residualFields) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                summary
                authorityBoundary
                evidenceComposition
                streamLedger
                if let selectedStream { streamInspector(selectedStream) }
                balanceMatrix
                if let selectedBalance { balanceInspector(selectedBalance) }
                residualLedger
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
                        .fill(AuroraTheme.accent.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "arrow.left.arrow.right.square.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Conservation & Stream Workspace").font(.largeTitle.bold())
                    Text("Returned streams · reconciliation evidence · residual ledger · explicit closure")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("No stream state, closure value, reconciliation result or residual is synthesized by the iOS client. Unlike engineering units are never plotted on a common magnitude axis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(text: app.activeResult == nil ? "No active result" : "Runtime linked")
                    Text(app.activeResultOrigin).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 11)], spacing: 11) {
            metric("Streams returned", "\(streams.count)", "point.topleft.down.curvedto.point.bottomright.up")
            metric("Balance objects", "\(balances.count)", "scale.3d")
            metric("Residual fields", "\(residualFields.count)", "waveform.path.ecg")
            metric("Explicit closed", "\(balances.filter { $0.closureClass == .closed }.count)", "checkmark.seal.fill")
            metric("Explicit issue", "\(balances.filter { $0.closureClass == .issue }.count)", "exclamationmark.triangle.fill")
            metric("Unreported closure", "\(balances.filter { $0.closureClass == .unreported }.count)", "questionmark.diamond.fill")
        }
    }

    private var authorityBoundary: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(AuroraTheme.good)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Balance Authority Boundary").font(.headline)
                    Text("Closure is classified only from explicit returned status/state/closure text inside a recognized balance object. Field provenance labels below are lexical UI classifications from returned field names; they do not convert a calculated value into a measured value or prove laboratory provenance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var evidenceComposition: some View {
        if !evidenceCounts.isEmpty {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Returned Field Evidence Classes").font(.headline)
                        Spacer()
                        Text("FIELD COUNTS ONLY").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                    }
                    Chart(evidenceCounts) { item in
                        BarMark(x: .value("Class", item.name), y: .value("Fields", item.count))
                    }
                    .frame(height: 210)
                    Text("This chart counts returned fields by lexical evidence class. It does not compare or aggregate their numeric values.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var streamLedger: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Canonical Stream Ledger").font(.headline)
                        Text("Recognized stream containers returned by the active result")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(filteredStreams.count) visible").font(.caption.monospaced()).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search stream, field path or returned value", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(9)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))

                if streams.isEmpty {
                    ContentUnavailableView(
                        "No stream ledger returned",
                        systemImage: "arrow.left.arrow.right.square",
                        description: Text("No recognized stream container is present in the active result. No synthetic stream is inserted.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 190)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 8) {
                                cell("Stream", 180, header: true)
                                cell("Mass flow", 120, header: true)
                                cell("Volume flow", 120, header: true)
                                cell("Solids", 100, header: true)
                                cell("Density", 100, header: true)
                                cell("P80", 100, header: true)
                                cell("pH", 80, header: true)
                                cell("Temperature", 115, header: true)
                                cell("Fields", 70, header: true)
                            }
                            .padding(.vertical, 8)
                            Divider().opacity(0.2)

                            ForEach(filteredStreams) { stream in
                                Button {
                                    selectedStreamID = stream.id
                                } label: {
                                    HStack(spacing: 8) {
                                        cell(stream.name, 180, emphasis: true)
                                        cell(stream.value(["mass_flow_tph", "mass_tph", "flow_tph", "solids_tph"]), 120)
                                        cell(stream.value(["volumetric_flow_m3_h", "volume_flow_m3_h", "flow_m3_h", "water_m3_h"]), 120)
                                        cell(stream.value(["solids_pct", "percent_solids", "solids_percent"]), 100)
                                        cell(stream.value(["density", "density_t_m3", "slurry_density"]), 100)
                                        cell(stream.value(["p80", "p80_um", "d80"]), 100)
                                        cell(stream.value(["ph", "pH"]), 80)
                                        cell(stream.value(["temperature_c", "temperature", "temp_c"]), 115)
                                        cell("\(stream.fields.count)", 70)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 5)
                                    .background(selectedStream?.id == stream.id ? AuroraTheme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                Divider().opacity(0.08)
                            }
                        }
                        .frame(minWidth: 1030, alignment: .leading)
                    }
                }
            }
        }
    }

    private func streamInspector(_ stream: PBStream) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stream.name).font(.title2.bold())
                        Text("Returned scalar state · values remain in their original representation")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: "\(stream.fields.count) fields")
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 9)], spacing: 9) {
                    ForEach(stream.fields) { field in fieldCard(field) }
                }

                Text("No magnitude chart is shown for stream variables because the returned fields may carry incompatible engineering units.")
                    .font(.caption2)
                    .foregroundStyle(AuroraTheme.warn)
            }
        }
    }

    private var balanceMatrix: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Conservation & Reconciliation Objects").font(.headline)
                        Text("Mass · water · mineral · element · species · charge · energy · reconciliation · residual ledgers")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(balances.count) returned").font(.caption.monospaced()).foregroundStyle(.secondary)
                }

                if balances.isEmpty {
                    ContentUnavailableView(
                        "No recognized balance object returned",
                        systemImage: "scale.3d",
                        description: Text("Closure is not inferred from process KPIs or from a zero-looking unrelated field.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 9)], spacing: 9) {
                        ForEach(balances) { balance in
                            Button { selectedBalanceID = balance.id } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: balance.closureClass.icon).foregroundStyle(balance.closureClass.color)
                                        Text(pretty(balance.id)).font(.caption.bold()).lineLimit(2)
                                        Spacer()
                                    }
                                    Text(balance.explicitStatus ?? "No explicit closure status")
                                        .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                                    HStack {
                                        Text("\(balance.fields.count) fields").font(.caption2).foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(balance.residualFields.count) residual-like").font(.caption2).foregroundStyle(AuroraTheme.gold)
                                    }
                                }
                                .padding(10)
                                .background(selectedBalance?.id == balance.id ? AuroraTheme.accent.opacity(0.11) : AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func balanceInspector(_ balance: PBBalance) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pretty(balance.id)).font(.title3.bold())
                        Text(balance.explicitStatus.map { "Explicit status: \($0)" } ?? "No explicit status returned")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: balance.closureClass.label)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 9)], spacing: 9) {
                    ForEach(balance.fields) { field in fieldCard(field) }
                }
            }
        }
    }

    @ViewBuilder
    private var residualLedger: some View {
        if !residualFields.isEmpty {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Returned Residual / Imbalance Ledger").font(.headline)
                        Spacer()
                        Text("\(residualFields.count) fields").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                    }
                    Text("Residual values are shown individually. No cross-balance residual norm is calculated on-device because units and scaling may differ.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(residualFields.prefix(200)) { field in
                        HStack(alignment: .top, spacing: 10) {
                            Text(field.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            Spacer(minLength: 12)
                            Text(field.displayValue).font(.caption.monospaced()).multilineTextAlignment(.trailing).textSelection(.enabled)
                        }
                        Divider().opacity(0.08)
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
                        Text("Stream & Balance Deliverables").font(.headline)
                        Text("Exports only recognized returned stream/balance objects and explicit classification metadata.")
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

                if projects.first == nil || (streams.isEmpty && balances.isEmpty) {
                    Text("Export requires a project and at least one recognized returned stream or balance object.")
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
            guard let project = projects.first, !(streams.isEmpty && balances.isEmpty) else { return }
            exportRequested = true
            app.exportProcessBalance(project: project, streams: streams, balances: balances, format: format)
        } label: { Label(title, systemImage: icon) }
        .buttonStyle(.bordered)
        .disabled(projects.first == nil || (streams.isEmpty && balances.isEmpty) || app.isExporting)
    }

    @ViewBuilder
    private var rawAudit: some View {
        if let result = app.activeResult {
            AuroraCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Complete Result Audit").font(.headline)
                    Text("The complete active result remains available for traceability; the balance workspace above is a conservative recognized-object projection.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Open raw governed response") {
                        Text(result.prettyString()).font(.caption2.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func fieldCard(_ field: PBField) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(field.name).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text(pretty(field.evidenceClass)).font(.system(size: 8, weight: .bold)).foregroundStyle(field.evidenceColor)
            }
            Text(field.displayValue).font(.caption.monospaced()).textSelection(.enabled).lineLimit(4)
            Text(field.path).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.65)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        }
    }

    private func cell(_ value: String, _ width: CGFloat, header: Bool = false, emphasis: Bool = false) -> some View {
        Text(value.isEmpty ? "—" : value)
            .font(header ? .caption.bold() : emphasis ? .caption.bold() : .caption.monospaced())
            .foregroundStyle(header ? .secondary : .primary)
            .lineLimit(2)
            .frame(width: width, alignment: .leading)
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }
}

struct PBField: Identifiable {
    let id: String
    let name: String
    let path: String
    let raw: JSONValue

    var displayValue: String { raw.stringValue ?? raw.prettyString() }

    var numericValue: Double? {
        switch raw {
        case .number(let value): return value
        case .string(let text):
            return Double(text.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    var evidenceClass: String {
        let lower = path.lowercased()
        if lower.contains("measured") || lower.contains("measurement") || lower.contains("observed") || lower.contains("assay") { return "measured_tagged" }
        if lower.contains("reconciled") || lower.contains("reconciliation") || lower.contains("wls") || lower.contains("adjusted") { return "reconciled_tagged" }
        if lower.contains("estimated") || lower.contains("estimate") || lower.contains("predicted") || lower.contains("modelled") || lower.contains("modeled") { return "estimated_tagged" }
        if lower.contains("assumed") || lower.contains("default") || lower.contains("heuristic") { return "assumed_tagged" }
        if lower.contains("calculated") || lower.contains("derived") || lower.contains("computed") { return "calculated_tagged" }
        return "unqualified_returned"
    }

    var evidenceColor: Color {
        switch evidenceClass {
        case "measured_tagged": return AuroraTheme.good
        case "reconciled_tagged": return AuroraTheme.accent
        case "estimated_tagged": return AuroraTheme.gold
        case "assumed_tagged": return AuroraTheme.warn
        case "calculated_tagged": return .secondary
        default: return .secondary
        }
    }

    static let evidenceOrder = ["measured_tagged", "reconciled_tagged", "calculated_tagged", "estimated_tagged", "assumed_tagged", "unqualified_returned"]
}

struct PBStream: Identifiable {
    let id: String
    let name: String
    let fields: [PBField]

    func value(_ keys: [String]) -> String {
        for key in keys {
            if let match = fields.first(where: { $0.name.lowercased() == key.lowercased() }) { return match.displayValue }
        }
        return "—"
    }
}

enum PBClosureClass {
    case closed, issue, reported, unreported

    var label: String {
        switch self {
        case .closed: return "Explicit closed/pass"
        case .issue: return "Explicit issue/open"
        case .reported: return "Status reported"
        case .unreported: return "Closure unreported"
        }
    }

    var icon: String {
        switch self {
        case .closed: return "checkmark.seal.fill"
        case .issue: return "exclamationmark.triangle.fill"
        case .reported: return "info.circle.fill"
        case .unreported: return "questionmark.diamond.fill"
        }
    }

    var color: Color {
        switch self {
        case .closed: return AuroraTheme.good
        case .issue: return AuroraTheme.bad
        case .reported: return AuroraTheme.accent
        case .unreported: return .secondary
        }
    }
}

struct PBBalance: Identifiable {
    let id: String
    let fields: [PBField]
    let explicitStatus: String?

    var residualFields: [PBField] {
        fields.filter {
            let lower = $0.path.lowercased()
            return lower.contains("residual") || lower.contains("imbalance") || lower.contains("closure_error") || lower.contains("balance_error") || lower.contains("mismatch")
        }
    }

    var closureClass: PBClosureClass {
        guard let explicitStatus, !explicitStatus.isEmpty else { return .unreported }
        let lower = explicitStatus.lowercased()
        if ["fail", "failed", "open", "error", "violation", "not_closed", "unclosed"].contains(where: { lower.contains($0) }) { return .issue }
        if ["pass", "passed", "closed", "ok", "balanced", "success"].contains(where: { lower.contains($0) }) { return .closed }
        return .reported
    }
}

private struct PBEvidenceCount: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

private enum PBParser {
    private static let streamKeys = ["streams", "process_streams", "stream_table", "material_streams", "stream_ledger"]
    private static let balanceKeys = [
        "mass_balance", "water_balance", "mineral_balance", "element_balance", "species_balance", "charge_balance",
        "energy_balance", "conservation", "conservation_ledger", "residual_ledger", "balance_ledger", "balances", "reconciliation"
    ]

    static func streams(from result: JSONValue?) -> [PBStream] {
        guard let result else { return [] }
        for key in streamKeys {
            guard let value = result.recursiveFind(key) else { continue }
            let parsed = parseStreams(value, root: key)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    static func balances(from result: JSONValue?) -> [PBBalance] {
        guard let result else { return [] }
        var output: [PBBalance] = []
        var seen = Set<String>()
        for key in balanceKeys {
            guard let value = result.recursiveFind(key) else { continue }
            for balance in parseBalances(value, root: key) where seen.insert(balance.id).inserted {
                output.append(balance)
            }
        }
        return output
    }

    private static func parseStreams(_ value: JSONValue, root: String) -> [PBStream] {
        switch value {
        case .array(let items):
            return items.enumerated().compactMap { index, item in parseStream(item, nameHint: nil, id: "\(root)[\(index)]") }
        case .object(let object):
            if object.values.allSatisfy({ if case .object = $0 { return true }; return false }) {
                return object.keys.sorted().compactMap { key in
                    guard let item = object[key] else { return nil }
                    return parseStream(item, nameHint: key, id: "\(root).\(key)")
                }
            }
            if let stream = parseStream(value, nameHint: nil, id: root) { return [stream] }
            return []
        default: return []
        }
    }

    private static func parseStream(_ value: JSONValue, nameHint: String?, id: String) -> PBStream? {
        guard case .object(let object) = value else { return nil }
        let name = nameHint ?? firstString(object, ["name", "stream_name", "stream", "id", "tag", "label"]) ?? id
        let fields = flatten(object, root: id)
        guard !fields.isEmpty else { return nil }
        return PBStream(id: id, name: name, fields: fields)
    }

    private static func parseBalances(_ value: JSONValue, root: String) -> [PBBalance] {
        switch value {
        case .array(let items):
            return items.enumerated().compactMap { index, item in balance(item, id: "\(root)[\(index)]") }
        case .object(let object):
            let nestedObjects = object.filter { _, value in if case .object = value { return true }; return false }
            if !nestedObjects.isEmpty && nestedObjects.count == object.count {
                return nestedObjects.keys.sorted().compactMap { key in
                    guard let item = nestedObjects[key] else { return nil }
                    return balance(item, id: "\(root).\(key)")
                }
            }
            if let one = balance(value, id: root) { return [one] }
            return []
        default:
            if let one = balance(value, id: root) { return [one] }
            return []
        }
    }

    private static func balance(_ value: JSONValue, id: String) -> PBBalance? {
        switch value {
        case .object(let object):
            let fields = flatten(object, root: id)
            let status = firstString(object, ["closure_status", "closure", "status", "state", "balance_status", "conservation_status"])
            guard !fields.isEmpty else { return nil }
            return PBBalance(id: id, fields: fields, explicitStatus: status)
        default:
            return PBBalance(id: id, fields: [PBField(id: id, name: id, path: id, raw: value)], explicitStatus: nil)
        }
    }

    private static func flatten(_ object: [String: JSONValue], root: String) -> [PBField] {
        var fields: [PBField] = []
        func walk(_ value: JSONValue, path: String, name: String, depth: Int) {
            guard depth <= 5, fields.count < 500 else { return }
            switch value {
            case .object(let nested):
                for key in nested.keys.sorted() {
                    if let child = nested[key] { walk(child, path: path + "." + key, name: key, depth: depth + 1) }
                }
            case .array(let items):
                for (index, child) in items.prefix(80).enumerated() { walk(child, path: path + "[\(index)]", name: "\(name)[\(index)]", depth: depth + 1) }
            default:
                fields.append(PBField(id: path, name: name, path: path, raw: value))
            }
        }
        for key in object.keys.sorted() {
            if let value = object[key] { walk(value, path: root + "." + key, name: key, depth: 0) }
        }
        return fields
    }

    private static func firstString(_ object: [String: JSONValue], _ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.stringValue, !value.isEmpty { return value }
        }
        return nil
    }
}

extension AppModel {
    func exportProcessBalance(project: AuroraProject, streams: [PBStream], balances: [PBBalance], format: String) {
        guard !isExporting, !(streams.isEmpty && balances.isEmpty) else { return }
        isExporting = true
        lastError = nil
        let api = AURORAAPI()

        let streamRows = streams.map { stream in
            JSONValue.object([
                "id": .string(stream.id),
                "name": .string(stream.name),
                "fields": .array(stream.fields.map { field in
                    .object([
                        "path": .string(field.path),
                        "name": .string(field.name),
                        "value": .string(field.displayValue),
                        "evidence_class": .string(field.evidenceClass)
                    ])
                })
            ])
        }

        let balanceRows = balances.map { balance in
            JSONValue.object([
                "id": .string(balance.id),
                "explicit_status": balance.explicitStatus.map(JSONValue.string) ?? .null,
                "closure_class": .string(balance.closureClass.label),
                "fields": .array(balance.fields.map { field in
                    .object([
                        "path": .string(field.path),
                        "name": .string(field.name),
                        "value": .string(field.displayValue),
                        "evidence_class": .string(field.evidenceClass)
                    ])
                })
            ])
        }

        let body = JSONValue.object([
            "format": .string(format),
            "filename": .string("AURORA_Stream_Balance_" + project.name),
            "project": project.payload,
            "designBasis": .object([
                "export_scope": .string("recognized_returned_stream_and_balance_objects"),
                "authority": .string("active_result_returned_values_only"),
                "closure_rule": .string("explicit_status_text_only"),
                "field_evidence_rule": .string("lexical_ui_classification_only"),
                "stream_count": .number(Double(streams.count)),
                "balance_count": .number(Double(balances.count))
            ]),
            "analyses": .array([]),
            "flowsheet": .object([:]),
            "diagnostics": .array([]),
            "result": .object([
                "streams": .array(streamRows),
                "balances": .array(balanceRows)
            ]),
            "run": .object([
                "id": activeJobID.map(JSONValue.string) ?? .null,
                "origin": .string(activeResultOrigin),
                "status": .string(runStatus),
                "scope": .string("stream_balance_workspace")
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
