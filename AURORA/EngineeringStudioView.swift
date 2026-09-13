import SwiftUI
import SwiftData

struct EngineeringStudioView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var selectedProjectID: UUID?
    @State private var tab: DrawingTab = .pfd
    @State private var zoom: CGFloat = 1.0
    @State private var selectedNodeID: String?

    private var project: AuroraProject? {
        if let selectedProjectID, let selected = projects.first(where: { $0.id == selectedProjectID }) { return selected }
        return projects.first
    }

    private var runtimeTopology: RuntimeTopology {
        RuntimeTopology.parse(result: app.activeResult, projectFlowsheet: project?.flowsheetJSON)
    }

    private var nodes: [DrawingNode] { runtimeTopology.nodes }
    private var streams: [EngineeringStream] { RuntimeTopology.streams(from: app.activeResult) }
    private var selectedNode: DrawingNode? { nodes.first { $0.id == selectedNodeID } }
    private var engineeringArtifacts: [EngineeringArtifactReference] {
        EngineeringArtifactReference.scan(app.activeResult)
    }

    enum DrawingTab: String, CaseIterable, Identifiable {
        case pfd = "PFD"
        case flowsheet = "Flowsheet"
        case pid = "P&ID"
        case layout = "2D Layout"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pfd: return "arrow.triangle.branch"
            case .flowsheet: return "rectangle.connected.to.line.below"
            case .pid: return "slider.horizontal.3"
            case .layout: return "square.grid.3x3"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                toolbar
                drawingSurface
                if let selectedNode { detailCard(selectedNode) }
                runtimeArtifactCenter
                engineeringAuthority
                legend
            }
            .padding(22)
        }
        .background(AuroraTheme.background)
    }

    private var hero: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [AuroraTheme.accent.opacity(0.85), AuroraTheme.gold.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                    Image(systemName: "drafting compass")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AuroraTheme.background)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Engineering Studio").font(.largeTitle.bold())
                    Text("Runtime-linked PFD · flowsheet · P&ID schematic · 2D layout")
                        .font(.subheadline)
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Topology is taken from the active AURORA result when available. Project flowsheetJSON is used only as a declared design-basis fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: runtimeTopology.isRuntime ? "Runtime topology" : "Project basis")
                    Text("\(nodes.count) units · \(streams.count) streams")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("\(engineeringArtifacts.count) returned artifact refs")
                        .font(.caption2.monospaced())
                        .foregroundStyle(engineeringArtifacts.isEmpty ? .secondary : AuroraTheme.gold)
                }
            }
        }
    }

    private var toolbar: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    ForEach(DrawingTab.allCases) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { tab = item }
                        } label: {
                            Label(item.rawValue, systemImage: item.icon)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .foregroundStyle(tab == item ? AuroraTheme.background : .primary)
                                .background(tab == item ? AuroraTheme.accent : AuroraTheme.panel2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text("ZOOM").font(.caption2.bold()).foregroundStyle(.secondary)
                    Slider(value: $zoom, in: 0.7...1.5).frame(width: 110)
                }

                HStack(spacing: 12) {
                    if projects.isEmpty {
                        Label("No project", systemImage: "folder.badge.questionmark")
                    } else {
                        Picker(
                            "Project",
                            selection: Binding<UUID?>(
                                get: { selectedProjectID ?? projects.first?.id },
                                set: { selectedProjectID = $0; selectedNodeID = nil }
                            )
                        ) {
                            ForEach(projects) { item in Text(item.name).tag(Optional(item.id)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    }
                    Spacer()
                    Text(runtimeTopology.sourceLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(runtimeTopology.isRuntime ? AuroraTheme.good : AuroraTheme.gold)
                }
            }
        }
    }

    private var drawingSurface: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(surfaceTitle).font(.headline)
                    Spacer()
                    Text("SELECT EQUIPMENT TO INSPECT")
                        .font(.caption2.bold())
                        .foregroundStyle(AuroraTheme.gold)
                }

                if nodes.isEmpty {
                    ContentUnavailableView(
                        "No topology available",
                        systemImage: "rectangle.dashed",
                        description: Text("Run AURORA or define an ordered units array in the project flowsheet.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            DrawingConnections(nodes: nodes, streams: streams, zoom: zoom, layout: tab == .layout, pid: tab == .pid)
                            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                                DrawingNodeCard(node: node, selected: selectedNodeID == node.id, compact: tab == .layout) {
                                    withAnimation(.easeInOut(duration: 0.18)) { selectedNodeID = node.id }
                                }
                                .position(
                                    x: node.x(index: index, zoom: zoom),
                                    y: tab == .layout ? node.layoutY(index: index) : 155
                                )
                            }
                        }
                        .frame(width: max(CGFloat(nodes.count) * 205 * zoom, 760), height: tab == .layout ? 470 : 320)
                        .padding(.horizontal, 18)
                    }
                    Text(surfaceCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detailCard(_ node: DrawingNode) -> some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: node.icon)
                        .font(.title2)
                        .foregroundStyle(AuroraTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(node.title).font(.title3.bold())
                        Text(node.kind.uppercased()).font(.caption2.bold()).tracking(1.1).foregroundStyle(AuroraTheme.gold)
                        Text(node.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: node.runtimeDerived ? "Runtime" : "Declared")
                    Button { selectedNodeID = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if !node.fields.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                        ForEach(Array(node.fields.prefix(24).enumerated()), id: \.offset) { _, field in
                            HStack(alignment: .top, spacing: 8) {
                                Text(field.0).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text(field.1).font(.caption2.monospaced()).multilineTextAlignment(.trailing).lineLimit(3)
                            }
                            .padding(8)
                            .background(AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
    }

    private var runtimeArtifactCenter: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Runtime Engineering Artifact References").font(.headline)
                        Text("References are discovered only from scalar values returned by the active AURORA result and carrying recognized engineering file extensions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: engineeringArtifacts.isEmpty ? "None returned" : "\(engineeringArtifacts.count) returned")
                }

                if engineeringArtifacts.isEmpty {
                    ContentUnavailableView(
                        "No engineering artifact reference returned",
                        systemImage: "doc.badge.ellipsis",
                        description: Text("The native schematic remains available above, but it is not promoted to an authoritative backend drawing.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    ForEach(engineeringArtifacts.prefix(80)) { artifact in
                        HStack(alignment: .top, spacing: 11) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9).fill(AuroraTheme.gold.opacity(0.11)).frame(width: 40, height: 40)
                                Image(systemName: artifact.icon).foregroundStyle(AuroraTheme.gold)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(artifact.format).font(.caption2.bold()).foregroundStyle(AuroraTheme.gold)
                                Text(artifact.label).font(.caption.bold()).lineLimit(2)
                                Text(artifact.raw).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(4)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                if let url = artifact.directURL {
                                    Link(destination: url) {
                                        Label("Open", systemImage: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.bordered)
                                    ShareLink(item: url) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    StatusBadge(text: "Reference only")
                                }
                            }
                        }
                        .padding(.vertical, 5)
                        Divider().opacity(0.08)
                    }
                    if engineeringArtifacts.count > 80 {
                        Text("Showing 80 of \(engineeringArtifacts.count) returned engineering references.")
                            .font(.caption2)
                            .foregroundStyle(AuroraTheme.warn)
                    }
                }

                Text("A returned path or URL proves only that the active result contains that reference. It does not by itself validate drawing contents, revision status, EPC approval, or whether the referenced file was generated in the current run.")
                    .font(.caption2)
                    .foregroundStyle(AuroraTheme.warn)
            }
        }
    }

    private var engineeringAuthority: some View {
        AuroraCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: runtimeTopology.isRuntime ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(runtimeTopology.isRuntime ? AuroraTheme.good : AuroraTheme.warn)
                VStack(alignment: .leading, spacing: 4) {
                    Text(runtimeTopology.isRuntime ? "Runtime engineering topology active" : "Declared-route schematic only")
                        .font(.subheadline.bold())
                    Text(runtimeTopology.isRuntime
                         ? "Equipment and topology shown above were discovered in the active runtime result. Final EPC coordinates, pipe classes and instrument tags remain authoritative only when explicitly returned."
                         : "The current drawing is generated from project route declarations. It must not be treated as a final PFD/P&ID/layout until the runtime returns governed engineering geometry and stream data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            Label("Material path", systemImage: "arrow.right").foregroundStyle(AuroraTheme.accent)
            Label("Stream value", systemImage: "tag.fill").foregroundStyle(AuroraTheme.gold)
            Label("Runtime-derived", systemImage: "checkmark.seal").foregroundStyle(AuroraTheme.good)
            Label("Returned artifact ref", systemImage: "doc.badge.arrow.up").foregroundStyle(AuroraTheme.gold)
        }
        .font(.caption)
        .padding(.horizontal, 6)
    }

    private var surfaceTitle: String {
        switch tab {
        case .pfd: return "Process Flow Diagram"
        case .flowsheet: return "Canonical process topology"
        case .pid: return "P&ID schematic overlay"
        case .layout: return "2D equipment arrangement"
        }
    }

    private var surfaceCaption: String {
        switch tab {
        case .pfd: return "PFD mode: ordered process equipment with available runtime stream labels."
        case .flowsheet: return "Flowsheet mode: unit-operation graph from runtime topology when available."
        case .pid: return "P&ID mode: schematic process/instrument overlay only. Instrumentation is not invented when tags are absent."
        case .layout: return "2D mode: schematic arrangement unless the runtime explicitly supplies governed equipment coordinates."
        }
    }
}

private struct EngineeringArtifactReference: Identifiable {
    let id = UUID()
    let label: String
    let raw: String
    let format: String
    let directURL: URL?

    var icon: String {
        switch format.lowercased() {
        case "svg", "png": return "photo.on.rectangle.angled"
        case "dxf", "dwg": return "ruler.fill"
        case "ifc", "step", "stp", "iges", "igs": return "cube.transparent.fill"
        case "pdf": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }

    static func scan(_ result: JSONValue?) -> [EngineeringArtifactReference] {
        guard let result else { return [] }
        let formats = ["pdf", "svg", "dxf", "dwg", "png", "ifc", "step", "stp", "iges", "igs"]
        let engineeringTerms = ["pfd", "pid", "p&id", "drawing", "layout", "engineering", "flowsheet", "equipment", "plot_plan", "plotplan", "cad", "diagram"]
        var output: [EngineeringArtifactReference] = []

        for (path, raw) in result.flattenedScalars(limit: 8000) {
            let joined = (path + " " + raw).lowercased()
            guard engineeringTerms.contains(where: { joined.contains($0) }) else { continue }
            guard let ext = formats.first(where: { joined.contains("." + $0) }) else { continue }

            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let url: URL?
            if let candidate = URL(string: trimmed), let scheme = candidate.scheme?.lowercased(), scheme == "https" || scheme == "http" {
                url = candidate
            } else {
                url = nil
            }

            output.append(.init(label: path, raw: raw, format: ext.uppercased(), directURL: url))
        }

        var seen = Set<String>()
        return output.filter { seen.insert($0.raw + "|" + $0.label).inserted }
    }
}

private struct RuntimeTopology {
    let nodes: [DrawingNode]
    let isRuntime: Bool
    let sourceLabel: String

    static func parse(result: JSONValue?, projectFlowsheet: String?) -> RuntimeTopology {
        if let result {
            let candidates = ["unit_operations", "equipment", "process_units", "unit_nodes", "nodes"]
            for key in candidates {
                if let value = result.recursiveFind(key) {
                    let parsed = DrawingNode.fromRuntime(value)
                    if !parsed.isEmpty {
                        return RuntimeTopology(nodes: parsed, isRuntime: true, sourceLabel: "Source: active runtime · \(key)")
                    }
                }
            }
        }
        return RuntimeTopology(nodes: DrawingNode.fromProject(projectFlowsheet), isRuntime: false, sourceLabel: "Source: project flowsheetJSON fallback")
    }

    static func streams(from result: JSONValue?) -> [EngineeringStream] {
        guard let result else { return [] }
        for key in ["streams", "process_streams", "stream_table", "material_streams", "stream_ledger"] {
            guard let value = result.recursiveFind(key) else { continue }
            let parsed = EngineeringStream.parse(value)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }
}

private struct DrawingNode: Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let subtitle: String
    let icon: String
    let runtimeDerived: Bool
    let fields: [(String, String)]

    static func == (lhs: DrawingNode, rhs: DrawingNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func x(index: Int, zoom: CGFloat) -> CGFloat { CGFloat(index) * 205 * zoom + 110 }
    func layoutY(index: Int) -> CGFloat { 145 + CGFloat(index % 3) * 115 }

    static func fromRuntime(_ value: JSONValue) -> [DrawingNode] {
        switch value {
        case .array(let items):
            return items.enumerated().compactMap { parseRuntimeItem($0.element, index: $0.offset, hint: nil) }
        case .object(let object):
            if object.values.allSatisfy({ if case .object = $0 { return true }; return false }) {
                return object.keys.sorted().enumerated().compactMap { index, key in
                    guard let item = object[key] else { return nil }
                    return parseRuntimeItem(item, index: index, hint: key)
                }
            }
            if let single = parseRuntimeItem(value, index: 0, hint: nil) { return [single] }
            return []
        default: return []
        }
    }

    static func fromProject(_ raw: String?) -> [DrawingNode] {
        guard let raw, let data = raw.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let value = json.recursiveFind("units"), case .array(let items) = value, !items.isEmpty else { return [] }

        return items.enumerated().compactMap { index, item in
            switch item {
            case .string(let text): return make(title: text, kind: "Unit operation", index: index, runtime: false, fields: [])
            case .object(let object):
                let title = scalar(object, ["name", "id", "tag", "type"]) ?? "Unit \(index + 1)"
                let kind = scalar(object, ["type", "category", "kind"]) ?? "Unit operation"
                return make(title: title, kind: kind, index: index, runtime: false, fields: flatten(object))
            default: return nil
            }
        }
    }

    private static func parseRuntimeItem(_ item: JSONValue, index: Int, hint: String?) -> DrawingNode? {
        guard case .object(let object) = item else {
            if let text = item.stringValue { return make(title: text, kind: "Unit operation", index: index, runtime: true, fields: []) }
            return nil
        }
        let title = hint ?? scalar(object, ["name", "id", "tag", "unit_id", "label", "type"]) ?? "Unit \(index + 1)"
        let kind = scalar(object, ["type", "category", "kind", "unit_type", "model"]) ?? "Unit operation"
        return make(title: title, kind: kind, index: index, runtime: true, fields: flatten(object))
    }

    private static func make(title: String, kind: String, index: Int, runtime: Bool, fields: [(String, String)]) -> DrawingNode {
        let lower = (title + " " + kind).lowercased()
        let icon: String
        if lower.contains("grind") || lower.contains("mill") { icon = "gearshape.2.fill" }
        else if lower.contains("float") { icon = "bubbles.and.sparkles" }
        else if lower.contains("class") || lower.contains("cycl") { icon = "line.3.crossed.swirl.circle" }
        else if lower.contains("crush") { icon = "diamond.fill" }
        else if lower.contains("pump") { icon = "arrow.up.circle.fill" }
        else if lower.contains("tank") || lower.contains("thick") { icon = "cylinder.fill" }
        else if lower.contains("filter") { icon = "line.3.horizontal.decrease.circle.fill" }
        else if lower.contains("product") || lower.contains("tail") { icon = "shippingbox.fill" }
        else { icon = "square.stack.3d.up.fill" }
        return DrawingNode(
            id: "\(runtime ? "runtime" : "project")-\(index)-\(title)",
            title: title,
            kind: kind,
            subtitle: runtime ? "Runtime process node \(index + 1)" : "Declared process node \(index + 1)",
            icon: icon,
            runtimeDerived: runtime,
            fields: fields
        )
    }

    private static func scalar(_ object: [String: JSONValue], _ keys: [String]) -> String? {
        for key in keys { if let value = object[key]?.stringValue, !value.isEmpty { return value } }
        return nil
    }

    private static func flatten(_ object: [String: JSONValue]) -> [(String, String)] {
        var output: [(String, String)] = []
        for key in object.keys.sorted() {
            guard let value = object[key] else { continue }
            if let scalar = value.stringValue { output.append((key, scalar)) }
            else if case .object(let nested) = value {
                for nestedKey in nested.keys.sorted().prefix(8) {
                    if let scalar = nested[nestedKey]?.stringValue { output.append(("\(key).\(nestedKey)", scalar)) }
                }
            }
            if output.count >= 28 { break }
        }
        return output
    }
}

private struct EngineeringStream: Identifiable {
    let id: String
    let name: String
    let label: String

    static func parse(_ value: JSONValue) -> [EngineeringStream] {
        switch value {
        case .array(let items): return items.enumerated().compactMap { parseItem($0.element, index: $0.offset, hint: nil) }
        case .object(let object):
            if object.values.allSatisfy({ if case .object = $0 { return true }; return false }) {
                return object.keys.sorted().enumerated().compactMap { index, key in
                    guard let item = object[key] else { return nil }
                    return parseItem(item, index: index, hint: key)
                }
            }
            if let one = parseItem(value, index: 0, hint: nil) { return [one] }
            return []
        default: return []
        }
    }

    private static func parseItem(_ value: JSONValue, index: Int, hint: String?) -> EngineeringStream? {
        guard case .object(let object) = value else { return nil }
        let name = hint ?? first(object, ["name", "stream_name", "id", "tag", "label"]) ?? "S\(index + 1)"
        let mass = first(object, ["mass_flow_tph", "mass_tph", "flow_tph", "solids_tph"])
        let volume = first(object, ["volumetric_flow_m3_h", "volume_flow_m3_h", "flow_m3_h"])
        let solids = first(object, ["solids_pct", "percent_solids", "solids_percent"])
        var parts: [String] = []
        if let mass { parts.append("\(mass) t/h") }
        if let volume { parts.append("\(volume) m³/h") }
        if let solids { parts.append("\(solids)% solids") }
        return EngineeringStream(id: "\(index)-\(name)", name: name, label: parts.isEmpty ? name : "\(name) · " + parts.joined(separator: " · "))
    }

    private static func first(_ object: [String: JSONValue], _ keys: [String]) -> String? {
        for key in keys { if let value = object[key]?.stringValue, !value.isEmpty { return value } }
        return nil
    }
}

private struct DrawingConnections: View {
    let nodes: [DrawingNode]
    let streams: [EngineeringStream]
    let zoom: CGFloat
    let layout: Bool
    let pid: Bool

    var body: some View {
        Canvas { context, _ in
            for index in 0..<max(nodes.count - 1, 0) {
                let start = CGPoint(x: CGFloat(index) * 205 * zoom + 165, y: layout ? nodes[index].layoutY(index: index) : 155)
                let end = CGPoint(x: CGFloat(index + 1) * 205 * zoom + 55, y: layout ? nodes[index + 1].layoutY(index: index + 1) : 155)
                var path = Path()
                path.move(to: start)
                if layout {
                    let midpoint = (start.x + end.x) / 2
                    path.addCurve(to: end, control1: CGPoint(x: midpoint, y: start.y), control2: CGPoint(x: midpoint, y: end.y))
                } else {
                    path.addLine(to: end)
                }
                context.stroke(path, with: .color(AuroraTheme.accent.opacity(0.72)), style: StrokeStyle(lineWidth: pid ? 2 : 3, lineCap: .round, dash: pid ? [8, 4] : []))

                let arrow = Path { p in
                    p.move(to: CGPoint(x: end.x - 9, y: end.y - 6))
                    p.addLine(to: end)
                    p.addLine(to: CGPoint(x: end.x - 9, y: end.y + 6))
                }
                context.stroke(arrow, with: .color(AuroraTheme.gold), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                if index < streams.count {
                    let text = Text(streams[index].label).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(AuroraTheme.gold)
                    context.draw(text, at: CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 18), anchor: .center)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct DrawingNodeCard: View {
    let node: DrawingNode
    let selected: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: node.icon)
                        .font(.title2.bold())
                        .foregroundStyle(selected ? AuroraTheme.gold : AuroraTheme.accent)
                    if node.runtimeDerived {
                        Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(AuroraTheme.good)
                    }
                }
                Text(node.title).font(.caption.bold()).lineLimit(2).multilineTextAlignment(.center)
                Text(node.kind).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: compact ? 140 : 150, height: compact ? 104 : 114)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(selected ? AuroraTheme.gold.opacity(0.16) : AuroraTheme.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(selected ? AuroraTheme.gold : Color.white.opacity(0.10), lineWidth: selected ? 2 : 1))
            )
        }
        .buttonStyle(.plain)
    }
}
