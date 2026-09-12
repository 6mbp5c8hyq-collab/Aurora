import Foundation

extension JSONValue {
    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            let clean = value
                .replacingOccurrences(of: "%", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(clean)
        case .bool(let value):
            return value ? 1 : 0
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1", "ready", "ok", "pass", "passed": return true
            case "false", "no", "0", "not_ready", "failed", "fail": return false
            default: return nil
            }
        default:
            return nil
        }
    }
}
