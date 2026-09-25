import Foundation

// Canonical engineering primitives used by the native client before any server dispatch.
// These types intentionally carry only evidence supplied by the project. They never invent
// process values and are safe to reuse by future local/server solver adapters.

enum CanonicalEngineeringRevision {
    static let schema = "AURORA-CANONICAL-ENGINEERING-1.0.0"
    static let registry = "AURORA-ENGINE-REGISTRY-1.0.0"
}

enum EngineeringDataAuthority: String, Codable, CaseIterable {
    case labMeasured = "LAB_MEASURED"
    case pilotMeasured = "PILOT_MEASURED"
    case plantMeasured = "PLANT_MEASURED"
    case vendor = "VENDOR"
    case literature = "LITERATURE"
    case userAssumption = "USER_ASSUMPTION"
    case calculated = "CALCULATED"
    case optimized = "OPTIMIZED"
    case defaultEstimate = "DEFAULT_ESTIMATE"
    case unqualified = "UNQUALIFIED"
}

enum EngineApplicabilityStatus: String, Codable {
    case ready = "READY"
    case blockedMissingInput = "BLOCKED_MISSING_INPUT"
    case blockedIncompatibleProcess = "BLOCKED_INCOMPATIBLE_PROCESS"
    case blockedUpstreamFailure = "BLOCKED_UPSTREAM_FAILURE"
    case blockedOutsideValidityRange = "BLOCKED_OUTSIDE_VALIDITY_RANGE"
    case warningExtrapolation = "WARNING_EXTRAPOLATION"
}

enum EngineeringBalanceStatus: String, Codable {
    case pass = "PASS"
    case fail = "FAIL"
    case insufficientData = "INSUFFICIENT_DATA"
    case notApplicable = "NOT_APPLICABLE"
}

struct CanonicalStreamEvidence: Hashable {
    let id: String
    let boundaryRole: String
    let totalMassTPH: Double?
    let drySolidsTPH: Double?
    let liquidMassTPH: Double?
    let componentMassTPH: [String: Double]

    var containsLiquid: Bool {
        if let liquidMassTPH { return liquidMassTPH > 1e-12 }
        if let totalMassTPH, let drySolidsTPH { return totalMassTPH - drySolidsTPH > 1e-12 }
        return false
    }

    var resolvedLiquidMassTPH: Double? {
        if let liquidMassTPH { return liquidMassTPH }
        if let totalMassTPH, let drySolidsTPH {
            let value = totalMassTPH - drySolidsTPH
            return value >= -1e-9 ? max(value, 0) : nil
        }
        return nil
    }
}

struct CanonicalEquipmentEvidence: Hashable {
    let id: String
    let tag: String
    let equipmentClass: String
    let installedPowerKW: Double?
    let operatingPowerKW: Double?
    let loadFactor: Double?

    var resolvedOperatingPowerKW: Double? {
        if let operatingPowerKW, operatingPowerKW >= 0 { return operatingPowerKW }
        if let installedPowerKW, let loadFactor, installedPowerKW >= 0, (0...1).contains(loadFactor) {
            return installedPowerKW * loadFactor
        }
        return nil
    }
}

struct CanonicalEngineContext {
    let processingMode: String
    let unitOperations: Set<String>
    let streams: [CanonicalStreamEvidence]

    var hasLiquidPhase: Bool { streams.contains(where: \.containsLiquid) }
    var hasSlurry: Bool {
        streams.contains { stream in
            guard stream.containsLiquid else { return false }
            if let solids = stream.drySolidsTPH { return solids > 1e-12 }
            return false
        }
    }
}

struct CanonicalEngineDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let domain: String
    let compatibleModes: Set<String>
    let requiredUnitOperations: Set<String>
    let requiresLiquidPhase: Bool
    let requiresSlurry: Bool
    let requiredInputs: [String]
    let solverMethod: String
    let validationLevel: Int

    var json: JSONValue {
        .object([
            "engine_id": .string(id),
            "engine_name": .string(name),
            "engine_version": .string("1.0.0"),
            "engineering_domain": .string(domain),
            "compatible_modes": .array(compatibleModes.sorted().map(JSONValue.string)),
            "required_unit_operations": .array(requiredUnitOperations.sorted().map(JSONValue.string)),
            "requires_liquid_phase": .bool(requiresLiquidPhase),
            "requires_slurry": .bool(requiresSlurry),
            "required_inputs": .array(requiredInputs.map(JSONValue.string)),
            "solver_method": .string(solverMethod),
            "validation_level": .number(Double(validationLevel)),
            "registry_revision": .string(CanonicalEngineeringRevision.registry)
        ])
    }
}

struct CanonicalEngineDecision: Identifiable, Hashable {
    let id: String
    let status: EngineApplicabilityStatus
    let reason: String

    var executable: Bool {
        status == .ready || status == .warningExtrapolation
    }

    var json: JSONValue {
        .object([
            "engine_id": .string(id),
            "status": .string(status.rawValue),
            "executable": .bool(executable),
            "reason": .string(reason)
        ])
    }
}

enum CanonicalEngineRegistry {
    static let engines: [CanonicalEngineDefinition] = [
        .init(id: "ore_intelligence", name: "Ore Intelligence", domain: "characterization", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: [], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["analyses"], solverMethod: "evidence-bound diagnosis", validationLevel: 1),
        .init(id: "resource_model", name: "Resource Model", domain: "mining", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: [], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: [], solverMethod: "resource model adapter", validationLevel: 0),
        .init(id: "comminution", name: "Comminution", domain: "mineral_processing", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: ["crushing", "grinding", "ball mill", "rod mill", "sag mill"], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["feed throughput"], solverMethod: "equipment-specific comminution model", validationLevel: 1),
        .init(id: "classification", name: "Classification", domain: "mineral_processing", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: ["screening", "screen", "classification", "hydrocyclone", "desliming"], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["PSD"], solverMethod: "partition/classification model", validationLevel: 1),
        .init(id: "flotation", name: "Flotation", domain: "mineral_processing", compatibleModes: ["wet", "hybrid"], requiredUnitOperations: ["flotation"], requiresLiquidPhase: true, requiresSlurry: true, requiredInputs: ["slurry", "PSD", "reagent scheme"], solverMethod: "kinetic/recovery model", validationLevel: 1),
        .init(id: "magnetic_gravity", name: "Magnetic & Gravity Separation", domain: "mineral_processing", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: ["magnetic separation", "magnetic", "gravity separation", "gravity"], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["feed throughput"], solverMethod: "separation partition model", validationLevel: 1),
        .init(id: "hydrometallurgy", name: "Hydrometallurgy", domain: "chemical_processing", compatibleModes: ["wet", "hybrid"], requiredUnitOperations: ["leaching", "acid leaching", "precipitation", "solvent extraction"], requiresLiquidPhase: true, requiresSlurry: false, requiredInputs: ["chemistry"], solverMethod: "stoichiometric/equilibrium adapter", validationLevel: 0),
        .init(id: "thermodynamics", name: "Thermodynamics", domain: "chemistry", compatibleModes: ["wet", "hybrid"], requiredUnitOperations: ["leaching", "precipitation", "solvent extraction", "reaction"], requiresLiquidPhase: true, requiresSlurry: false, requiredInputs: ["species", "temperature"], solverMethod: "activity/equilibrium adapter", validationLevel: 0),
        .init(id: "water_circuit", name: "Water Circuit", domain: "water", compatibleModes: ["wet", "hybrid"], requiredUnitOperations: [], requiresLiquidPhase: true, requiresSlurry: false, requiredInputs: ["liquid stream flow"], solverMethod: "network conservation", validationLevel: 1),
        .init(id: "conservation", name: "Conservation", domain: "process_balance", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: [], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["boundary stream flows"], solverMethod: "mass/component conservation", validationLevel: 1),
        .init(id: "equipment_epc", name: "Equipment & EPC", domain: "equipment", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: [], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["equipment design basis"], solverMethod: "equipment-specific sizing", validationLevel: 1),
        .init(id: "economics", name: "Economics", domain: "economics", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: [], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["dated cost assumptions"], solverMethod: "cash-flow model", validationLevel: 0),
        .init(id: "tailings", name: "Tailings", domain: "waste", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: ["tailings", "waste"], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["tailings stream"], solverMethod: "material-state adapter", validationLevel: 0),
        .init(id: "digital_twin", name: "Digital Twin", domain: "operations", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: [], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["canonical project state"], solverMethod: "state synchronization", validationLevel: 0),
        .init(id: "hybrid_ai", name: "Engineering Copilot", domain: "ai", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: [], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: ["solver results"], solverMethod: "explanation only; no numerical authority", validationLevel: 0),
        .init(id: "diagnostics", name: "Diagnostics", domain: "qa", compatibleModes: ["dry", "wet", "hybrid", "unspecified"], requiredUnitOperations: [], requiresLiquidPhase: false, requiresSlurry: false, requiredInputs: [], solverMethod: "deterministic rule checks", validationLevel: 1)
    ]

    static func definition(id: String) -> CanonicalEngineDefinition? {
        engines.first { $0.id == id }
    }

    static func evaluate(_ engine: CanonicalEngineDefinition, context: CanonicalEngineContext) -> CanonicalEngineDecision {
        let mode = normalize(context.processingMode)
        if !engine.compatibleModes.contains(mode) && !engine.compatibleModes.contains("unspecified") {
            return .init(id: engine.id, status: .blockedIncompatibleProcess, reason: "\(engine.name) is not compatible with processing mode '\(mode)'.")
        }

        if !engine.requiredUnitOperations.isEmpty {
            let routeMatch = !engine.requiredUnitOperations.isDisjoint(with: context.unitOperations)
            if !routeMatch {
                return .init(id: engine.id, status: .blockedIncompatibleProcess, reason: "No applicable unit operation for \(engine.name) exists in the canonical process graph.")
            }
        }

        if engine.requiresLiquidPhase && !context.hasLiquidPhase {
            return .init(id: engine.id, status: .blockedMissingInput, reason: "\(engine.name) requires an evidenced liquid phase; no stream with liquid mass is available.")
        }

        if engine.requiresSlurry && !context.hasSlurry {
            return .init(id: engine.id, status: .blockedMissingInput, reason: "\(engine.name) requires an evidenced slurry stream containing both solids and liquid.")
        }

        return .init(id: engine.id, status: .ready, reason: "Canonical route, mode and phase requirements are satisfied.")
    }

    static func evaluateAll(context: CanonicalEngineContext) -> [CanonicalEngineDecision] {
        engines.map { evaluate($0, context: context) }
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum CanonicalJSON {
    static func number(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .number(let number):
            return number.isFinite ? number : nil
        case .string(let text):
            let clean = text
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Double(clean), parsed.isFinite else { return nil }
            return parsed
        default:
            return nil
        }
    }

    static func object(_ value: JSONValue?) -> [String: JSONValue]? {
        guard let value, case .object(let object) = value else { return nil }
        return object
    }

    static func array(_ value: JSONValue?) -> [JSONValue] {
        guard let value, case .array(let rows) = value else { return [] }
        return rows
    }

    static func string(_ value: JSONValue?) -> String? {
        value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
