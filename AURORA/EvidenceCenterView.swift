import SwiftUI

struct EvidenceCenterView: View {
    @EnvironmentObject private var app: AppModel

    private var sections: [EvidenceSection] {
        EvidenceParser.sections(from: app.activeResult)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                posture
                evidenceSections
                missingAuthority
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AuroraTheme.gold.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(AuroraTheme.gold)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Evidence & Uncertainty Center").font(.largeTitle.bold())
                    Text("Provenance · validation · uncertainty · applicability · governance")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Only evidence objects explicitly returned by the active AURORA result are surfaced. Absence is treated as an evidence gap, not silently filled by the iOS client.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.activeResult == nil ? "No active result" : "Evidence linked")
            }
        }
    }

    private var posture: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            postureCard("Claim ceiling", claimCeiling, "gauge.with.dots.needle.67percent")
            postureCard("Result origin", app.activeResultOrigin, "point.3.connected.trianglepath.dotted")
            postureCard("Evidence groups", "\(sections.count)", "books.vertical.fill")
            postureCard("Validation posture", validationPosture, "checkmark.seal.fill")
            postureCard("Uncertainty", uncertaintyPosture, "plusminus.circle.fill")
            postureCard("OOD / domain", domainPosture, "scope")
        }
    }

    private var evidenceSections: some View {
        VStack(spacing: 14) {
            if sections.isEmpty {
                AuroraCard {
                    ContentUnavailableView(
                        "No evidence ledger reported",
                        systemImage: "checkmark.shield",
                        description: Text("The active result does not expose recognized evidence, validation, uncertainty, provenance, applicability-domain or governance objects.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 230)
                }
            } else {
                ForEach(sections) { section in
                    evidenceCard(section)
                }
            }
        }
    }

    private func evidenceCard(_ section: EvidenceSection) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.title).font(.headline)
                        Text(section.sourceKey).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: section.status)
                }

                if section.fields.isEmpty {
                    Text(section.scalarValue ?? "Reported without scalar detail")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 8)], spacing: 8) {
                        ForEach(section.fields) { field in
                            HStack(alignment: .top, spacing: 8) {
                                Text(field.name)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                Spacer(minLength: 8)
                                Text(field.value)
                                    .font(.caption2.monospaced())
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                                    .lineLimit(5)
                            }
                            .padding(9)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private var missingAuthority: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(AuroraTheme.warn)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Authority rule").font(.headline)
                    Text("A missing validation certificate, uncertainty statement, applicability-domain result or provenance field is displayed as missing/not reported. It does not inherit authority from a successful numerical result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var claimCeiling: String {
        ResultTools.ceiling(app.activeResult) ?? "Not reported"
    }

    private var validationPosture: String {
        postureFor(keys: ["validation", "validated", "validation_status", "validation_certificate", "benchmark_status"])
    }

    private var uncertaintyPosture: String {
        postureFor(keys: ["uncertainty", "uncertainty_status", "confidence", "confidence_interval", "prediction_interval"])
    }

    private var domainPosture: String {
        postureFor(keys: ["ood", "ood_status", "applicability_domain", "domain_status", "in_domain"])
    }

    private func postureFor(keys: [String]) -> String {
        guard let result = app.activeResult else { return "No result" }
        for key in keys {
            if let value = result.recursiveFind(key) {
                if let scalar = value.stringValue { return scalar }
                if case .object(let object) = value {
                    for candidate in ["status", "state", "result", "label", "classification"] {
                        if let scalar = object[candidate]?.stringValue { return scalar }
                    }
                    return "Reported"
                }
                return "Reported"
            }
        }
        return "Not reported"
    }

    private func postureCard(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.headline).lineLimit(2).minimumScaleFactor(0.72)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        }
    }
}

private struct EvidenceField: Identifiable {
    let id: String
    let name: String
    let value: String
}

private struct EvidenceSection: Identifiable {
    let id: String
    let title: String
    let sourceKey: String
    let status: String
    let scalarValue: String?
    let fields: [EvidenceField]
}

private enum EvidenceParser {
    private static let keys: [(String, String)] = [
        ("evidence", "Evidence"),
        ("evidence_ledger", "Evidence Ledger"),
        ("provenance", "Provenance"),
        ("data_lineage", "Data Lineage"),
        ("validation", "Validation"),
        ("validation_certificate", "Validation Certificate"),
        ("benchmarks", "Benchmarks"),
        ("benchmark", "Benchmark"),
        ("uncertainty", "Uncertainty"),
        ("uncertainty_quantification", "Uncertainty Quantification"),
        ("applicability_domain", "Applicability Domain"),
        ("ood", "Out-of-Domain Assessment"),
        ("ood_status", "Out-of-Domain Status"),
        ("governance", "Governance"),
        ("warnings", "Warnings"),
        ("diagnostics", "Diagnostics")
    ]

    static func sections(from result: JSONValue?) -> [EvidenceSection] {
        guard let result else { return [] }
        var output: [EvidenceSection] = []
        var seenFingerprints = Set<String>()

        for (key, title) in keys {
            guard let value = result.recursiveFind(key) else { continue }
            let fingerprint = value.prettyString()
            guard seenFingerprints.insert(fingerprint).inserted else { continue }

            let fields = flatten(value, root: key, limit: 100)
            let status = status(for: value)
            output.append(EvidenceSection(
                id: "\(key)-\(output.count)",
                title: title,
                sourceKey: key,
                status: status,
                scalarValue: value.stringValue,
                fields: fields
            ))
        }
        return output
    }

    private static func status(for value: JSONValue) -> String {
        if let scalar = value.stringValue { return scalar.count <= 36 ? scalar : "Reported" }
        if case .object(let object) = value {
            for key in ["status", "state", "result", "classification", "gate", "authority"] {
                if let scalar = object[key]?.stringValue { return scalar }
            }
        }
        return "Reported"
    }

    private static func flatten(_ value: JSONValue, root: String, limit: Int) -> [EvidenceField] {
        var output: [EvidenceField] = []

        func walk(_ item: JSONValue, path: String) {
            guard output.count < limit else { return }
            switch item {
            case .object(let object):
                for key in object.keys.sorted() {
                    guard let child = object[key] else { continue }
                    walk(child, path: path.isEmpty ? key : "\(path).\(key)")
                }
            case .array(let array):
                if array.count <= 20 && array.allSatisfy({ $0.stringValue != nil }) {
                    output.append(EvidenceField(
                        id: path,
                        name: path,
                        value: array.compactMap { $0.stringValue }.joined(separator: ", ")
                    ))
                } else {
                    for (index, child) in array.prefix(30).enumerated() {
                        walk(child, path: "\(path)[\(index)]")
                    }
                }
            default:
                output.append(EvidenceField(
                    id: path,
                    name: path.replacingOccurrences(of: "\(root).", with: ""),
                    value: item.stringValue ?? item.prettyString()
                ))
            }
        }

        walk(value, path: root)
        return output
    }
}
