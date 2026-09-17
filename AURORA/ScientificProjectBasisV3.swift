import SwiftUI
import SwiftData
import Foundation

enum ScientificProjectObjective: String, CaseIterable, Identifiable, Codable {
    case rawOreDiagnosis = "raw_ore_diagnosis"
    case beneficiation = "beneficiation"
    case gradeUpgrade = "grade_upgrade"
    case impurityRemoval = "impurity_removal"
    case recoveryMaximization = "recovery_maximization"
    case acidProduction = "acid_production"
    case criticalMetalsRecovery = "critical_metals_recovery"
    case dewatering = "dewatering"
    case waterMinimization = "water_minimization"
    case mineToProductOptimization = "mine_to_product_optimization"
    case custom = "custom"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .rawOreDiagnosis: return "Raw Ore Diagnosis"
        case .beneficiation: return "Beneficiation"
        case .gradeUpgrade: return "Grade Upgrade"
        case .impurityRemoval: return "Impurity Removal"
        case .recoveryMaximization: return "Recovery Maximization"
        case .acidProduction: return "Acid Production"
        case .criticalMetalsRecovery: return "Critical-Metals Recovery"
        case .dewatering: return "Dewatering"
        case .waterMinimization: return "Water Minimization"
        case .mineToProductOptimization: return "Mine-to-Product Optimization"
        case .custom: return "Custom Objective"
        }
    }
}

enum ScientificProcessingMode: String, CaseIterable, Identifiable, Codable {
    case dry
    case wet
    case hybrid

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var waterRequirement: String {
        switch self {
        case .dry: return "not_applicable"
        case .wet: return "required_for_water_dependent_unit_operations"
        case .hybrid: return "route_conditioned"
        }
    }
}

struct ScientificProjectBasisV3: Codable, Hashable {
    static let schemaVersion = "AURORA-SCIENTIFIC-PROJECT-CONTRACT-V3-2026.09.17"

    var objective: String
    var processingMode: ScientificProcessingMode
    var valuableComponent: String
    var targetGrade: Double?
    var targetRecovery: Double?
    var maximumImpurityComponent: String
    var maximumImpurityGrade: Double?
    var productSpecification: String
    var allowedUnitOperations: [String]
    var prohibitedUnitOperations: [String]
    var authority: String = "user_declared_scientific_project_basis"
    var updatedAt: Date = .now

    static func defaults(component: String, grade: Double) -> ScientificProjectBasisV3 {
        ScientificProjectBasisV3(
            objective: ScientificProjectObjective.beneficiation.rawValue,
            processingMode: .dry,
            valuableComponent: component,
            targetGrade: grade > 0 ? grade : nil,
            targetRecovery: nil,
            maximumImpurityComponent: "",
            maximumImpurityGrade: nil,
            productSpecification: "",
            allowedUnitOperations: [],
            prohibitedUnitOperations: [],
            updatedAt: .now
        )
    }

    var contractJSON: JSONValue {
        var constraints: [String: JSONValue] = [:]
        if !maximumImpurityComponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            constraints["maximumImpurityComponent"] = .string(maximumImpurityComponent)
        }
        if let maximumImpurityGrade {
            constraints["maximumImpurityGrade"] = .number(maximumImpurityGrade)
        }

        var result: [String: JSONValue] = [
            "schemaVersion": .string(Self.schemaVersion),
            "objective": .string(objective),
            "processingMode": .string(processingMode.rawValue),
            "valuableComponent": .string(valuableComponent),
            "waterRequirement": .string(processingMode.waterRequirement),
            "authority": .string(authority),
            "unitOperationPolicy": .object([
                "allowed": .array(allowedUnitOperations.map(JSONValue.string)),
                "prohibited": .array(prohibitedUnitOperations.map(JSONValue.string))
            ]),
            "updatedAt": .string(updatedAt.ISO8601Format())
        ]
        if let targetGrade { result["targetGrade"] = .number(targetGrade) }
        if let targetRecovery { result["targetRecovery"] = .number(targetRecovery) }
        if !productSpecification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result["productSpecification"] = .string(productSpecification)
        }
        if !constraints.isEmpty { result["constraints"] = .object(constraints) }
        return .object(result)
    }
}

enum ScientificProjectBasisV3Store {
    private static let prefix = "aurora.scientificProjectBasisV3."

    static func load(projectID: UUID, fallbackComponent: String, fallbackGrade: Double) -> ScientificProjectBasisV3 {
        let key = prefix + projectID.uuidString
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ScientificProjectBasisV3.self, from: data) else {
            return .defaults(component: fallbackComponent, grade: fallbackGrade)
        }
        return decoded
    }

    static func load(project: AuroraProject) -> ScientificProjectBasisV3 {
        load(projectID: project.id, fallbackComponent: project.targetComponent, fallbackGrade: project.targetGrade)
    }

    static func save(_ basis: ScientificProjectBasisV3, projectID: UUID) {
        var value = basis
        value.updatedAt = .now
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: prefix + projectID.uuidString)
    }
}

enum ScientificProjectContractV3 {
    static func enrich(_ value: JSONValue) -> JSONValue {
        switch value {
        case .array(let values):
            return .array(values.map(enrich))
        case .object(let object):
            var result: [String: JSONValue] = [:]
            for (key, child) in object { result[key] = enrich(child) }
            applyContract(to: &result)
            return .object(result)
        default:
            return value
        }
    }

    private static func applyContract(to object: inout [String: JSONValue]) {
        guard let projectValue = object["project"],
              case .object(let projectObject) = projectValue,
              let rawID = projectObject["id"]?.stringValue,
              let projectID = UUID(uuidString: rawID) else { return }

        var designBasis: [String: JSONValue]
        if let current = object["designBasis"], case .object(let currentObject) = current {
            designBasis = currentObject
        } else {
            designBasis = [:]
        }

        let fallbackComponent = designBasis["targetComponent"]?.stringValue ?? "unspecified"
        let fallbackGrade = number(designBasis["targetGrade"]) ?? 0
        let basis = ScientificProjectBasisV3Store.load(
            projectID: projectID,
            fallbackComponent: fallbackComponent,
            fallbackGrade: fallbackGrade
        )

        designBasis["schemaVersion"] = .string(ScientificProjectBasisV3.schemaVersion)
        designBasis["objective"] = .string(basis.objective)
        designBasis["processingMode"] = .string(basis.processingMode.rawValue)
        designBasis["valuableComponent"] = .string(basis.valuableComponent)
        designBasis["targetComponent"] = .string(basis.valuableComponent)
        designBasis["waterRequirement"] = .string(basis.processingMode.waterRequirement)
        designBasis["authority"] = .string(basis.authority)
        designBasis["unitOperationPolicy"] = .object([
            "allowed": .array(basis.allowedUnitOperations.map(JSONValue.string)),
            "prohibited": .array(basis.prohibitedUnitOperations.map(JSONValue.string))
        ])

        if let targetGrade = basis.targetGrade { designBasis["targetGrade"] = .number(targetGrade) }
        if let targetRecovery = basis.targetRecovery { designBasis["targetRecovery"] = .number(targetRecovery) }

        var constraints: [String: JSONValue] = [:]
        if !basis.maximumImpurityComponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            constraints["maximumImpurityComponent"] = .string(basis.maximumImpurityComponent)
        }
        if let maximumImpurityGrade = basis.maximumImpurityGrade {
            constraints["maximumImpurityGrade"] = .number(maximumImpurityGrade)
        }
        if !constraints.isEmpty { designBasis["constraints"] = .object(constraints) }
        if !basis.productSpecification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            designBasis["productSpecification"] = .string(basis.productSpecification)
        }

        object["designBasis"] = .object(designBasis)
        object["scientificProjectContract"] = basis.contractJSON
    }

    private static func number(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .number(let number): return number.isFinite ? number : nil
        case .string(let text): return Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }
}

struct ScientificProjectBasisV3View: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedProjectID: UUID?
    @State private var objective: ScientificProjectObjective = .beneficiation
    @State private var customObjective = ""
    @State private var processingMode: ScientificProcessingMode = .dry
    @State private var valuableComponent = ""
    @State private var targetGrade = ""
    @State private var targetRecovery = ""
    @State private var maximumImpurityComponent = ""
    @State private var maximumImpurityGrade = ""
    @State private var productSpecification = ""
    @State private var allowedUnitOperations = ""
    @State private var prohibitedUnitOperations = ""
    @State private var saveStatus = ""

    private var selectedProject: AuroraProject? {
        if let selectedProjectID, let project = projects.first(where: { $0.id == selectedProjectID }) { return project }
        return projects.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                projectSelection
                scientificIntent
                productTargets
                processPolicy
                governanceSummary
                saveButton
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .navigationTitle("Scientific Project Basis V3")
        .onAppear { initializeSelection() }
        .onChange(of: selectedProjectID) { _, _ in loadSelectedProject() }
    }

    private var header: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: "scope").font(.title2).foregroundStyle(AuroraTheme.accent)
                    Text("Canonical Scientific Project Contract V3").font(.title2.bold())
                    Spacer()
                    StatusBadge(text: "V3 governed")
                }
                Text("Declares the scientific objective, dry/wet/hybrid mode, valuable component, recovery target, product constraints and unit-operation policy before DAG execution.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("This contract is merged into outgoing validation, DAG, engine-job and export payloads without changing measured-evidence authority.")
                    .font(.caption2).foregroundStyle(AuroraTheme.gold)
            }
        }
    }

    private var projectSelection: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Project").font(.headline)
                if projects.isEmpty {
                    Text("Create a project first in Project Intake.").foregroundStyle(.secondary)
                } else {
                    Picker("Project", selection: Binding<UUID?>(get: { selectedProjectID ?? projects.first?.id }, set: { selectedProjectID = $0 })) {
                        ForEach(projects) { project in Text(project.name).tag(Optional(project.id)) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var scientificIntent: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Scientific Intent").font(.headline)
                Picker("Objective", selection: $objective) {
                    ForEach(ScientificProjectObjective.allCases) { item in Text(item.label).tag(item) }
                }
                .pickerStyle(.menu)

                if objective == .custom {
                    TextField("Explicit custom objective", text: $customObjective).textFieldStyle(.roundedBorder)
                }

                Picker("Processing mode", selection: $processingMode) {
                    ForEach(ScientificProcessingMode.allCases) { item in Text(item.label).tag(item) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Water gate").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(processingMode.waterRequirement.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.caption2.bold()).foregroundStyle(processingMode == .dry ? AuroraTheme.good : AuroraTheme.accent)
                }
            }
        }
    }

    private var productTargets: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Product Targets & Constraints").font(.headline)
                TextField("Valuable component, e.g. K2O or P2O5", text: $valuableComponent).textFieldStyle(.roundedBorder)
                TextField("Target grade (%) — optional for diagnosis", text: $targetGrade).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                TextField("Target recovery (%) — optional", text: $targetRecovery).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                Divider().opacity(0.12)
                TextField("Maximum impurity component, e.g. Fe2O3", text: $maximumImpurityComponent).textFieldStyle(.roundedBorder)
                TextField("Maximum impurity grade (%)", text: $maximumImpurityGrade).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                TextField("Product specification / acceptance envelope", text: $productSpecification, axis: .vertical).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var processPolicy: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Unit-Operation Policy").font(.headline)
                Text("Comma-separated canonical unit names. Empty means no explicit allow/prohibit restriction.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Allowed: Crushing, Screening, Magnetic Separation", text: $allowedUnitOperations, axis: .vertical).textFieldStyle(.roundedBorder)
                TextField("Prohibited: Hydrocyclone, Flotation", text: $prohibitedUnitOperations, axis: .vertical).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var governanceSummary: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Execution Governance").font(.headline)
                Label("Dry mode declares water requirement as not applicable.", systemImage: "drop.slash")
                Label("Objective and valuable component are explicit; they are not inferred from ore family.", systemImage: "target")
                Label("Targets are design-basis declarations, not measured evidence.", systemImage: "checkmark.shield")
                Label("Engine/DAG eligibility remains a server-side governed decision.", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .font(.caption)
        }
    }

    private var saveButton: some View {
        VStack(spacing: 8) {
            Button(action: save) {
                Label("SAVE SCIENTIFIC PROJECT CONTRACT V3", systemImage: "checkmark.seal.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedProject == nil || valuableComponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !saveStatus.isEmpty {
                Text(saveStatus).font(.caption).foregroundStyle(AuroraTheme.good)
            }
        }
    }

    private func initializeSelection() {
        if selectedProjectID == nil { selectedProjectID = projects.first?.id }
        loadSelectedProject()
    }

    private func loadSelectedProject() {
        guard let project = selectedProject else { return }
        let basis = ScientificProjectBasisV3Store.load(project: project)
        if let known = ScientificProjectObjective(rawValue: basis.objective) {
            objective = known
            customObjective = ""
        } else {
            objective = .custom
            customObjective = basis.objective
        }
        processingMode = basis.processingMode
        valuableComponent = basis.valuableComponent
        targetGrade = basis.targetGrade.map { String(format: "%.6g", $0) } ?? ""
        targetRecovery = basis.targetRecovery.map { String(format: "%.6g", $0) } ?? ""
        maximumImpurityComponent = basis.maximumImpurityComponent
        maximumImpurityGrade = basis.maximumImpurityGrade.map { String(format: "%.6g", $0) } ?? ""
        productSpecification = basis.productSpecification
        allowedUnitOperations = basis.allowedUnitOperations.joined(separator: ", ")
        prohibitedUnitOperations = basis.prohibitedUnitOperations.joined(separator: ", ")
        saveStatus = ""
    }

    private func save() {
        guard let project = selectedProject else { return }
        let explicitObjective: String = objective == .custom
            ? customObjective.trimmingCharacters(in: .whitespacesAndNewlines)
            : objective.rawValue
        let basis = ScientificProjectBasisV3(
            objective: explicitObjective.isEmpty ? ScientificProjectObjective.beneficiation.rawValue : explicitObjective,
            processingMode: processingMode,
            valuableComponent: valuableComponent.trimmingCharacters(in: .whitespacesAndNewlines),
            targetGrade: parseNumber(targetGrade),
            targetRecovery: parseNumber(targetRecovery),
            maximumImpurityComponent: maximumImpurityComponent.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumImpurityGrade: parseNumber(maximumImpurityGrade),
            productSpecification: productSpecification.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedUnitOperations: parseList(allowedUnitOperations),
            prohibitedUnitOperations: parseList(prohibitedUnitOperations),
            updatedAt: .now
        )
        ScientificProjectBasisV3Store.save(basis, projectID: project.id)

        // Keep legacy fields synchronized for the current V220 backend contract.
        project.targetComponent = basis.valuableComponent
        if let targetGrade = basis.targetGrade { project.targetGrade = targetGrade }
        project.updatedAt = .now
        try? context.save()
        saveStatus = "Saved. V3 contract will be merged into the next server request."
    }

    private func parseNumber(_ raw: String) -> Double? {
        let clean = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let value = Double(clean), value.isFinite else { return nil }
        return value
    }

    private func parseList(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
