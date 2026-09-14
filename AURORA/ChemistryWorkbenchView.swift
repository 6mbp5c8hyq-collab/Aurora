import SwiftUI
import SwiftData

struct ChemistryWorkbenchView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedProjectID: UUID?
    @State private var outputQuery = ""

    private let domains: [ChemistryDomain] = [
        .init(
            id: "aqueous",
            title: "Aqueous Speciation",
            subtitle: "species · ionic strength · activities",
            module: "thermodynamics",
            icon: "drop.degreesign",
            terms: ["speciation", "species", "ionic", "activity", "complex", "molality", "aqueous"]
        ),
        .init(
            id: "equilibrium",
            title: "Phase Equilibria",
            subtitle: "Gibbs · precipitation · dissolution",
            module: "thermodynamics",
            icon: "cube.transparent",
            terms: ["gibbs", "equilibrium", "precip", "dissolution", "saturation", "solid_solution", "phase"]
        ),
        .init(
            id: "redox",
            title: "Redox Authority",
            subtitle: "Eh · pe · ORP · Nernst",
            module: "thermodynamics",
            icon: "bolt.horizontal.circle",
            terms: ["redox", "eh", "orp", "nernst", "oxidation", "reduction", "pe"]
        ),
        .init(
            id: "surface",
            title: "Surface & Exchange",
            subtitle: "surface complexation · CD-MUSIC · ion exchange",
            module: "thermodynamics",
            icon: "circle.hexagongrid",
            terms: ["surface", "complexation", "cd_music", "triple_layer", "exchange", "zeta", "charge"]
        ),
        .init(
            id: "kinetics",
            title: "Reaction Kinetics",
            subtitle: "rate laws · kinetic coupling",
            module: "hydrometallurgy",
            icon: "timer",
            terms: ["kinetic", "rate", "reaction_path", "residence", "conversion"]
        ),
        .init(
            id: "hydromet",
            title: "Hydrometallurgy",
            subtitle: "leach · SX · precipitation · recovery",
            module: "hydrometallurgy",
            icon: "flask",
            terms: ["leach", "hydromet", "solvent", "extraction", "raffinate", "pregnant", "recovery", "precip"]
        ),
        .init(
            id: "water",
            title: "Water & Recycle",
            subtitle: "scaling · corrosion · bleed · salinity",
            module: "water_circuit",
            icon: "arrow.triangle.2.circlepath",
            terms: ["water", "recycle", "bleed", "scale", "scaling", "corrosion", "salinity", "alkalinity", "conductivity"]
        ),
        .init(
            id: "electrolyte",
            title: "Electrolyte Models",
            subtitle: "Davies · SIT · Pitzer authority evidence",
            module: "thermodynamics",
            icon: "function",
            terms: ["davies", "sit", "pitzer", "electrolyte", "debye", "activity_model"]
        )
    ]

    private var selectedProject: AuroraProject? {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) {
            return selected
        }
        return projects.first
    }

    private var rows: [(String, String)] {
        guard let result = app.activeResult else { return [] }
        return result.flattenedScalars(limit: 12_000)
    }

    private var filteredRows: [(String, String)] {
        let chemistryTerms = domains.flatMap(\.terms)
        let chemistryRows = rows.filter { row in
            let path = row.0.lowercased()
            return chemistryTerms.contains(where: path.contains)
        }
        let q = outputQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(chemistryRows.prefix(600)) }
        return chemistryRows.filter {
            $0.0.lowercased().contains(q) || $0.1.lowercased().contains(q)
        }.prefix(600).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                projectAndExecution
                parityStrip
                domainGrid
                outputLedger
                governance
            }
            .padding(20)
        }
        .navigationTitle("Chemistry Suite")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "atom")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AuroraTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("AURORA CHEMISTRY AUTHORITY")
                        .font(.caption.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Thermodynamics · Geochemistry · Hydrometallurgy · Water Chemistry")
                        .font(.title2.bold())
                    Text("One governed surface over the canonical chemistry engines. Values are displayed only when returned by the runtime; the app does not synthesize missing species, equilibrium states or industrial claims.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: app.connectionLabel)
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var projectAndExecution: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chemistry execution basis")
                    .font(.headline)
                Spacer()
                if app.isRunning {
                    ProgressView()
                }
            }

            if projects.isEmpty {
                ContentUnavailableView(
                    "No AURORA project",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Create or load a project before running chemistry engines.")
                )
            } else {
                Picker("Project", selection: Binding(
                    get: { selectedProject?.id ?? projects[0].id },
                    set: { selectedProjectID = $0 }
                )) {
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 10) {
                    runButton("Thermodynamics", module: "thermodynamics", icon: "atom")
                    runButton("Hydrometallurgy", module: "hydrometallurgy", icon: "flask")
                    runButton("Water Circuit", module: "water_circuit", icon: "drop.fill")
                }

                if let error = app.lastError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !app.runStatus.isEmpty {
                    Text(app.runStatus)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var parityStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REFERENCE CAPABILITY TARGET")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                parityBadge("PHREEQC", detail: "speciation · Pitzer/SIT · surfaces · kinetics")
                parityBadge("GWB", detail: "reaction paths · kinetics · reactive transport")
                parityBadge("OLI", detail: "electrolytes · multiphase · scaling/corrosion")
            }
        }
    }

    private var domainGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(domains) { domain in
                domainCard(domain)
            }
        }
    }

    private var outputLedger: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHEMISTRY OUTPUT LEDGER")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(AuroraTheme.accent)
                    Text("\(filteredRows.count) returned scalar paths")
                        .font(.headline)
                }
                Spacer()
                TextField("Filter paths / values", text: $outputQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 330)
            }

            if filteredRows.isEmpty {
                ContentUnavailableView(
                    "No chemistry outputs in the active result",
                    systemImage: "atom",
                    description: Text("Run Thermodynamics, Hydrometallurgy or Water Circuit. Missing values remain explicitly unreported.")
                )
                .frame(minHeight: 180)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredRows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .top, spacing: 14) {
                            Text(row.0)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            Text(row.1)
                                .font(.caption.monospaced().weight(.semibold))
                                .frame(width: 220, alignment: .trailing)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 8)
                        if index < filteredRows.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var governance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Chemistry governance", systemImage: "checkmark.shield")
                .font(.headline)
            Text("Required numerical authority: explicit activity model, thermodynamic database provenance, species charge metadata, solver convergence, component/charge conservation, applicability-domain warnings, and benchmark evidence. Pitzer, surface-complexation, kinetic, gas/solid-solution and reactive-transport claims must not silently degrade to simpler models.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func runButton(_ title: String, module: String, icon: String) -> some View {
        Button {
            guard let project = selectedProject else { return }
            app.run(project: project, context: modelContext, module: module)
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(app.isRunning || selectedProject == nil)
    }

    private func parityBadge(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.subheadline.bold())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func domainCard(_ domain: ChemistryDomain) -> some View {
        let count = rowsForDomain(domain).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: domain.icon)
                    .foregroundStyle(AuroraTheme.accent)
                Spacer()
                Text(count == 0 ? "UNREPORTED" : "\(count) PATHS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(count == 0 ? .secondary : AuroraTheme.good)
            }
            Text(domain.title)
                .font(.headline)
            Text(domain.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Button("Run governed engine") {
                guard let project = selectedProject else { return }
                app.run(project: project, context: modelContext, module: domain.module)
            }
            .font(.caption.weight(.semibold))
            .disabled(app.isRunning || selectedProject == nil)
        }
        .padding(14)
        .frame(minHeight: 145, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func rowsForDomain(_ domain: ChemistryDomain) -> [(String, String)] {
        rows.filter { row in
            let path = row.0.lowercased()
            return domain.terms.contains(where: path.contains)
        }
    }
}

private struct ChemistryDomain: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let module: String
    let icon: String
    let terms: [String]
}
