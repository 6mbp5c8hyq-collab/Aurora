import Foundation

/// Deterministic non-network invariant checks for the V3 project contract.
enum ScientificProjectContractV3SelfTest {
    static func evaluate() -> [String: Bool] {
        let dry = ScientificProjectBasisV3(
            objective: ScientificProjectObjective.rawOreDiagnosis.rawValue,
            processingMode: .dry,
            valuableComponent: "K2O",
            targetGrade: nil,
            targetRecovery: nil,
            maximumImpurityComponent: "",
            maximumImpurityGrade: nil,
            productSpecification: "",
            allowedUnitOperations: ["Screening", "Magnetic Separation"],
            prohibitedUnitOperations: ["Hydrocyclone"],
            updatedAt: .now
        )

        let wet = ScientificProjectBasisV3(
            objective: ScientificProjectObjective.beneficiation.rawValue,
            processingMode: .wet,
            valuableComponent: "P2O5",
            targetGrade: 35.0,
            targetRecovery: 90.0,
            maximumImpurityComponent: "MgO",
            maximumImpurityGrade: 1.0,
            productSpecification: "Phosphate concentrate",
            allowedUnitOperations: ["Desliming", "Flotation"],
            prohibitedUnitOperations: [],
            updatedAt: .now
        )

        return [
            "dry_water_not_applicable": dry.processingMode.waterRequirement == "not_applicable",
            "raw_diagnosis_targetless": dry.targetGrade == nil && dry.targetRecovery == nil,
            "wet_water_conditioned": wet.processingMode.waterRequirement == "required_for_water_dependent_unit_operations",
            "valuable_component_explicit": wet.valuableComponent == "P2O5",
            "recovery_preserved": wet.targetRecovery == 90.0,
            "policy_preserved": dry.prohibitedUnitOperations.contains("Hydrocyclone")
        ]
    }

    static var allPass: Bool { evaluate().values.allSatisfy { $0 } }
}
