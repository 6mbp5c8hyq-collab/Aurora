import Foundation

enum ExecutionGovernancePolicyV3 {
    static func finalize(_ value: JSONValue) -> JSONValue {
        ExecutionSubmodelScopeV3.enrich(finalizeBase(value))
    }

    private static func finalizeBase(_ value: JSONValue) -> JSONValue {
        switch value {
        case .array(let rows):
            return .array(rows.map(finalizeBase))
        case .object(let object):
            var out: [String: JSONValue] = [:]
            for (key, child) in object { out[key] = finalizeBase(child) }
            applyRawDiagnosisPolicy(to: &out)
            return .object(out)
        default:
            return value
        }
    }

    static func directDispatchBlockReason(_ value: JSONValue) -> String? {
        guard let governance = recursiveFind(value, key: "executionGovernance"),
              case .object(let object) = governance else { return nil }

        if object["dagExecutable"] == .bool(false) {
            return "AURORA execution is blocked because the process graph is not executable: \(object["blockReason"]?.stringValue ?? "graph/policy validation failed")"
        }

        guard let requested = firstString(value, keys: ["requested_module", "requestedModule", "engine_id", "engineId"]),
              !requested.isEmpty else { return nil }

        if let blocked = object["blockedEngines"], case .array(let rows) = blocked {
            for row in rows {
                guard case .object(let item) = row,
                      item["id"]?.stringValue == requested else { continue }
                return "AURORA engine \(requested) is ineligible for this project: \(item["reason"]?.stringValue ?? "route/mode mismatch")"
            }
        }
        return nil
    }

    static func governedFullRunBypassReason(_ value: JSONValue) -> String? {
        guard let governance = recursiveFind(value, key: "executionGovernance"),
              case .object(let object) = governance,
              object["serverEnforcementRequired"] == .bool(true) else { return nil }

        if object["dagExecutable"] == .bool(false) {
            return object["blockReason"]?.stringValue ?? "Process graph is not executable."
        }

        if let requested = firstString(value, keys: ["requested_module", "requestedModule", "engine_id", "engineId"]),
           !requested.isEmpty {
            return nil
        }

        return "Governed full-project execution must use the selective DAG fan-out; /api/jobs requires an explicit eligible requested_module."
    }

    private static func applyRawDiagnosisPolicy(to object: inout [String: JSONValue]) {
        guard let basis = object["designBasis"], case .object(let design) = basis,
              design["objective"]?.stringValue == ScientificProjectObjective.rawOreDiagnosis.rawValue,
              let governanceValue = object["executionGovernance"], case .object(var governance) = governanceValue,
              let graphValidation = governance["graphValidation"], case .object(let graph) = graphValidation else { return }

        let nodeCount = number(graph["nodeCount"]) ?? 0
        let blockersEmpty: Bool
        if let blockers = graph["blockers"], case .array(let rows) = blockers { blockersEmpty = rows.isEmpty }
        else { blockersEmpty = true }

        guard nodeCount == 0, blockersEmpty else { return }

        governance["dagExecutable"] = .bool(true)
        governance["blockReason"] = .string("")
        governance["executionClass"] = .string("graphless_raw_ore_diagnosis")
        governance["diagnosticGraphExemption"] = .bool(true)
        governance["diagnosticGraphExemptionAuthority"] = .string("explicit_raw_ore_diagnosis_objective")
        object["executionGovernance"] = .object(governance)
    }

    private static func recursiveFind(_ value: JSONValue, key: String) -> JSONValue? {
        switch value {
        case .object(let object):
            if let direct = object[key] { return direct }
            for child in object.values { if let found = recursiveFind(child, key: key) { return found } }
        case .array(let rows):
            for child in rows { if let found = recursiveFind(child, key: key) { return found } }
        default: break
        }
        return nil
    }

    private static func firstString(_ value: JSONValue, keys: [String]) -> String? {
        for key in keys {
            if let found = recursiveFind(value, key: key)?.stringValue { return found }
        }
        return nil
    }

    private static func number(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .number(let n): return n
        case .string(let text): return Double(text)
        default: return nil
        }
    }
}
