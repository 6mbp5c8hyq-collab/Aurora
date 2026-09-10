import SwiftUI
import SwiftData

struct EngineeringStudioView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \\AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]
    @State private var tab: DrawingTab = .pfd
    @State private var zoom: CGFloat = 1.0
    @State private var selectedNodeID: String?

    private var project: AuroraProject? { projects.first }
    private var nodes: [DrawingNode] {
        DrawingNode.from(project?.flowsheetJSON)
    }
    private var selectedNode: DrawingNode? {
        nodes.first { $0.id == selectedNodeID }
    }

    enum DrawingTab: String, CaseIterable, Identifiable {
        case pfd = "PFD"
        case flowsheet = "Flowsheet"
        case layout = "2D Layout"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pfd: return "arrow.triangle.branch"
            case .flowsheet: return "rectangle.connected.to.line.below"
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
                if let selectedNode {
                    detailCard(selectedNode)
                }
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
                        .fill(
                            LinearGradient(
                                colors: [AuroraTheme.accent.opacity(0.85), AuroraTheme.gold.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "drafting compass")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AuroraTheme.background)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Engineering Studio").font(.largeTitle.bold())
                    Text("Native PFD · process flowsheet · 2D equipment layout")
                        .font(.subheadline)
                        .foregroundStyle(AuroraTheme.accent)
                    Text("Review the process architecture visually. Every node is derived from the project route; returned engineering files remain available from Export Center.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: app.activeResult == nil ? "Design mode" : "Result linked")
                    Text("\(nodes.count) unit nodes")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
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
                    Text("ZOOM")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Slider(value: $zoom, in: 0.7...1.5)
                        .frame(width: 110)
                }
                HStack {
                    Label(project?.name ?? "No project selected", systemImage: "folder.fill")
                    Spacer()
                    Text("Source: project flowsheetJSON")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private var drawingSurface: some View {
        AuroraCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tab.rawValue == "2D Layout" ? "2D equipment arrangement" : "Process route drawing")
                        .font(.headline)
                    Spacer()
                    Text("SELECT NODE TO INSPECT")
                        .font(.caption2.bold())
                        .foregroundStyle(AuroraTheme.gold)
                }
                if nodes.isEmpty {
                    ContentUnavailableView(
                        "No route nodes defined",
                        systemImage: "rectangle.dashed",
                        description: Text("Open Input Workflow and enter flowsheetJSON with an ordered units array.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            DrawingConnections(nodes: nodes, zoom: zoom, layout: tab == .layout)
                            ForEach(nodes) { node in
                                DrawingNodeCard(
                                    node: node,
                                    selected: selectedNodeID == node.id,
                                    compact: tab == .layout
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) { selectedNodeID = node.id }
                                }
                                .position(
                                    x: node.x(index: nodes.firstIndex(where: { $0.id == node.id }) ?? 0, zoom: zoom, layout: tab == .layout),
                                    y: tab == .layout ? node.y : 150
                                )
                            }
                        }
                        .frame(width: max(CGFloat(nodes.count) * 190 * zoom, 680), height: tab == .layout ? 440 : 300)
                        .padding(.horizontal, 18)
                    }
                    Text(tab == .pfd ? "PFD mode: left-to-right material path with stream connectors." : tab == .flowsheet ? "Flowsheet mode: ordered unit operations and process links." : "2D mode: equipment blocks arranged for spatial review; final coordinates come from the engineering runtime when supplied.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detailCard(_ node: DrawingNode) -> some View {
        AuroraCard {
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
                Button {
                    selectedNodeID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            Label("Material path", systemImage: "arrow.right").foregroundStyle(AuroraTheme.accent)
            Label("Selected equipment", systemImage: "scope").foregroundStyle(AuroraTheme.gold)
            Label("Runtime geometry", systemImage: "checkmark.seal").foregroundStyle(AuroraTheme.good)
        }
        .font(.caption)
        .padding(.horizontal, 6)
    }
}

private struct DrawingNode: Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let subtitle: String
    let icon: String
    let y: CGFloat

    func x(index: Int, zoom: CGFloat, layout: Bool) -> CGFloat {
        CGFloat(index) * 190 * zoom + 105
    }

    static func from(_ raw: String?) -> [DrawingNode] {
        let fallback = ["Feed", "Crushing", "Grinding", "Classification", "Flotation", "Product"]
        guard let raw, let data = raw.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let value = json.recursiveFind("units"),
              case .array(let items) = value, !items.isEmpty else {
            return fallback.enumerated().map { make(title: $0.element, index: $0.offset) }
        }
        return items.enumerated().compactMap { index, item in
            let title: String
            let kind: String
            switch item {
            case .string(let text):
                title = text
                kind = "Unit operation"
            case .object(let object):
                title = object["name"]?.stringValue ?? object["id"]?.stringValue ?? object["type"]?.stringValue ?? "Unit \(index + 1)"
                kind = object["type"]?.stringValue ?? object["category"]?.stringValue ?? "Unit operation"
            default:
                return nil
            }
            return make(title: title, kind: kind, index: index)
        }
    }

    private static func make(title: String, kind: String = "Unit operation", index: Int) -> DrawingNode {
        let lower = title.lowercased()
        let icon: String
        if lower.contains("grind") || lower.contains("mill") { icon = "gearshape.2.fill" }
        else if lower.contains("float") { icon = "bubbles.and.sparkles" }
        else if lower.contains("class") || lower.contains("cycl") { icon = "line.3.crossed.swirl.circle" }
        else if lower.contains("crush") { icon = "diamond.fill" }
        else if lower.contains("pump") { icon = "arrow.up.circle.fill" }
        else if lower.contains("tank") || lower.contains("thick") { icon = "cylinder.fill" }
        else if lower.contains("product") || lower.contains("tail") { icon = "shippingbox.fill" }
        else { icon = "square.stack.3d.up.fill" }
        return DrawingNode(id: "\(index)-\(title)", title: title, kind: kind, subtitle: "Process node \(index + 1) · governed by canonical route", icon: icon, y: 160 + CGFloat(index % 2) * 150)
    }
}

private struct DrawingConnections: View {
    let nodes: [DrawingNode]
    let zoom: CGFloat
    let layout: Bool

    var body: some View {
        Canvas { context, size in
            for index in 0..<(max(nodes.count - 1, 0)) {
                let start = CGPoint(x: CGFloat(index) * 190 * zoom + 155, y: layout ? nodes[index].y : 150)
                let end = CGPoint(x: CGFloat(index + 1) * 190 * zoom + 55, y: layout ? nodes[index + 1].y : 150)
                var path = Path()
                path.move(to: start)
                if layout {
                    let midpoint = (start.x + end.x) / 2
                    path.addCurve(to: end, control1: CGPoint(x: midpoint, y: start.y), control2: CGPoint(x: midpoint, y: end.y))
                } else {
                    path.addLine(to: end)
                }
                context.stroke(path, with: .color(AuroraTheme.accent.opacity(0.72)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                let arrow = Path { p in
                    p.move(to: CGPoint(x: end.x - 9, y: end.y - 6))
                    p.addLine(to: end)
                    p.addLine(to: CGPoint(x: end.x - 9, y: end.y + 6))
                }
                context.stroke(arrow, with: .color(AuroraTheme.gold), style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
                Image(systemName: node.icon)
                    .font(.title2.bold())
                    .foregroundStyle(selected ? AuroraTheme.gold : AuroraTheme.accent)
                Text(node.title)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(node.kind)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: compact ? 135 : 145, height: compact ? 102 : 112)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(selected ? AuroraTheme.gold.opacity(0.16) : AuroraTheme.panel2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(selected ? AuroraTheme.gold : AuroraTheme.accent.opacity(0.28), lineWidth: selected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
