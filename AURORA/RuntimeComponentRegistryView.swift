import SwiftUI

struct RuntimeComponentRegistryView: View {
    @State private var registry: JSONValue?
    @State private var query = ""
    @State private var selectedDomain = "all"
    @State private var selectedRole = "all"
    @State private var directOnly = false
    @State private var isLoading = false
    @State private var errorText: String?

    private let api = RuntimeComponentRegistryAPI()

    private var executionEngines: [RuntimeExecutionEngine] {
        guard let registry,
              let value = registry.recursiveFind("execution_engines"),
              case .array(let rows) = value else { return [] }
        return rows.compactMap(RuntimeExecutionEngine.init)
    }

    private var roles: [String] {
        guard let registry,
              let value = registry.recursiveFind("role_counts"),
              case .object(let object) = value else { return [] }
        return object.keys.sorted()
    }

    private var components: [RuntimeComponent] {
        guard let registry,
              let value = registry.recursiveFind("components"),
              case .array(let rows) = value else { return [] }
        return rows.compactMap(RuntimeComponent.init)
    }

    private var visibleComponents: [RuntimeComponent] {
        components.filter { item in
            let domainMatch = selectedDomain == "all" || item.domainLinks.contains(selectedDomain)
            let roleMatch = selectedRole == "all" || item.role == selectedRole
            let storageMatch = !directOnly || item.storage == "direct_runtime_file"
            let textMatch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.module.localizedCaseInsensitiveContains(query)
                || item.path.localizedCaseInsensitiveContains(query)
            return domainMatch && roleMatch && storageMatch && textMatch
        }
    }

    private var collisions: [RuntimeBasenameCollision] {
        guard let registry,
              let value = registry.recursiveFind("basename_collisions"),
              case .array(let rows) = value else { return [] }
        return rows.compactMap(RuntimeBasenameCollision.init)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                summary
                authorityBoundary
                engineContract
                filters
                componentInventory
                collisionLedger
                if let errorText { errorCard(errorText) }
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(AuroraTheme.accent.opacity(0.14))
                        .frame(width: 70, height: 70)
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Runtime Component Registry").font(.largeTitle.bold())
                    Text("Execution authority · Python components · domain associations · syntax census")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("The registry separates the governed execution-engine contract from Python files packaged inside the runtime. A module name never becomes execution authority by filename semantics alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: isLoading ? "Scanning" : registry == nil ? "Unavailable" : "Runtime indexed")
            }
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            metric("Execution engines", scalar("execution_engine_count"), "cpu.fill")
            metric("Python components", scalar("component_count"), "shippingbox.fill")
            metric("Direct runtime", scalar("direct_component_count"), "internaldrive.fill")
            metric("Archive source", scalar("archive_component_count"), "archivebox.fill")
            metric("Readable", scalar("readable_component_count"), "checkmark.seal.fill")
            metric("AST parse OK", scalar("parse_ok_count"), "checkmark.shield.fill")
            metric("Basename collisions", scalar("basename_collision_count"), "square.stack.3d.up.fill")
        }
    }

    private var authorityBoundary: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(AuroraTheme.gold)
                    Text("Authority Boundary").font(.headline)
                }
                governanceRow("engine_authority", fallback: "Only registered execution engines are execution authorities.")
                governanceRow("component_claim", fallback: "Python files remain internal/server components unless independently registered as an execution engine.")
                governanceRow("domain_association", fallback: "Domain links are semantic associations, not proof of execution in a specific run.")
                governanceRow("syntax_validation", fallback: "AST parse success is not scientific validation or runtime execution proof.")
                governanceRow("duplicate_policy", fallback: "Filename collisions are not asserted logical duplicates.")
            }
        }
    }

    private var engineContract: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Registered Execution Engine Contract").font(.headline)
                        Text("Only these entries carry registered execution authority in this registry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(executionEngines.count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(AuroraTheme.gold)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 9)], spacing: 9) {
                    ForEach(executionEngines) { engine in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: engine.icon).foregroundStyle(AuroraTheme.accent)
                                Text(engine.label).font(.caption.bold()).lineLimit(1)
                                Spacer()
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(AuroraTheme.good)
                            }
                            Text(engine.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                            Text(engine.group).font(.caption2).foregroundStyle(AuroraTheme.gold)
                            Text(engine.executeVia).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }
        }
    }

    private var filters: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Component Filters").font(.headline)
                    Spacer()
                    Text("\(visibleComponents.count) visible")
                        .font(.caption.monospaced())
                        .foregroundStyle(AuroraTheme.gold)
                }
                HStack(spacing: 10) {
                    Picker("Domain", selection: $selectedDomain) {
                        Text("All domains").tag("all")
                        ForEach(executionEngines) { engine in
                            Text(engine.label).tag(engine.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Role", selection: $selectedRole) {
                        Text("All roles").tag("all")
                        ForEach(roles, id: \.self) { role in
                            Text(pretty(role)).tag(role)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Direct only", isOn: $directOnly)
                        .toggleStyle(.switch)
                        .fixedSize()

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search module, file or runtime path", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(9)
                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private var componentInventory: some View {
        if isLoading && registry == nil {
            AuroraCard {
                HStack { ProgressView(); Text("Scanning runtime Python components…") }
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        } else if visibleComponents.isEmpty {
            AuroraCard {
                ContentUnavailableView(
                    "No matching runtime components",
                    systemImage: "shippingbox",
                    description: Text("Change the domain, role, storage or search filters.")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        } else {
            AuroraCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Python Runtime Components").font(.headline)
                        Spacer()
                        Text("FILES ≠ EXECUTION ENGINES")
                            .font(.caption2.bold())
                            .foregroundStyle(AuroraTheme.warn)
                    }
                    ForEach(visibleComponents.prefix(1200)) { component in
                        componentRow(component)
                        Divider().opacity(0.08)
                    }
                    if visibleComponents.count > 1200 {
                        Text("Showing the first 1,200 matching components on-device. Narrow the filters for deeper inspection.")
                            .font(.caption2)
                            .foregroundStyle(AuroraTheme.warn)
                    }
                }
            }
        }
    }

    private func componentRow(_ component: RuntimeComponent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: component.roleIcon)
                    .foregroundStyle(component.role == "canonical_server_component" ? AuroraTheme.gold : AuroraTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(component.name).font(.subheadline.bold()).textSelection(.enabled)
                    Text(component.module).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                StatusBadge(text: pretty(component.role))
                StatusBadge(text: component.syntaxState == "parse_ok" ? "AST OK" : pretty(component.syntaxState))
            }

            Text(component.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 14) {
                Label(pretty(component.storage), systemImage: "internaldrive")
                Label(byteLabel(component.bytes), systemImage: "doc")
                if let sha = component.sha1, !sha.isEmpty {
                    Text(String(sha.prefix(12))).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Text(component.executionAuthority ? "EXECUTION AUTHORITY" : "COMPONENT ONLY")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(component.executionAuthority ? AuroraTheme.good : .secondary)
            }
            .font(.caption2)

            if !component.domainLinks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(component.domainLinks, id: \.self) { domain in
                            Text(pretty(domain).uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(AuroraTheme.panel2, in: Capsule())
                        }
                    }
                }
            }

            if let syntaxError = component.syntaxError, !syntaxError.isEmpty {
                Text(syntaxError)
                    .font(.caption2.monospaced())
                    .foregroundStyle(AuroraTheme.bad)
            }
        }
        .padding(.vertical, 4)
    }

    private var collisionLedger: some View {
        AuroraCard {
            DisclosureGroup("Basename collision ledger · \(collisions.count) groups") {
                Text("These are filename collisions only. AURORA does not infer that same-name files are logical duplicates or duplicate execution authorities.")
                    .font(.caption)
                    .foregroundStyle(AuroraTheme.warn)
                    .padding(.vertical, 8)
                ForEach(collisions.prefix(100)) { collision in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(collision.name).font(.caption.bold())
                            Spacer()
                            Text("\(collision.count) paths").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        ForEach(collision.paths, id: \.self) { path in
                            Text(path).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 5)
                    Divider().opacity(0.08)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).foregroundStyle(AuroraTheme.accent)
                Text(value).font(.title3.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        }
    }

    private func governanceRow(_ key: String, fallback: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(pretty(key)).font(.caption2.bold()).foregroundStyle(AuroraTheme.gold).frame(width: 130, alignment: .leading)
            Text(registry?.recursiveFind(key)?.stringValue ?? fallback)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func scalar(_ key: String) -> String {
        registry?.recursiveFind(key)?.stringValue ?? "—"
    }

    private func pretty(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func byteLabel(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }

    private func errorCard(_ text: String) -> some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Component registry error").font(.headline)
                    Text(text).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refresh() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            registry = try await api.components()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private actor RuntimeComponentRegistryAPI {
    enum RegistryError: LocalizedError {
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid AURORA component registry response"
            case .http(let code, let text): return "AURORA component registry HTTP \(code): \(text)"
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

    func components() async throws -> JSONValue {
        var components = URLComponents(url: AppConfig.backend.appendingPathComponent("api/platform/components"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "8000")]
        guard let url = components.url else { throw RegistryError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RegistryError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw RegistryError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private struct RuntimeExecutionEngine: Identifiable {
    let id: String
    let label: String
    let group: String
    let executeVia: String

    init?(_ value: JSONValue) {
        guard case .object(let object) = value,
              let id = object["id"]?.stringValue else { return nil }
        self.id = id
        self.label = object["label"]?.stringValue ?? id
        self.group = object["group"]?.stringValue ?? "Runtime"
        self.executeVia = object["execute_via"]?.stringValue ?? "POST /api/jobs"
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
}

private struct RuntimeComponent: Identifiable {
    let id: String
    let name: String
    let module: String
    let path: String
    let storage: String
    let role: String
    let executionAuthority: Bool
    let bytes: Double
    let readable: Bool
    let syntaxState: String
    let syntaxError: String?
    let sha1: String?
    let domainLinks: [String]

    init?(_ value: JSONValue) {
        guard case .object(let object) = value else { return nil }
        self.id = object["component_id"]?.stringValue ?? UUID().uuidString
        self.name = object["name"]?.stringValue ?? "unknown.py"
        self.module = object["module"]?.stringValue ?? name
        self.path = object["relative_path"]?.stringValue ?? name
        self.storage = object["storage"]?.stringValue ?? "unknown"
        self.role = object["role"]?.stringValue ?? "internal_component"
        self.executionAuthority = object["execution_authority"]?.boolValue ?? false
        self.bytes = object["bytes"]?.doubleValue ?? 0
        self.readable = object["readable"]?.boolValue ?? false
        self.syntaxState = object["syntax_state"]?.stringValue ?? "unknown"
        self.syntaxError = object["syntax_error"]?.stringValue
        self.sha1 = object["sha1"]?.stringValue
        if let links = object["domain_links"], case .array(let rows) = links {
            self.domainLinks = rows.compactMap { $0.stringValue }
        } else {
            self.domainLinks = []
        }
    }

    var roleIcon: String {
        switch role {
        case "canonical_server_component": return "bolt.horizontal.circle.fill"
        case "server_component": return "server.rack"
        case "test_component": return "checkmark.diamond.fill"
        case "compatibility_component": return "arrow.triangle.2.circlepath"
        default: return "shippingbox.fill"
        }
    }
}

private struct RuntimeBasenameCollision: Identifiable {
    let id: String
    let name: String
    let count: Int
    let paths: [String]

    init?(_ value: JSONValue) {
        guard case .object(let object) = value else { return nil }
        let name = object["name"]?.stringValue ?? "unknown.py"
        self.name = name
        self.id = name
        self.count = Int(object["count"]?.doubleValue ?? 0)
        if let rows = object["paths"], case .array(let values) = rows {
            self.paths = values.compactMap { $0.stringValue }
        } else {
            self.paths = []
        }
    }
}
