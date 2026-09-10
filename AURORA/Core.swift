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

    var payload: JSONValue {
        let analyses = (try? JSONDecoder().decode(JSONValue.self, from: Data(analysesJSON.utf8))) ?? .object([:])
        let flowsheet = (try? JSONDecoder().decode(JSONValue.self, from: Data(flowsheetJSON.utf8))) ?? .object(["units": .array([])])
        return .object([
            "project_id": .string(id.uuidString),
            "project_name": .string(name),
            "feed_tph": .number(feedTPH),
            "declared_family": .string(declaredFamily),
            "target_component": .string(targetComponent),
            "target_grade": .number(targetGrade),
            "notes": .string(notes),
            "analyses": analyses,
            "flowsheet": flowsheet
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
