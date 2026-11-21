import XCTest
@testable import AURORA

final class EngineeringProcessTopologyTests: XCTestCase {
    private func stream(_ id: String, _ from: String?, _ to: String?,
                        solids: JSONValue = .number(8), water: JSONValue = .number(0)) -> JSONValue {
        .object([
            "stream_id": .string(id),
            "from_unit": from.map(JSONValue.string) ?? .null,
            "to_unit": to.map(JSONValue.string) ?? .null,
            "solids_tph": solids,
            "water_tph": water
        ])
    }

    private func canonicalResult() -> JSONValue {
        .object([
            "response": .object([
                "streams": .array([.object(["id": .string("DECOY"), "flow_tph": .number(999)])]),
                "engineering_phase_b": .object([
                    "equipment_sizing": .object([
                        "register": .array([
                            .object(["tag": .string("SC-101")]),
                            .object(["tag": .string("MS-101")])
                        ])
                    ]),
                    "mass_balance": .object([
                        "stream_table": .array([
                            stream("F", nil, "SC-101", solids: .number(10)),
                            stream("I", "SC-101", "MS-101"),
                            stream("R", "SC-101", nil, solids: .number(2)),
                            stream("P", "MS-101", nil),
                            stream("Z", "MISSING-999", "MS-101", solids: .number(0), water: .string("NaN"))
                        ])
                    ])
                ]),
                "engineering_cross_phase_integrity": .object([
                    "status": .string("FAIL_CROSS_PHASE_CONTRADICTION"),
                    "issues": .array([
                        .object([
                            "code": .string("UNREGISTERED_STREAM_ENDPOINT"),
                            "stream_id": .string("Z"),
                            "equipment_tag": .string("MISSING-999")
                        ]),
                        .object([
                            "code": .string("UNIT_SOLIDS_CONSERVATION_FAILED"),
                            "tag": .string("SC-101")
                        ]),
                        .object([
                            "code": .string("STREAM_MASS_ANNOTATION_MISMATCH"),
                            "stream_id": .string("UNKNOWN-STREAM")
                        ])
                    ]),
                    "design_holds": .array([
                        .object(["code": .string("MISSING_3D_OR_FOOTPRINT_ENVELOPE"),
                                 "tag": .string("MS-101")])
                    ])
                ])
            ])
        ])
    }

    func testCanonicalStreamAuthorityOverridesIncidentalNamedStreamArray() throws {
        let result = canonicalResult()
        let visible = PBParser.streams(from: result)
        XCTAssertEqual(visible.count, 5)
        XCTAssertEqual(visible.first?.name, "F")
        XCTAssertEqual(visible.first?.value(["stream_id"]), "F")
        XCTAssertEqual(visible[1].value(["from_unit"]), "SC-101")
        XCTAssertFalse(visible.contains { $0.name == "DECOY" })
        XCTAssertTrue(visible[0].id.hasPrefix("engineering_phase_b.mass_balance.stream_table"))
    }

    func testActualIssueReferencesResolveOnlyExactStreamOrEquipment() throws {
        guard let graph = EngineeringProcessTopology.parse(canonicalResult()) else {
            return XCTFail("Canonical engineering graph was not read")
        }
        XCTAssertEqual(graph.equipment.map(\.sourceTag), ["SC-101", "MS-101"])
        XCTAssertEqual(graph.reportedStreamCount, 5)
        XCTAssertEqual(graph.reportedIssueCount, 3)
        XCTAssertEqual(graph.reportedHoldCount, 1)
        XCTAssertEqual(graph.findings.count, 4)
        XCTAssertEqual(graph.streams[4].fromTag, "MISSING-999")
        XCTAssertNil(graph.streams[4].waterTph, "NaN may not be inferred as numeric 0")
        XCTAssertFalse(graph.equipment.contains { $0.sourceTag == "MISSING-999" })

        let unknownUnit = try XCTUnwrap(graph.findings.first { $0.code == "UNREGISTERED_STREAM_ENDPOINT" })
        XCTAssertEqual(graph.matchingStreams(for: unknownUnit).map(\.sourceID), ["Z"])
        XCTAssertEqual(graph.relatedFindings(to: graph.streams[4]).map(\.code).contains("UNREGISTERED_STREAM_ENDPOINT"), true)

        let unitBalance = try XCTUnwrap(graph.findings.first { $0.code == "UNIT_SOLIDS_CONSERVATION_FAILED" })
        XCTAssertEqual(Set(graph.matchingStreams(for: unitBalance).map(\.sourceID)),
                       Set(["F", "I", "R"]))

        let unresolvable = try XCTUnwrap(graph.findings.first { $0.code == "STREAM_MASS_ANNOTATION_MISMATCH" })
        XCTAssertEqual(graph.matchingStreams(for: unresolvable).count, 0,
                       "Never attach unrecognized stream references to arbitrary graph edges")
    }

    func testMissingEngineeringPhaseDoesNotFabricateConnectivity() {
        let synthetic: JSONValue = .object([
            "streams": .array([.object(["id": .string("UNQUALIFIED")])]),
            "engineering_cross_phase_integrity": .object(["status": .string("PASS")])
        ])
        XCTAssertNil(EngineeringProcessTopology.parse(nil))
        XCTAssertNil(EngineeringProcessTopology.parse(synthetic))
    }

    func testCanonicalFlowsWithAbsentRatesRemainUnreported() throws {
        let result: JSONValue = .object([
            "engineering_phase_b": .object([
                "equipment_sizing": .object([
                    "register": .array([.object(["tag": .string("SC-101")])])
                ]),
                "mass_balance": .object([
                    "stream_table": .array([
                        .object([
                            "stream_id": .string("F"),
                            "to_unit": .string("SC-101"),
                            "from_unit": .null,
                            "solids_tph": .null
                        ])
                    ])
                ])
            ])
        ])
        let graph = try XCTUnwrap(EngineeringProcessTopology.parse(result))
        XCTAssertEqual(graph.streams.count, 1)
        XCTAssertNil(graph.streams[0].solidsTph)
        XCTAssertNil(graph.streams[0].waterTph)
        XCTAssertNil(graph.reportedIssueCount)
        XCTAssertNil(graph.reportedHoldCount)
        XCTAssertEqual(graph.findings.count, 0)
    }
}
