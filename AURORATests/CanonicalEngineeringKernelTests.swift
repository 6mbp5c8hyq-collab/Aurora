import XCTest
@testable import AURORA

final class CanonicalEngineeringKernelTests: XCTestCase {
    private func payload(
        mode: String,
        units: [String],
        streams: [JSONValue] = [],
        equipment: [JSONValue] = [],
        requestedModule: String? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "project": .object([
                "id": .string(UUID().uuidString),
                "name": .string("Canonical Kernel Test"),
                "feedTph": .number(100)
            ]),
            "designBasis": .object([
                "processingMode": .string(mode),
                "authority": .string("test_explicit_basis")
            ]),
            "flowsheet": .object([
                "units": .array(units.map(JSONValue.string)),
                "streams": .array(streams)
            ]),
            "equipment": .array(equipment)
        ]
        if let requestedModule {
            object["requested_module"] = .string(requestedModule)
        }
        return .object(object)
    }

    private func stream(
        id: String,
        role: String,
        total: Double? = nil,
        dry: Double? = nil,
        liquid: Double? = nil,
        components: [String: Double] = [:]
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "boundaryRole": .string(role)
        ]
        if let total { object["totalMassTPH"] = .number(total) }
        if let dry { object["drySolidsTPH"] = .number(dry) }
        if let liquid { object["liquidMassTPH"] = .number(liquid) }
        if !components.isEmpty {
            object["componentMassTPH"] = .object(components.mapValues(JSONValue.number))
        }
        return .object(object)
    }

    func testDryRouteBlocksWetUnitOperationsAndFlotationDispatch() throws {
        let raw = payload(
            mode: "dry",
            units: ["ROM Feed", "Screening", "Magnetic Separation", "Flotation", "Product"],
            streams: [
                stream(id: "F001", role: "external_feed", total: 100, dry: 100, liquid: 0),
                stream(id: "P001", role: "product", total: 70, dry: 70, liquid: 0),
                stream(id: "T001", role: "tailings", total: 30, dry: 30, liquid: 0)
            ],
            requestedModule: "flotation"
        )

        let enriched = CanonicalExecutionOrchestrator.enrich(raw)
        let reason = CanonicalExecutionOrchestrator.dispatchBlockReason(enriched)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.localizedCaseInsensitiveContains("flotation") == true)

        guard let operations = enriched.recursiveFind("unitOperationApplicability"),
              case .array(let rows) = operations else {
            XCTFail("Missing unit-operation applicability receipt")
            return
        }

        let flotation = rows.first { row in
            row.firstString(["unit_operation"])?.lowercased() == "flotation"
        }
        XCTAssertEqual(flotation?.firstString(["status"]), EngineApplicabilityStatus.blockedIncompatibleProcess.rawValue)
    }

    func testWetHydrocycloneRequiresEvidencedSlurry() throws {
        let raw = payload(
            mode: "wet",
            units: ["ROM Feed", "Hydrocyclone", "Product"],
            streams: [
                stream(id: "F001", role: "external_feed", total: 100, dry: 100, liquid: 0),
                stream(id: "P001", role: "product", total: 100, dry: 100, liquid: 0)
            ]
        )

        let enriched = CanonicalExecutionOrchestrator.enrich(raw)
        guard let operations = enriched.recursiveFind("unitOperationApplicability"),
              case .array(let rows) = operations,
              let cyclone = rows.first(where: { $0.firstString(["unit_operation"])?.lowercased() == "hydrocyclone" }) else {
            XCTFail("Missing hydrocyclone applicability receipt")
            return
        }

        XCTAssertEqual(cyclone.firstString(["status"]), EngineApplicabilityStatus.blockedMissingInput.rawValue)
    }

    func testBalancedDryMassAndSolidsClosurePasses() throws {
        let raw = payload(
            mode: "dry",
            units: ["ROM Feed", "Screening", "Product", "Tailings"],
            streams: [
                stream(id: "F001", role: "external_feed", total: 100, dry: 100, liquid: 0, components: ["K2O": 15]),
                stream(id: "P001", role: "product", total: 70, dry: 70, liquid: 0, components: ["K2O": 12]),
                stream(id: "T001", role: "tailings", total: 30, dry: 30, liquid: 0, components: ["K2O": 3])
            ]
        )

        let enriched = CanonicalExecutionOrchestrator.enrich(raw)
        let balances = enriched.recursiveFind("balances")

        XCTAssertEqual(balances?.recursiveFind("mass")?.firstString(["status"]), EngineeringBalanceStatus.pass.rawValue)
        XCTAssertEqual(balances?.recursiveFind("drySolids")?.firstString(["status"]), EngineeringBalanceStatus.pass.rawValue)
        XCTAssertEqual(balances?.recursiveFind("water")?.firstString(["status"]), EngineeringBalanceStatus.pass.rawValue)

        let component = balances?.recursiveFind("components")?.recursiveFind("K2O")
        XCTAssertEqual(component?.firstString(["status"]), EngineeringBalanceStatus.pass.rawValue)
    }

    func testUnbalancedMassFailsConfiguredTolerance() throws {
        let raw = payload(
            mode: "dry",
            units: ["ROM Feed", "Screening", "Product", "Tailings"],
            streams: [
                stream(id: "F001", role: "external_feed", total: 100, dry: 100, liquid: 0),
                stream(id: "P001", role: "product", total: 65, dry: 65, liquid: 0),
                stream(id: "T001", role: "tailings", total: 25, dry: 25, liquid: 0)
            ]
        )

        let enriched = CanonicalExecutionOrchestrator.enrich(raw)
        let mass = enriched.recursiveFind("balances")?.recursiveFind("mass")
        XCTAssertEqual(mass?.firstString(["status"]), EngineeringBalanceStatus.fail.rawValue)
        XCTAssertEqual(CanonicalJSON.number(mass?.recursiveFind("error_percent")), 10.0, accuracy: 1e-9)
    }

    func testMissingBoundaryFlowsReturnsInsufficientDataInsteadOfFabricating() throws {
        let raw = payload(
            mode: "wet",
            units: ["ROM Feed", "Flotation", "Product"],
            streams: [
                .object(["id": .string("S001"), "boundaryRole": .string("internal")])
            ]
        )

        let enriched = CanonicalExecutionOrchestrator.enrich(raw)
        let mass = enriched.recursiveFind("balances")?.recursiveFind("mass")
        XCTAssertEqual(mass?.firstString(["status"]), EngineeringBalanceStatus.insufficientData.rawValue)
        XCTAssertNil(CanonicalJSON.number(mass?.recursiveFind("input_tph")))
        XCTAssertNil(CanonicalJSON.number(mass?.recursiveFind("output_tph")))
    }

    func testEnergySummaryUsesOnlyEvidencedEquipmentPower() throws {
        let raw = payload(
            mode: "dry",
            units: ["ROM Feed", "Crushing", "Screening", "Product"],
            equipment: [
                .object([
                    "id": .string("CR-101"),
                    "tag": .string("CR-101"),
                    "type": .string("Crusher"),
                    "installedPowerKW": .number(200),
                    "loadFactor": .number(0.75)
                ]),
                .object([
                    "id": .string("SCRN-101"),
                    "tag": .string("SCRN-101"),
                    "type": .string("Screen"),
                    "installedPowerKW": .number(40),
                    "operatingPowerKW": .number(32)
                ])
            ]
        )

        let enriched = CanonicalExecutionOrchestrator.enrich(raw)
        let energy = enriched.recursiveFind("balances")?.recursiveFind("energy")
        XCTAssertEqual(energy?.firstString(["status"]), EngineeringBalanceStatus.pass.rawValue)
        XCTAssertEqual(CanonicalJSON.number(energy?.recursiveFind("installed_power_kw")), 240.0, accuracy: 1e-9)
        XCTAssertEqual(CanonicalJSON.number(energy?.recursiveFind("operating_power_kw")), 182.0, accuracy: 1e-9)
    }
}

private extension XCTestCase {
    func XCTAssertEqual(_ expression1: Double?, _ expression2: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let expression1 else {
            XCTFail("Expected numeric value but received nil.", file: file, line: line)
            return
        }
        XCTAssertEqual(expression1, expression2, accuracy: accuracy, file: file, line: line)
    }
}
