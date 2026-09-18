import XCTest
@testable import AURORA

final class Phase1DryGlauconiteAcceptanceTests: XCTestCase {
    private func strings(_ value: JSONValue?) -> [String] {
        guard let value, case .array(let rows) = value else { return [] }
        return rows.compactMap(\.stringValue)
    }

    private func blockedIDs(_ value: JSONValue?) -> Set<String> {
        guard let value, case .array(let rows) = value else { return [] }
        return Set(rows.compactMap { row in
            guard case .object(let object) = row else { return nil }
            return object["id"]?.stringValue
        })
    }

    func testDryGlauconitePhase1Acceptance() throws {
        let proof = ProcessExecutionGovernanceV3.dryGlauconiteAcceptanceProof()
        XCTAssertEqual(proof.recursiveFind("ok"), .bool(true))
        XCTAssertEqual(proof.recursiveFind("processingMode")?.stringValue, "dry")
        XCTAssertEqual(proof.recursiveFind("waterRequirement")?.stringValue, "not_applicable")
        XCTAssertEqual(proof.recursiveFind("valuableComponent")?.stringValue, "K2O")
        XCTAssertEqual(proof.recursiveFind("maximumImpurity")?.stringValue, "Fe2O3 <= 3 wt%")

        guard let governance = proof.recursiveFind("executionGovernance") else {
            XCTFail("Missing executionGovernance receipt")
            return
        }

        XCTAssertEqual(governance.recursiveFind("dagExecutable"), .bool(true))
        XCTAssertEqual(governance.recursiveFind("processingMode")?.stringValue, "dry")
        XCTAssertEqual(governance.recursiveFind("waterRequirement")?.stringValue, "not_applicable")

        let eligible = Set(strings(governance.recursiveFind("eligibleEngines")))
        let blocked = blockedIDs(governance.recursiveFind("blockedEngines"))

        for engine in [
            "ore_intelligence", "resource_model", "comminution", "classification",
            "magnetic_gravity", "conservation", "equipment_epc", "economics",
            "digital_twin", "hybrid_ai", "diagnostics"
        ] {
            XCTAssertTrue(eligible.contains(engine), "Expected eligible engine: \(engine)")
        }

        for engine in ["flotation", "hydrometallurgy", "thermodynamics", "water_circuit"] {
            XCTAssertFalse(eligible.contains(engine), "Wet-only engine must not be eligible: \(engine)")
            XCTAssertTrue(blocked.contains(engine), "Wet-only engine must be explicitly blocked: \(engine)")
        }

        guard let scopes = governance.recursiveFind("engineScopes"),
              let classification = scopes.recursiveFind("classification") else {
            XCTFail("Missing classification submodel scope")
            return
        }

        let allowed = Set(strings(classification.recursiveFind("allowedUnitOperations")))
        let blockedSubmodels = Set(strings(classification.recursiveFind("blockedUnitOperations")))
        XCTAssertEqual(allowed, ["screening"])
        XCTAssertTrue(blockedSubmodels.contains("hydrocyclone"))
        XCTAssertTrue(blockedSubmodels.contains("desliming"))
        XCTAssertEqual(classification.recursiveFind("strictResultScope"), .bool(true))
    }

    func testRawOreDiagnosisIsGraphlessAndTargetless() throws {
        let basis = ScientificProjectBasisV3(
            objective: ScientificProjectObjective.rawOreDiagnosis.rawValue,
            processingMode: .dry,
            valuableComponent: "K2O",
            targetGrade: nil,
            targetRecovery: nil,
            maximumImpurityComponent: "",
            maximumImpurityGrade: nil,
            productSpecification: "Diagnostic-only raw ore characterization",
            allowedUnitOperations: [],
            prohibitedUnitOperations: [],
            authority: "phase1_graphless_raw_diagnosis_acceptance",
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let rawGovernance = ProcessExecutionGovernanceV3.deterministicReceipt(
            unitOperations: [],
            basis: basis
        )
        XCTAssertEqual(rawGovernance.recursiveFind("dagExecutable"), .bool(false))
        XCTAssertEqual(rawGovernance.recursiveFind("graphValidation")?.recursiveFind("nodeCount")?.stringValue, "0")

        let payload = JSONValue.object([
            "designBasis": basis.contractJSON,
            "executionGovernance": rawGovernance
        ])
        let finalized = ExecutionGovernancePolicyV3.finalize(payload)

        XCTAssertEqual(finalized.recursiveFind("dagExecutable"), .bool(true))
        XCTAssertEqual(finalized.recursiveFind("blockReason")?.stringValue, "")
        XCTAssertEqual(finalized.recursiveFind("executionClass")?.stringValue, "graphless_raw_ore_diagnosis")
        XCTAssertEqual(finalized.recursiveFind("diagnosticGraphExemption"), .bool(true))
        XCTAssertEqual(
            finalized.recursiveFind("diagnosticGraphExemptionAuthority")?.stringValue,
            "explicit_raw_ore_diagnosis_objective"
        )
        XCTAssertNil(finalized.recursiveFind("targetGrade"))

        let directPayload = JSONValue.object([
            "requested_module": .string("ore_intelligence"),
            "designBasis": basis.contractJSON,
            "executionGovernance": finalized.recursiveFind("executionGovernance") ?? .object([:])
        ])
        XCTAssertNil(ExecutionGovernancePolicyV3.directDispatchBlockReason(directPayload))
    }

    func testWetUnitsFailClosedInExplicitDryMode() throws {
        let basis = ScientificProjectBasisV3(
            objective: ScientificProjectObjective.impurityRemoval.rawValue,
            processingMode: .dry,
            valuableComponent: "K2O",
            targetGrade: 15,
            targetRecovery: nil,
            maximumImpurityComponent: "Fe2O3",
            maximumImpurityGrade: 3,
            productSpecification: "Dry route only",
            allowedUnitOperations: ["Crushing", "Screening", "Magnetic Separation", "Hydrocyclone"],
            prohibitedUnitOperations: [],
            authority: "phase1_negative_acceptance_test",
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let receipt = ProcessExecutionGovernanceV3.deterministicReceipt(
            unitOperations: ["ROM Feed", "Crushing", "Hydrocyclone", "Product"],
            basis: basis
        )

        XCTAssertEqual(receipt.recursiveFind("dagExecutable"), .bool(false))
        let reason = receipt.recursiveFind("blockReason")?.stringValue ?? ""
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("dry mode"))
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("hydrocyclone"))
    }
}
