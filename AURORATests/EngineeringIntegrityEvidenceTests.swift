import XCTest
@testable import AURORA

final class EngineeringIntegrityEvidenceTests: XCTestCase {
    func testCanonicalAuditPreservesFailedUnitEvidenceWithoutSynthesizingClosure() {
        let response: JSONValue = .object([
            "response": .object([
                "engineering_cross_phase_integrity": .object([
                    "status": .string("FAIL_CROSS_PHASE_CONTRADICTION"),
                    "issue_count": .number(2),
                    "hold_count": .number(1),
                    "counts": .object([
                        "phase_b_unit_mass_checks": .number(2),
                        "phase_b_unit_mass_failures": .number(1)
                    ]),
                    "issues": .array([
                        .object(["code": .string("UNREGISTERED_STREAM_ENDPOINT")]),
                        .object(["code": .string("NEGATIVE_STREAM_MASS_FLOW")])
                    ]),
                    "design_holds": .array([
                        .object(["code": .string("FULL_PLANT_EXPLICIT_COORDINATES_NOT_QUALIFIED")])
                    ]),
                    "unit_mass_reconciliation": .array([
                        .object([
                            "tag": .string("SC-101"),
                            "status": .string("fail"),
                            "input_solids_tph": .number(10),
                            "output_solids_tph": .number(9),
                            "residual_tph": .number(1),
                            "allowed_residual_tph": .number(0.05)
                        ]),
                        .object([
                            "tag": .string("MS-101"),
                            "status": .string("HOLD_MISSING_SOLIDS")
                        ])
                    ])
                ])
            ])
        ])
        guard let evidence = EngineeringIntegrityEvidence.parse(response) else {
            XCTFail("Canonical cross-phase audit was not found")
            return
        }
        XCTAssertEqual(evidence.state, "FAIL_CROSS_PHASE_CONTRADICTION")
        XCTAssertEqual(evidence.issueCount, 2)
        XCTAssertEqual(evidence.holdCount, 1)
        XCTAssertEqual(evidence.totalUnitChecks, 2)
        XCTAssertEqual(evidence.failedUnitChecks, 1)
        XCTAssertEqual(evidence.issues, ["UNREGISTERED_STREAM_ENDPOINT", "NEGATIVE_STREAM_MASS_FLOW"])
        XCTAssertEqual(evidence.units.count, 2)
        XCTAssertEqual(evidence.units[0].tag, "SC-101")
        XCTAssertEqual(evidence.units[0].residualTph, 1)
        XCTAssertEqual(evidence.units[0].toleranceTph, 0.05)
        XCTAssertEqual(evidence.units[1].state, "HOLD_MISSING_SOLIDS")
        XCTAssertNil(evidence.units[1].residualTph)
    }

    func testAbsentAuditDoesNotImplyPassedEngineeringRelease() {
        XCTAssertNil(EngineeringIntegrityEvidence.parse(nil))
        XCTAssertNil(EngineeringIntegrityEvidence.parse(.object(["status": .string("PASS")])))
    }
}
