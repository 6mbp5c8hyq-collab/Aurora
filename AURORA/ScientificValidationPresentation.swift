import SwiftUI

struct ScientificValidationPresentation: Equatable {
    let metadataPresent: Bool
    let effectiveStatus: String
    let applicability: String
    let engineeringGradeEligible: Bool
    let industrialVerifiedInScope: Bool
    let resultAuthority: String
    let requiredLabel: String
    let exportMark: String?
    let claimBlockers: [String]
    let evidenceIDs: [String]

    static let missing = ScientificValidationPresentation(
        metadataPresent: false,
        effectiveStatus: "UNVERIFIED",
        applicability: "UNKNOWN",
        engineeringGradeEligible: false,
        industrialVerifiedInScope: false,
        resultAuthority: "validation_metadata_missing",
        requiredLabel: "VALIDATION METADATA MISSING · NOT ENGINEERING-GRADE",
        exportMark: "SCIENTIFIC VALIDATION METADATA MISSING",
        claimBlockers: ["No machine-readable scientific-validation receipt was returned for this engine result."],
        evidenceIDs: []
    )

    static func parse(engineResult: JSONValue?) -> ScientificValidationPresentation {
        guard let engineResult else { return .missing }
        guard let receipt = validationReceipt(in: engineResult) else { return .missing }

        let policy = object(receipt["presentation_policy"])
        let status = receipt["effective_status"]?.stringValue?.uppercased() ?? "UNVERIFIED"
        let applicability = receipt["applicability"]?.stringValue?.uppercased() ?? "UNKNOWN"
        let engineering = receipt["engineering_grade_eligible"]?.boolValue ?? false
        let industrial = receipt["industrial_verified_in_scope"]?.boolValue ?? false
        let authority = receipt["result_authority"]?.stringValue ?? "scientific_claim_authority_unspecified"
        let required = policy?["required_label"]?.stringValue
            ?? receipt["required_label"]?.stringValue
            ?? defaultLabel(status: status, engineering: engineering)
        let exportMark = policy?["export_mark"]?.stringValue
            ?? receipt["export_mark"]?.stringValue

        return ScientificValidationPresentation(
            metadataPresent: true,
            effectiveStatus: status,
            applicability: applicability,
            engineeringGradeEligible: engineering,
            industrialVerifiedInScope: industrial,
            resultAuthority: authority,
            requiredLabel: required,
            exportMark: exportMark,
            claimBlockers: strings(receipt["claim_blockers"]),
            evidenceIDs: strings(receipt["evidence_ids"])
        )
    }

    var shortStatus: String {
        guard metadataPresent else { return "VALIDATION MISSING" }
        if engineeringGradeEligible { return effectiveStatus }
        return "\(effectiveStatus) · NOT ENGINEERING-GRADE"
    }

    var engineeringLabel: String {
        if industrialVerifiedInScope { return "INDUSTRIAL VERIFIED · EPC CLAIM ELIGIBLE" }
        if engineeringGradeEligible { return "ENGINEERING-GRADE ELIGIBLE IN SCOPE" }
        return "NOT ENGINEERING-GRADE"
    }

    var tint: Color {
        if industrialVerifiedInScope { return AuroraTheme.good }
        if engineeringGradeEligible { return AuroraTheme.accent }
        if effectiveStatus == "UNVERIFIED" || !metadataPresent { return .red }
        return AuroraTheme.warn
    }

    private static func validationReceipt(in value: JSONValue) -> [String: JSONValue]? {
        if case .object(let object) = value {
            if let nested = object["scientific_validation"],
               let nestedObject = self.object(nested),
               nestedObject["effective_status"] != nil {
                return nestedObject
            }
            if object["effective_status"] != nil,
               object["engineering_grade_eligible"] != nil {
                return object
            }
        }
        return nil
    }

    private static func defaultLabel(status: String, engineering: Bool) -> String {
        engineering ? "\(status) · WITHIN DECLARED VALIDITY ENVELOPE" : "\(status) · NOT ENGINEERING-GRADE"
    }

    fileprivate static func object(_ value: JSONValue?) -> [String: JSONValue]? {
        guard let value, case .object(let object) = value else { return nil }
        return object
    }

    fileprivate static func strings(_ value: JSONValue?) -> [String] {
        guard let value else { return [] }
        switch value {
        case .array(let values):
            return values.compactMap(\.stringValue)
        case .string(let value):
            return value.isEmpty ? [] : [value]
        default:
            return []
        }
    }
}

struct ScientificValidationAggregate: Equatable {
    let metadataPresent: Bool
    let engineeringGradeEligible: Bool
    let engineCount: Int
    let classifiedEngineCount: Int
    let blockingEngines: [String]
    let resultAuthority: String

    static let missing = ScientificValidationAggregate(
        metadataPresent: false,
        engineeringGradeEligible: false,
        engineCount: 0,
        classifiedEngineCount: 0,
        blockingEngines: [],
        resultAuthority: "validation_summary_missing"
    )

    static func parse(result: JSONValue?) -> ScientificValidationAggregate {
        guard let result,
              let summary = findAggregate(in: result) else { return .missing }
        return ScientificValidationAggregate(
            metadataPresent: true,
            engineeringGradeEligible: summary["engineering_grade_eligible"]?.boolValue ?? false,
            engineCount: Int(summary["engine_count"]?.doubleValue ?? 0),
            classifiedEngineCount: Int(summary["classified_engine_count"]?.doubleValue ?? 0),
            blockingEngines: ScientificValidationPresentation.strings(summary["blocking_engines"]),
            resultAuthority: summary["result_authority"]?.stringValue ?? "scientific_claim_authority_unspecified"
        )
    }

    private static func findAggregate(in value: JSONValue) -> [String: JSONValue]? {
        switch value {
        case .object(let object):
            if let scientific = object["scientific_validation"],
               let candidate = ScientificValidationPresentation.object(scientific),
               candidate["engine_count"] != nil || candidate["blocking_engines"] != nil {
                return candidate
            }
            for child in object.values {
                if let found = findAggregate(in: child) { return found }
            }
        case .array(let values):
            for child in values {
                if let found = findAggregate(in: child) { return found }
            }
        default:
            break
        }
        return nil
    }
}

struct ScientificValidationBanner: View {
    let presentation: ScientificValidationPresentation
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.engineeringGradeEligible ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(compact ? .body.bold() : .title3.bold())
                    .foregroundStyle(presentation.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Scientific Validation Authority")
                        .font(compact ? .caption.bold() : .headline)
                    Text(presentation.requiredLabel)
                        .font(compact ? .caption2.bold() : .caption.bold())
                        .foregroundStyle(presentation.tint)
                }

                Spacer(minLength: 8)
                Text(presentation.engineeringLabel)
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(presentation.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(presentation.tint.opacity(0.11), in: Capsule())
            }

            if !compact {
                HStack(spacing: 8) {
                    authorityChip("STATUS", presentation.effectiveStatus)
                    authorityChip("APPLICABILITY", presentation.applicability)
                    authorityChip("EVIDENCE", "\(presentation.evidenceIDs.count)")
                }

                if !presentation.claimBlockers.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Claim blockers").font(.caption2.bold()).foregroundStyle(.secondary)
                        ForEach(Array(presentation.claimBlockers.prefix(4).enumerated()), id: \.offset) { _, blocker in
                            Text("• \(blocker)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let exportMark = presentation.exportMark, !exportMark.isEmpty {
                    Text("EXPORT MARK · \(exportMark)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(AuroraTheme.warn)
                }
            }
        }
        .padding(compact ? 10 : 12)
        .background(presentation.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(presentation.tint.opacity(0.28), lineWidth: 1)
        )
    }

    private func authorityChip(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 9, weight: .bold, design: .monospaced)).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(AuroraTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ScientificValidationAggregateBanner: View {
    let result: JSONValue?

    var body: some View {
        let summary = ScientificValidationAggregate.parse(result: result)
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.engineeringGradeEligible ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(summary.engineeringGradeEligible ? AuroraTheme.good : AuroraTheme.warn)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Scientific Claim Authority").font(.headline)
                    if !summary.metadataPresent {
                        Text("Validation summary is missing. The active result must be treated as NOT ENGINEERING-GRADE until a canonical scientific-validation receipt is returned.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if summary.engineeringGradeEligible {
                        Text("All classified engines in this returned DAG result are engineering-grade eligible within their declared validation envelopes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This result set contains unvalidated, insufficiently validated, or out-of-scope engine output. Numeric values remain inspectable, but the result set is not engineering-grade as a whole.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if summary.metadataPresent {
                        Text("\(summary.classifiedEngineCount)/\(summary.engineCount) engines classified · \(summary.blockingEngines.count) blocking")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        if !summary.blockingEngines.isEmpty {
                            Text("Blocking: " + summary.blockingEngines.prefix(8).joined(separator: ", "))
                                .font(.caption2.monospaced())
                                .foregroundStyle(AuroraTheme.warn)
                        }
                    }
                }

                Spacer()
                Text(summary.engineeringGradeEligible ? "ENGINEERING-GRADE ELIGIBLE" : "NOT ENGINEERING-GRADE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(summary.engineeringGradeEligible ? AuroraTheme.good : AuroraTheme.warn)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background((summary.engineeringGradeEligible ? AuroraTheme.good : AuroraTheme.warn).opacity(0.11), in: Capsule())
            }
        }
    }
}
