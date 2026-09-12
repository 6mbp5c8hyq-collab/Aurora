import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct InputWorkflowView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedProjectID: UUID?

    private var selectedProject: AuroraProject? {
        if let selectedProjectID, let selected = projects.first(where: { $0.id == selectedProjectID }) { return selected }
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
                ProjectIntakeEditor(project: selectedProject)
            } else {
                ContentUnavailableView(
                    "No project selected",
                    systemImage: "folder.badge.plus",
                    description: Text("Create a project to define the ore evidence, design basis and process route.")
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

private struct ProjectIntakeEditor: View {
    @Bindable var project: AuroraProject
    @Environment(\.modelContext) private var context
    @State private var importer = false
    @State private var importMessage: String?
    @State private var quickAssays: [String: String] = [:]
    @State private var route: [String] = []
    @State private var showRawAnalyses = false
    @State private var showRawFlowsheet = false

    private let assayFields: [(String, String, String)] = [
        ("P2O5", "P₂O₅", "%"),
        ("CaO", "CaO", "%"),
        ("MgO", "MgO", "%"),
        ("SiO2", "SiO₂", "%"),
        ("Fe2O3", "Fe₂O₃", "%"),
        ("Al2O3", "Al₂O₃", "%"),
        ("LOI", "LOI", "%"),
        ("P80_um", "P80", "µm"),
        ("solids_pct", "Solids", "%"),
        ("pH", "pH", "")
    ]

    private let routeLibrary = [
        "ROM Feed", "Crushing", "Screening", "Scrubbing", "Desliming", "Grinding",
        "Classification", "Flotation", "Magnetic Separation", "Gravity Separation",
        "Leaching", "Thickening", "Filtration", "Drying", "Product", "Tailings"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                designBasis
                oreEvidence
                processRoute
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
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Project name", text: $project.name)
                    .font(.largeTitle.bold())
                Text("Ore evidence → process route → governed AURORA execution")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(text: "Design basis")
        }
    }

    private var designBasis: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Project & Design Basis").font(.headline)
                    Spacer()
                    Image(systemName: "scope").foregroundStyle(AuroraTheme.accent)
                }
                LabeledContent("Ore / deposit family") {
                    TextField("phosphate", text: $project.declaredFamily)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Plant feed") {
                    HStack(spacing: 5) {
                        TextField("100", value: $project.feedTPH, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("t/h").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Target component") {
                    TextField("P2O5", text: $project.targetComponent)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Target grade") {
                    HStack(spacing: 5) {
                        TextField("35", value: $project.targetGrade, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var oreEvidence: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ore Evidence & Quick Assays").font(.headline)
                        Text("Quick fields are stored as quick_assays and do not overwrite imported laboratory records.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { importer = true } label: {
                        Label("Import Lab File", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    ForEach(assayFields, id: \.0) { field in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(field.1).font(.caption.bold())
                                Spacer()
                                Text(field.2).font(.caption2).foregroundStyle(.secondary)
                            }
                            TextField("Not entered", text: assayBinding(field.0))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(10)
                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                HStack {
                    Button("Apply quick assays") { persistQuickAssays() }
                        .buttonStyle(.bordered)
                    if let importMessage {
                        Text(importMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(showRawAnalyses ? "Hide advanced JSON" : "Advanced JSON") {
                        withAnimation { showRawAnalyses.toggle() }
                    }
                    .font(.caption)
                }

                if showRawAnalyses {
                    TextEditor(text: $project.analysesJSON)
                        .font(.caption2.monospaced())
                        .frame(minHeight: 190)
                        .padding(8)
                        .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var processRoute: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Process Route Builder").font(.headline)
                        Text("Tap operations to add them in sequence; reorder by removing and rebuilding the route.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                                Label(unit, systemImage: icon(for: unit))
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if route.isEmpty {
                    ContentUnavailableView(
                        "No process route defined",
                        systemImage: "arrow.triangle.branch",
                        description: Text("Add unit operations from the library above.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(route.enumerated()), id: \.offset) { index, unit in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .frame(width: 28, height: 28)
                                    .background(AuroraTheme.accent.opacity(0.14), in: Circle())
                                Image(systemName: icon(for: unit)).foregroundStyle(AuroraTheme.accent)
                                Text(unit).font(.subheadline.bold())
                                Spacer()
                                Button {
                                    route.remove(at: index)
                                    persistRoute()
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(AuroraTheme.bad)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }

                HStack {
                    Button("Clear route", role: .destructive) {
                        route.removeAll()
                        persistRoute()
                    }
                    Spacer()
                    Button(showRawFlowsheet ? "Hide flowsheet JSON" : "Advanced flowsheet JSON") {
                        withAnimation { showRawFlowsheet.toggle() }
                    }
                    .font(.caption)
                }

                if showRawFlowsheet {
                    TextEditor(text: $project.flowsheetJSON)
                        .font(.caption2.monospaced())
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var engineeringNotes: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Engineering Notes & Constraints").font(.headline)
                TextEditor(text: $project.notes)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var saveBar: some View {
        Button {
            persistQuickAssays()
            persistRoute()
            project.updatedAt = .now
            try? context.save()
        } label: {
            Label("SAVE PROJECT BASIS", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
    }

    private func assayBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { quickAssays[key] ?? "" },
            set: { quickAssays[key] = $0 }
        )
    }

    private func loadState() {
        quickAssays = parseQuickAssays(project.analysesJSON)
        route = parseRoute(project.flowsheetJSON)
    }

    private func parseQuickAssays(_ raw: String) -> [String: String] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let quick = json.recursiveFind("quick_assays"),
              case .object(let object) = quick else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in object { if let scalar = value.stringValue { result[key] = scalar } }
        return result
    }

    private func persistQuickAssays() {
        let existing = (try? JSONDecoder().decode(JSONValue.self, from: Data(project.analysesJSON.utf8))) ?? .object([:])
        var root: [String: JSONValue]
        if case .object(let object) = existing { root = object } else { root = ["imported": existing] }

        var quick: [String: JSONValue] = [:]
        for (key, text) in quickAssays {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            if let number = Double(clean.replacingOccurrences(of: ",", with: "")) { quick[key] = .number(number) }
            else { quick[key] = .string(clean) }
        }
        root["quick_assays"] = .object(quick)
        root["quick_assays_authority"] = .string("user_declared")
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
            if case .object(let object) = item {
                return object["name"]?.stringValue ?? object["id"]?.stringValue ?? object["type"]?.stringValue
            }
            return nil
        }
    }

    private func persistRoute() {
        let unitValues = route.map { JSONValue.string($0) }
        project.flowsheetJSON = JSONValue.object([
            "units": .array(unitValues),
            "authority": .string("user_declared_process_route")
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

                        let existing = (try? JSONDecoder().decode(JSONValue.self, from: Data(project.analysesJSON.utf8))) ?? .object([:])
                        var root: [String: JSONValue]
                        if case .object(let current) = existing { root = current } else { root = [:] }
                        root["analyses"] = .array(records)
                        root["import_source"] = .string(filename)
                        root["import_authority"] = .string("server_parsed_input")
                        project.analysesJSON = JSONValue.object(root).prettyString()
                        importMessage = "Imported \(records.count) numeric record(s) from \(filename)."
                        project.updatedAt = .now
                        try? context.save()
                        loadState()
                    } catch {
                        importMessage = error.localizedDescription
                    }
                }
            } else {
                project.analysesJSON = String(decoding: data, as: UTF8.self)
                importMessage = "Imported \(url.lastPathComponent)."
                project.updatedAt = .now
                try? context.save()
                loadState()
            }
        } catch {
            importMessage = error.localizedDescription
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
}
