import SwiftUI

struct PlatformCatalogView: View {
    @State private var capabilities: JSONValue?
    @State private var catalog: JSONValue?
    @State private var selectedEngine = "all"
    @State private var selectedCategory = "all"
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorText: String?

    private let api = PlatformCatalogAPI()

    private var engines: [(id: String, label: String)] {
        guard let capabilities,
              let value = capabilities.recursiveFind("engines"),
              case .array(let rows) = value else { return [] }
        return rows.compactMap { row in
            guard case .object(let object) = row,
                  let id = object["id"]?.stringValue else { return nil }
            return (id, object["label"]?.stringValue ?? id)
        }
    }

    private var categories: [String] {
        guard let catalog,
              let value = catalog.recursiveFind("categories"),
              case .object(let object) = value else { return [] }
        return object.keys.sorted()
    }

    private var assets: [CatalogAsset] {
        guard let catalog,
              let value = catalog.recursiveFind("assets"),
              case .array(let rows) = value else { return [] }
        return rows.compactMap(CatalogAsset.init)
            .filter { asset in
                query.isEmpty
                || asset.name.localizedCaseInsensitiveContains(query)
                || asset.path.localizedCaseInsensitiveContains(query)
                || asset.category.localizedCaseInsensitiveContains(query)
                || asset.format.localizedCaseInsensitiveContains(query)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                summary
                filters
                governanceCard
                assetGrid
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
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AuroraTheme.accent.opacity(0.15))
                        .frame(width: 68, height: 68)
                    Image(systemName: "server.rack")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(AuroraTheme.accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Scientific Data & Model Catalog").font(.largeTitle.bold())
                    Text("Runtime databases · models · reference assets · validation resources")
                        .foregroundStyle(AuroraTheme.accent)
                    Text("This view inventories packaged/readable resources reported by the AURORA production runtime and preserves the backend governance distinction between resource availability and proof of use in a specific run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: isLoading ? "Scanning" : catalog == nil ? "Unavailable" : "Runtime indexed")
            }
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            metric("Engines", scalar(capabilities, "engine_count"), "cpu")
            metric("Assets", scalar(capabilities, "asset_count"), "externaldrive.fill")
            metric("Readable", scalar(capabilities, "readable_asset_count"), "checkmark.seal.fill")
            metric("Direct files", scalar(capabilities, "direct_asset_count"), "doc.fill")
            metric("Archive assets", scalar(capabilities, "archive_asset_count"), "archivebox.fill")
            metric("Scanned archives", scalar(capabilities, "archives_scanned"), "shippingbox.fill")
        }
    }

    private var filters: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Catalog Filters").font(.headline)
                    Spacer()
                    Text("\(assets.count) visible resources").font(.caption.monospaced()).foregroundStyle(AuroraTheme.gold)
                }
                HStack(spacing: 10) {
                    Picker("Engine", selection: $selectedEngine) {
                        Text("All engines").tag("all")
                        ForEach(engines, id: \.id) { engine in
                            Text(engine.label).tag(engine.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Category", selection: $selectedCategory) {
                        Text("All categories").tag("all")
                        ForEach(categories, id: \.self) { category in
                            Text(pretty(category)).tag(category)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search resource name, path, format or category", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(9)
                    .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
                }
                .onChange(of: selectedEngine) { _, _ in Task { await loadAssets() } }
                .onChange(of: selectedCategory) { _, _ in Task { await loadAssets() } }
            }
        }
    }

    private var governanceCard: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(AuroraTheme.gold)
                    Text("Resource Governance").font(.headline)
                }
                if let catalog,
                   let governance = catalog.recursiveFind("governance") {
                    ForEach(Array(governance.flattenedScalars(limit: 20).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.0).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(row.1).font(.caption2).multilineTextAlignment(.trailing)
                        }
                    }
                } else {
                    Text("No governance ledger returned.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var assetGrid: some View {
        if isLoading && catalog == nil {
            AuroraCard {
                HStack { ProgressView(); Text("Scanning AURORA runtime resources…") }
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        } else if assets.isEmpty {
            AuroraCard {
                ContentUnavailableView(
                    "No matching runtime resources",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text("Change the engine/category filters or search expression.")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 12)], spacing: 12) {
                ForEach(assets.prefix(1200)) { asset in
                    assetCard(asset)
                }
            }
            if assets.count > 1200 {
                Text("Showing the first 1,200 matching assets on-device. Narrow the filters for more precise inspection.")
                    .font(.caption)
                    .foregroundStyle(AuroraTheme.warn)
            }
        }
    }

    private func assetCard(_ asset: CatalogAsset) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    Image(systemName: asset.icon).foregroundStyle(AuroraTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name).font(.subheadline.bold()).lineLimit(2)
                        Text(asset.format.uppercased()).font(.caption2.bold()).foregroundStyle(AuroraTheme.gold)
                    }
                    Spacer()
                    StatusBadge(text: asset.readable ? "Readable" : "Unverified")
                }
                Text(pretty(asset.category)).font(.caption.bold())
                Text(asset.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                HStack {
                    Text(asset.storage).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(byteLabel(asset.bytes)).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                if !asset.engineLinks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(asset.engineLinks, id: \.self) { engine in
                                Text(engine.replacingOccurrences(of: "_", with: " ").uppercased())
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(AuroraTheme.panel2, in: Capsule())
                            }
                        }
                    }
                }
                Text(asset.validation)
                    .font(.caption2.monospaced())
                    .foregroundStyle(asset.readable ? AuroraTheme.good : AuroraTheme.warn)
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

    private func errorCard(_ text: String) -> some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AuroraTheme.bad)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Catalog error").font(.headline)
                    Text(text).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scalar(_ source: JSONValue?, _ key: String) -> String {
        source?.recursiveFind(key)?.stringValue ?? "—"
    }

    private func pretty(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func byteLabel(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
    }

    private func refresh() async {
        isLoading = true
        errorText = nil
        do {
            capabilities = try await api.capabilities()
            await loadAssets()
        } catch {
            errorText = error.localizedDescription
            isLoading = false
        }
    }

    private func loadAssets() async {
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await api.databases(
                engine: selectedEngine == "all" ? nil : selectedEngine,
                category: selectedCategory == "all" ? nil : selectedCategory
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private actor PlatformCatalogAPI {
    enum CatalogError: LocalizedError {
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid AURORA platform catalog response"
            case .http(let code, let text): return "AURORA catalog HTTP \(code): \(text)"
            }
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    func capabilities() async throws -> JSONValue {
        try await get("/api/platform/capabilities")
    }

    func databases(engine: String?, category: String?) async throws -> JSONValue {
        var components = URLComponents(url: AppConfig.backend.appendingPathComponent("api/platform/databases"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let engine { items.append(.init(name: "engine", value: engine)) }
        if let category { items.append(.init(name: "category", value: category)) }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw CatalogError.invalidResponse }
        return try await request(url)
    }

    private func get(_ path: String) async throws -> JSONValue {
        guard let url = URL(string: path, relativeTo: AppConfig.backend)?.absoluteURL else {
            throw CatalogError.invalidResponse
        }
        return try await request(url)
    }

    private func request(_ url: URL) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw CatalogError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private struct CatalogAsset: Identifiable {
    let id: String
    let name: String
    let path: String
    let format: String
    let category: String
    let storage: String
    let bytes: Double
    let readable: Bool
    let validation: String
    let engineLinks: [String]

    init?(_ value: JSONValue) {
        guard case .object(let object) = value else { return nil }
        let path = object["relative_path"]?.stringValue ?? object["name"]?.stringValue ?? "unknown"
        self.id = object["asset_id"]?.stringValue ?? path
        self.name = object["name"]?.stringValue ?? path
        self.path = path
        self.format = object["format"]?.stringValue ?? "unknown"
        self.category = object["category"]?.stringValue ?? "data_resource"
        self.storage = object["storage"]?.stringValue ?? "unknown"
        self.bytes = object["bytes"]?.doubleValue ?? 0
        self.readable = object["readable"]?.boolValue ?? false
        self.validation = object["validation"]?.stringValue ?? "not_tested"
        if let links = object["engine_links"], case .array(let items) = links {
            self.engineLinks = items.compactMap { $0.stringValue }
        } else {
            self.engineLinks = []
        }
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
