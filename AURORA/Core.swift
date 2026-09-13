import SwiftUI
import Foundation
import SwiftData

enum AppConfig {
    static let defaultBackend = URL(string: "https://todo-app-production-afcc.up.railway.app")!
    static let key = "aurora.backend.url"

    static var backend: URL {
        if let raw = UserDefaults.standard.string(forKey: key),
           let url = URL(string: raw),
           url.scheme == "https" {
            return url
        }
        return defaultBackend
    }

    static func saveBackend(_ raw: String) throws {
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil else {
            throw URLError(.badURL)
        }
        UserDefaults.standard.set(
            url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            forKey: key
        )
    }
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.formatted(.number.precision(.fractionLength(0...4)))
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        default: return nil
        }
    }

    func data(pretty: Bool = false) -> Data? {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        }
        return try? encoder.encode(self)
    }

    func prettyString() -> String {
        String(decoding: data(pretty: true) ?? Data("{}".utf8), as: UTF8.self)
    }

    func recursiveFind(_ key: String) -> JSONValue? {
        switch self {
        case .object(let object):
            if let direct = object[key] { return direct }
            for value in object.values {
                if let found = value.recursiveFind(key) { return found }
            }
        case .array(let array):
            for value in array {
                if let found = value.recursiveFind(key) { return found }
            }
        default:
            break
        }
        return nil
    }

    func firstString(_ keys: [String]) -> String? {
        for key in keys {
            if let value = recursiveFind(key)?.stringValue { return value }
        }
        return nil
    }

    func flattenedScalars(limit: Int = 400) -> [(String, String)] {
        var output: [(String, String)] = []

        func walk(_ value: JSONValue, path: String) {
            guard output.count < limit else { return }
            switch value {
            case .object(let object):
                for key in object.keys.sorted() {
                    guard let child = object[key] else { continue }
                    walk(child, path: path.isEmpty ? key : "\(path).\(key)")
                }
            case .array(let array):
                for (index, child) in array.prefix(50).enumerated() {
                    walk(child, path: "\(path)[\(index)]")
                }
            default:
                if let scalar = value.stringValue { output.append((path, scalar)) }
            }
        }

        walk(self, path: "")
        return output
    }
}

@Model
final class AuroraProject {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var declaredFamily: String
    var feedTPH: Double
    var targetComponent: String
    var targetGrade: Double
    var notes: String
    var analysesJSON: String
    var flowsheetJSON: String

    init(
        name: String = "New AURORA Project",
        declaredFamily: String = "phosphate",
        feedTPH: Double = 100,
        targetComponent: String = "P2O5",
        targetGrade: Double = 35
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.declaredFamily = declaredFamily
        self.feedTPH = feedTPH
        self.targetComponent = targetComponent
        self.targetGrade = targetGrade
        self.notes = ""
        self.analysesJSON = "{}"
        self.flowsheetJSON = "{\"units\":[]}"
    }

    /// Canonical project object consumed by mobile_adapter_v220.AuroraMobileRuntime.
    var canonicalProject: JSONValue {
        .object([
            "id": .string(id.uuidString),
            "name": .string(name),
            "oreType": .string(declaredFamily),
            "feedTph": .number(feedTPH)
        ])
    }

    /// Canonical design-basis object consumed by mobile_adapter_v220.AuroraMobileRuntime.
    var canonicalDesignBasis: JSONValue {
        .object([
            "targetComponent": .string(targetComponent),
            "targetGrade": .number(targetGrade),
            "notes": .string(notes),
            "authority": .string("user_declared_design_basis")
        ])
    }

    /// Runtime-facing evidence rows. Local governance metadata remains preserved in analysesJSON,
    /// but the scientific runtime receives the array contract it actually validates.
    var canonicalAnalyses: JSONValue {
        let stored = storedAnalysesValue
        var rows: [JSONValue] = []
        var importedIsUnqualified = false

        if case .array(let directRows) = stored {
            importedIsUnqualified = true
            rows.append(contentsOf: directRows.compactMap { normalizedImportedRow($0, forceUnqualified: true) })
        } else if case .object(let root) = stored {
            importedIsUnqualified = root["import_authority"]?.stringValue == "user_imported_unqualified_input"
            if let imported = root["analyses"], case .array(let importedRows) = imported {
                rows.append(contentsOf: importedRows.compactMap { normalizedImportedRow($0, forceUnqualified: importedIsUnqualified) })
            }

            if let quick = root["quick_assays"], case .object(let quickValues) = quick {
                let metadata: [String: JSONValue]
                if let rawMetadata = root["quick_assay_metadata"], case .object(let object) = rawMetadata {
                    metadata = object
                } else {
                    metadata = [:]
                }
                for key in quickValues.keys.sorted() {
                    guard let value = quickValues[key],
                          let row = quickAnalysisRow(key: key, value: value, metadata: metadata[key]) else { continue }
                    rows.append(row)
                }
            }
        }

        _ = importedIsUnqualified
        return .array(rows)
    }

    /// Governance information travels beside the canonical scientific inputs, but is not promoted
    /// into the scientific evidence array and is ignored by runtimes that do not consume it.
    var canonicalInputGovernance: JSONValue {
        guard case .object(let root) = storedAnalysesValue else {
            return .object([
                "storage_authority": .string("unqualified_input_container"),
                "runtime_projection": .string("canonical_analysis_array")
            ])
        }

        var governance: [String: JSONValue] = [
            "runtime_projection": .string("canonical_analysis_array"),
            "measured_rule": .string("measured_requires_nonempty_source_reference")
        ]
        for key in [
            "quick_assays_authority", "quick_assay_metadata", "input_governance",
            "import_source", "import_authority", "import_record_count", "import_governance_note"
        ] {
            if let value = root[key] { governance[key] = value }
        }
        return .object(governance)
    }

    var canonicalFlowsheet: JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(flowsheetJSON.utf8)))
            ?? .object(["units": .array([])])
    }

    /// Exact inner payload expected by POST /api/validate and POST /api/dag/runs.
    var payload: JSONValue {
        .object([
            "project": canonicalProject,
            "designBasis": canonicalDesignBasis,
            "analyses": canonicalAnalyses,
            "flowsheet": canonicalFlowsheet,
            "inputGovernance": canonicalInputGovernance
        ])
    }

    private var storedAnalysesValue: JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(analysesJSON.utf8))) ?? .object([:])
    }

    private func numericValue(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .number(let number):
            return number.isFinite ? number : nil
        case .string(let text):
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "%", with: "")
            guard let number = Double(clean), number.isFinite else { return nil }
            return number
        default:
            return nil
        }
    }

    private func normalizedImportedRow(_ row: JSONValue, forceUnqualified: Bool) -> JSONValue? {
        guard case .object(var object) = row,
              let parameter = object["parameter"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !parameter.isEmpty,
              let number = numericValue(object["value"]) else { return nil }

        object["value"] = .number(number)
        if object["type"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            object["type"] = .string("Assay")
        }

        let existingStatus = object["status"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if forceUnqualified || existingStatus.isEmpty {
            object["status"] = .string("UNQUALIFIED")
        }

        let existingSource = object["source"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingSource.isEmpty {
            object["source"] = .string(forceUnqualified ? "unqualified_import" : "mobile_input")
        }
        if object["sample"] == nil { object["sample"] = .string("FEED") }
        return .object(object)
    }

    private func quickAnalysisRow(key: String, value: JSONValue, metadata: JSONValue?) -> JSONValue? {
        guard let number = numericValue(value) else { return nil }

        let type: String
        let parameter: String
        let defaultUnit: String
        switch key {
        case "P80_um":
            type = "PSD"; parameter = "P80"; defaultUnit = "µm"
        case "solids_pct":
            type = "Physical"; parameter = "solids_pct"; defaultUnit = "%"
        case "pH":
            type = "Water Chemistry"; parameter = "pH"; defaultUnit = ""
        default:
            type = "XRF"; parameter = key; defaultUnit = "%"
        }

        var requested = "user_declared"
        var effective = "user_declared"
        var sourceReference = ""
        var unit = defaultUnit
        if let metadata, case .object(let object) = metadata {
            requested = object["requested_authority"]?.stringValue ?? requested
            effective = object["effective_authority"]?.stringValue ?? requested
            sourceReference = object["source_reference"]?.stringValue ?? ""
            unit = object["unit"]?.stringValue ?? unit
        }

        let status: String
        switch effective.lowercased() {
        case "measured_source_tagged": status = "MEASURED"
        case "estimated": status = "ESTIMATED"
        case "assumed": status = "ASSUMED"
        case "user_declared": status = "DECLARED"
        default: status = "UNQUALIFIED"
        }

        let source: String
        if !sourceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source = sourceReference
        } else if requested.lowercased() == "measured" {
            source = "source_missing"
        } else {
            source = "mobile_quick_assay"
        }

        return .object([
            "type": .string(type),
            "parameter": .string(parameter),
            "value": .number(number),
            "unit": .string(unit),
            "status": .string(status),
            "source": .string(source),
            "sample": .string("FEED"),
            "authority_requested": .string(requested),
            "authority_effective": .string(effective)
        ])
    }
}

@Model
final class RunRecord {
    var id: UUID
    var projectID: UUID
    var createdAt: Date
    var updatedAt: Date
    var status: String
    var jobID: String?
    var rawResultJSON: String
    var errorText: String?

    init(projectID: UUID) {
        self.id = UUID()
        self.projectID = projectID
        self.createdAt = .now
        self.updatedAt = .now
        self.status = "queued"
        self.rawResultJSON = "{}"
    }
}

enum AuroraTheme {
    static let background = Color(red: 0.018, green: 0.035, blue: 0.050)
    static let panel = Color(red: 0.035, green: 0.063, blue: 0.082)
    static let panel2 = Color(red: 0.055, green: 0.090, blue: 0.112)
    static let accent = Color(red: 0.25, green: 0.71, blue: 0.98)
    static let gold = Color(red: 0.94, green: 0.69, blue: 0.26)
    static let good = Color(red: 0.24, green: 0.78, blue: 0.52)
    static let warn = Color(red: 0.96, green: 0.67, blue: 0.24)
    static let bad = Color(red: 0.95, green: 0.35, blue: 0.38)
}

struct AuroraCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AuroraTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

struct StatusBadge: View {
    let text: String

    private var tint: Color {
        let value = text.lowercased()
        if value.contains("success") || value.contains("complete") || value.contains("online") { return AuroraTheme.good }
        if value.contains("block") || value.contains("warn") || value.contains("govern") { return AuroraTheme.warn }
        if value.contains("error") || value.contains("fail") || value.contains("offline") { return AuroraTheme.bad }
        return AuroraTheme.accent
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}
