import SwiftUI

struct RuntimeAuthorityGraphView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("aurora.engine.workspace.selected") private var selectedEngineID = "ore_intelligence"

    @State private var capabilities: JSONValue?
    @State private var componentResponse: JSONValue?
    @State private var assetResponse: JSONValue?
    @State private var isLoading = false
    @State private var errorText: String?

    private let api = RuntimeAuthorityGraphAPI()

    private var engines: [AuthorityEngine] {
        guard let capabilities,
              let value = capabilities.recursiveFind("engines"),
              case .array(let rows) = value else { return AuthorityEngine.fallback }
        let parsed = rows.compactMap(AuthorityEngine.init)
        return parsed.isEmpty ? AuthorityEngine.fallback : parsed
    }

    private var selectedEngine: AuthorityEngine {
        engines.first(where: { $0.id == selectedEngineID }) ?? engines.first ?? AuthorityEngine.fallback[0]
    }

    private var components: [AuthorityComponent] {
        guard let componentResponse,
              let value = componentResponse.recursiveFind("components"),
              case .array(let rows) = value else { return [] }
        return rows.compactMap(AuthorityComponent.init)
    }

    private var assets: [AuthorityAsset] {
        guard let assetResponse,
              let value = assetResponse.recursiveFind("assets"),
              case .array(let rows) = value else { return [] }
        return rows.compactMap(AuthorityAsset.init)
    }

    private var dagStageNames: [String] {
        guard let audit = app.runtimeAudit,
              let dagValue = audit.recursiveFind("dag"),
              case .object(let dagObject) = dagValue,
              let declaredValue = dagObject["declared"],
              case .array(let rows) = declaredValue else { return [] }
        return rows.compactMap { row in
            switch row {
            case .string(let value): return value
            case .object(let object):
                return object["id"]?.stringValue
                    ?? object["stage"]?.stringValue
                    ?? object["name"]?.stringValue
                    ?? object["key"]?.stringValue
            default: return nil
            }
        }
    }

    private var enginePayloadReturned: Bool {
        guard let result = app.activeResult else { return false }
        return result.recursiveFind(selectedEngine.id) != nil
            || result.recursiveFind(selectedEngine.id.replacingOccurrences(of: "_", with: "")) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                engineSelector
                relationshipLegend
                authorityChain
                evidenceBoundary
                componentColumn
                assetColumn
                dagContext
                if let errorText { errorCard(errorText) }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .task {
            await loadCapabilitiesIfNeeded()
            await loadSelectedEngine()
        }
        .task(id: selectedEngineID) {
            await loadSelectedEngine()
        }
        .refreshable {
            await loadCapabilities(force: true)
            await loadSelectedEngine()
        }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AuroraTheme.gold.opacity(0.14))
                        .frame(width: 72, height: 72)
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(AuroraTheme.gold)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Runtime Authority Graph").font(.largeTitle.bold())
                    Text("DAG context · registered execution authority · internal components · scientific assets")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("This is an authority and evidence map, not an inferred Python call graph. Every relationship is labeled by its actual evidence class.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: isLoading ? "Refreshing" : "Governed map")
                    StatusBadge(text: enginePayloadReturned ? "Active payload returned" : "No active engine payload")
                }
            }
        }
    }

    private var engineSelector: some View {
        AuroraCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Authority Focus").font(.headline)
                    Text("Choose a registered execution engine; component and asset associations are reloaded from the production runtime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Engine", selection: $selectedEngineID) {
                    ForEach(engines) { engine in
                        Text(engine.label).tag(engine.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
            }
        }
    }

    private var relationshipLegend: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Relationship Classes").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 9)], spacing: 9) {
                    legendItem("Registered execution", "Runtime engine contract", "checkmark.seal.fill", AuroraTheme.good)
                    legendItem("Returned payload evidence", "Observed in active result", "arrow.down.doc.fill", AuroraTheme.accent)
                    legendItem("Semantic domain association", "Path/name classification only", "link", AuroraTheme.gold)
                    legendItem("Declared DAG context", "Orchestration declaration only", "point.3.connected.trianglepath.dotted", .secondary)
                }
            }
        }
    }

    private var authorityChain: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Authority Chain · \(selectedEngine.label)").font(.headline)
                    Spacer()
                    Text("NO INFERRED CALL EDGES")
                        .font(.caption2.bold())
                        .foregroundStyle(AuroraTheme.warn)
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        authorityNode(
                            title: "Canonical DAG",
                            subtitle: "\(dagStageNames.count) declared stages",
                            icon: "point.3.connected.trianglepath.dotted",
                            badge: "DECLARED CONTEXT",
                            color: .secondary
                        )
                        relationshipArrow("ORCHESTRATION CONTEXT", .secondary)
                        authorityNode(
                            title: selectedEngine.label,
                            subtitle: selectedEngine.id,
                            icon: selectedEngine.icon,
                            badge: "REGISTERED EXECUTION",
                            color: AuroraTheme.good
                        )
                        relationshipArrow("SEMANTIC ASSOCIATION", AuroraTheme.gold)
                        authorityNode(
                            title: "Python Components",
                            subtitle: "\(components.count) linked components",
                            icon: "shippingbox.fill",
                            badge: "COMPONENTS ONLY",
                            color: AuroraTheme.accent
                        )
                        relationshipArrow("SEMANTIC ASSOCIATION", AuroraTheme.gold)
                        authorityNode(
                            title: "Scientific Assets",
                            subtitle: "\(assets.count) linked resources",
                            icon: "server.rack",
                            badge: "RESOURCE INVENTORY",
                            color: AuroraTheme.gold
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var evidenceBoundary: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: enginePayloadReturned ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(enginePayloadReturned ? AuroraTheme.good : AuroraTheme.warn)
                VStack(alignment: .leading, spacing: 5) {
                    Text(enginePayloadReturned ? "Active-run evidence exists" : "No active-run execution evidence").font(.headline)
                    Text(enginePayloadReturned
                         ? "The active AURORA result contains a payload matching \(selectedEngine.id). This proves a returned engine payload for the active result; it does not prove that every semantically linked component or asset below was used during that run."
                         : "The engine is registered in the execution contract, but the active result does not currently expose a matching engine payload. Component and asset associations below remain inventory relationships only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(app.runStatus).font(.caption.bold())
                    Text(app.activeResultOrigin).font(.caption2).foregroundStyle(.secondary)
                    if let id = app.activeJobID {
                        Text(id).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var componentColumn: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Internal Component Associations").font(.headline)
                        Text("Semantic domain association from the governed component registry; not runtime call proof.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(components.count)").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                }

                if components.isEmpty {
                    Text("No Python components are semantically linked to this engine in the current registry response.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(components.prefix(80)) { component in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: component.icon).foregroundStyle(AuroraTheme.accent).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.name).font(.caption.bold())
                                Text(component.module).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                Text(component.path).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(pretty(component.role)).font(.caption2.bold())
                                Text(component.syntaxState == "parse_ok" ? "AST OK" : pretty(component.syntaxState))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(component.syntaxState == "parse_ok" ? AuroraTheme.good : AuroraTheme.warn)
                                Text("COMPONENT ONLY").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider().opacity(0.08)
                    }
                    if components.count > 80 {
                        Text("Showing 80 of \(components.count) linked components. Use Component Registry for the complete filtered census.")
                            .font(.caption2)
                            .foregroundStyle(AuroraTheme.warn)
                    }
                }
            }
        }
    }

    private var assetColumn: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scientific Asset Associations").font(.headline)
                        Text("Databases, models and reference resources linked by the platform catalog.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(assets.count)").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                }

                if assets.isEmpty {
                    Text("No catalog assets are semantically linked to this engine in the current runtime response.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 9)], spacing: 9) {
                        ForEach(assets.prefix(96)) { asset in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: asset.icon).foregroundStyle(AuroraTheme.gold)
                                    Text(asset.name).font(.caption.bold()).lineLimit(2)
                                    Spacer()
                                    if asset.readable {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AuroraTheme.good)
                                    }
                                }
                                Text(pretty(asset.category)).font(.caption2).foregroundStyle(AuroraTheme.accent)
                                Text(asset.path).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                                Text(asset.validation).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    if assets.count > 96 {
                        Text("Showing 96 of \(assets.count) linked resources. Open Data & Model Catalog for the complete inventory.")
                            .font(.caption2)
                            .foregroundStyle(AuroraTheme.warn)
                    }
                }
            }
        }
    }

    private var dagContext: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Declared DAG Context").font(.headline)
                    Spacer()
                    Text("\(dagStageNames.count) stages").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text("These stages belong to the declared orchestration contract. This view does not assert a direct stage-to-engine call edge unless the runtime exposes such evidence separately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if dagStageNames.isEmpty {
                    Text("No declared DAG stage list is available in the current audit response.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(dagStageNames, id: \.self) { stage in
                                Text(pretty(stage))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(AuroraTheme.panel2, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private func authorityNode(title: String, subtitle: String, icon: String, badge: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).font(.title2.bold()).foregroundStyle(color)
            Text(title).font(.subheadline.bold()).lineLimit(2)
            Text(subtitle).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            Text(badge)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        }
        .padding(12)
        .frame(width: 205, minHeight: 128, alignment: .leading)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 13))
    }

    private func relationshipArrow(_ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.right").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.system(size: 7, weight: .bold)).foregroundStyle(color).multilineTextAlignment(.center).frame(width: 120)
        }
        .frame(width: 130)
    }

    private func legendItem(_ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.bold())
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(9)
        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorCard(_ text: String) -> some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authority graph error").font(.headline)
                    Text(text).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func loadCapabilitiesIfNeeded() async {
        guard capabilities == nil else { return }
        await loadCapabilities(force: false)
    }

    private func loadCapabilities(force: Bool) async {
        do {
            capabilities = try await api.capabilities()
            if !engines.contains(where: { $0.id == selectedEngineID }), let first = engines.first {
                selectedEngineID = first.id
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadSelectedEngine() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            async let componentTask = api.components(domain: selectedEngineID)
            async let assetTask = api.assets(engine: selectedEngineID)
            componentResponse = try await componentTask
            assetResponse = try await assetTask
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private actor RuntimeAuthorityGraphAPI {
    enum GraphError: LocalizedError {
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid AURORA authority graph response"
            case .http(let code, let text): return "AURORA authority graph HTTP \(code): \(text)"
            }
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 240
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    func capabilities() async throws -> JSONValue {
        try await get(path: "api/platform/capabilities", queryItems: [])
    }

    func components(domain: String) async throws -> JSONValue {
        try await get(path: "api/platform/components", queryItems: [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "limit", value: "8000")
        ])
    }

    func assets(engine: String) async throws -> JSONValue {
        try await get(path: "api/platform/databases", queryItems: [
            URLQueryItem(name: "engine", value: engine)
        ])
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> JSONValue {
        var components = URLComponents(url: AppConfig.backend.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw GraphError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GraphError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GraphError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private struct AuthorityEngine: Identifiable {
    let id: String
    let label: String
    let group: String

    init?(_ value: JSONValue) {
        guard case .object(let object) = value,
              let id = object["id"]?.stringValue else { return nil }
        self.id = id
        self.label = object["label"]?.stringValue ?? id
        self.group = object["group"]?.stringValue ?? "Runtime"
    }

    init(id: String, label: String, group: String) {
        self.id = id
        self.label = label
        self.group = group
    }

    var icon: String {
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

    static let fallback: [AuthorityEngine] = [
        .init(id: "ore_intelligence", label: "Ore Intelligence", group: "Geometallurgy"),
        .init(id: "resource_model", label: "Resource & Mining", group: "Mining"),
        .init(id: "comminution", label: "Comminution", group: "Process physics"),
        .init(id: "classification", label: "Classification", group: "Process physics"),
        .init(id: "flotation", label: "Flotation", group: "Separation"),
        .init(id: "magnetic_gravity", label: "Magnetic & Gravity", group: "Separation"),
        .init(id: "hydrometallurgy", label: "Hydrometallurgy", group: "Chemistry"),
        .init(id: "thermodynamics", label: "Thermodynamics", group: "Chemistry"),
        .init(id: "water_circuit", label: "Water & Recycle", group: "Utilities"),
        .init(id: "conservation", label: "Conservation & Reconciliation", group: "Assurance"),
        .init(id: "equipment_epc", label: "Equipment & EPC", group: "Engineering"),
        .init(id: "economics", label: "Economics", group: "Decision"),
        .init(id: "tailings", label: "Tailings & ESG", group: "Closure"),
        .init(id: "digital_twin", label: "Digital Twin", group: "Intelligence"),
        .init(id: "hybrid_ai", label: "Hybrid AI & Uncertainty", group: "Intelligence"),
        .init(id: "diagnostics", label: "Governance & Diagnostics", group: "Assurance")
    ]
}

private struct AuthorityComponent: Identifiable {
    let id: String
    let name: String
    let module: String
    let path: String
    let role: String
    let syntaxState: String

    init?(_ value: JSONValue) {
        guard case .object(let object) = value else { return nil }
        self.id = object["component_id"]?.stringValue ?? UUID().uuidString
        self.name = object["name"]?.stringValue ?? "unknown.py"
        self.module = object["module"]?.stringValue ?? name
        self.path = object["relative_path"]?.stringValue ?? name
        self.role = object["role"]?.stringValue ?? "internal_component"
        self.syntaxState = object["syntax_state"]?.stringValue ?? "unknown"
    }

    var icon: String {
        switch role {
        case "canonical_server_component": return "bolt.horizontal.circle.fill"
        case "server_component": return "server.rack"
        case "test_component": return "checkmark.diamond.fill"
        case "compatibility_component": return "arrow.triangle.2.circlepath"
        default: return "shippingbox.fill"
        }
    }
}

private struct AuthorityAsset: Identifiable {
    let id: String
    let name: String
    let path: String
    let category: String
    let validation: String
    let readable: Bool

    init?(_ value: JSONValue) {
        guard case .object(let object) = value else { return nil }
        self.id = object["asset_id"]?.stringValue ?? UUID().uuidString
        self.name = object["name"]?.stringValue ?? "resource"
        self.path = object["relative_path"]?.stringValue ?? name
        self.category = object["category"]?.stringValue ?? "data_resource"
        self.validation = object["validation"]?.stringValue ?? "not_tested"
        self.readable = object["readable"]?.boolValue ?? false
    }

    var icon: String {
        switch category {
        case "model": return "brain.head.profile"
        case "database": return "cylinder.split.1x2.fill"
        case "thermodynamic_reference": return "flame.fill"
        case "process_reference": return "gearshape.2.fill"
        case "engineering_reference": return "wrench.and.screwdriver.fill"
        case "validation_reference": return "checkmark.shield.fill"
        case "economic_reference": return "chart.line.uptrend.xyaxis"
        case "configuration_registry": return "list.bullet.rectangle.fill"
        default: return "doc.text.fill"
        }
    }
}
