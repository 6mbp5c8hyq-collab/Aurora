import Foundation
import SwiftUI

/// Read-only presentation model for the backend's canonical cross-phase audit.
/// The iOS client never recomputes balances or changes qualification decisions.
struct EngineeringIntegrityEvidence {
    struct UnitRow: Identifiable {
        let id: String
        let tag: String
        let state: String
        let inputTph: Double?
        let outputTph: Double?
        let residualTph: Double?
        let toleranceTph: Double?
    }

    let state: String
    let issueCount: Int?
    let holdCount: Int?
    let totalUnitChecks: Int?
    let failedUnitChecks: Int?
    let issues: [String]
    let designHolds: [String]
    let units: [UnitRow]

    static func parse(_ result: JSONValue?) -> EngineeringIntegrityEvidence? {
        guard let audit = result?.recursiveFind("engineering_cross_phase_integrity"),
              case .object(let fields) = audit else { return nil }

        let counts: [String: JSONValue]
        if let nested = fields["counts"], case .object(let dictionary) = nested {
            counts = dictionary
        } else {
            counts = [:]
        }

        func codes(_ key: String) -> [String] {
            guard let raw = fields[key], case .array(let records) = raw else { return [] }
            return records.compactMap { record in
                guard case .object(let obj) = record else { return nil }
                return obj["code"]?.stringValue
            }
        }

        var unitRows: [UnitRow] = []
        if let raw = fields["unit_mass_reconciliation"], case .array(let records) = raw {
            for (index, record) in records.enumerated() {
                guard case .object(let obj) = record else { continue }
                let tag = obj["tag"]?.stringValue ?? ""
                unitRows.append(UnitRow(
                    id: "\(tag)#\(index)",
                    tag: tag.isEmpty ? "Unit tag unreported" : tag,
                    state: obj["status"]?.stringValue ?? "UNREPORTED",
                    inputTph: finite(obj["input_solids_tph"]),
                    outputTph: finite(obj["output_solids_tph"]),
                    residualTph: finite(obj["residual_tph"]),
                    toleranceTph: finite(obj["allowed_residual_tph"])
                ))
            }
        }

        return EngineeringIntegrityEvidence(
            state: fields["status"]?.stringValue ?? "UNREPORTED",
            issueCount: count(fields["issue_count"]),
            holdCount: count(fields["hold_count"]),
            totalUnitChecks: count(counts["phase_b_unit_mass_checks"]),
            failedUnitChecks: count(counts["phase_b_unit_mass_failures"]),
            issues: codes("issues"),
            designHolds: codes("design_holds"),
            units: unitRows
        )
    }

    private static func finite(_ value: JSONValue?) -> Double? {
        guard let value, case .number(let n) = value, n.isFinite else { return nil }
        return n
    }

    private static func count(_ value: JSONValue?) -> Int? {
        guard let n = finite(value), n >= 0,
              n < Double(Int.max), n.rounded(.towardZero) == n else { return nil }
        return Int(n)
    }
}

struct EngineeringIntegrityPanel: View {
    let result: JSONValue?

    private var evidence: EngineeringIntegrityEvidence? {
        EngineeringIntegrityEvidence.parse(result)
    }

    var body: some View {
        if let evidence {
            AuroraCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cross-Phase Engineering Integrity")
                                .font(.headline)
                            Text("Canonical Phase B–C–H–J–K audit · server-reported evidence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(text: evidence.state)
                    }

                    Text("An audit PASS is not authorization for IFC drawings or OEM calibration. Design holds remain explicitly visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], spacing: 8) {
                        countTile("Issues", evidence.issueCount)
                        countTile("Design holds", evidence.holdCount)
                        countTile("Unit checks", evidence.totalUnitChecks)
                        countTile("Failed unit checks", evidence.failedUnitChecks)
                    }

                    if !evidence.issues.isEmpty {
                        codeSection("Blocking contradictions", values: evidence.issues, color: AuroraTheme.warn)
                    }
                    if !evidence.designHolds.isEmpty {
                        codeSection("Design holds", values: evidence.designHolds, color: AuroraTheme.gold)
                    }

                    if !evidence.units.isEmpty {
                        Text("Independent dry-solids reconciliation · t/h").font(.subheadline.bold())
                        ForEach(evidence.units.prefix(80)) { unit in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(unit.tag).font(.subheadline.bold()).lineLimit(2)
                                    Spacer()
                                    Text(unit.state.uppercased())
                                        .font(.caption2.monospaced().bold())
                                        .foregroundStyle(unit.state.lowercased() == "pass" ? AuroraTheme.good : AuroraTheme.warn)
                                }
                                Text("In: \(amount(unit.inputTph))  |  Out: \(amount(unit.outputTph))  |  Residual: \(amount(unit.residualTph))  |  Tolerance: \(amount(unit.toleranceTph))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                        }
                        if let total = evidence.totalUnitChecks, total > evidence.units.prefix(80).count {
                            Text("Showing only returned unit evidence; complete count: \(total).")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func countTile(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { String($0) } ?? "Unreported")
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func codeSection(_ title: String, values: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold()).foregroundStyle(color)
            ForEach(Array(values.prefix(8).enumerated()), id: \.offset) { entry in
                Text(entry.element).font(.caption.monospaced()).fixedSize(horizontal: false, vertical: true)
            }
            if values.count > 8 {
                Text("\(values.count - 8) additional entries are retained in the full canonical response.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func amount(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3f", value)
    }
}
