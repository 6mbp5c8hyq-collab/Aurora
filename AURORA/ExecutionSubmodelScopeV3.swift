import Foundation

enum ExecutionSubmodelScopeV3 {
    static let revision = "AURORA-SUBMODEL-SCOPE-V3-2026.09.17"

    private static let routeSensitiveCatalog: [String: [String]] = [
        "comminution": ["crushing", "grinding", "milling"],
        "classification": ["screening", "desliming", "hydrocyclone"],
        "flotation": ["flotation"],
        "magnetic_gravity": ["magnetic separation", "gravity separation"],
        "hydrometallurgy": ["leaching"],
        "water_circuit": ["scrubbing", "desliming", "hydrocyclone", "flotation", "leaching", "thickening", "filtration"]
    ]

    static func enrich(_ value: JSONValue) -> JSONValue {
        switch value {
        case .array(let rows):
            return .array(rows.map(enrich))
        case .object(let object):
            var out: [String: JSONValue] = [:]
            for (key, child) in object { out[key] = enrich(child) }
            apply(to: &out)
            return .object(out)
        default:
            return value
        }
    }

    private static func apply(to object: inout [String: JSONValue]) {
        guard let governanceValue = object["executionGovernance"],
              case .object(var governance) = governanceValue,
              let flowsheet = object["flowsheet"],
              case .object(let flowsheetObject) = flowsheet else { return }

        let graphUnits = Set(extractGraphUnits(flowsheetObject).map(normalize))
        let eligible = Set(arrayStrings(governance["eligibleEngines"]))
        let mode = (governance["processingMode"]?.stringValue ?? designMode(object)).lowercased()
        var scopes: [String: JSONValue] = [:]

        for (engineID, catalog) in routeSensitiveCatalog where eligible.contains(engineID) {
            let allowed = catalog.filter { graphUnits.contains(normalize($0)) }
            let blocked = catalog.filter { !allowed.contains($0) }
            let strict = !allowed.isEmpty

            scopes[engineID] = .object([
                "engineID": .string(engineID),
                "scopeRevision": .string(revision),
                "processingMode": .string(mode),
                "allowedUnitOperations": .array(allowed.map(JSONValue.string)),
                "blockedUnitOperations": .array(blocked.map(JSONValue.string)),
                "strictResultScope": .bool(strict),
                "scopeAuthority": .string(strict ? "user_declared_process_graph" : "engine_eligibility_without_explicit_submodel_node"),
                "scopeFailurePolicy": .string(strict ? "fail_closed_on_blocked_submodel_output" : "engine_family_only_no_submodel_claim")
            ])
        }

        governance["submodelScopeRevision"] = .string(revision)
        governance["engineScopes"] = .object(scopes)
        governance["submodelScopeAuthority"] = .string("deterministic_graph_unit_operation_scope")
        object["executionGovernance"] = .object(governance)
    }

    private static func extractGraphUnits(_ flowsheet: [String: JSONValue]) -> [String] {
        if let graph = flowsheet["graph"], case .object(let graphObject) = graph,
           let nodes = graphObject["nodes"], case .array(let rows) = nodes {
            return rows.compactMap { row in
                guard case .object(let object) = row else { return nil }
                return object["unitType"]?.stringValue ?? object["unit_type"]?.stringValue ?? object["label"]?.stringValue
            }
        }
        if let units = flowsheet["units"], case .array(let rows) = units {
            return rows.compactMap { row in
                if let text = row.stringValue { return text }
                guard case .object(let object) = row else { return nil }
                return object["unitType"]?.stringValue ?? object["name"]?.stringValue ?? object["type"]?.stringValue
            }
        }
        return []
    }

    private static func designMode(_ object: [String: JSONValue]) -> String {
        guard let value = object["designBasis"], case .object(let basis) = value else { return "unspecified" }
        return basis["processingMode"]?.stringValue ?? "unspecified"
    }

    private static func arrayStrings(_ value: JSONValue?) -> [String] {
        guard let value, case .array(let rows) = value else { return [] }
        return rows.compactMap(\.stringValue)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
