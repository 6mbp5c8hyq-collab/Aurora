import Foundation

struct CanonicalClosureResult: Hashable {
    let status: EngineeringBalanceStatus
    let basis: String
    let inputTPH: Double?
    let outputTPH: Double?
    let residualTPH: Double?
    let errorPercent: Double?
    let tolerancePercent: Double
    let missingInputs: [String]
    let note: String

    var json: JSONValue {
        var object: [String: JSONValue] = [
            "status": .string(status.rawValue),
            "basis": .string(basis),
            "tolerance_percent": .number(tolerancePercent),
            "missing_inputs": .array(missingInputs.map(JSONValue.string)),
            "note": .string(note)
        ]
        if let inputTPH { object["input_tph"] = .number(inputTPH) }
        if let outputTPH { object["output_tph"] = .number(outputTPH) }
        if let residualTPH { object["residual_tph"] = .number(residualTPH) }
        if let errorPercent { object["error_percent"] = .number(errorPercent) }
        return .object(object)
    }
}

struct CanonicalEnergySummary: Hashable {
    let status: EngineeringBalanceStatus
    let installedPowerKW: Double?
    let operatingPowerKW: Double?
    let equipmentCount: Int
    let missingEquipment: [String]

    var json: JSONValue {
        var object: [String: JSONValue] = [
            "status": .string(status.rawValue),
            "equipment_count": .number(Double(equipmentCount)),
            "missing_equipment_power": .array(missingEquipment.map(JSONValue.string)),
            "authority": .string("calculated_from_evidenced_equipment_power_only")
        ]
        if let installedPowerKW { object["installed_power_kw"] = .number(installedPowerKW) }
        if let operatingPowerKW { object["operating_power_kw"] = .number(operatingPowerKW) }
        return .object(object)
    }
}

enum CanonicalBalanceSolver {
    static let defaultTolerancePercent = 0.5

    static func massBalance(
        streams: [CanonicalStreamEvidence],
        tolerancePercent: Double = defaultTolerancePercent
    ) -> CanonicalClosureResult {
        closure(
            streams: streams,
            value: { $0.totalMassTPH },
            basis: "total_mass",
            tolerancePercent: tolerancePercent,
            insufficientNote: "Boundary total-mass flows are required. No values are inferred from throughput targets or grades."
        )
    }

    static func drySolidsBalance(
        streams: [CanonicalStreamEvidence],
        tolerancePercent: Double = defaultTolerancePercent
    ) -> CanonicalClosureResult {
        closure(
            streams: streams,
            value: { $0.drySolidsTPH },
            basis: "dry_solids",
            tolerancePercent: tolerancePercent,
            insufficientNote: "Boundary dry-solids flows are required for solids closure."
        )
    }

    static func waterBalance(
        streams: [CanonicalStreamEvidence],
        processingMode: String,
        tolerancePercent: Double = defaultTolerancePercent
    ) -> CanonicalClosureResult {
        let mode = CanonicalEngineRegistry.normalize(processingMode)
        let hasPositiveLiquid = streams.contains { ($0.resolvedLiquidMassTPH ?? 0) > 1e-12 }
        if mode == "dry" && !hasPositiveLiquid {
            return .init(
                status: .notApplicable,
                basis: "liquid_mass",
                inputTPH: nil,
                outputTPH: nil,
                residualTPH: nil,
                errorPercent: nil,
                tolerancePercent: tolerancePercent,
                missingInputs: [],
                note: "Dry processing mode with no evidenced liquid streams; water balance is not applicable."
            )
        }

        return closure(
            streams: streams,
            value: { $0.resolvedLiquidMassTPH },
            basis: "liquid_mass",
            tolerancePercent: tolerancePercent,
            insufficientNote: "Boundary liquid-mass flows are required for water closure."
        )
    }

    static func componentBalances(
        streams: [CanonicalStreamEvidence],
        tolerancePercent: Double = defaultTolerancePercent
    ) -> [String: CanonicalClosureResult] {
        let components = Set(streams.flatMap { $0.componentMassTPH.keys })
        guard !components.isEmpty else { return [:] }

        var results: [String: CanonicalClosureResult] = [:]
        for component in components.sorted() {
            results[component] = closure(
                streams: streams,
                value: { stream in stream.componentMassTPH[component] },
                basis: "component_mass:\(component)",
                tolerancePercent: tolerancePercent,
                insufficientNote: "Explicit component mass flows are required. Assay percentages are not silently converted without a declared basis."
            )
        }
        return results
    }

    static func energySummary(equipment: [CanonicalEquipmentEvidence]) -> CanonicalEnergySummary {
        guard !equipment.isEmpty else {
            return .init(status: .insufficientData, installedPowerKW: nil, operatingPowerKW: nil, equipmentCount: 0, missingEquipment: ["equipment list"])
        }

        let installedRows = equipment.compactMap { item -> Double? in
            guard let value = item.installedPowerKW, value.isFinite, value >= 0 else { return nil }
            return value
        }
        let operatingRows = equipment.compactMap { $0.resolvedOperatingPowerKW }
        let missing = equipment.filter { $0.installedPowerKW == nil || $0.resolvedOperatingPowerKW == nil }.map { $0.tag.isEmpty ? $0.id : $0.tag }

        guard installedRows.count == equipment.count, operatingRows.count == equipment.count else {
            return .init(
                status: .insufficientData,
                installedPowerKW: installedRows.isEmpty ? nil : installedRows.reduce(0, +),
                operatingPowerKW: operatingRows.isEmpty ? nil : operatingRows.reduce(0, +),
                equipmentCount: equipment.count,
                missingEquipment: missing
            )
        }

        return .init(
            status: .pass,
            installedPowerKW: installedRows.reduce(0, +),
            operatingPowerKW: operatingRows.reduce(0, +),
            equipmentCount: equipment.count,
            missingEquipment: []
        )
    }

    private static func closure(
        streams: [CanonicalStreamEvidence],
        value: (CanonicalStreamEvidence) -> Double?,
        basis: String,
        tolerancePercent: Double,
        insufficientNote: String
    ) -> CanonicalClosureResult {
        let inputs = streams.filter { isExternalInput($0.boundaryRole) }
        let outputs = streams.filter { isExternalOutput($0.boundaryRole) }

        guard !inputs.isEmpty, !outputs.isEmpty else {
            var missing: [String] = []
            if inputs.isEmpty { missing.append("at least one external feed/input boundary stream") }
            if outputs.isEmpty { missing.append("at least one product/tailings/waste/loss output boundary stream") }
            return .init(
                status: .insufficientData,
                basis: basis,
                inputTPH: nil,
                outputTPH: nil,
                residualTPH: nil,
                errorPercent: nil,
                tolerancePercent: tolerancePercent,
                missingInputs: missing,
                note: insufficientNote
            )
        }

        let missingInputs = inputs.filter { value($0) == nil }.map(\.id)
        let missingOutputs = outputs.filter { value($0) == nil }.map(\.id)
        let missing = (missingInputs + missingOutputs).sorted()

        guard missing.isEmpty else {
            return .init(
                status: .insufficientData,
                basis: basis,
                inputTPH: nil,
                outputTPH: nil,
                residualTPH: nil,
                errorPercent: nil,
                tolerancePercent: tolerancePercent,
                missingInputs: missing,
                note: insufficientNote
            )
        }

        let inputTotal = inputs.compactMap(value).reduce(0, +)
        let outputTotal = outputs.compactMap(value).reduce(0, +)
        guard inputTotal.isFinite, outputTotal.isFinite, inputTotal >= 0, outputTotal >= 0 else {
            return .init(
                status: .fail,
                basis: basis,
                inputTPH: inputTotal.isFinite ? inputTotal : nil,
                outputTPH: outputTotal.isFinite ? outputTotal : nil,
                residualTPH: nil,
                errorPercent: nil,
                tolerancePercent: tolerancePercent,
                missingInputs: [],
                note: "Non-finite or negative boundary flow detected."
            )
        }

        let residual = inputTotal - outputTotal
        let denominator = max(abs(inputTotal), 1e-12)
        let error = abs(residual) / denominator * 100.0
        let status: EngineeringBalanceStatus = error <= tolerancePercent ? .pass : .fail

        return .init(
            status: status,
            basis: basis,
            inputTPH: inputTotal,
            outputTPH: outputTotal,
            residualTPH: residual,
            errorPercent: error,
            tolerancePercent: tolerancePercent,
            missingInputs: [],
            note: status == .pass ? "Closure is within the configured engineering tolerance." : "Closure exceeds the configured engineering tolerance."
        )
    }

    private static func isExternalInput(_ role: String) -> Bool {
        let token = CanonicalJSON.normalizedToken(role)
        return [
            "feed", "external feed", "external input", "inlet", "fresh water",
            "makeup water", "reagent input", "utility input"
        ].contains(token)
    }

    private static func isExternalOutput(_ role: String) -> Bool {
        let token = CanonicalJSON.normalizedToken(role)
        return [
            "product", "tailings", "waste", "loss", "losses", "external output",
            "outlet", "bleed", "purge", "evaporation"
        ].contains(token)
    }
}
