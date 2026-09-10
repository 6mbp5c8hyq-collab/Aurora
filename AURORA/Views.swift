import SwiftUI
import SwiftData
import Charts
import QuickLook
import UniformTypeIdentifiers

struct DashboardView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @Query(sort: \RunRecord.updatedAt, order: .reverse) private var runs: [RunRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Industrial Command Center")
                            .font(.largeTitle.bold())
                        Text("Native iOS control surface for the canonical AURORA runtime")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    connectionBadge
                }

                HStack(spacing: 12) {
                    metric("Projects", "\(projects.count)", "folder.fill")
                    metric("Runs", "\(runs.count)", "bolt.fill")
                    metric("Runtime", "Python 3.12", "cpu")
                    metric("Storage", "Native", "internaldrive")
                }

                if let result = app.activeResult {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Latest AURORA Result").font(.headline)
                                Spacer()
                                StatusBadge(text: ResultTools.status(result))
                            }
                            if let ceiling = ResultTools.ceiling(result) {
                                Text("Claim ceiling: \(ceiling)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            let kpis = ResultTools.kpis(result)
                            if !kpis.isEmpty {
                                Chart(kpis) { item in
                                    BarMark(
                                        x: .value("KPI", item.name),
                                        y: .value("Value", item.value)
                                    )
                                }
                                .frame(height: 220)
                            }
                        }
                    }
                } else {
                    AuroraCard {
                        ContentUnavailableView(
                            "No active run",
                            systemImage: "waveform.path.ecg",
                            description: Text("Create a project and run AURORA.")
                        )
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Runs").font(.headline)
                        ForEach(runs.prefix(6)) { run in
                            HStack {
                                StatusBadge(text: run.status)
                                Text(run.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let id = run.jobID {
                                    Text(id.prefix(10) + "…").font(.caption.monospaced())
                                }
                            }
                            Divider().opacity(0.15)
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch app.connection {
        case .unknown: StatusBadge(text: "Unknown")
        case .checking: StatusBadge(text: "Checking")
        case .online: StatusBadge(text: "Runtime Online")
        case .offline: StatusBadge(text: "Runtime Offline")
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    var body: some View {
        NavigationStack {
            List {
                ForEach(projects) { project in
                    NavigationLink {
                        ProjectWorkspace(project: project)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name).font(.headline)
                            Text("\(project.declaredFamily.capitalized) · \(project.feedTPH.formatted()) t/h · \(project.targetComponent) \(project.targetGrade.formatted())%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet { context.delete(projects[index]) }
                    try? context.save()
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                Button {
                    context.insert(AuroraProject())
                    try? context.save()
                } label: {
                    Label("New Project", systemImage: "plus")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraTheme.background)
        }
    }
}

struct ProjectWorkspace: View {
    @Bindable var project: AuroraProject
    @Environment(\.modelContext) private var context
    @State private var importer = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Project name", text: $project.name)
                    .font(.largeTitle.bold())

                AuroraCard {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Project Basis").font(.headline)
                        LabeledContent("Ore family") {
                            TextField("phosphate", text: $project.declaredFamily)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Feed (t/h)") {
                            TextField("100", value: $project.feedTPH, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Target component") {
                            TextField("P2O5", text: $project.targetComponent)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Target grade (%)") {
                            TextField("35", value: $project.targetGrade, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ore & Analyses").font(.headline)
                            Spacer()
                            Button("Import PDF / Excel / CSV / JSON") { importer = true }
                        }
                        TextEditor(text: $project.analysesJSON)
                            .font(.caption.monospaced())
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        if let message {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Process Route").font(.headline)
                            Spacer()
                            Text("flowsheetJSON").font(.caption2.monospaced()).foregroundStyle(AuroraTheme.gold)
                        }
                        Text("Enter the ordered unit operations that become the native PFD and the canonical request.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $project.flowsheetJSON)
                            .font(.caption.monospaced())
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(AuroraTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        Text(#"{ "units": ["Crushing", "Grinding", "Flotation"] }"#)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Engineering Notes").font(.headline)
                        TextEditor(text: $project.notes).frame(minHeight: 100)
                    }
                }

                Button {
                    project.updatedAt = .now
                    try? context.save()
                } label: {
                    Label("Save Project", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(22)
        }
        .fileImporter(
            isPresented: $importer,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText, .pdf, .spreadsheet]
        ) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let extensionName = url.pathExtension.lowercased()
                if ["pdf", "xlsx", "xls", "csv"].contains(extensionName) {
                    let filename = url.lastPathComponent
                    Task { @MainActor in
                        do {
                            let response = try await AURORAAPI().importOre(data: data, filename: filename)
                            guard case .object(let object) = response else {
                                message = "The server returned an invalid import response."
                                return
                            }
                            guard let recordsValue = object["records"],
                                  case .array(let records) = recordsValue,
                                  !records.isEmpty else {
                                if let warningValue = object["warnings"],
                                   case .array(let warnings) = warningValue {
                                    message = warnings.compactMap { $0.stringValue }.joined(separator: " ")
                                } else {
                                    message = "No numeric ore records were found."
                                }
                                return
                            }
                            project.analysesJSON = JSONValue.object(["analyses": .array(records)]).prettyString()
                            var warningText = ""
                            if let warningValue = object["warnings"],
                               case .array(let warnings) = warningValue {
                                warningText = warnings.compactMap { $0.stringValue }.joined(separator: " ")
                            }
                            message = "Imported \(records.count) record(s) from \(filename). Review authority before running."
                            if !warningText.isEmpty {
                                message += " " + warningText
                            }
                            project.updatedAt = .now
                            try? context.save()
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                } else {
                    project.analysesJSON = try String(contentsOf: url, encoding: .utf8)
                    message = "Imported \(url.lastPathComponent)"
                    project.updatedAt = .now
                    try? context.save()
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct ExecutionView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var chosen: UUID?

    private var project: AuroraProject? {
        if let chosen { return projects.first { $0.id == chosen } }
        return projects.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Canonical Execution").font(.largeTitle.bold())
                Text("Governance blocks are displayed as governed results, not hidden.")
                    .foregroundStyle(.secondary)

                AuroraCard {
                    HStack {
                        Picker(
                            "Project",
                            selection: Binding<UUID?>(
                                get: { chosen ?? projects.first?.id },
                                set: { chosen = $0 }
                            )
                        ) {
                            ForEach(projects) { item in
                                Text(item.name).tag(Optional(item.id))
                            }
                        }
                        Spacer()
                        if let project {
                            Button {
                                app.run(project: project, context: context)
                            } label: {
                                if app.isRunning {
                                    ProgressView()
                                    Text("Running AURORA")
                                } else {
                                    Label("RUN FULL AURORA", systemImage: "bolt.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(app.isRunning)
                        }
                    }
                }

                if let error = app.lastError {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 8) {
                            StatusBadge(text: "Execution error")
                            Text(error).font(.caption.monospaced())
                        }
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Execution State").font(.headline)
                            Spacer()
                            StatusBadge(text: app.runStatus)
                        }
                        if let id = app.activeJobID {
                            Text("Job \(id)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        let stages = ResultTools.stages(app.activeResult)
                        if stages.isEmpty {
                            Text("Engine trace will appear exactly as AURORA reports it.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(stages) { stage in
                                HStack(alignment: .top) {
                                    Image(systemName: "circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(AuroraTheme.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(stage.name).bold()
                                        Text(stage.status).font(.caption).foregroundStyle(.secondary)
                                        if let detail = stage.detail {
                                            Text(detail).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                Divider().opacity(0.15)
                            }
                        }
                    }
                }

                if let result = app.activeResult {
                    ResultsPanel(result: result)
                }
            }
            .padding(22)
        }
    }
}

struct ResultsPanel: View {
    let result: JSONValue

    var body: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Process Results").font(.headline)
                    Spacer()
                    StatusBadge(text: ResultTools.status(result))
                }

                let kpis = ResultTools.kpis(result)
                if !kpis.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(kpis) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.caption).foregroundStyle(.secondary)
                                Text("\(item.value.formatted(.number.precision(.fractionLength(0...3)))) \(item.unit)")
                                    .font(.title3.bold())
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                DisclosureGroup("Detailed result table") {
                    ForEach(Array(result.flattenedScalars(limit: 250).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top) {
                            Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            Spacer()
                            Text(row.1).font(.caption2.monospaced())
                        }
                        .padding(.vertical, 3)
                    }
                }

                DisclosureGroup("Diagnostics JSON") {
                    Text(result.prettyString())
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct EngineeringView: View {
    @EnvironmentObject private var app: AppModel
    @State private var previewURL: URL?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Engineering Workspace").font(.largeTitle.bold())
                Text("Native QuickLook/PDFKit preview for AURORA engineering files. No browser view is used.")
                    .foregroundStyle(.secondary)

                let artifacts = ResultTools.artifacts(app.activeResult)
                if artifacts.isEmpty {
                    AuroraCard {
                        ContentUnavailableView(
                            "No engineering artifacts in active result",
                            systemImage: "wrench.and.screwdriver",
                            description: Text("When AURORA returns downloadable PFD/P&ID/2D/DXF/PDF/PNG links they appear here.")
                        )
                    }
                } else {
                    ForEach(artifacts) { artifact in
                        AuroraCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artifact.format).font(.caption.bold()).foregroundStyle(AuroraTheme.gold)
                                    Text(artifact.label).font(.subheadline.bold())
                                    Text(artifact.raw).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Button("Open") { Task { await open(artifact) } }
                            }
                        }
                    }
                }

                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(22)
        }
        .sheet(
            isPresented: Binding(
                get: { previewURL != nil },
                set: { if !$0 { previewURL = nil } }
            )
        ) {
            if let previewURL { QuickLookView(url: previewURL) }
        }
    }

    private func open(_ artifact: ArtifactLink) async {
        guard let url = URL(string: artifact.raw), url.scheme?.hasPrefix("http") == true else {
            await MainActor.run {
                message = "Server-local artifact path: AURORA must expose it as an HTTPS download URL."
            }
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let name = url.lastPathComponent.isEmpty ? "AURORA.\(artifact.format.lowercased())" : url.lastPathComponent
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: target, options: .atomic)
            await MainActor.run { previewURL = target }
        } catch {
            await MainActor.run { message = error.localizedDescription }
        }
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct DeliverablesView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var pdfURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Deliverables").font(.largeTitle.bold())
                Text("PDF and CSV summaries are generated natively. Canonical XLSX/DOCX/SVG/DXF/PNG/ZIP are surfaced when returned by AURORA.")
                    .foregroundStyle(.secondary)

                if let project = projects.first {
                    AuroraCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Native Exports").font(.headline)
                            Button("Generate PDF Summary") {
                                pdfURL = NativeReport.makePDF(project: project, result: app.activeResult)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Generate CSV Result Table") {
                                csvURL = NativeReport.makeCSV(result: app.activeResult)
                            }
                            .buttonStyle(.bordered)

                            if let pdfURL {
                                ShareLink(item: pdfURL) {
                                    Label("Share PDF", systemImage: "square.and.arrow.up")
                                }
                            }
                            if let csvURL {
                                ShareLink(item: csvURL) {
                                    Label("Share CSV", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Canonical Export Catalog").font(.headline)
                        let artifacts = ResultTools.artifacts(app.activeResult)
                        if artifacts.isEmpty {
                            Text("No server export links in active result.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(artifacts) { artifact in
                                HStack {
                                    Text(artifact.format).font(.caption.bold()).foregroundStyle(AuroraTheme.gold)
                                    Text(artifact.label).font(.caption)
                                    Spacer()
                                    if let url = URL(string: artifact.raw), url.scheme?.hasPrefix("http") == true {
                                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var backend = AppConfig.backend.absoluteString
    @State private var message: String?

    var body: some View {
        Form {
            Section("Canonical Runtime") {
                TextField("Backend URL", text: $backend)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Save Runtime Endpoint") {
                    do {
                        try AppConfig.saveBackend(backend)
                        message = "Saved"
                        app.checkHealth()
                    } catch {
                        message = "Invalid HTTPS URL"
                    }
                }
                Button("Test /api/health") { app.checkHealth() }

                switch app.connection {
                case .unknown: StatusBadge(text: "Unknown")
                case .checking: ProgressView("Checking")
                case .online(let status): StatusBadge(text: "Online · \(status)")
                case .offline(let error): Text(error).foregroundStyle(AuroraTheme.bad)
                }
            }

            Section("Application") {
                LabeledContent("Interface", value: "SwiftUI Native")
                LabeledContent("Project store", value: "SwiftData")
                LabeledContent("Browser / WebView", value: "Not used")
                LabeledContent("Execution API", value: "/api/validate + /api/jobs")
                LabeledContent("Version", value: "1.0.0")
            }

            if let message { Text(message) }
        }
        .scrollContentBackground(.hidden)
        .background(AuroraTheme.background)
    }
}
