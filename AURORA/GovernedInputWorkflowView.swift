import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct GovernedInputWorkflowView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedProjectID: UUID?

    private var selectedProject: AuroraProject? {
        if let selectedProjectID,
           let selected = projects.first(where: { $0.id == selectedProjectID }) { return selected }
        return projects.first
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProjectID) {
                ForEach(projects) { project in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.headline)
                        Text("\(project.declaredFamily.capitalized) · \(project.feedTPH.formatted()) t/h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Design basis · evidence governed")
                            .font(.caption2)
                            .foregroundStyle(AuroraTheme.gold)
                    }
                    .tag(Optional(project.id))
                }
                .onDelete { indexSet in
                    for index in indexSet { context.delete(projects[index]) }
                    try? context.save()
                    if let selectedProjectID, !projects.contains(where: { $0.id == selectedProjectID }) {
                        self.selectedProjectID = nil
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                Button {
                    let project = AuroraProject()
                    context.insert(project)
                    try? context.save()
                    selectedProjectID = project.id
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraTheme.background)
        } detail: {
            if let selectedProject {
                GovernedProjectIntakeEditor(project: selectedProject)
            } else {
                ContentUnavailableView(
                    "No project selected",
                    systemImage: "folder.badge.plus",
                    description: Text("Create a project to define design basis, source-tagged evidence and process route.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AuroraTheme.background)
            }
        }
        .onAppear {
            if selectedProjectID == nil { selectedProjectID = projects.first?.id }
        }
    }
}

private struct GovernedProjectIntakeEditor: View {
    @Bindable var project: AuroraProject
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context

    @State private var importer = false
    @State private var importMessage: String?
    @State private var quickValues: [String: String] = [:]
    @State private var quickAuthorities: [String: String] = [:]
    @State private var quickSources: [String: String] = [:]
    @State private var route: [String] = []
    @State private var showRawAnalyses = false
    @State private var showRawFlowsheet = false
    @State private var preflightResult: JSONValue?
    @State private var preflightError: String?
    @State private var isValidating = false
    @State private var selectedEngineID = "ore_intelligence"

    private let assayFields: [InputAssayField] = [
        .init(id: "P2O5", label: "P₂O₅", unit: "%"),
        .init(id: "CaO", label: "CaO", unit: "%"),
        .init(id: "MgO", label: "MgO", unit: "%"),
        .init(id: "SiO2", label: "SiO₂", unit: "%"),
        .init(id: "Fe2O3", label: "Fe₂O₃", unit: "%"),
        .init(id: "Al2O3", label: "Al₂O₃", unit: "%"),
        .init(id: "LOI", label: "LOI", unit: "%"),
        .init(id: "P80_um", label: "P80", unit: "µm"),
        .init(id: "solids_pct", label: "Solids", unit: "%"),
        .init(id: "pH", label: "pH", unit: "")
    ]

    private let routeLibrary = [
        "ROM Feed", "Crushing", "Screening", "Scrubbing", "Desliming", "Grinding",
        "Classification", "Flotation", "Magnetic Separation", "Gravity Separation",
        "Leaching", "Thickening", "Filtration", "Drying", "Product", "Tailings"
    ]

    private var analysesValue: JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(project.analysesJSON.utf8))) ?? .object([:])
    }

    private var inventory: InputEvidenceInventory {
        InputEvidenceInventory.build(analyses: analysesValue, route: route)
    }

    private var engineRows: [InputEngineEvidenceRow] {
        let runtimeIDs = runtimeEngineIDs
        return runtimeIDs.map { id in
            InputEngineEvidenceRow(engineID: id, relevantCategoryIDs: InputEvidenceSemanticMap.relevantCategories(for: id))
        }
    }

    private var runtimeEngineIDs: [String] {
        guard let audit = app.runtimeAudit,
              let engines = audit.recursiveFind("engines"),
              case .object(let object) = engines,
              let declared = object["declared"],
              case .array(let rows) = declared else { return InputEvidenceSemanticMap.engineFallback }
        let ids = rows.compactMap { row -> String? in
            if case .object(let object) = row { return object["id"]?.stringValue }
            return row.stringValue
        }
        return ids.isEmpty ? InputEvidenceSemanticMap.engineFallback : ids
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                authorityRule
                designBasis
                quickEvidence
                importedEvidence
                scientificInventory
                engineEvidenceMatrix
                processRoute
                serverPreflight
                engineeringNotes
                saveBar
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .onAppear { loadState() }
        .onChange(of: project.id) { _, _ in loadState() }
        .fileImporter(
            isPresented: $importer,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText, .pdf, .spreadsheet]
        ) { result in
            importFile(result)
        }
    }

    private var titleBlock: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("Project name", text: $project.name)
                        .font(.largeTitle.bold())
                    Text("Design basis → source-aware evidence → process route → server preflight → governed execution")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Input authority is kept separate from scientific value. A numeric field is not treated as measured merely because it exists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    StatusBadge(text: "Input governance")
                    Text("\(inventory.observedCategoryIDs.count)/\(InputEvidenceCategory.all.count) evidence dimensions present")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var authorityRule: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(AuroraTheme.good)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Input Authority Rule").font(.headline)
                    Text("Project throughput, target grade and route are design-basis declarations. Quick assay values remain user-declared unless their metadata says otherwise. A quick value requested as 'Measured' is credited as measured_source_tagged only when a non-empty source reference is supplied. Server-parsed PDF/XLSX/CSV records remain server_parsed_input and are not automatically promoted to measured laboratory evidence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var designBasis: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Project & Design Basis").font(.headline)
                        Text("Authority: user_declared_design_basis · not measured plant state")
                            .font(.caption2.monospaced())
                            .foregroundStyle(AuroraTheme.gold)
                    }
                    Spacer()
                    Image(systemName: "scope").foregroundStyle(AuroraTheme.accent)
                }
                LabeledContent("Ore / deposit family") {
                    TextField("phosphate", text: $project.declaredFamily).multilineTextAlignment(.trailing)
                }
                LabeledContent("Plant feed") {
                    HStack(spacing: 5) {
                        TextField("100", value: $project.feedTPH, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text("t/h").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Target component") {
                    TextField("P2O5", text: $project.targetComponent).multilineTextAlignment(.trailing)
                }
                LabeledContent("Target grade") {
                    HStack(spacing: 5) {
                        TextField("35", value: $project.targetGrade, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var quickEvidence: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Quick Assay Evidence").font(.headline)
                        Text("Each field carries an explicit requested authority and optional source reference.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { importer = true } label: {
                        Label("Import Lab / Ore File", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 10)], spacing: 10) {
                    ForEach(assayFields) { field in
                        quickFieldCard(field)
                    }
                }

                HStack {
                    Button("Apply quick evidence") { persistQuickEvidence() }
                        .buttonStyle(.bordered)
                    if let importMessage {
                        Text(importMessage).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer()
                    Button(showRawAnalyses ? "Hide advanced JSON" : "Advanced evidence JSON") {
                        withAnimation { showRawAnalyses.toggle() }
                    }
                    .font(.caption)
                }

                if showRawAnalyses {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Editing raw JSON may introduce unqualified inputs. The evidence inventory will classify only what it can resolve from the stored structure.")
                            .font(.caption2).foregroundStyle(AuroraTheme.warn)
                        TextEditor(text: $project.analysesJSON)
                            .font(.caption2.monospaced())
                            .frame(minHeight: 230)
                            .padding(8)
                            .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func quickFieldCard(_ field: InputAssayField) -> some View {
        let requested = quickAuthorities[field.id] ?? InputAuthority.userDeclared.rawValue
        let source = quickSources[field.id] ?? ""
        let effective = InputAuthority.effective(requested: requested, source: source)
        let sourceMissing = requested == InputAuthority.measured.rawValue && source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(field.label).font(.caption.bold())
                Spacer()
                Text(field.unit).font(.caption2).foregroundStyle(.secondary)
            }
            TextField("Not entered", text: valueBinding(field.id))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)

            Picker("Authority", selection: authorityBinding(field.id)) {
                ForEach(InputAuthority.allCases) { authority in
                    Text(authority.label).tag(authority.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            TextField("Source reference / lab record / certificate ID", text: sourceBinding(field.id))
                .font(.caption)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(pretty(effective))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(authorityColor(effective))
                Spacer()
                if sourceMissing {
                    Label("Measured claim needs source", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AuroraTheme.warn)
                }
            }
        }
        .padding(10)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
    }

    private var importedEvidence: some View {
        let summary = InputEvidenceImportSummary.parse(analysesValue)
        return AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Imported Evidence Provenance").font(.headline)
                        Text("Server parsing establishes ingestion provenance, not measurement authority.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: summary.hasImportedRecords ? "Imported records present" : "No imported records")
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 9)], spacing: 9) {
                    inputMetric("Source file", summary.source ?? "Not reported", "doc.fill")
                    inputMetric("Import authority", summary.authority ?? "Not reported", "server.rack")
                    inputMetric("Record count", summary.recordCount.map(String.init) ?? "Not reported", "number.square.fill")
                    inputMetric("Source-tagged quick fields", "\(sourceTaggedQuickCount)", "link")
                }

                if summary.authority == "server_parsed_input" {
                    Text("server_parsed_input means the backend parsed numeric records from the submitted file. The client does not relabel those values as measured unless the data itself supplies a stronger traceable authority basis.")
                        .font(.caption2).foregroundStyle(AuroraTheme.warn)
                }
            }
        }
    }

    private var scientificInventory: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scientific Evidence Inventory").font(.headline)
                        Text("Presence and strongest stored authority class by evidence dimension")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("NO COMPLETENESS SCORE").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 255), spacing: 9)], spacing: 9) {
                    ForEach(InputEvidenceCategory.all) { category in
                        let observation = inventory.observation(for: category.id)
                        evidenceCategoryCard(category, observation: observation)
                    }
                }

                Text("A green category means relevant input fields are present, not that they are sufficient, calibrated, representative, or fit for industrial design. Open the field ledger below for authority details.")
                    .font(.caption2).foregroundStyle(.secondary)

                DisclosureGroup("Input evidence field ledger") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(inventory.fields.prefix(600)) { field in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(field.path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                    Text(field.categories.map(pretty).joined(separator: " · "))
                                        .font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.accent)
                                }
                                Spacer(minLength: 10)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(field.value).font(.caption2.monospaced()).textSelection(.enabled).lineLimit(2)
                                    Text(pretty(field.authority)).font(.system(size: 8, weight: .bold)).foregroundStyle(authorityColor(field.authority))
                                    if let source = field.source, !source.isEmpty {
                                        Text(source).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                            Divider().opacity(0.06)
                        }
                    }
                }
            }
        }
    }

    private func evidenceCategoryCard(_ category: InputEvidenceCategory, observation: InputEvidenceObservation?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill((observation == nil ? Color.secondary : AuroraTheme.good).opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: category.icon).foregroundStyle(observation == nil ? .secondary : AuroraTheme.good)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(category.label).font(.caption.bold())
                if let observation {
                    Text("\(observation.fieldCount) returned input field(s)").font(.caption2).foregroundStyle(.secondary)
                    Text(pretty(observation.strongestAuthority)).font(.system(size: 8, weight: .bold)).foregroundStyle(authorityColor(observation.strongestAuthority))
                } else {
                    Text("No recognized input evidence").font(.caption2).foregroundStyle(.secondary)
                    Text("MISSING DIMENSION").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                }
            }
            Spacer()
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
    }

    private var engineEvidenceMatrix: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Engine-Relevance Evidence Matrix").font(.headline)
                        Text("UI semantic relevance guide · not the runtime required-input contract")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Engine", selection: $selectedEngineID) {
                        ForEach(runtimeEngineIDs, id: \.self) { Text(pretty($0)).tag($0) }
                    }
                    .pickerStyle(.menu).frame(maxWidth: 250)
                }

                if let row = engineRows.first(where: { $0.engineID == selectedEngineID }) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Image(systemName: engineIcon(row.engineID)).foregroundStyle(AuroraTheme.accent)
                            Text(pretty(row.engineID)).font(.title3.bold())
                            Spacer()
                            Text("SEMANTIC RELEVANCE ONLY").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                            ForEach(row.relevantCategoryIDs, id: \.self) { categoryID in
                                if let category = InputEvidenceCategory.byID(categoryID) {
                                    let observation = inventory.observation(for: categoryID)
                                    HStack(spacing: 8) {
                                        Image(systemName: observation == nil ? "minus.circle" : "checkmark.circle.fill")
                                            .foregroundStyle(observation == nil ? .secondary : AuroraTheme.good)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(category.label).font(.caption.bold())
                                            Text(observation == nil ? "Not observed in project evidence" : pretty(observation!.strongestAuthority))
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(9).background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }

                Divider().opacity(0.12)
                Text("All registered engines").font(.subheadline.bold())
                ForEach(engineRows) { row in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: engineIcon(row.engineID)).foregroundStyle(AuroraTheme.accent).frame(width: 24)
                        Text(pretty(row.engineID)).font(.caption.bold()).frame(width: 160, alignment: .leading)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(row.relevantCategoryIDs, id: \.self) { categoryID in
                                    if let category = InputEvidenceCategory.byID(categoryID) {
                                        let present = inventory.observation(for: categoryID) != nil
                                        HStack(spacing: 4) {
                                            Circle().fill(present ? AuroraTheme.good : Color.secondary.opacity(0.6)).frame(width: 6, height: 6)
                                            Text(category.shortLabel).font(.system(size: 8, weight: .bold)).foregroundStyle(present ? .primary : .secondary)
                                        }
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(AuroraTheme.panel2, in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }

                Text("Missing badges identify evidence dimensions not recognized in the current project input. They are not automatic execution blockers and do not imply that every engine mathematically requires every listed dimension.")
                    .font(.caption2).foregroundStyle(AuroraTheme.warn)
            }
        }
    }

    private var processRoute: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Process Route Builder").font(.headline)
                        Text("Authority: user_declared_process_route · design intent, not as-built plant topology")
                            .font(.caption2.monospaced()).foregroundStyle(AuroraTheme.gold)
                    }
                    Spacer()
                    Text("\(route.count) units").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(routeLibrary, id: \.self) { unit in
                            Button {
                                route.append(unit)
                                persistRoute()
                            } label: {
                                Label(unit, systemImage: icon(for: unit)).font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if route.isEmpty {
                    ContentUnavailableView(
                        "No process route defined",
                        systemImage: "arrow.triangle.branch",
                        description: Text("Add unit operations from the library above. No default route is inferred.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(route.enumerated()), id: \.offset) { index, unit in
                            HStack(spacing: 10) {
                                Text("\(index + 1)").font(.caption.bold()).frame(width: 28, height: 28).background(AuroraTheme.accent.opacity(0.14), in: Circle())
                                Image(systemName: icon(for: unit)).foregroundStyle(AuroraTheme.accent)
                                Text(unit).font(.subheadline.bold())
                                Spacer()
                                Button {
                                    route.remove(at: index)
                                    persistRoute()
                                } label: { Image(systemName: "trash").foregroundStyle(AuroraTheme.bad) }
                                .buttonStyle(.plain)
                            }
                            .padding(10).background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }

                HStack {
                    Button("Clear route", role: .destructive) { route.removeAll(); persistRoute() }
                    Spacer()
                    Button(showRawFlowsheet ? "Hide flowsheet JSON" : "Advanced flowsheet JSON") { withAnimation { showRawFlowsheet.toggle() } }
                        .font(.caption)
                }
                if showRawFlowsheet {
                    TextEditor(text: $project.flowsheetJSON)
                        .font(.caption2.monospaced()).frame(minHeight: 170).padding(8)
                        .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var serverPreflight: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Server Preflight Validation").font(.headline)
                        Text("Calls the production /api/validate contract using the exact current project payload. The iOS client does not reinterpret a server rejection as a warning.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        validateProject()
                    } label: {
                        if isValidating { ProgressView(); Text("Validating") }
                        else { Label("VALIDATE INPUT", systemImage: "checkmark.shield") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isValidating)
                }

                if let preflightError {
                    Label(preflightError, systemImage: "xmark.octagon.fill")
                        .font(.caption.monospaced()).foregroundStyle(AuroraTheme.bad)
                }
                if let preflightResult {
                    HStack {
                        StatusBadge(text: ResultTools.status(preflightResult))
                        Spacer()
                        Text("Server response · not client-generated").font(.caption2).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Open preflight response") {
                        Text(preflightResult.prettyString()).font(.caption2.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var engineeringNotes: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Engineering Notes & Constraints").font(.headline)
                    Spacer()
                    Text("UNSTRUCTURED · USER DECLARED").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraTheme.warn)
                }
                TextEditor(text: $project.notes)
                    .frame(minHeight: 110).padding(8)
                    .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 12))
                Text("Notes are preserved as project context but are not credited as measured evidence in the inventory above.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var saveBar: some View {
        Button {
            persistQuickEvidence()
            persistRoute()
            project.updatedAt = .now
            try? context.save()
        } label: {
            Label("SAVE GOVERNED PROJECT BASIS", systemImage: "checkmark.circle.fill")
                .font(.headline).frame(maxWidth: .infinity).padding()
        }
        .buttonStyle(.borderedProminent)
    }

    private var sourceTaggedQuickCount: Int {
        assayFields.filter { field in
            let requested = quickAuthorities[field.id] ?? InputAuthority.userDeclared.rawValue
            let source = quickSources[field.id] ?? ""
            return InputAuthority.effective(requested: requested, source: source) == "measured_source_tagged"
        }.count
    }

    private func valueBinding(_ key: String) -> Binding<String> {
        Binding(get: { quickValues[key] ?? "" }, set: { quickValues[key] = $0 })
    }

    private func authorityBinding(_ key: String) -> Binding<String> {
        Binding(get: { quickAuthorities[key] ?? InputAuthority.userDeclared.rawValue }, set: { quickAuthorities[key] = $0 })
    }

    private func sourceBinding(_ key: String) -> Binding<String> {
        Binding(get: { quickSources[key] ?? "" }, set: { quickSources[key] = $0 })
    }

    private func loadState() {
        let json = analysesValue
        quickValues = parseQuickValues(json)
        let metadata = parseQuickMetadata(json)
        quickAuthorities = metadata.authorities
        quickSources = metadata.sources
        route = parseRoute(project.flowsheetJSON)
        preflightResult = nil
        preflightError = nil
        if !runtimeEngineIDs.contains(selectedEngineID) { selectedEngineID = runtimeEngineIDs.first ?? "ore_intelligence" }
    }

    private func parseQuickValues(_ json: JSONValue) -> [String: String] {
        guard let quick = json.recursiveFind("quick_assays"), case .object(let object) = quick else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in object { if let scalar = value.stringValue { result[key] = scalar } }
        return result
    }

    private func parseQuickMetadata(_ json: JSONValue) -> (authorities: [String: String], sources: [String: String]) {
        guard let value = json.recursiveFind("quick_assay_metadata"), case .object(let metadata) = value else { return ([:], [:]) }
        var authorities: [String: String] = [:]
        var sources: [String: String] = [:]
        for (key, item) in metadata {
            guard case .object(let object) = item else { continue }
            if let requested = object["requested_authority"]?.stringValue { authorities[key] = requested }
            if let source = object["source_reference"]?.stringValue { sources[key] = source }
        }
        return (authorities, sources)
    }

    private func persistQuickEvidence() {
        let existing = analysesValue
        var root: [String: JSONValue]
        if case .object(let object) = existing { root = object } else { root = ["imported_unstructured": existing] }

        var quick: [String: JSONValue] = [:]
        var metadata: [String: JSONValue] = [:]

        for field in assayFields {
            let clean = (quickValues[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let requested = quickAuthorities[field.id] ?? InputAuthority.userDeclared.rawValue
            let source = (quickSources[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let effective = InputAuthority.effective(requested: requested, source: source)

            if !clean.isEmpty {
                if let number = Double(clean.replacingOccurrences(of: ",", with: "")) { quick[field.id] = .number(number) }
                else { quick[field.id] = .string(clean) }
            }

            if !clean.isEmpty || !source.isEmpty || requested != InputAuthority.userDeclared.rawValue {
                metadata[field.id] = .object([
                    "requested_authority": .string(requested),
                    "effective_authority": .string(effective),
                    "source_reference": .string(source),
                    "unit": .string(field.unit),
                    "governance_rule": .string("measured_requires_nonempty_source_reference")
                ])
            }
        }

        root["quick_assays"] = .object(quick)
        root["quick_assays_authority"] = .string("field_level_metadata")
        root["quick_assay_metadata"] = .object(metadata)
        root["input_governance"] = .object([
            "design_basis_authority": .string("user_declared_design_basis"),
            "quick_assay_rule": .string("field_level_authority_with_measured_source_requirement"),
            "server_import_rule": .string("server_parsed_input_not_automatically_measured")
        ])
        project.analysesJSON = JSONValue.object(root).prettyString()
        project.updatedAt = .now
        try? context.save()
    }

    private func parseRoute(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let units = json.recursiveFind("units"), case .array(let items) = units else { return [] }
        return items.compactMap { item in
            if let text = item.stringValue { return text }
            if case .object(let object) = item { return object["name"]?.stringValue ?? object["id"]?.stringValue ?? object["type"]?.stringValue }
            return nil
        }
    }

    private func persistRoute() {
        project.flowsheetJSON = JSONValue.object([
            "units": .array(route.map(JSONValue.string)),
            "authority": .string("user_declared_process_route"),
            "topology_status": .string("design_intent_not_as_built")
        ]).prettyString()
        project.updatedAt = .now
        try? context.save()
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()

            if ["pdf", "xlsx", "xls", "csv"].contains(ext) {
                let filename = url.lastPathComponent
                Task { @MainActor in
                    do {
                        let response = try await AURORAAPI().importOre(data: data, filename: filename)
                        guard case .object(let object) = response,
                              let recordsValue = object["records"], case .array(let records) = recordsValue, !records.isEmpty else {
                            importMessage = "No numeric ore records were returned from \(filename)."
                            return
                        }

                        let existing = analysesValue
                        var root: [String: JSONValue]
                        if case .object(let current) = existing { root = current } else { root = [:] }
                        root["analyses"] = .array(records)
                        root["import_source"] = .string(filename)
                        root["import_authority"] = .string("server_parsed_input")
                        root["import_record_count"] = .number(Double(records.count))
                        root["import_governance_note"] = .string("parsed_numeric_records_not_automatically_promoted_to_measured_evidence")
                        project.analysesJSON = JSONValue.object(root).prettyString()
                        importMessage = "Imported \(records.count) server-parsed numeric record(s) from \(filename)."
                        project.updatedAt = .now
                        try? context.save()
                        loadState()
                    } catch {
                        importMessage = error.localizedDescription
                    }
                }
            } else {
                let text = String(decoding: data, as: UTF8.self)
                if let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) {
                    var root: [String: JSONValue]
                    if case .object(let object) = parsed { root = object } else { root = ["imported_unstructured": parsed] }
                    root["import_source"] = .string(url.lastPathComponent)
                    root["import_authority"] = .string("user_imported_unqualified_input")
                    root["import_governance_note"] = .string("direct_text_or_json_import_not_automatically_measured")
                    project.analysesJSON = JSONValue.object(root).prettyString()
                } else {
                    project.analysesJSON = JSONValue.object([
                        "imported_unstructured_text": .string(text),
                        "import_source": .string(url.lastPathComponent),
                        "import_authority": .string("user_imported_unqualified_input")
                    ]).prettyString()
                }
                importMessage = "Imported \(url.lastPathComponent) as unqualified input content."
                project.updatedAt = .now
                try? context.save()
                loadState()
            }
        } catch {
            importMessage = error.localizedDescription
        }
    }

    private func validateProject() {
        persistQuickEvidence()
        persistRoute()
        isValidating = true
        preflightError = nil
        preflightResult = nil
        let payload = project.payload
        Task { @MainActor in
            do {
                preflightResult = try await AURORAAPI().validate(.object(["payload": payload]))
            } catch {
                preflightError = error.localizedDescription
            }
            isValidating = false
        }
    }

    private func inputMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
            Text(value).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(9).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func authorityColor(_ authority: String) -> Color {
        switch authority {
        case "measured_source_tagged": return AuroraTheme.good
        case "server_parsed_input": return AuroraTheme.accent
        case "source_tagged_unqualified": return AuroraTheme.accent
        case "user_declared": return AuroraTheme.gold
        case "estimated": return AuroraTheme.warn
        case "assumed": return AuroraTheme.warn
        case "measured_claim_source_missing": return AuroraTheme.bad
        default: return .secondary
        }
    }

    private func engineIcon(_ id: String) -> String {
        switch id {
        case "ore_intelligence": return "cube.transparent"
        case "resource_model": return "map"
        case "comminution": return "gearshape.2"
        case "classification": return "line.3.crossed.swirl.circle"
        case "flotation": return "bubbles.and.sparkles"
        case "magnetic_gravity": return "magnet"
        case "hydrometallurgy": return "drop.triangle"
        case "thermodynamics": return "flame"
        case "water_circuit": return "drop"
        case "conservation": return "arrow.triangle.2.circlepath"
        case "equipment_epc": return "wrench.and.screwdriver"
        case "economics": return "chart.line.uptrend.xyaxis"
        case "tailings": return "exclamationmark.triangle"
        case "digital_twin": return "dot.radiowaves.left.and.right"
        case "hybrid_ai": return "brain.head.profile"
        case "diagnostics": return "stethoscope"
        default: return "cpu"
        }
    }

    private func icon(for unit: String) -> String {
        let lower = unit.lowercased()
        if lower.contains("grind") { return "gearshape.2.fill" }
        if lower.contains("crush") { return "diamond.fill" }
        if lower.contains("screen") || lower.contains("class") { return "line.3.horizontal.decrease.circle" }
        if lower.contains("float") { return "bubbles.and.sparkles" }
        if lower.contains("magnetic") { return "magnet" }
        if lower.contains("gravity") { return "arrow.down.to.line" }
        if lower.contains("leach") { return "drop.triangle" }
        if lower.contains("thick") || lower.contains("tank") { return "cylinder.fill" }
        if lower.contains("filter") { return "line.3.horizontal.decrease.circle.fill" }
        if lower.contains("product") || lower.contains("tail") { return "shippingbox.fill" }
        return "square.stack.3d.up.fill"
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct InputAssayField: Identifiable {
    let id: String
    let label: String
    let unit: String
}

private enum InputAuthority: String, CaseIterable, Identifiable {
    case userDeclared = "user_declared"
    case measured = "measured"
    case estimated = "estimated"
    case assumed = "assumed"
    case unknown = "unknown"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .userDeclared: return "User declared"
        case .measured: return "Measured · source required"
        case .estimated: return "Estimated"
        case .assumed: return "Assumed"
        case .unknown: return "Unknown authority"
        }
    }

    static func effective(requested: String, source: String) -> String {
        switch requested {
        case measured.rawValue:
            return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "measured_claim_source_missing" : "measured_source_tagged"
        case estimated.rawValue: return "estimated"
        case assumed.rawValue: return "assumed"
        case unknown.rawValue: return "unqualified_input"
        default: return "user_declared"
        }
    }
}

private struct InputEvidenceImportSummary {
    let source: String?
    let authority: String?
    let recordCount: Int?
    let hasImportedRecords: Bool

    static func parse(_ analyses: JSONValue) -> InputEvidenceImportSummary {
        let source = analyses.recursiveFind("import_source")?.stringValue
        let authority = analyses.recursiveFind("import_authority")?.stringValue
        let count = analyses.recursiveFind("import_record_count")?.doubleValue.map { Int($0) }
        let recordsPresent: Bool
        if let records = analyses.recursiveFind("analyses"), case .array(let values) = records { recordsPresent = !values.isEmpty }
        else { recordsPresent = false }
        return .init(source: source, authority: authority, recordCount: count, hasImportedRecords: recordsPresent)
    }
}

private struct InputEvidenceField: Identifiable {
    let id: String
    let path: String
    let value: String
    let authority: String
    let source: String?
    let categories: [String]
}

private struct InputEvidenceObservation {
    let categoryID: String
    let fieldCount: Int
    let strongestAuthority: String
}

private struct InputEvidenceInventory {
    let fields: [InputEvidenceField]

    var observedCategoryIDs: Set<String> { Set(fields.flatMap(\.categories)) }

    func observation(for categoryID: String) -> InputEvidenceObservation? {
        let matching = fields.filter { $0.categories.contains(categoryID) }
        guard !matching.isEmpty else { return nil }
        let strongest = matching.map(\.authority).max { InputEvidenceInventory.authorityRank($0) < InputEvidenceInventory.authorityRank($1) } ?? "unqualified_input"
        return .init(categoryID: categoryID, fieldCount: matching.count, strongestAuthority: strongest)
    }

    static func build(analyses: JSONValue, route: [String]) -> InputEvidenceInventory {
        let importAuthority = analyses.recursiveFind("import_authority")?.stringValue
        let importSource = analyses.recursiveFind("import_source")?.stringValue
        var metadata: [String: (authority: String, source: String?)] = [:]

        if let metaValue = analyses.recursiveFind("quick_assay_metadata"), case .object(let object) = metaValue {
            for (key, value) in object {
                guard case .object(let meta) = value else { continue }
                let authority = meta["effective_authority"]?.stringValue ?? "user_declared"
                let source = meta["source_reference"]?.stringValue
                metadata[key] = (authority, source)
            }
        }

        var output: [InputEvidenceField] = []
        for (path, value) in analyses.flattenedScalars(limit: 12000) {
            let lower = path.lowercased()
            if lower.contains("quick_assay_metadata") || lower.contains("input_governance") || lower.hasSuffix("import_authority") || lower.hasSuffix("import_source") || lower.hasSuffix("import_record_count") || lower.contains("governance_note") { continue }
            let categories = InputEvidenceCategory.categories(for: path + " " + value)
            guard !categories.isEmpty else { continue }

            var authority = "unqualified_input"
            var source: String?
            if let quickKey = quickFieldKey(path), let meta = metadata[quickKey] {
                authority = meta.authority
                source = meta.source
            } else if lower.contains("analyses") || lower.contains("imported") {
                authority = importAuthority ?? "unqualified_input"
                source = importSource
            } else if lower.contains("measured") || lower.contains("measurement") {
                authority = "source_tagged_unqualified"
            }
            output.append(.init(id: path, path: path, value: value, authority: authority, source: source, categories: categories))
        }

        if !route.isEmpty {
            output.append(.init(
                id: "flowsheet.units",
                path: "flowsheet.units",
                value: route.joined(separator: " → "),
                authority: "user_declared",
                source: nil,
                categories: ["process_route"]
            ))
        }

        return .init(fields: output)
    }

    private static func quickFieldKey(_ path: String) -> String? {
        let marker = "quick_assays."
        guard let range = path.range(of: marker) else { return nil }
        let tail = String(path[range.upperBound...])
        return tail.split(separator: ".").first.map(String.init)?.split(separator: "[").first.map(String.init)
    }

    static func authorityRank(_ authority: String) -> Int {
        switch authority {
        case "measured_source_tagged": return 8
        case "server_parsed_input": return 7
        case "source_tagged_unqualified": return 6
        case "user_declared": return 5
        case "estimated": return 4
        case "measured_claim_source_missing": return 3
        case "assumed": return 2
        default: return 1
        }
    }
}

private struct InputEvidenceCategory: Identifiable {
    let id: String
    let label: String
    let shortLabel: String
    let icon: String
    let keywords: [String]

    static let all: [InputEvidenceCategory] = [
        .init(id: "bulk_chemistry", label: "Bulk Chemistry / Assay", shortLabel: "CHEM", icon: "testtube.2", keywords: ["p2o5", "cao", "mgo", "sio2", "fe2o3", "al2o3", "loi", "xrf", "assay", "element", "oxide"]),
        .init(id: "mineralogy", label: "Mineralogy / Phase ID", shortLabel: "MIN", icon: "cube.transparent", keywords: ["xrd", "mineralogy", "modal_mineralogy", "phase", "apatite", "calcite", "dolomite", "quartz", "clay"]),
        .init(id: "particle_size", label: "Particle Size Distribution", shortLabel: "PSD", icon: "circle.grid.cross", keywords: ["p80", "p50", "p10", "psd", "particle_size", "size_fraction", "d80", "d50", "sieve"]),
        .init(id: "liberation", label: "Liberation / Association", shortLabel: "LIB", icon: "square.grid.3x3.fill", keywords: ["liberation", "mla", "qemscan", "qla", "association", "locking", "grain_size"]),
        .init(id: "comminution_testwork", label: "Comminution Testwork", shortLabel: "COMM", icon: "gearshape.2.fill", keywords: ["bond_work", "bwi", "work_index", "a*b", "drop_weight", "breakage", "abrasivity", "ai_index", "sag"]),
        .init(id: "separation_testwork", label: "Separation Testwork", shortLabel: "SEP", icon: "bubbles.and.sparkles", keywords: ["flotation", "reagent", "collector", "depressant", "frother", "magnetic_suscept", "gravity_test", "washability", "separation_test", "recovery_test"]),
        .init(id: "surface_chemistry", label: "Surface Chemistry", shortLabel: "SURF", icon: "wave.3.right", keywords: ["zeta", "contact_angle", "bet", "surface_area", "surface_charge", "iep", "pzc", "adsorption"]),
        .init(id: "water_solution_chemistry", label: "Water / Solution Chemistry", shortLabel: "WATER", icon: "drop.fill", keywords: [".ph", "_ph", "conductivity", "alkalinity", "ionic", "chloride", "sulfate", "calcium", "magnesium", "sodium", "potassium", "carbonate", "bicarbonate", "orp", "redox", "water_chem"]),
        .init(id: "physical_rheology", label: "Physical / Rheology", shortLabel: "PHYS", icon: "aqi.medium", keywords: ["density", "viscosity", "rheology", "solids_pct", "percent_solids", "porosity", "specific_gravity", "moisture"]),
        .init(id: "sampling_provenance_qa", label: "Sampling / Provenance / QA-QC", shortLabel: "QA", icon: "checkmark.shield.fill", keywords: ["sample_id", "sampling", "campaign", "source_reference", "certificate", "qa", "qc", "timestamp", "laboratory", "method", "replicate", "standard", "blank"]),
        .init(id: "spatial_resource", label: "Spatial / Resource Data", shortLabel: "GEO", icon: "map.fill", keywords: ["coordinate", "easting", "northing", "elevation", "block_model", "drillhole", "collar", "geostat", "variogram", "resource", "orebody", "domain_code"]),
        .init(id: "plant_telemetry", label: "Plant / Historian Telemetry", shortLabel: "LIVE", icon: "dot.radiowaves.left.and.right", keywords: ["historian", "telemetry", "opc", "scada", "plc", "dcs", "sensor", "tag_id", "timestamp_series", "timeseries", "plant_data"]),
        .init(id: "economics_environment", label: "Economics / Environment", shortLabel: "ECO", icon: "leaf.fill", keywords: ["cost", "capex", "opex", "price", "revenue", "carbon", "co2", "tailings", "acid_generation", "neutralization", "radioactivity", "environment"]),
        .init(id: "process_route", label: "Declared Process Route", shortLabel: "ROUTE", icon: "arrow.triangle.branch", keywords: ["flowsheet", "process_route"])
    ]

    static func byID(_ id: String) -> InputEvidenceCategory? { all.first { $0.id == id } }

    static func categories(for text: String) -> [String] {
        let lower = text.lowercased()
        return all.filter { category in category.id != "process_route" && category.keywords.contains { lower.contains($0.lowercased()) } }.map(\.id)
    }
}

private struct InputEngineEvidenceRow: Identifiable {
    let engineID: String
    let relevantCategoryIDs: [String]
    var id: String { engineID }
}

private enum InputEvidenceSemanticMap {
    static let engineFallback = [
        "ore_intelligence", "resource_model", "comminution", "classification", "flotation",
        "magnetic_gravity", "hydrometallurgy", "thermodynamics", "water_circuit", "conservation",
        "equipment_epc", "economics", "tailings", "digital_twin", "hybrid_ai", "diagnostics"
    ]

    static func relevantCategories(for engine: String) -> [String] {
        switch engine {
        case "ore_intelligence": return ["bulk_chemistry", "mineralogy", "particle_size", "liberation", "sampling_provenance_qa"]
        case "resource_model": return ["spatial_resource", "sampling_provenance_qa", "bulk_chemistry", "mineralogy"]
        case "comminution": return ["particle_size", "comminution_testwork", "physical_rheology", "mineralogy"]
        case "classification": return ["particle_size", "physical_rheology", "water_solution_chemistry"]
        case "flotation": return ["bulk_chemistry", "mineralogy", "particle_size", "liberation", "surface_chemistry", "water_solution_chemistry", "separation_testwork"]
        case "magnetic_gravity": return ["mineralogy", "particle_size", "liberation", "physical_rheology", "separation_testwork"]
        case "hydrometallurgy": return ["bulk_chemistry", "mineralogy", "water_solution_chemistry", "separation_testwork"]
        case "thermodynamics": return ["bulk_chemistry", "water_solution_chemistry", "sampling_provenance_qa"]
        case "water_circuit": return ["water_solution_chemistry", "physical_rheology", "plant_telemetry"]
        case "conservation": return ["physical_rheology", "plant_telemetry", "sampling_provenance_qa", "process_route"]
        case "equipment_epc": return ["process_route", "physical_rheology", "particle_size", "plant_telemetry"]
        case "economics": return ["economics_environment", "process_route", "plant_telemetry"]
        case "tailings": return ["bulk_chemistry", "mineralogy", "water_solution_chemistry", "economics_environment"]
        case "digital_twin": return ["plant_telemetry", "process_route", "sampling_provenance_qa"]
        case "hybrid_ai": return ["sampling_provenance_qa", "plant_telemetry", "bulk_chemistry", "mineralogy"]
        case "diagnostics": return ["sampling_provenance_qa", "process_route", "plant_telemetry"]
        default: return ["sampling_provenance_qa"]
        }
    }
}
