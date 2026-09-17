import SwiftUI
import SwiftData
import Foundation

struct ProcessGraphValidationV3: Hashable {
    let valid: Bool
    let blockers: [String]
    let warnings: [String]
    let nodeCount: Int
    let edgeCount: Int
    let recycleCount: Int

    var json: JSONValue {
        .object([
            "valid": .bool(valid),
            "blockers": .array(blockers.map(JSONValue.string)),
            "warnings": .array(warnings.map(JSONValue.string)),
            "nodeCount": .number(Double(nodeCount)),
            "edgeCount": .number(Double(edgeCount)),
            "recycleCount": .number(Double(recycleCount))
        ])
    }
}

struct EngineEligibilityDecisionV3: Identifiable, Hashable {
    let id: String
    let eligible: Bool
    let reason: String
}

enum ProcessExecutionGovernanceV3 {
    static let graphRevision = "AURORA-PROCESS-GRAPH-V3-2026.09.17"
    static let compilerRevision = "AURORA-ENGINE-ELIGIBILITY-V3-2026.09.17"

    static let canonicalEngines = [
        "ore_intelligence", "resource_model", "comminution", "classification", "flotation",
        "magnetic_gravity", "hydrometallurgy", "thermodynamics", "water_circuit", "conservation",
        "equipment_epc", "economics", "tailings", "digital_twin", "hybrid_ai", "diagnostics"
    ]

    private static let structuralUnits: Set<String> = ["rom feed", "feed", "product", "tailings", "waste"]
    private static let hardWetUnits: Set<String> = [
        "scrubbing", "desliming", "flotation", "leaching", "thickening", "filtration", "hydrocyclone"
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

    static func dispatchBlockReason(_ value: JSONValue) -> String? {
        guard let module = firstString(value, keys: ["requested_module", "requestedModule", "engine_id", "engineId"]),
              !module.isEmpty else { return nil }
        guard let governance = recursiveFind(value, key: "executionGovernance"),
              case .object(let object) = governance else { return nil }

        if object["dagExecutable"] == .bool(false) {
            let reason = object["blockReason"]?.stringValue ?? "Process graph is not executable."
            return "AURORA execution blocked before dispatch: \(reason)"
        }

        if let blocked = object["blockedEngines"], case .array(let rows) = blocked {
            for row in rows {
                guard case .object(let item) = row else { continue }
                if item["id"]?.stringValue == module {
                    return "AURORA engine \(module) is ineligible for this process graph: \(item["reason"]?.stringValue ?? "route/mode mismatch")"
                }
            }
        }
        return nil
    }

    static func receipt(for project: AuroraProject) -> JSONValue {
        enrich(project.payload).recursiveFind("executionGovernance") ?? .object([:])
    }

    static func decisions(for project: AuroraProject) -> [EngineEligibilityDecisionV3] {
        let enriched = enrich(project.payload)
        guard let governance = enriched.recursiveFind("executionGovernance"),
              case .object(let object) = governance else { return [] }
        var decisions: [EngineEligibilityDecisionV3] = []
        if let eligible = object["eligibleEngines"], case .array(let rows) = eligible {
            for row in rows {
                if let id = row.stringValue { decisions.append(.init(id: id, eligible: true, reason: "Eligible for declared route")) }
            }
        }
        if let blocked = object["blockedEngines"], case .array(let rows) = blocked {
            for row in rows {
                guard case .object(let item) = row,
                      let id = item["id"]?.stringValue else { continue }
                decisions.append(.init(id: id, eligible: false, reason: item["reason"]?.stringValue ?? "Ineligible"))
            }
        }
        return decisions.sorted { $0.id < $1.id }
    }

    private static func apply(to object: inout [String: JSONValue]) {
        guard let projectValue = object["project"],
              case .object(let projectObject) = projectValue,
              let rawID = projectObject["id"]?.stringValue,
              let projectID = UUID(uuidString: rawID),
              let rawFlowsheet = object["flowsheet"] else { return }

        let savedBasis = loadSavedBasis(projectID: projectID)
        let (flowsheet, graph, validation) = compileFlowsheet(rawFlowsheet)
        object["flowsheet"] = flowsheet

        let decisions = compileEligibility(graph: graph, validation: validation, basis: savedBasis)
        let eligible = decisions.filter(\.eligible).map(\.id)
        let blocked = decisions.filter { !$0.eligible }

        let hardPolicyBlock = policyBlockers(graph: graph, basis: savedBasis)
        let allBlockers = validation.blockers + hardPolicyBlock
        let dagExecutable = allBlockers.isEmpty && validation.nodeCount > 0

        object["executionGovernance"] = .object([
            "revision": .string(compilerRevision),
            "graphRevision": .string(graphRevision),
            "authority": .string("deterministic_route_and_mode_compiler"),
            "scientificBasisState": .string(savedBasis == nil ? "legacy_unspecified_pass_through" : "explicit_v3_basis"),
            "processingMode": .string(savedBasis?.processingMode.rawValue ?? "unspecified"),
            "dagExecutable": .bool(dagExecutable),
            "blockReason": .string(allBlockers.joined(separator: "; ")),
            "eligibleEngines": .array(eligible.map(JSONValue.string)),
            "blockedEngines": .array(blocked.map { decision in
                .object(["id": .string(decision.id), "reason": .string(decision.reason)])
            }),
            "graphValidation": validation.json,
            "policyBlockers": .array(hardPolicyBlock.map(JSONValue.string)),
            "serverEnforcementRequired": .bool(true),
            "clientDirectDispatchEnforced": .bool(true)
        ])
    }

    private static func compileFlowsheet(_ value: JSONValue) -> (JSONValue, JSONValue, ProcessGraphValidationV3) {
        var root: [String: JSONValue]
        if case .object(let object) = value { root = object } else { root = ["units": .array([])] }

        let graph: JSONValue
        if let existing = root["graph"], case .object(let graphObject) = existing,
           graphObject["nodes"] != nil, graphObject["edges"] != nil {
            graph = normalizeExistingGraph(existing)
        } else {
            graph = linearGraph(from: root["units"] ?? .array([]))
        }
        root["graph"] = graph
        root["graphSchemaVersion"] = .string(graphRevision)
        root["topology_authority"] = .string("user_declared_process_graph")
        let validation = validate(graph)
        root["topology_validation"] = validation.json
        return (.object(root), graph, validation)
    }

    private static func linearGraph(from unitsValue: JSONValue) -> JSONValue {
        let names = unitNames(unitsValue)
        let nodes: [JSONValue] = names.enumerated().map { index, name in
            .object([
                "id": .string(String(format: "U%03d", index + 1)),
                "unitType": .string(name),
                "label": .string(name),
                "ordinal": .number(Double(index + 1)),
                "inputPorts": .array([.string("in")]),
                "outputPorts": .array([.string("out")])
            ])
        }
        let edges: [JSONValue] = names.indices.dropLast().map { index in
            .object([
                "id": .string(String(format: "S%03d", index + 1)),
                "fromNode": .string(String(format: "U%03d", index + 1)),
                "fromPort": .string("out"),
                "toNode": .string(String(format: "U%03d", index + 2)),
                "toPort": .string("in"),
                "streamClass": .string("material"),
                "recycle": .bool(false)
            ])
        }
        return .object([
            "schemaVersion": .string(graphRevision),
            "authority": .string("compiled_from_user_declared_linear_route"),
            "topologyStatus": .string("design_intent_not_as_built"),
            "nodes": .array(nodes),
            "edges": .array(edges)
        ])
    }

    private static func normalizeExistingGraph(_ graph: JSONValue) -> JSONValue {
        guard case .object(var object) = graph else { return graph }
        object["schemaVersion"] = .string(graphRevision)
        if object["authority"] == nil { object["authority"] = .string("user_declared_process_graph") }
        if object["topologyStatus"] == nil { object["topologyStatus"] = .string("design_intent_not_as_built") }
        return .object(object)
    }

    private static func validate(_ graph: JSONValue) -> ProcessGraphValidationV3 {
        guard case .object(let object) = graph,
              let nodesValue = object["nodes"], case .array(let nodeRows) = nodesValue,
              let edgesValue = object["edges"], case .array(let edgeRows) = edgesValue else {
            return .init(valid: false, blockers: ["Graph requires nodes and edges arrays."], warnings: [], nodeCount: 0, edgeCount: 0, recycleCount: 0)
        }

        let nodeIDs = nodeRows.compactMap { row -> String? in
            guard case .object(let item) = row else { return nil }
            return item["id"]?.stringValue
        }
        var blockers: [String] = []
        var warnings: [String] = []
        let uniqueNodeIDs = Set(nodeIDs)
        if nodeIDs.count != nodeRows.count { blockers.append("Every graph node requires an id.") }
        if uniqueNodeIDs.count != nodeIDs.count { blockers.append("Graph node ids must be unique.") }

        var edgeIDs: [String] = []
        var backbone: [String: Set<String>] = [:]
        var indegree: [String: Int] = Dictionary(uniqueKeysWithValues: uniqueNodeIDs.map { ($0, 0) })
        var undirected: [String: Set<String>] = Dictionary(uniqueKeysWithValues: uniqueNodeIDs.map { ($0, []) })
        var recycleCount = 0

        for row in edgeRows {
            guard case .object(let item) = row else { blockers.append("Every edge must be an object."); continue }
            guard let id = item["id"]?.stringValue,
                  let from = item["fromNode"]?.stringValue,
                  let to = item["toNode"]?.stringValue else {
                blockers.append("Every edge requires id, fromNode and toNode.")
                continue
            }
            edgeIDs.append(id)
            if from == to { blockers.append("Self-loop edge \(id) is not permitted.") }
            if !uniqueNodeIDs.contains(from) || !uniqueNodeIDs.contains(to) {
                blockers.append("Edge \(id) references an unknown node.")
                continue
            }
            undirected[from, default: []].insert(to)
            undirected[to, default: []].insert(from)
            let recycle = bool(item["recycle"]) ?? false
            if recycle {
                recycleCount += 1
            } else {
                backbone[from, default: []].insert(to)
                indegree[to, default: 0] += 1
            }
        }
        if Set(edgeIDs).count != edgeIDs.count { blockers.append("Graph edge ids must be unique.") }

        if uniqueNodeIDs.count > 1 {
            var visited: Set<String> = []
            if let start = uniqueNodeIDs.first {
                var stack = [start]
                while let current = stack.popLast() {
                    guard visited.insert(current).inserted else { continue }
                    stack.append(contentsOf: undirected[current, default: []])
                }
            }
            if visited.count != uniqueNodeIDs.count { blockers.append("Process graph contains disconnected nodes.") }
        }

        var queue = indegree.filter { $0.value == 0 }.map(\.key)
        var seen = 0
        var indegreeWork = indegree
        while let current = queue.popLast() {
            seen += 1
            for next in backbone[current, default: []] {
                indegreeWork[next, default: 0] -= 1
                if indegreeWork[next] == 0 { queue.append(next) }
            }
        }
        if seen != uniqueNodeIDs.count && !uniqueNodeIDs.isEmpty {
            blockers.append("A non-recycle cycle exists. Mark only intentional recycle closure edges as recycle=true.")
        }
        if recycleCount > 0 { warnings.append("Recycle edges are explicit and excluded from backbone acyclicity testing.") }
        if uniqueNodeIDs.isEmpty { warnings.append("No process units are declared.") }

        return .init(valid: blockers.isEmpty, blockers: blockers, warnings: warnings, nodeCount: nodeRows.count, edgeCount: edgeRows.count, recycleCount: recycleCount)
    }

    private static func compileEligibility(graph: JSONValue, validation: ProcessGraphValidationV3, basis: ScientificProjectBasisV3?) -> [EngineEligibilityDecisionV3] {
        let units = Set(graphUnitNames(graph).map(normalize))
        let mode = basis?.processingMode
        let objective = basis?.objective ?? ""
        let hasGraph = validation.valid && validation.nodeCount > 0

        func hasAny(_ terms: Set<String>) -> Bool { !units.isDisjoint(with: terms) }
        func decision(_ id: String, _ eligible: Bool, _ reason: String) -> EngineEligibilityDecisionV3 {
            .init(id: id, eligible: eligible, reason: reason)
        }

        let wetPresent = !units.isDisjoint(with: hardWetUnits)
        let wetAllowed = mode != .dry
        var out: [EngineEligibilityDecisionV3] = []
        out.append(decision("ore_intelligence", true, "Project/ore diagnostic authority is route-independent."))
        out.append(decision("resource_model", true, "Resource context is route-independent."))
        out.append(decision("comminution", hasAny(["crushing", "grinding", "milling"]), "Requires Crushing/Grinding/Milling in the graph."))
        out.append(decision("classification", hasAny(["screening", "classification", "desliming", "hydrocyclone"]), "Requires a classification unit in the graph."))
        out.append(decision("flotation", hasAny(["flotation"]) && wetAllowed, mode == .dry ? "Flotation is water-dependent and is blocked in explicit dry mode." : "Requires Flotation in the graph."))
        out.append(decision("magnetic_gravity", hasAny(["magnetic separation", "gravity separation"]), "Requires magnetic or gravity separation in the graph."))
        let hydroRoute = hasAny(["leaching"]) || ["acid_production", "critical_metals_recovery"].contains(objective)
        out.append(decision("hydrometallurgy", hydroRoute && wetAllowed, mode == .dry ? "Hydrometallurgy is blocked in explicit dry mode." : "Requires Leaching or a hydrometallurgical objective."))
        let thermoRoute = hydroRoute || wetPresent || mode == .wet || mode == .hybrid
        out.append(decision("thermodynamics", thermoRoute && wetAllowed, mode == .dry ? "Wet aqueous thermodynamics is not scheduled for an explicit dry route." : "Requires wet/hybrid chemistry context."))
        let waterRoute = wetPresent || mode == .wet || mode == .hybrid
        out.append(decision("water_circuit", waterRoute && wetAllowed, mode == .dry ? "Water-circuit engine is blocked in explicit dry mode." : "Requires a water-dependent route."))
        out.append(decision("conservation", hasGraph, "Requires a valid non-empty process graph."))
        out.append(decision("equipment_epc", hasGraph, "Requires a valid non-empty process graph."))
        out.append(decision("economics", hasGraph, "Requires a valid non-empty process graph."))
        out.append(decision("tailings", hasAny(["tailings"]), "Requires a Tailings node in the graph."))
        out.append(decision("digital_twin", hasGraph, "Requires a valid process topology."))
        out.append(decision("hybrid_ai", hasGraph, "Requires a valid process topology."))
        out.append(decision("diagnostics", hasGraph, "Requires a valid process topology."))
        return out
    }

    private static func policyBlockers(graph: JSONValue, basis: ScientificProjectBasisV3?) -> [String] {
        guard let basis else { return [] }
        let units = Set(graphUnitNames(graph).map(normalize))
        let prohibited = Set(basis.prohibitedUnitOperations.map(normalize).filter { !$0.isEmpty })
        let allowed = Set(basis.allowedUnitOperations.map(normalize).filter { !$0.isEmpty })
        var blockers: [String] = []

        let forbiddenPresent = units.intersection(prohibited)
        if !forbiddenPresent.isEmpty {
            blockers.append("Graph contains explicitly prohibited unit operations: \(forbiddenPresent.sorted().joined(separator: ", ")).")
        }

        if !allowed.isEmpty {
            let operational = units.subtracting(structuralUnits)
            let outside = operational.subtracting(allowed)
            if !outside.isEmpty {
                blockers.append("Graph contains operations outside the explicit allow-list: \(outside.sorted().joined(separator: ", ")).")
            }
        }

        if basis.processingMode == .dry {
            let wet = units.intersection(hardWetUnits)
            if !wet.isEmpty {
                blockers.append("Explicit dry mode conflicts with water-dependent units: \(wet.sorted().joined(separator: ", ")).")
            }
        }
        return blockers
    }

    private static func loadSavedBasis(projectID: UUID) -> ScientificProjectBasisV3? {
        let key = "aurora.scientificProjectBasisV3." + projectID.uuidString
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ScientificProjectBasisV3.self, from: data)
    }

    private static func unitNames(_ value: JSONValue) -> [String] {
        guard case .array(let rows) = value else { return [] }
        return rows.compactMap { row in
            switch row {
            case .string(let value): return value
            case .object(let object):
                return object["unitType"]?.stringValue ?? object["unit_type"]?.stringValue ?? object["name"]?.stringValue ?? object["type"]?.stringValue
            default: return nil
            }
        }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func graphUnitNames(_ graph: JSONValue) -> [String] {
        guard case .object(let object) = graph,
              let nodes = object["nodes"], case .array(let rows) = nodes else { return [] }
        return rows.compactMap { row in
            guard case .object(let item) = row else { return nil }
            return item["unitType"]?.stringValue ?? item["unit_type"]?.stringValue ?? item["label"]?.stringValue
        }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func bool(_ value: JSONValue?) -> Bool? {
        guard let value else { return nil }
        if case .bool(let flag) = value { return flag }
        if case .string(let text) = value { return ["true", "1", "yes"].contains(text.lowercased()) }
        return nil
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
}

extension AURORAAPI {
    func runEligibilityGovernedProject(_ payload: JSONValue, onUpdate: @Sendable (JSONValue) async -> Void) async throws -> JSONValue {
        let governed = ProcessExecutionGovernanceV3.enrich(payload)
        if let governance = governed.recursiveFind("executionGovernance"),
           case .object(let object) = governance,
           object["dagExecutable"] == .bool(false) {
            throw AURORAAPI.APIError.executionGovernanceBlocked(object["blockReason"]?.stringValue ?? "Process graph is not executable.")
        }
        return try await runProject(governed, onUpdate: onUpdate)
    }

    func runEligibilityGoverned(_ payload: JSONValue, onUpdate: @Sendable (JSONValue) async -> Void) async throws -> JSONValue {
        let governed = ProcessExecutionGovernanceV3.enrich(payload)
        if let reason = ProcessExecutionGovernanceV3.dispatchBlockReason(governed) {
            throw AURORAAPI.APIError.executionGovernanceBlocked(reason)
        }
        return try await run(governed, onUpdate: onUpdate)
    }
}

struct ProcessGraphEligibilityV3View: View {
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedProjectID: UUID?

    private var selectedProject: AuroraProject? {
        if let selectedProjectID, let project = projects.first(where: { $0.id == selectedProjectID }) { return project }
        return projects.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Process Graph & Execution Eligibility V3").font(.title2.bold())
                        Text("Directed topology is compiled from the declared route unless an explicit nodes/edges graph is supplied. Eligibility controls direct engine dispatch and emits a server-enforcement contract for DAG execution.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !projects.isEmpty {
                    AuroraCard {
                        Picker("Project", selection: Binding<UUID?>(get: { selectedProjectID ?? projects.first?.id }, set: { selectedProjectID = $0 })) {
                            ForEach(projects) { project in Text(project.name).tag(Optional(project.id)) }
                        }.pickerStyle(.menu)
                    }
                }
                if let project = selectedProject {
                    graphSummary(project)
                    engineMatrix(project)
                } else {
                    ContentUnavailableView("No project", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Create a project in Project Intake."))
                }
            }.padding(22)
        }
        .background(AuroraTheme.background)
        .navigationTitle("Execution Eligibility V3")
        .onAppear { selectedProjectID = selectedProjectID ?? projects.first?.id }
    }

    private func graphSummary(_ project: AuroraProject) -> some View {
        let receipt = ProcessExecutionGovernanceV3.receipt(for: project)
        let validation = receipt.recursiveFind("graphValidation")
        let nodes = validation?.recursiveFind("nodeCount")?.stringValue ?? "0"
        let edges = validation?.recursiveFind("edgeCount")?.stringValue ?? "0"
        let recycles = validation?.recursiveFind("recycleCount")?.stringValue ?? "0"
        let executable = receipt.recursiveFind("dagExecutable")?.stringValue ?? "false"
        let reason = receipt.recursiveFind("blockReason")?.stringValue ?? ""
        return AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Directed Graph Contract").font(.headline)
                HStack { metric("Nodes", nodes); metric("Edges", edges); metric("Recycles", recycles); metric("DAG", executable.uppercased()) }
                if !reason.isEmpty { Text(reason).font(.caption).foregroundStyle(AuroraTheme.warn) }
                Text("Splits and merges are represented by multiple outgoing/incoming edges. Recycle closure edges must be explicitly tagged recycle=true; hidden cycles fail closed.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func engineMatrix(_ project: AuroraProject) -> some View {
        let rows = ProcessExecutionGovernanceV3.decisions(for: project)
        return AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Engine Eligibility Compiler").font(.headline)
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.eligible ? "checkmark.circle.fill" : "nosign")
                            .foregroundStyle(row.eligible ? AuroraTheme.good : AuroraTheme.warn)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.id).font(.caption.bold().monospaced())
                            Text(row.reason).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.eligible ? "ELIGIBLE" : "BLOCKED").font(.caption2.bold())
                    }
                    Divider().opacity(0.1)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospaced())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
