import SwiftUI
import SwiftData
import Charts

struct ProcessBalanceView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedStreamID: String?

    private var streams: [ProcessStreamRow] {
        ProcessResultParser.streams(from: app.activeResult)
    }

    private var balanceGroups: [BalanceGroup] {
        ProcessResultParser.balances(from: app.activeResult)
    }

    private var selectedStream: ProcessStreamRow? {
        streams.first { $0.id == selectedStreamID } ?? streams.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                summaryStrip
                streamLedger
                if let selectedStream {
                    streamInspector(selectedStream)
                }
                balanceLedger
                evidenceNote
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.16))
                        .frame(width: 68, height: 68)
                    Image(systemName: "arrow.left.arrow.right.square.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Stream & Balance Center")
                        .font(.largeTitle.bold())
                    Text("Canonical material streams · conservation ledgers · closure residuals")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("This surface reports only stream and balance values returned by the active AURORA result. Missing quantities remain explicitly unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.activeResult == nil ? "No active result" : "Result linked")
            }
        }
    }

    private var summaryStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            metric("Streams", "\(streams.count)", "point.topleft.down.curvedto.point.bottomright.up")
            metric("Balance groups", "\(balanceGroups.count)", "scale.3d")
            metric("Measured fields", "\(streams.reduce(0) { $0 + $1.fields.count })", "list.bullet.rectangle")
            metric("Closure posture", closureLabel, "checkmark.seal.fill")
        }
    }

    private var streamLedger: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Canonical Stream Ledger").font(.headline)
                        Text("Material, water and state variables discovered in the active result")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let project = projects.first {
                        Text(project.name).font(.caption).foregroundStyle(AuroraTheme.gold)
                    }
                }

                if streams.isEmpty {
                    ContentUnavailableView(
                        "No stream ledger returned",
                        systemImage: "arrow.left.arrow.right.square",
                        description: Text("The active result does not currently expose streams, process_streams, stream_table, material_streams or stream_ledger. No synthetic stream values are inserted.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            streamHeader
                            Divider().opacity(0.25)
                            ForEach(streams) { stream in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.16)) { selectedStreamID = stream.id }
                                } label: {
                                    streamRow(stream)
                                }
                                .buttonStyle(.plain)
                                Divider().opacity(0.10)
                            }
                        }
                        .frame(minWidth: 920, alignment: .leading)
                    }
                }
            }
        }
    }

    private var streamHeader: some View {
        HStack(spacing: 8) {
            tableCell("Stream", width: 180, header: true)
            tableCell("Mass t/h", width: 95, header: true)
            tableCell("Vol. m³/h", width: 95, header: true)
            tableCell("Solids %", width: 90, header: true)
            tableCell("Density", width: 90, header: true)
            tableCell("P80", width: 90, header: true)
            tableCell("pH", width: 70, header: true)
            tableCell("Temp °C", width: 85, header: true)
            tableCell("Status", width: 105, header: true)
        }
        .padding(.vertical, 8)
    }

    private func streamRow(_ stream: ProcessStreamRow) -> some View {
        let selected = selectedStream?.id == stream.id
        return HStack(spacing: 8) {
            tableCell(stream.name, width: 180, emphasis: true)
            tableCell(stream.value(keys: ["mass_flow_tph", "mass_tph", "flow_tph", "solids_tph"]), width: 95)
            tableCell(stream.value(keys: ["volumetric_flow_m3_h", "volume_flow_m3_h", "flow_m3_h", "water_m3_h"]), width: 95)
            tableCell(stream.value(keys: ["solids_pct", "percent_solids", "solids_percent"]), width: 90)
            tableCell(stream.value(keys: ["density", "density_t_m3", "slurry_density"]), width: 90)
            tableCell(stream.value(keys: ["p80", "p80_um", "d80"]), width: 90)
            tableCell(stream.value(keys: ["ph", "pH"]), width: 70)
            tableCell(stream.value(keys: ["temperature_c", "temperature", "temp_c"]), width: 85)
            tableCell(stream.status.uppercased(), width: 105, emphasis: true)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background(selected ? AuroraTheme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func streamInspector(_ stream: ProcessStreamRow) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stream.name).font(.title2.bold())
                        Text("Complete scalar state returned for this stream")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: stream.status)
                }

                if stream.numericFields.isEmpty {
                    Text("No numeric state variables are present for this stream.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(stream.numericFields.prefix(12)) { field in
                        BarMark(
                            x: .value("Variable", field.name),
                            y: .value("Value", field.value)
                        )
                    }
                    .frame(height: 220)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 9)], spacing: 9) {
                    ForEach(stream.fields) { field in
                        HStack(alignment: .top, spacing: 8) {
                            Text(field.name)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text(field.displayValue)
                                .font(.caption2.monospaced())
                                .multilineTextAlignment(.trailing)
                                .lineLimit(3)
                        }
                        .padding(9)
                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var balanceLedger: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Conservation & Reconciliation Ledger").font(.headline)
                        Text("Mass · water · mineral · element · species · charge · energy · residual closure")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: closureLabel)
                }

                if balanceGroups.isEmpty {
                    ContentUnavailableView(
                        "No conservation ledger exposed",
                        systemImage: "scale.3d",
                        description: Text("AURORA has not exposed a recognized balance/residual object in the active result. The interface does not infer closure from unrelated KPIs.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(balanceGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.title).font(.subheadline.bold())
                                Spacer()
                                StatusBadge(text: group.status)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], spacing: 8) {
                                ForEach(group.fields) { field in
                                    HStack(alignment: .top) {
                                        Text(field.name)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 8)
                                        Text(field.displayValue)
                                            .font(.caption2.monospaced())
                                            .multilineTextAlignment(.trailing)
                                    }
                                    .padding(8)
                                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                        }
                        Divider().opacity(0.14)
                    }
                }
            }
        }
    }

    private var evidenceNote: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(AuroraTheme.gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidence rule").font(.subheadline.bold())
                    Text("Values shown here are parsed from the active AURORA runtime result. A blank field means the runtime did not return that quantity; it is not automatically estimated by the iOS client.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var closureLabel: String {
        guard !balanceGroups.isEmpty else { return "Not reported" }
        if balanceGroups.contains(where: { $0.status.lowercased().contains("fail") || $0.status.lowercased().contains("open") || $0.status.lowercased().contains("error") }) {
            return "Closure issue"
        }
        if balanceGroups.contains(where: { $0.status.lowercased().contains("pass") || $0.status.lowercased().contains("closed") || $0.status.lowercased().contains("ok") }) {
            return "Reported closed"
        }
        return "Reported"
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.65)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tableCell(_ text: String, width: CGFloat, header: Bool = false, emphasis: Bool = false) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(header ? .caption.bold() : emphasis ? .caption.bold() : .caption.monospaced())
            .foregroundStyle(header ? .secondary : .primary)
            .lineLimit(2)
            .frame(width: width, alignment: .leading)
    }
}

private struct ProcessField: Identifiable, Hashable {
    let id: String
    let name: String
    let raw: JSONValue

    var displayValue: String {
        raw.stringValue ?? raw.prettyString()
    }

    var numericValue: Double? {
        switch raw {
        case .number(let value): return value
        case .string(let text):
            let normalized = text
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(normalized)
        default: return nil
        }
    }
}

private struct NumericProcessField: Identifiable {
    let id: String
    let name: String
    let value: Double
}

private struct ProcessStreamRow: Identifiable {
    let id: String
    let name: String
    let status: String
    let fields: [ProcessField]

    var numericFields: [NumericProcessField] {
        fields.compactMap { field in
            guard let value = field.numericValue else { return nil }
            return NumericProcessField(id: field.id, name: field.name, value: value)
        }
    }

    func value(keys: [String]) -> String {
        let lowered = Dictionary(uniqueKeysWithValues: fields.map { ($0.name.lowercased(), $0.displayValue) })
        for key in keys {
            if let value = lowered[key.lowercased()] { return value }
        }
        return "—"
    }
}

private struct BalanceGroup: Identifiable {
    let id: String
    let title: String
    let status: String
    let fields: [ProcessField]
}

private enum ProcessResultParser {
    private static let streamKeys = ["streams", "process_streams", "stream_table", "material_streams", "stream_ledger"]
    private static let balanceKeys = [
        "mass_balance", "water_balance", "mineral_balance", "element_balance", "species_balance",
        "charge_balance", "energy_balance", "conservation", "conservation_ledger", "residual_ledger",
        "balance_ledger", "balances", "reconciliation"
    ]

    static func streams(from result: JSONValue?) -> [ProcessStreamRow] {
        guard let result else { return [] }
        for key in streamKeys {
            guard let found = result.recursiveFind(key) else { continue }
            let parsed = parseStreamContainer(found)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    static func balances(from result: JSONValue?) -> [BalanceGroup] {
        guard let result else { return [] }
        var output: [BalanceGroup] = []
        var used = Set<String>()

        for key in balanceKeys {
            guard let found = result.recursiveFind(key) else { continue }
            let group = parseBalance(key: key, value: found)
            if !group.fields.isEmpty, used.insert(group.id).inserted {
                output.append(group)
            }
        }
        return output
    }

    private static func parseStreamContainer(_ value: JSONValue) -> [ProcessStreamRow] {
        switch value {
        case .array(let items):
            return items.enumerated().compactMap { index, item in parseStream(item, index: index, hintedName: nil) }
        case .object(let object):
            if object.values.allSatisfy({ if case .object = $0 { return true }; return false }) {
                return object.keys.sorted().enumerated().compactMap { index, key in
                    guard let item = object[key] else { return nil }
                    return parseStream(item, index: index, hintedName: key)
                }
            }
            if let row = parseStream(value, index: 0, hintedName: nil) { return [row] }
            return []
        default:
            return []
        }
    }

    private static func parseStream(_ value: JSONValue, index: Int, hintedName: String?) -> ProcessStreamRow? {
        guard case .object(let object) = value else { return nil }
        let name = hintedName
            ?? firstScalar(object, keys: ["name", "stream_name", "stream", "id", "tag", "label"])
            ?? "Stream \(index + 1)"
        let status = firstScalar(object, keys: ["status", "state", "authority", "evidence_status"]) ?? "reported"

        var fields: [ProcessField] = []
        for key in object.keys.sorted() {
            guard !["name", "stream_name", "stream", "id", "tag", "label"].contains(key), let raw = object[key] else { continue }
            flatten(value: raw, path: key, output: &fields, limit: 80)
        }
        return ProcessStreamRow(id: "\(index)-\(name)", name: name, status: status, fields: fields)
    }

    private static func parseBalance(key: String, value: JSONValue) -> BalanceGroup {
        var fields: [ProcessField] = []
        flatten(value: value, path: "", output: &fields, limit: 120)
        let status = value.firstString(["status", "state", "closure_status", "balance_status", "gate"]) ?? inferredStatus(fields)
        let title = key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
        return BalanceGroup(id: key, title: title, status: status, fields: fields)
    }

    private static func inferredStatus(_ fields: [ProcessField]) -> String {
        for field in fields {
            let key = field.name.lowercased()
            let value = field.displayValue.lowercased()
            if key.contains("status") || key.contains("closure") || key.contains("gate") {
                return value
            }
        }
        return "reported"
    }

    private static func firstScalar(_ object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let scalar = object[key]?.stringValue, !scalar.isEmpty { return scalar }
        }
        return nil
    }

    private static func flatten(value: JSONValue, path: String, output: inout [ProcessField], limit: Int) {
        guard output.count < limit else { return }
        switch value {
        case .object(let object):
            for key in object.keys.sorted() {
                guard let child = object[key] else { continue }
                let next = path.isEmpty ? key : "\(path).\(key)"
                flatten(value: child, path: next, output: &output, limit: limit)
            }
        case .array(let array):
            if array.count <= 12 && array.allSatisfy({ $0.stringValue != nil }) {
                output.append(ProcessField(id: path, name: path, raw: .string(array.compactMap { $0.stringValue }.joined(separator: ", "))))
            } else {
                for (index, child) in array.prefix(20).enumerated() {
                    flatten(value: child, path: "\(path)[\(index)]", output: &output, limit: limit)
                }
            }
        default:
            output.append(ProcessField(id: path, name: path, raw: value))
        }
    }
}
