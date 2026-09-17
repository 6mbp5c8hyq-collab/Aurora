import Foundation

/// Lightweight compile-time smoke surface for Repair Phase 1.
/// It intentionally performs no network request and no scientific calculation.
enum ScientificProjectContractV3Smoke {
    static func dryBeneficiationExample(projectID: UUID) -> JSONValue {
        let basis = ScientificProjectBasisV3(
            objective: ScientificProjectObjective.beneficiation.rawValue,
            processingMode: .dry,
            valuableComponent: "K2O",
            targetGrade: 14.0,
            targetRecovery: 90.0,
            maximumImpurityComponent: "Fe2O3",
            maximumImpurityGrade: 3.0,
            productSpecification: "Dry upgraded glauconite concentrate",
            allowedUnitOperations: ["Crushing", "Screening", "Magnetic Separation"],
            prohibitedUnitOperations: ["Hydrocyclone", "Flotation"],
            updatedAt: .now
        )
        return basis.contractJSON
    }
}
