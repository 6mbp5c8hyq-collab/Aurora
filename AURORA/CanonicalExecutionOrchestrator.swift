import Foundation

enum CanonicalExecutionOrchestrator {
    static let revision = "AURORA-CANONICAL-ORCHESTRATOR-1.0.0"

    static func enrich(_ value: JSONValue) -> JSONValue {
        switch value {
        case .array(let rows):
            return .array(rows.map(enrich))
        case .object(let object):
            var out: [String: JSONValue] = [:]
            for (key, child) in object {
                out[key] = enrich(child)
            }
            if out["project"] != nil, out["flowsheet"] != nil {
                apply(to: &out)
            }
            return .object(out)
        default:
            return value
        }
    }

    static func dispatchBlockReason(_ value: JSONValue) -> String? {
        guard let requested = value.firstString(["requested_module", "requestedModule", "engine_id", "engineId"]),
              !requested.isEmpty else { return nil }

        guard let engineering = value.recursiveFind("canonicalEngineering"),
              let applicability = engineering.recursiveFind("engineApplicability"),
              case .array(let rows) = applicability else { return nil }

        for row in rows {
            guard case .object(let item) = row,
                  item["engine_id"]?.stringValue == requested,
                  let rawStatus = item["status"]?.stringValue,
                  rawStatus != EngineApplicabilityStatus.ready.rawValue,
                  rawStatus != EngineApplicabilityStatus.warningExtrapolation.rawValue else { continue }

            return "AURORA canonical applicability gate blocked \(requested): \(item["reason"]?.stringValue ?? rawStatus)"
        }
        return nil
    }

    static func preflightReceipt(_ value: JSONValue) -> JSONValue? {
        enrich(value).recursiveFind("canonicalEngineering")
    }

    private static func apply(to object: inout [String: JSONValue]) {
        let mode = processingMode(from: object)
        let unitOperations = extractUnitOperations(from: object["flowsheet"])
        let streams = extractStreams(from: object)
        let equipment = extractEquipment(from: object)

        let context = CanonicalEngineContext(
            processingMode: mode,
            unitOperations: Set(unitOperations.map(CanonicalJSON.normalizedToken)),
            streams: streams
        )
        let engineDecisions = CanonicalEngineRegistry.evaluateAll(context: context)
        let operationDecisions = evaluateUnitOperations(
            unitOperations,
            processingMode: mode,
            streams: streams
        )

        let mass = CanonicalBalanceSolver.massBalance(streams: streams)
        let dry = CanonicalBalanceSolver.drySolidsBalance(streams: streams)
        let water = CanonicalBalanceSolver.waterBalance(streams: streams, processingMode: mode)
        let components = CanonicalBalanceSolver.componentBalances(streams: streams)
        let energy = CanonicalBalanceSolver.energySummary(equipment: equipment)

        let blockedOperations = operationDecisions.filter {
            guard case .object(let item) = $0 else { return false }
            let status = item["status"]?.stringValue ?? ""
            return status.hasPrefix("BLOCKED")
        }

        let resultState = blockedOperations.isEmpty ? "READY" : "BLOCKED"
        let insufficientBalances = [mass.status, dry.status, water.status, energy.status].filter { $0 == .insufficientData }.count

        object["canonicalEngineering"] = .object([
            "schemaVersion": .string(CanonicalEngineeringRevision.schema),
            "orchestratorRevision": .string(revision),
            "authority": .string("canonical_fail_closed_pre_dispatch"),
            "processingMode": .string(mode),
            "state": .string(resultState),
            "noFabricationPolicy": .bool(true),
            "unitOperations": .array(unitOperations.map(JSONValue.string)),
            "streamEvidenceCount": .number(Double(streams.count)),
            "equipmentEvidenceCount": .number(Double(equipment.count)),
            "engineRegistry": .array(CanonicalEngineRegistry.engines.map(\.json)),
            "engineApplicability": .array(engineDecisions.map(\.json)),
            "unitOperationApplicability": .array(operationDecisions),
            "balances": .object([
                "mass": mass.json,
                "drySolids": dry.json,
                "water": water.json,
                "components": .object(components.mapValues(\.json)),
                "energy": energy.json
            ]),
            "balanceDataGaps": .number(Double(insufficientBalances)),
            "dispatchRule": .string("Only READY or WARNING_EXTRAPOLATION engines may be directly dispatched."),
            "calculationAuthority": .string("No engineering value is synthesized when required evidence is absent.")
        ])
    }

    private static func processingMode(from object: [String: JSONValue]) -> String {
        if let basis = CanonicalJSON.object(object["designBasis"]) {
            if let raw = CanonicalJSON.string(basis["processingMode"]), !raw.isEmpty {
                return CanonicalEngineRegistry.normalize(raw)
            }
            if let water = CanonicalJSON.string(basis["waterRequirement"]) {
                let token = CanonicalEngineRegistry.normalize(water)
                if token == "not_applicable" || token == "none" { return "dry" }
                if token.contains("required") { return "wet" }
            }
        }
        return "unspecified"
    }

    private static func extractUnitOperations(from flowsheet: JSONValue?) -> [String] {
        guard let flowsheet = CanonicalJSON.object(flowsheet) else { return [] }
        var values: [String] = []

        for row in CanonicalJSON.array(flowsheet["units"]) {
            if let text = CanonicalJSON.string(row), !text.isEmpty {
                values.append(text)
                continue
            }
            if case .object(let item) = row {
                for key in ["unitType", "unit_type", "type", "name", "label"] {
                    if let text = CanonicalJSON.string(item[key]), !text.isEmpty {
                        values.append(text)
                        break
                    }
                }
            }
        }

        if let graph = CanonicalJSON.object(flowsheet["graph"]) {
            for row in CanonicalJSON.array(graph["nodes"]) {
                guard case .object(let item) = row else { continue }
                for key in ["unitType", "unit_type", "type", "name", "label"] {
                    if let text = CanonicalJSON.string(item[key]), !text.isEmpty {
                        values.append(text)
                        break
                    }
                }
            }
        }

        var seen: Set<String> = []
        return values.filter {
            let token = CanonicalJSON.normalizedToken($0)
            guard !token.isEmpty, seen.insert(token).inserted else { return false }
            return true
        }
    }

    private static func extractStreams(from root: [String: JSONValue]) -> [CanonicalStreamEvidence] {
        var rowsByID: [String: CanonicalStreamEvidence] = [:]

        if let flowsheet = CanonicalJSON.object(root["flowsheet"]),
           let graph = CanonicalJSON.object(flowsheet["graph"]) {
            for row in CanonicalJSON.array(graph["edges"]) {
                if let parsed = parseStream(row) { rowsByID[parsed.id] = parsed }
            }
        }

        if let flowsheet = CanonicalJSON.object(root["flowsheet"]) {
            for row in CanonicalJSON.array(flowsheet["streams"]) {
                if let parsed = parseStream(row) { rowsByID[parsed.id] = parsed }
            }
        }

        for row in CanonicalJSON.array(root["streams"]) {
            if let parsed = parseStream(row) { rowsByID[parsed.id] = parsed }
        }

        return rowsByID.values.sorted { $0.id < $1.id }
    }

    private static func parseStream(_ value: JSONValue) -> CanonicalStreamEvidence? {
        guard case .object(let object) = value else { return nil }
        let id = firstString(object, ["id", "streamID", "stream_id", "tag"]) ?? ""
        guard !id.isEmpty else { return nil }

        let role = firstString(object, ["boundaryRole", "boundary_role", "role", "streamRole", "stream_role"]) ?? "internal"
        let total = firstNumber(object, ["totalMassTPH", "total_mass_tph", "massFlowTPH", "mass_flow_tph", "flow_tph", "tph"])
        let dry = firstNumber(object, ["drySolidsTPH", "dry_solids_tph", "solidsTPH", "solids_tph"])
        let liquid = firstNumber(object, ["liquidMassTPH", "liquid_mass_tph", "waterTPH", "water_tph"])

        var components: [String: Double] = [:]
        for key in ["componentMassTPH", "component_mass_tph", "componentMassFlowTPH"] {
            guard let raw = CanonicalJSON.object(object[key]) else { continue }
            for (component, value) in raw {
                if let number = CanonicalJSON.number(value) {
                    components[component] = number
                }
            }
            if !components.isEmpty { break }
        }

        return .init(
            id: id,
            boundaryRole: role,
            totalMassTPH: total,
            drySolidsTPH: dry,
            liquidMassTPH: liquid,
            componentMassTPH: components
        )
    }

    private static func extractEquipment(from root: [String: JSONValue]) -> [CanonicalEquipmentEvidence] {
        var rowsByID: [String: CanonicalEquipmentEvidence] = [:]

        if let flowsheet = CanonicalJSON.object(root["flowsheet"]) {
            for row in CanonicalJSON.array(flowsheet["equipment"]) {
                if let parsed = parseEquipment(row) { rowsByID[parsed.id] = parsed }
            }
        }
        for row in CanonicalJSON.array(root["equipment"]) {
            if let parsed = parseEquipment(row) { rowsByID[parsed.id] = parsed }
        }

        return rowsByID.values.sorted { $0.id < $1.id }
    }

    private static func parseEquipment(_ value: JSONValue) -> CanonicalEquipmentEvidence? {
        guard case .object(let object) = value else { return nil }
        let id = firstString(object, ["id", "equipmentID", "equipment_id", "tag"]) ?? ""
        guard !id.isEmpty else { return nil }
        let tag = firstString(object, ["tag", "equipmentTag", "equipment_tag"]) ?? id
        let type = firstString(object, ["equipmentClass", "equipment_class", "type", "unitType"]) ?? "unspecified"

        return .init(
            id: id,
            tag: tag,
            equipmentClass: type,
            installedPowerKW: firstNumber(object, ["installedPowerKW", "installed_power_kw", "powerKW", "power_kw"]),
            operatingPowerKW: firstNumber(object, ["operatingPowerKW", "operating_power_kw"]),
            loadFactor: firstNumber(object, ["loadFactor", "load_factor"])
        )
    }

    private static func evaluateUnitOperations(
        _ operations: [String],
        processingMode: String,
        streams: [CanonicalStreamEvidence]
    ) -> [JSONValue] {
        let mode = CanonicalEngineRegistry.normalize(processingMode)
        let hasLiquid = streams.contains(where: \.containsLiquid)
        let hasSlurry = streams.contains { $0.containsLiquid && ($0.drySolidsTPH ?? 0) > 1e-12 }

        let slurryRequired: Set<String> = ["hydrocyclone", "flotation", "thickening", "filtration", "desliming"]
        let liquidRequired: Set<String> = ["scrubbing", "leaching", "acid leaching", "precipitation", "solvent extraction"]

        return operations.map { operation in
            let token = CanonicalJSON.normalizedToken(operation)
            let status: EngineApplicabilityStatus
            let reason: String

            if (slurryRequired.contains(token) || liquidRequired.contains(token)) && mode == "dry" {
                status = .blockedIncompatibleProcess
                reason = "\(operation) is a wet/slurry unit operation and cannot execute in an explicit dry process."
            } else if slurryRequired.contains(token) && !hasSlurry {
                status = .blockedMissingInput
                reason = "\(operation) requires an evidenced slurry stream containing both solids and liquid."
            } else if liquidRequired.contains(token) && !hasLiquid {
                status = .blockedMissingInput
                reason = "\(operation) requires an evidenced liquid phase."
            } else {
                status = .ready
                reason = "Declared process mode and evidenced phase state permit this unit operation."
            }

            return .object([
                "unit_operation": .string(operation),
                "status": .string(status.rawValue),
                "reason": .string(reason)
            ])
        }
    }

    private static func firstString(_ object: [String: JSONValue], _ keys: [String]) -> String? {
        for key in keys {
            if let value = CanonicalJSON.string(object[key]), !value.isEmpty { return value }
        }
        return nil
    }

    private static func firstNumber(_ object: [String: JSONValue], _ keys: [String]) -> Double? {
        for key in keys {
            if let value = CanonicalJSON.number(object[key]) { return value }
        }
        return nil
    }
}
