import SwiftUI

struct ResultsExplorerView: View {
    @EnvironmentObject private var app: AppModel
    @State private var query = ""
    @State private var numericOnly = false
    @State private var expandedDomains: Set<String> = []

    private var rows: [ResultExplorerRow] {
        guard let result = app.activeResult else { return [] }
        return result.flattenedScalars(limit: 5000).map { path, value in
            ResultExplorerRow(path: path, value: value)
        }
    }

    private var filteredRows: [ResultExplorerRow] {
        rows.filter { row in
            let queryMatch = query.isEmpty
                || row.path.localizedCaseInsensitiveContains(query)
                || row.value.localizedCaseInsensitiveContains(query)
            return queryMatch && (!numericOnly || row.numericValue != nil)
        }
    }

    private var groupedRows: [(String, [ResultExplorerRow])] {
        let groups = Dictionary(grouping: filteredRows, by: \.domain)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchBar
                summary
                domainNavigator
                resultLedger
                rawAuthority
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
    }

    private var header: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.16))
                        .frame(width: 66, height: 66)
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title.bold())
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Results Explorer").font(.largeTitle.bold())
                    Text("Search the complete governed output without using raw JSON as the primary interface")
                        .foregroundStyle(.secondary)
                    Text("Every displayed value is read from the active AURORA result. Paths preserve their source hierarchy so chemistry, process, mining, economics, evidence and engineering outputs remain auditable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.activeResult == nil ? "No result" : ResultTools.status(app.activeResult))
            }
        }
    }

    private var searchBar: some View {
        AuroraCard {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search path or value — e.g. recovery, p80, water, npv, mineral", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Numeric only", isOn: $numericOnly)
                    .toggleStyle(.switch)
                    .fixedSize()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
            metric("Output paths", "\(rows.count)", "point.3.filled.connected.trianglepath.dotted")
            metric("Visible", "\(filteredRows.count)", "line.3.horizontal.decrease.circle")
            metric("Domains", "\(Set(rows.map(\.domain)).count)", "square.grid.3x3.fill")
            metric("Numeric", "\(rows.filter { $0.numericValue != nil }.count)", "number.square.fill")
            metric("Artifacts", "\(ResultTools.artifacts(app.activeResult).count)", "doc.richtext.fill")
            metric("Origin", app.activeResultOrigin, "externaldrive.fill")
        }
    }

    @ViewBuilder
    private var domainNavigator: some View {
        if !groupedRows.isEmpty {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Output Domains").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                        ForEach(groupedRows, id: \.0) { domain, domainRows in
                            Button {
                                if expandedDomains.contains(domain) {
                                    expandedDomains.remove(domain)
                                } else {
                                    expandedDomains.insert(domain)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pretty(domain)).font(.caption.bold()).lineLimit(1)
                                        Text("\(domainRows.count) values").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: expandedDomains.contains(domain) ? "chevron.up.circle.fill" : "chevron.down.circle")
                                        .foregroundStyle(AuroraTheme.accent)
                                }
                                .padding(10)
                                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultLedger: some View {
        if app.activeResult == nil {
            AuroraCard {
                ContentUnavailableView(
                    "No active result",
                    systemImage: "waveform.path.ecg",
                    description: Text("Run AURORA or recover a result from Result Vault.")
                )
            }
        } else if filteredRows.isEmpty {
            AuroraCard {
                ContentUnavailableView(
                    "No matching output",
                    systemImage: "magnifyingglass",
                    description: Text("Change the search expression or disable Numeric only.")
                )
            }
        } else {
            ForEach(groupedRows, id: \.0) { domain, domainRows in
                if query.isEmpty && !expandedDomains.contains(domain) {
                    EmptyView()
                } else {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(pretty(domain)).font(.headline)
                                Spacer()
                                Text("\(domainRows.count) paths")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(domainRows.prefix(250)) { row in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.path)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                        if row.numericValue != nil {
                                            Text("NUMERIC")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(AuroraTheme.gold)
                                        }
                                    }
                                    Spacer(minLength: 14)
                                    Text(row.value)
                                        .font(.caption.monospaced())
                                        .multilineTextAlignment(.trailing)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: 320, alignment: .trailing)
                                }
                                .padding(.vertical, 4)
                                Divider().opacity(0.08)
                            }
                            if domainRows.count > 250 {
                                Text("Showing the first 250 matching paths in this domain. Narrow the search to inspect the remainder.")
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
                    HStack {
                        Text("Authority & Raw Result").font(.headline)
                        Spacer()
                        if let ceiling = ResultTools.ceiling(result) {
                            StatusBadge(text: ceiling)
                        }
                    }
                    Text("Raw JSON remains available for audit and debugging, but is intentionally secondary to the structured explorer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("Open raw governed response") {
                        Text(result.prettyString())
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold()).lineLimit(2).minimumScaleFactor(0.65)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
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

private struct ResultExplorerRow: Identifiable {
    let id = UUID()
    let path: String
    let value: String
    let numericValue: Double?
    let domain: String

    init(path: String, value: String) {
        self.path = path
        self.value = value
        let sanitized = value
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.numericValue = Double(sanitized)
        self.domain = path
            .split(whereSeparator: { $0 == "." || $0 == "[" })
            .first
            .map(String.init) ?? "root"
    }
}
