import SwiftUI
import SwiftData
import Charts
import Foundation

enum AuroraSurfaceSection: String, CaseIterable, Identifiable, Hashable {
    case command = "Command Center"
    case inputs = "Input Workflow"
    case ore = "Raw Ore Diagnosis"
    case process = "Process & PFD"
    case engines = "Engine Explorer"
    case engineering = "Engineering Drawings"
    case charts = "Charts & Trends"
    case results = "Results Vault"
    case exports = "Export Center"
    case project = "Project Setup"
    case settings = "Runtime Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .command: return "square.grid.2x2.fill"
        case .inputs: return "arrow.down.to.line.compact"
        case .ore: return "circle.hexagongrid.circle"
        case .process: return "arrow.triangle.branch"
        case .engines: return "cpu"
        case .engineering: return "drafting compass"
        case .charts: return "chart.xyaxis.line"
        case .results: return "list.bullet.rectangle.portrait"
        case .exports: return "arrow.down.doc"
        case .project: return "slider.horizontal.3"
        case .settings: return "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .command: return "Live system overview"
        case .inputs: return "Guided data intake"
        case .ore: return "Evidence, quality and problems"
        case .process: return "Route, streams and PFD"
        case .engines: return "Every canonical engine"
        case .engineering: return "PFD and equipment files"
        case .charts: return "Measured and returned trends"
        case .results: return "Governed output vault"
        case .exports: return "PDF, Word, Excel and ZIP"
        case .project: return "Basis and input records"
        case .settings: return "Runtime endpoint and status"
        }
    }
}

struct AuroraIndustrialEngine: Identifiable, Hashable {
    let id: String
    let name: String
    let group: String
    let icon: String
    let description: String
    let keys: [String]
}

let auroraIndustrialEngines: [AuroraIndustrialEngine] = [
    .init(id: "ore_intelligence", name: "Ore Intelligence", group: "Geometallurgy", icon: "OI", description: "Assay, mineralogy, PSD, liberation and ore fingerprint.", keys: ["ore", "assay", "mineral", "mineralogy", "psd", "liberation", "qla", "xrf", "xrd"]),
    .init(id: "resource_model", name: "Resource & Mining", group: "Mining", icon: "RM", description: "Resource classification, mine inputs and mine-to-plant basis.", keys: ["resource", "mining", "mine", "geostat", "block", "pit", "stope", "schedule"]),
    .init(id: "comminution", name: "Comminution", group: "Process physics", icon: "CO", description: "Crushing, grinding, breakage, energy and size reduction.", keys: ["comminution", "grinding", "crushing", "mill", "breakage", "bond", "work_index", "p80"]),
    .init(id: "classification", name: "Classification", group: "Process physics", icon: "CL", description: "Screens, cyclones, partition and size classification.", keys: ["classification", "cyclone", "screen", "partition", "size"]),
    .init(id: "flotation", name: "Flotation", group: "Separation", icon: "FL", description: "Recovery, grade, kinetics, reagents and froth response.", keys: ["flotation", "recovery", "grade", "reagent", "froth", "kinetic"]),
    .init(id: "magnetic_gravity", name: "Magnetic & Gravity", group: "Separation", icon: "MG", description: "Magnetic susceptibility, field response and gravity separation.", keys: ["magnetic", "gravity", "susceptibility", "separator", "field"]),
    .init(id: "hydrometallurgy", name: "Hydrometallurgy", group: "Chemistry", icon: "HY", description: "Leaching, precipitation, solution chemistry and recovery.", keys: ["hydro", "leach", "precip", "dissolution", "solution"]),
    .init(id: "thermodynamics", name: "Thermodynamics", group: "Chemistry", icon: "TH", description: "Activities, speciation, redox, Gibbs and geochemistry.", keys: ["thermo", "gibbs", "speciation", "redox", "activity", "chemistry"]),
    .init(id: "water_recycle", name: "Water & Recycle", group: "Utilities", icon: "WR", description: "Water chemistry, recycle, bleed, scaling and corrosion.", keys: ["water", "recycle", "bleed", "scaling", "corrosion", "ph"]),
    .init(id: "conservation", name: "Conservation & Reconciliation", group: "Balances", icon: "CR", description: "Mass, water, element, charge and energy closure.", keys: ["conservation", "balance", "reconciliation", "closure", "residual", "mass"]),
    .init(id: "equipment_epc", name: "Equipment & EPC", group: "Engineering", icon: "EP", description: "Equipment duties, sizing, cost basis and engineering deliverables.", keys: ["equipment", "epc", "sizing", "duty", "capex", "opex", "engineering"]),
    .init(id: "economics", name: "Economics", group: "Decision intelligence", icon: "EC", description: "CAPEX, OPEX, cash flow, NPV, IRR and sensitivity.", keys: ["economic", "capex", "opex", "npv", "irr", "cash", "cost"]),
    .init(id: "tailings_esg", name: "Tailings & ESG", group: "Sustainability", icon: "ES", description: "Tailings value, water, acid generation and footprint.", keys: ["tailings", "esg", "carbon", "footprint", "acid", "waste"]),
    .init(id: "digital_twin", name: "Digital Twin", group: "Operations", icon: "DT", description: "State estimation, monitoring and operational intelligence.", keys: ["digital", "twin", "historian", "telemetry", "optimization"]),
    .init(id: "hybrid_ai", name: "Hybrid AI & Uncertainty", group: "Decision intelligence", icon: "AI", description: "Physics-residual AI, uncertainty, OOD and evidence ceilings.", keys: ["ai", "uncertainty", "ood", "prediction", "model", "confidence"]),
    .init(id: "governance", name: "Governance & Diagnostics", group: "Assurance", icon: "GD", description: "Runtime status, claim ceilings, gates and audit evidence.", keys: ["govern", "diagnos", "claim", "gate", "quality", "evidence", "warning", "error"])
]

enum IndustrialResultSupport {
    static func rows(for engine: AuroraIndustrialEngine, result: JSONValue?) -> [(String, String)] {
        guard let result else { return [] }
        let needles = engine.keys.map { $0.lowercased() }
        return result.flattenedScalars(limit: 3000).filter { path, _ in
            let lower = path.lowercased()
            return needles.contains(where: { lower.contains($0) })
        }
    }

    static func diagnosis(_ result: JSONValue?) -> [(String, String)] {
        guard let result else { return [] }
        return result.flattenedScalars(limit: 1000).filter { path, _ in
            path.range(of: "issue|warning|error|diagnos|risk|limitation|gate|claim|quality|evidence", options: .regularExpression) != nil
        }
    }

    static func analysisRows(_ project: AuroraProject?) -> [(String, String)] {
        guard let project,
              let data = project.analysesJSON.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return json.flattenedScalars(limit: 500)
    }
}

struct IndustrialSurfaceView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var section: AuroraSurfaceSection = .command

    private var activeProject: AuroraProject? { projects.first }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles.square.filled.on.square")
                            .font(.title2.bold())
                            .foregroundStyle(AuroraTheme.accent)
                        Text("AURORA")
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                            .tracking(5)
                    }
                    Text("INDUSTRIAL INTELLIGENCE OS")
                        .font(.caption2.bold())
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                }
                .padding(18)

                List {
                    Section("CONTROL SURFACE") {
                        ForEach(AuroraSurfaceSection.allCases) { item in
                            Button {
                                section = item
                            } label: {
                                Label(item.rawValue, systemImage: item.icon)
                                    .foregroundStyle(section == item ? AuroraTheme.accent : .primary)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(section == item ? AuroraTheme.panel2 : Color.clear)
                        }
                    }
                }
                .scrollContentBackground(.hidden)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(connectionColor)
                            .frame(width: 9, height: 9)
                        Text(connectionText)
                            .font(.caption.bold())
                    }
                    Text("Railway · Canonical Python authority")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 14))
                .padding(12)
            }
            .background(AuroraTheme.background)
        } detail: {
            Group {
                switch section {
                case .command: IndustrialCommandCenter(section: $section)
                case .inputs: IndustrialInputWorkflow(section: $section, project: activeProject)
                case .ore: IndustrialOreDiagnosis(section: $section, project: activeProject)
                case .process: IndustrialProcessSurface(section: $section, project: activeProject)
                case .engines: IndustrialEngineExplorer(section: $section, project: activeProject)
                case .engineering: EngineeringStudioView()
                case .charts: IndustrialChartsSurface()
                case .results: IndustrialResultsVault()
                case .exports: IndustrialExportCenter(project: activeProject)
                case .project: ProjectsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AuroraTheme.background.ignoresSafeArea())
        }
        .tint(AuroraTheme.accent)
        .task { app.checkHealth() }
    }

    private var connectionText: String {
        switch app.connection {
        case .unknown: return "Runtime status unknown"
        case .checking: return "Checking canonical runtime"
        case .online(let status): return "Runtime online · \(status)"
        case .offline: return "Runtime offline"
        }
    }

    private var connectionColor: Color {
        switch app.connection {
        case .online: return AuroraTheme.good
        case .offline: return AuroraTheme.bad
        case .checking, .unknown: return AuroraTheme.warn
        }
    }
}

struct IndustrialHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption2.bold())
                .tracking(2)
                .foregroundStyle(AuroraTheme.accent)
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct IndustrialMetric: View {
    let label: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.caption.bold())
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct IndustrialInputStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let section: AuroraSurfaceSection
    let isComplete: Bool
}

enum IndustrialInputSupport {
    static func evidenceIsReady(_ project: AuroraProject?) -> Bool {
        guard let project else { return false }
        let raw = project.analysesJSON.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count > 4, raw != "{}", raw != "null" else { return false }
        let hasMeasured = raw.contains("measured")
        let hasOreMeasurement = raw.contains("xrf") || raw.contains("assay") || raw.contains("xrd") || raw.contains("mineral")
        return hasMeasured && hasOreMeasurement
    }

    static func routeIsReady(_ project: AuroraProject?) -> Bool {
        guard let project,
              let data = project.flowsheetJSON.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let unitsValue = value.recursiveFind("units") else { return false }
        if case .array(let units) = unitsValue { return !units.isEmpty }
        return false
    }

    static func steps(for project: AuroraProject?) -> [IndustrialInputStep] {
        let name = (project?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let family = (project?.declaredFamily ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let component = (project?.targetComponent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let identityReady = project != nil && !name.isEmpty && name.lowercased() != "new aurora project" && !family.isEmpty && (project?.feedTPH ?? 0) > 0
        let basisReady = project != nil && !component.isEmpty && (project?.targetGrade ?? 0) > 0
        return [
            IndustrialInputStep(id: "identity", title: "Project identity", detail: "Name · ore family · feed rate", section: .project, isComplete: identityReady),
            IndustrialInputStep(id: "basis", title: "Design target", detail: "Valuable component · target grade", section: .project, isComplete: basisReady),
            IndustrialInputStep(id: "evidence", title: "Measured ore evidence", detail: "XRF · assay · XRD / mineralogy", section: .ore, isComplete: evidenceIsReady(project)),
            IndustrialInputStep(id: "route", title: "Process route", detail: "Ordered units → native PFD", section: .process, isComplete: routeIsReady(project))
        ]
    }

    static func ready(for project: AuroraProject?) -> Bool {
        steps(for: project).allSatisfy { $0.isComplete }
    }

    static func nextStep(for project: AuroraProject?) -> IndustrialInputStep? {
        steps(for: project).first(where: { !$0.isComplete })
    }
}

struct IndustrialInputRail: View {
    let steps: [IndustrialInputStep]
    @Binding var section: AuroraSurfaceSection

    private var nextID: String? {
        steps.first(where: { !$0.isComplete })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clear input path").font(.headline)
                    Text("Project → design target → measured ore evidence → process route → run")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(steps.filter(\.isComplete).count) / \(steps.count)")
                    .font(.headline.monospaced())
                    .foregroundStyle(steps.allSatisfy(\.isComplete) ? AuroraTheme.good : AuroraTheme.accent)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    let isNext = nextID == step.id
                    Button { section = step.section } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(String(format: "%02d", index + 1))
                                    .font(.caption.bold().monospaced())
                                    .foregroundStyle(step.isComplete ? AuroraTheme.background : AuroraTheme.accent)
                                    .padding(7)
                                    .background(step.isComplete ? AuroraTheme.good : isNext ? AuroraTheme.accent : AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 8))
                                Spacer()
                                Image(systemName: step.isComplete ? "checkmark.circle.fill" : isNext ? "arrow.right.circle.fill" : "circle")
                                    .foregroundStyle(step.isComplete ? AuroraTheme.good : isNext ? AuroraTheme.accent : AuroraTheme.warn)
                            }
                            Text(step.title).font(.subheadline.bold()).foregroundStyle(.primary)
                            Text(step.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            Text(step.isComplete ? "COMPLETE" : isNext ? "NEXT ACTION" : "REQUIRED")
                                .font(.caption2.bold())
                                .foregroundStyle(step.isComplete ? AuroraTheme.good : isNext ? AuroraTheme.accent : AuroraTheme.warn)
                        }
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                        .padding(12)
                        .background(step.isComplete ? AuroraTheme.good.opacity(0.10) : isNext ? AuroraTheme.accent.opacity(0.12) : AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isNext ? AuroraTheme.accent.opacity(0.8) : .white.opacity(0.07), lineWidth: isNext ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                if let next = steps.first(where: { !$0.isComplete }) {
                    Label("Next required action: \(next.title)", systemImage: "arrow.turn.down.right")
                        .font(.caption.bold())
                        .foregroundStyle(AuroraTheme.accent)
                } else {
                    Label("All input gates are complete. Review and run.", systemImage: "checkmark.shield.fill")
                        .font(.caption.bold())
                        .foregroundStyle(AuroraTheme.good)
                }
                Spacer()
            }
        }
    }
}

struct IndustrialInputWorkflow: View {
    @Binding var section: AuroraSurfaceSection
    let project: AuroraProject?
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context

    private var steps: [IndustrialInputStep] { IndustrialInputSupport.steps(for: project) }
    private var completed: Int { steps.filter(\.isComplete).count }
    private var isReady: Bool { completed == steps.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IndustrialHeader(eyebrow: "Controlled data intake", title: "Input Workflow", subtitle: "A guided admission path for the exact project, evidence and route payload sent to the canonical Railway runtime.")

                HStack {
                    Button { section = .command } label: { Label("Command Center", systemImage: "square.grid.2x2") }
                    Button {
                        if let next = IndustrialInputSupport.nextStep(for: project) { section = next.section }
                        else if let project { app.run(project: project, context: context) }
                    } label: {
                        Label(isReady ? "Run Full AURORA" : "Continue input", systemImage: isReady ? "bolt.fill" : "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.isRunning)
                }

                AuroraCard {
                    IndustrialInputRail(steps: steps, section: $section)
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            Text("What enters the canonical request").font(.headline)
                            Spacer()
                            StatusBadge(text: isReady ? "Ready to execute" : "Inputs required")
                        }
                        Text("These four blocks are persisted with the project and are reviewed before any engine is called. Estimates stay qualified; they never replace measured ore evidence.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 10)], spacing: 10) {
                            Label("Identity: name, ore family, feed t/h", systemImage: "folder")
                            Label("Design: target component and grade", systemImage: "scope")
                            Label("Evidence: XRF/assay/XRD with MEASURED authority", systemImage: "waveform.path.ecg")
                            Label("Route: flowsheetJSON units in process order", systemImage: "arrow.triangle.branch")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Where to enter each item").font(.headline)
                        Text("01 Project Setup → project basis and design target")
                        Text("02 Project Setup → Ore & Analyses → paste or import JSON / CSV evidence")
                        Text("03 Project Setup → Process Route → enter flowsheet JSON, for example:")
                        Text(#"{ "units": ["Crushing", "Grinding", "Flotation"] }"#)
                            .font(.caption.monospaced())
                            .foregroundStyle(AuroraTheme.gold)
                            .textSelection(.enabled)
                        Text("04 Return here → confirm all four cards are green → Run Full AURORA")
                            .font(.caption.bold())
                            .foregroundStyle(AuroraTheme.accent)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Live input inventory").font(.headline)
                            Spacer()
                            Text("\(completed) / \(steps.count) gates")
                                .font(.caption.bold())
                                .foregroundStyle(isReady ? AuroraTheme.good : AuroraTheme.warn)
                        }
                        LabeledContent("Project") { Text(project?.name ?? "No project").foregroundStyle(.secondary) }
                        LabeledContent("Ore evidence") { Text(IndustrialInputSupport.evidenceIsReady(project) ? "Measured evidence detected" : "Not ready").foregroundStyle(IndustrialInputSupport.evidenceIsReady(project) ? AuroraTheme.good : AuroraTheme.warn) }
                        LabeledContent("Process route") { Text(IndustrialInputSupport.routeIsReady(project) ? "Ordered units detected" : "Not configured").foregroundStyle(IndustrialInputSupport.routeIsReady(project) ? AuroraTheme.good : AuroraTheme.warn) }
                        ProgressView(value: Double(completed), total: Double(steps.count))
                            .tint(isReady ? AuroraTheme.good : AuroraTheme.accent)
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Admission result").font(.headline)
                        if isReady {
                            Label("All input gates are complete. You can run the full workflow or select one engine from Engine Explorer.", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(AuroraTheme.good)
                        } else if let next = IndustrialInputSupport.nextStep(for: project) {
                            Label("Complete \(next.title) next, then return here for review.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(AuroraTheme.warn)
                        }
                        Button("Open Project Setup") { section = .project }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(22)
        }
    }
}

struct IndustrialCommandCenter: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @Query(sort: \RunRecord.updatedAt, order: .reverse) private var runs: [RunRecord]
    @Binding var section: AuroraSurfaceSection

    private var project: AuroraProject? { projects.first }
    private var inputSteps: [IndustrialInputStep] { IndustrialInputSupport.steps(for: project) }
    private var inputReady: Bool { inputSteps.allSatisfy { $0.isComplete } }
    private var covered: Int {
        guard app.activeResult != nil else { return 0 }
        return auroraIndustrialEngines.filter { !IndustrialResultSupport.rows(for: $0, result: app.activeResult).isEmpty }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IndustrialHeader(eyebrow: "AURORA control surface", title: "Command Center", subtitle: "One native surface for raw-ore diagnosis, process physics, engineering outputs and decisions.")

                HStack(spacing: 10) {
                    Button { section = .inputs } label: { Label("Input workflow", systemImage: "arrow.down.to.line.compact") }
                        .buttonStyle(.borderedProminent)
                    Button { section = .project } label: { Label("Configure inputs", systemImage: "slider.horizontal.3") }
                    Button { section = .ore } label: { Label("Inspect ore", systemImage: "circle.hexagongrid.circle") }
                    Button {
                        guard let project else { section = .inputs; return }
                        if inputReady { app.run(project: project, context: context) }
                        else { section = .inputs }
                    } label: {
                        Label(inputReady ? (app.isRunning ? "Running AURORA" : "Run Full AURORA") : "Complete input path", systemImage: inputReady ? "bolt.fill" : "exclamationmark.triangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.isRunning)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    IndustrialMetric(label: "ACTIVE PROJECT", value: project?.name ?? "None", detail: project?.declaredFamily.capitalized ?? "Awaiting basis", icon: "folder.fill", tint: AuroraTheme.accent)
                    IndustrialMetric(label: "CANONICAL RUNS", value: "\(runs.count)", detail: "saved locally", icon: "bolt.fill", tint: AuroraTheme.gold)
                    IndustrialMetric(label: "INPUT PATH", value: "\(inputSteps.filter { $0.isComplete }.count) / \(inputSteps.count)", detail: "gated steps complete", icon: "checklist", tint: inputReady ? AuroraTheme.good : AuroraTheme.warn)
                    IndustrialMetric(label: "ENGINE COVERAGE", value: "\(covered) / \(auroraIndustrialEngines.count)", detail: "engines with returned paths", icon: "cpu", tint: AuroraTheme.warn)
                }

                AuroraCard {
                    IndustrialInputRail(steps: inputSteps, section: $section)
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Execution readiness").font(.headline)
                            Spacer()
                            StatusBadge(text: inputReady ? "Ready to execute" : "Inputs required")
                        }
                        Text("The same four-step input contract controls the native run button. Missing measurements and unsupported evidence stay visible as blockers.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if inputReady {
                            Label("Project, design target, measured ore evidence and process route are present.", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(AuroraTheme.good)
                        } else if let next = IndustrialInputSupport.nextStep(for: project) {
                            Label("Complete \(next.title) next. Open the blue card in Input Workflow.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(AuroraTheme.warn)
                        }
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Engine map").font(.headline)
                            Spacer()
                            Button("Open explorer") { section = .engines }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                            ForEach(auroraIndustrialEngines.prefix(8)) { engine in
                                Button { section = .engines } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(engine.icon).font(.caption.bold()).foregroundStyle(AuroraTheme.background).padding(7).background(AuroraTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                                        Text(engine.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                        Text(engine.description).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(3)
                                        Text(IndustrialResultSupport.rows(for: engine, result: app.activeResult).isEmpty ? "AWAITING RUN" : "OUTPUT AVAILABLE")
                                            .font(.caption2.bold()).foregroundStyle(IndustrialResultSupport.rows(for: engine, result: app.activeResult).isEmpty ? AuroraTheme.warn : AuroraTheme.good)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let result = app.activeResult {
                    ResultsPanel(result: result)
                } else {
                    AuroraCard {
                        ContentUnavailableView("No canonical run yet", systemImage: "waveform.path.ecg", description: Text("Complete the input workflow, then run AURORA with real project and ore evidence."))
                    }
                }
            }
            .padding(22)
        }
    }
}

struct IndustrialOreDiagnosis: View {
    @Binding var section: AuroraSurfaceSection
    let project: AuroraProject?
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IndustrialHeader(eyebrow: "Geometallurgy", title: "Raw Ore Diagnosis", subtitle: "Measured evidence, quality gates, derived descriptors and explicit problem register.")
                HStack {
                    Button { section = .inputs } label: { Label("Input workflow", systemImage: "arrow.down.to.line.compact") }
                    Button { section = .project } label: { Label("Open project inputs", systemImage: "slider.horizontal.3") }
                    Button {
                        if let project, IndustrialInputSupport.ready(for: project) { app.run(project: project, context: context, module: "ore_intelligence") }
                        else { section = .inputs }
                    } label: { Label("Run Ore Intelligence", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.isRunning)
                    Button { section = .exports } label: { Label("Export diagnosis", systemImage: "arrow.down.doc") }
                }

                if let project {
                    let analysis = IndustrialResultSupport.analysisRows(project)
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("Evidence profile").font(.headline); Spacer(); StatusBadge(text: analysis.isEmpty ? "No evidence" : "Evidence loaded") }
                            Text("\(analysis.count) returned scalar field(s) from the local ore record. Authority remains attached to the input JSON and canonical result.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if analysis.isEmpty {
                                Label("Add XRF/assay, XRD/mineralogy, PSD or QLA data in Project Setup.", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(AuroraTheme.warn)
                            } else {
                                ForEach(Array(analysis.prefix(12).enumerated()), id: \.offset) { _, row in
                                    HStack(alignment: .top) { Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary); Spacer(); Text(row.1).font(.caption2.monospaced()) }
                                }
                            }
                        }
                    }

                    AuroraCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Problem register").font(.headline)
                            let problems = IndustrialResultSupport.diagnosis(app.activeResult)
                            if problems.isEmpty {
                                Label(app.activeResult == nil ? "Run the canonical workflow to populate ore problems." : "No explicit diagnostic path was returned.", systemImage: app.activeResult == nil ? "info.circle" : "checkmark.circle")
                                    .foregroundStyle(app.activeResult == nil ? AuroraTheme.warn : AuroraTheme.good)
                            } else {
                                ForEach(Array(problems.prefix(30).enumerated()), id: \.offset) { _, row in
                                    VStack(alignment: .leading, spacing: 3) { Text(row.0).font(.caption2.monospaced()).foregroundStyle(AuroraTheme.accent); Text(row.1).font(.caption).foregroundStyle(.secondary) }
                                    Divider().opacity(0.15)
                                }
                            }
                        }
                    }

                    AuroraCard {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("Ore engine output").font(.headline); Spacer(); Button("Open in Engine Explorer") { section = .engines } }
                            let rows = IndustrialResultSupport.rows(for: auroraIndustrialEngines[0], result: app.activeResult)
                            if rows.isEmpty { Text("No returned output path for this engine in the current run.").foregroundStyle(.secondary) }
                            else { ForEach(Array(rows.prefix(35).enumerated()), id: \.offset) { _, row in HStack { Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary); Spacer(); Text(row.1).font(.caption2.monospaced()) } } }
                        }
                    }
                } else {
                    AuroraCard { ContentUnavailableView("No active project", systemImage: "folder.badge.questionmark", description: Text("Create a project before adding ore evidence.")) }
                }
            }
            .padding(22)
        }
    }
}

struct IndustrialProcessSurface: View {
    @Binding var section: AuroraSurfaceSection
    let project: AuroraProject?
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context

    private let referenceRoute = [
        ("RAW ORE", "circle.hexagongrid.circle"),
        ("COMMINUTION", "gearshape.2"),
        ("CLASSIFICATION", "line.3.horizontal.decrease.circle"),
        ("SEPARATION", "arrow.triangle.branch"),
        ("PRODUCT", "shippingbox"),
        ("TAILINGS + WATER", "drop.triangle")
    ]

    private var displayedRoute: [(String, String)] {
        guard let project,
              let data = project.flowsheetJSON.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let unitsValue = value.recursiveFind("units"),
              case .array(let units) = unitsValue else { return referenceRoute }
        let names = units.compactMap { $0.stringValue }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return referenceRoute }
        return names.map { (String($0.prefix(24)).uppercased(), "circle.fill") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IndustrialHeader(eyebrow: "Process architecture", title: "Process & PFD", subtitle: "A native process surface for route review, returned streams and engineering drawings.")
                HStack {
                    Button { section = .inputs } label: { Label("Input workflow", systemImage: "arrow.down.to.line.compact") }
                    Button {
                        if let project {
                            if IndustrialInputSupport.ready(for: project) { app.run(project: project, context: context) }
                            else { section = .inputs }
                        } else { section = .inputs }
                    } label: { Label("Run Full AURORA", systemImage: "bolt.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.isRunning)
                    Button("Engineering drawings") { section = .engineering }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Route schematic").font(.headline); Spacer(); StatusBadge(text: app.activeResult == nil ? "Reference preview" : "Canonical result available") }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(displayedRoute.enumerated()), id: \.offset) { index, item in
                                    HStack(spacing: 8) {
                                        VStack(spacing: 7) {
                                            Image(systemName: item.1).font(.title3).foregroundStyle(AuroraTheme.accent)
                                            Text(item.0).font(.caption2.bold()).multilineTextAlignment(.center).frame(width: 92)
                                        }
                                        .frame(width: 112, height: 88)
                                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 14))
                                        if index < displayedRoute.count - 1 { Image(systemName: "arrow.right").foregroundStyle(AuroraTheme.gold) }
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                        }
                        Text("This schematic is a review surface. Engineering geometry and stream values are shown only when returned by the canonical runtime.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Returned process paths").font(.headline)
                        let rows = app.activeResult?.flattenedScalars(limit: 1500).filter { path, _ in
                            let p = path.lowercased(); return p.contains("flow") || p.contains("stream") || p.contains("unit") || p.contains("pfd") || p.contains("process")
                        } ?? []
                        if rows.isEmpty { Text("No canonical process path is available yet.").foregroundStyle(.secondary) }
                        else { ForEach(Array(rows.prefix(40).enumerated()), id: \.offset) { _, row in HStack { Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary); Spacer(); Text(row.1).font(.caption2.monospaced()) } } }
                    }
                }
            }
            .padding(22)
        }
    }
}

struct IndustrialEngineExplorer: View {
    @Binding var section: AuroraSurfaceSection
    let project: AuroraProject?
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @State private var selectedID = auroraIndustrialEngines[0].id

    private var selected: AuroraIndustrialEngine { auroraIndustrialEngines.first(where: { $0.id == selectedID }) ?? auroraIndustrialEngines[0] }
    private var rows: [(String, String)] { IndustrialResultSupport.rows(for: selected, result: app.activeResult) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IndustrialHeader(eyebrow: "Canonical outputs", title: "Engine Explorer", subtitle: "Open one engine at a time. Values are displayed from the returned canonical response, with no synthetic fill.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 10)], spacing: 10) {
                    ForEach(auroraIndustrialEngines) { engine in
                        Button { selectedID = engine.id } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Text(engine.icon).font(.caption.bold()).foregroundStyle(AuroraTheme.background).padding(7).background(engine.id == selectedID ? AuroraTheme.accent : AuroraTheme.gold, in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) { Text(engine.name).font(.subheadline.bold()).foregroundStyle(.primary); Text(engine.group).font(.caption2).foregroundStyle(.secondary); Text(IndustrialResultSupport.rows(for: engine, result: app.activeResult).isEmpty ? "No returned paths" : "\(IndustrialResultSupport.rows(for: engine, result: app.activeResult).count) paths").font(.caption2).foregroundStyle(IndustrialResultSupport.rows(for: engine, result: app.activeResult).isEmpty ? AuroraTheme.warn : AuroraTheme.good) }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(11)
                            .background(engine.id == selectedID ? AuroraTheme.panel2 : AuroraTheme.panel, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) { Text(selected.name).font(.title2.bold()); Text("\(selected.group) · \(selected.description)").font(.subheadline).foregroundStyle(.secondary) }
                            Spacer()
                            Button {
                                if let project, IndustrialInputSupport.ready(for: project) { app.run(project: project, context: context, module: selected.id) }
                                else { section = .inputs }
                            } label: { Label("Run engine", systemImage: "play.fill") }
                                .buttonStyle(.borderedProminent)
                                .disabled(app.isRunning)
                        }
                        Divider().opacity(0.2)
                        if rows.isEmpty {
                            ContentUnavailableView("No returned output for \(selected.name)", systemImage: "cpu", description: Text("Run this engine with a real project basis. Missing or unsupported outputs remain explicitly unavailable."))
                        } else {
                            ForEach(Array(rows.prefix(160).enumerated()), id: \.offset) { _, row in
                                VStack(alignment: .leading, spacing: 4) { Text(row.0).font(.caption2.monospaced()).foregroundStyle(AuroraTheme.accent); Text(row.1).font(.caption.monospaced()).textSelection(.enabled) }
                                Divider().opacity(0.12)
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
    }
}

struct IndustrialChartsSurface: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IndustrialHeader(eyebrow: "Visual analytics", title: "Charts & Trends", subtitle: "Charts use numeric values returned by the canonical runtime only. No chart is fabricated when data is absent.")
                AuroraCard {
                    let kpis = ResultTools.kpis(app.activeResult)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Canonical KPI chart").font(.headline); Spacer(); StatusBadge(text: kpis.isEmpty ? "Awaiting run" : "Returned values") }
                        if kpis.isEmpty {
                            ContentUnavailableView("No numeric result values yet", systemImage: "chart.xyaxis.line", description: Text("Run AURORA to populate measured, derived or governed numeric outputs."))
                        } else {
                            Chart(kpis) { item in
                                BarMark(x: .value("KPI", item.name), y: .value("Value", item.value))
                                    .foregroundStyle(AuroraTheme.accent.gradient)
                                    .annotation(position: .top) { Text(item.value.formatted(.number.precision(.fractionLength(0...2)))).font(.caption2).foregroundStyle(.secondary) }
                            }
                            .frame(height: 280)
                        }
                    }
                }
                if let result = app.activeResult {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 9) { Text("Numeric trend source").font(.headline); ForEach(Array(result.flattenedScalars(limit: 1200).filter { _, value in Double(value) != nil }.prefix(35).enumerated()), id: \.offset) { _, row in HStack { Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary); Spacer(); Text(row.1).font(.caption2.monospaced()) } } }
                    }
                }
            }
            .padding(22)
        }
    }
}

struct IndustrialResultsVault: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IndustrialHeader(eyebrow: "Governed data", title: "Results Vault", subtitle: "The latest canonical response, engine paths, evidence labels and claim ceiling in one native view.")
                if let result = app.activeResult {
                    ResultsPanel(result: result)
                    AuroraCard { DisclosureGroup("Full canonical JSON") { Text(result.prettyString()).font(.caption2.monospaced()).textSelection(.enabled) } }
                } else {
                    AuroraCard { ContentUnavailableView("No canonical run saved", systemImage: "archivebox", description: Text("Run the full workflow or an individual engine to populate the vault.")) }
                }
            }
            .padding(22)
        }
    }
}

struct IndustrialExportFormat: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
}

let industrialExportFormats: [IndustrialExportFormat] = [
    .init(id: "pdf", name: "PDF report", icon: "doc.richtext", description: "Paginated engineering report"),
    .init(id: "docx", name: "Word document", icon: "doc.text", description: "Editable governed deliverable"),
    .init(id: "xlsx", name: "Excel workbook", icon: "tablecells", description: "Summary, evidence and outputs"),
    .init(id: "csv", name: "CSV output table", icon: "list.number", description: "Flat path/value table"),
    .init(id: "json", name: "Canonical JSON", icon: "curlybraces", description: "Exact structured response"),
    .init(id: "bundle", name: "Complete ZIP bundle", icon: "archivebox", description: "PDF, Word, Excel, CSV, JSON and HTML")
]

struct IndustrialExportCenter: View {
    let project: AuroraProject?
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IndustrialHeader(eyebrow: "Deliverables", title: "Export Center", subtitle: "Generate one consolidated output from the project, ore diagnosis, engine paths, drawings metadata and governance record.")
                if project == nil {
                    AuroraCard { ContentUnavailableView("No project basis yet", systemImage: "doc.badge.gearshape", description: Text("Exports can be generated after a project is created.")) }
                } else {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Current export scope").font(.headline)
                            Text(app.activeResult == nil ? "Project and diagnosis context will be exported. Full engine output will be added after a canonical run." : "The latest canonical result will be included with the project and evidence context.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                                ForEach(industrialExportFormats) { format in
                                    Button { app.export(project: project!, format: format.id) } label: {
                                        VStack(alignment: .leading, spacing: 7) {
                                            Image(systemName: format.icon).font(.title3).foregroundStyle(AuroraTheme.accent)
                                            Text(format.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                            Text(format.description).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                            Text(app.isExporting ? "GENERATING" : "EXPORT").font(.caption2.bold()).foregroundStyle(AuroraTheme.gold)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 13))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(app.isExporting)
                                }
                            }
                            if app.isExporting { ProgressView("Generating server-side deliverable…") }
                            if let url = app.lastExportURL {
                                Divider().opacity(0.2)
                                ShareLink(item: url) { Label("Share \(app.lastExportName ?? "latest file")", systemImage: "square.and.arrow.up") }
                                Text(url.lastPathComponent).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let error = app.lastError, !error.isEmpty {
                    AuroraCard { VStack(alignment: .leading, spacing: 6) { StatusBadge(text: "Export or runtime error"); Text(error).font(.caption.monospaced()).textSelection(.enabled) } }
                }
            }
            .padding(22)
        }
    }
}
