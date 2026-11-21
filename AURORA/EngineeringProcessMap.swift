import Foundation
import SwiftUI

/// An evidence-only connectivity projection. This is a logical stream graph,
/// not an inferred equipment layout, routing diagram, or engineering drawing.
struct EngineeringProcessTopology {
    struct Equipment: Identifiable {
        let id: String
        let sourceTag: String
    }

    struct Stream: Identifiable {
        let id: String
        let sourceID: String
        let fromTag: String?
        let toTag: String?
        let solidsTph: Double?
        let waterTph: Double?
    }

    struct Finding: Identifiable {
        let id: String
        let code: String
        let classification: String
        let equipmentTags: [String]
        let streamIDs: [String]
        let sourcePath: String
    }

    let equipment: [Equipment]
    let streams: [Stream]
    let findings: [Finding]
    let reportedEquipmentCount: Int
    let reportedStreamCount: Int
    let reportedIssueCount: Int
    let reportedHoldCount: Int

    static func parse(_ result: JSONValue?) -> EngineeringProcessTopology? {
        guard let source = result?.recursiveFind("engineering_phase_b"),
              case .object(let b) = source,
              let sizing = b["equipment_sizing"], case .object(let equipmentSizing) = sizing,
              let rawEquipment = equipmentSizing["register"], case .array(let registry) = rawEquipment,
              let mass = b["mass_balance"], case .object(let massBalance) = mass,
              let rawStreams = massBalance["stream_table"], case .array(let streamTable) = rawStreams
        else { return nil }

        func explicitTag(_ fields: [String: JSONValue], _ key: String) -> String? {
            guard let value = fields[key], case .string(let text) = value else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func numeric(_ fields: [String: JSONValue], _ key: String) -> Double? {
            guard let value = fields[key], case .number(let n) = value, n.isFinite else { return nil }
            return n
        }

        // Preserve source indices as stable presentation IDs, even when source
        // identity is duplicated or omitted (the server audit blocks those).
        let equipment = registry.prefix(300).enumerated().compactMap { index, record -> Equipment? in
            guard case .object(let fields) = record,
                  let tag = explicitTag(fields, "tag") else { return nil }
            return Equipment(id: "equipment[\(index)]", sourceTag: tag)
        }
        let streams = streamTable.prefix(400).enumerated().compactMap { index, record -> Stream? in
            guard case .object(let fields) = record else { return nil }
            return Stream(
                id: "stream[\(index)]",
                sourceID: explicitTag(fields, "stream_id") ?? "",
                fromTag: explicitTag(fields, "from_unit"),
                toTag: explicitTag(fields, "to_unit"),
                solidsTph: numeric(fields, "solids_tph"),
                waterTph: numeric(fields, "water_tph")
            )
        }

        var findings: [Finding] = []
        var issueCount = 0
        var holdCount = 0
        if let audit = result?.recursiveFind("engineering_cross_phase_integrity"),
           case .object(let integrity) = audit {
            func parseFindings(_ key: String, classification: String) -> Int {
                guard let raw = integrity[key], case .array(let records) = raw else { return 0 }
                for (index, record) in records.prefix(200).enumerated() {
                    guard case .object(let fields) = record else { continue }
                    let tags = ["tag", "tag_a", "tag_b", "equipment_tag"]
                        .compactMap { explicitTag(fields, $0) }
                    let streamIDs = ["stream_id"].compactMap { explicitTag(fields, $0) }
                    findings.append(Finding(
                        id: "\(key)[\(index)]",
                        code: explicitTag(fields, "code") ?? "CODE_UNREPORTED",
                        classification: classification,
                        equipmentTags: Array(Set(tags)).sorted(),
                        streamIDs: Array(Set(streamIDs)).sorted(),
                        sourcePath: "engineering_cross_phase_integrity.\(key)[\(index)]"
                    ))
                }
                return records.count
            }
            issueCount = parseFindings("issues", classification: "BLOCKER")
            holdCount = parseFindings("design_holds", classification: "HOLD")
        }

        return EngineeringProcessTopology(
            equipment: equipment,
            streams: streams,
            findings: findings,
            reportedEquipmentCount: registry.count,
            reportedStreamCount: streamTable.count,
            reportedIssueCount: issueCount,
            reportedHoldCount: holdCount
        )
    }

    func matchingStreams(for finding: Finding) -> [Stream] {
        // Match only explicit canonical source identities. Do not resolve
        // unregistered equipment names to synthetic graph nodes.
        streams.filter { stream in
            finding.streamIDs.contains(stream.sourceID)
                || (stream.fromTag.map { finding.equipmentTags.contains($0) } ?? false)
                || (stream.toTag.map { finding.equipmentTags.contains($0) } ?? false)
        }
    }

    func relatedFindings(to stream: Stream) -> [Finding] {
        findings.filter { finding in
            finding.streamIDs.contains(stream.sourceID)
                || (stream.fromTag.map { finding.equipmentTags.contains($0) } ?? false)
                || (stream.toTag.map { finding.equipmentTags.contains($0) } ?? false)
        }
    }
}

struct EngineeringProcessMap: View {
    let result: JSONValue?
    let onInspectStream: (String) -> Void

    @State private var selectedEquipment: String?
    @State private var selectedStream: String?
    @State private var selectedFinding: String?

    private var graph: EngineeringProcessTopology? {
        EngineeringProcessTopology.parse(result)
    }

    private func visibleStreams(_ graph: EngineeringProcessTopology) -> [EngineeringProcessTopology.Stream] {
        if let selectedFinding,
           let finding = graph.findings.first(where: { $0.id == selectedFinding }) {
            return graph.matchingStreams(for: finding)
        }
        if let selectedEquipment {
            return graph.streams.filter {
                $0.fromTag == selectedEquipment || $0.toTag == selectedEquipment
            }
        }
        if let selectedStream {
            return graph.streams.filter { $0.id == selectedStream }
        }
        return graph.streams
    }

    var body: some View {
        if let graph {
            AuroraCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Process Connectivity & Issue Navigator").font(.headline)
                            Text("Logical equipment–stream links from Phase B; audit references from B–C–H–J–K.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear selection") {
                            selectedFinding = nil
                            selectedEquipment = nil
                            selectedStream = nil
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("This is a source-linked connectivity map, not a spatial PFD, P&ID or certified 3D plant layout. Blank endpoints indicate plant boundaries, not invented equipment.")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Text("\(graph.reportedEquipmentCount) registered units")
                        Text("\(graph.reportedStreamCount) streams")
                        Text("\(graph.reportedIssueCount) blocking findings")
                        Text("\(graph.reportedHoldCount) design holds")
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)

                    if !graph.findings.isEmpty {
                        Text("Select an audit finding to isolate its exact linked streams")
                            .font(.subheadline.bold())
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(graph.findings.prefix(60)) { finding in
                                    findingRow(finding, graph: graph)
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                    }

                    if !graph.equipment.isEmpty {
                        Text("Equipment lookup").font(.subheadline.bold())
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(graph.equipment) { equipment in
                                    Button(equipment.sourceTag) {
                                        selectedFinding = nil
                                        selectedStream = nil
                                        selectedEquipment = equipment.sourceTag
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(selectedEquipment == equipment.sourceTag ? AuroraTheme.accent : .secondary)
                                }
                            }
                        }
                    }

                    let visible = visibleStreams(graph)
                    HStack {
                        Text("Canonical stream connections").font(.subheadline.bold())
                        Spacer()
                        Text("\(visible.count) linked").font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if visible.isEmpty {
                        Text("No canonical stream is linked to this reference. The missing link remains unresolved; no connection is inferred.")
                            .font(.caption)
                            .foregroundStyle(AuroraTheme.warn)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(visible.prefix(80)) { stream in
                                streamRow(stream, graph: graph)
                            }
                        }
                    }
                    if graph.reportedStreamCount > graph.streams.count
                        || graph.reportedEquipmentCount > graph.equipment.count
                        || visible.count > 80 || graph.reportedIssueCount + graph.reportedHoldCount > 60 {
                        Text("A bounded preview is displayed. The complete source remains in the canonical result.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func findingRow(_ finding: EngineeringProcessTopology.Finding,
                            graph: EngineeringProcessTopology) -> some View {
        let linked = graph.matchingStreams(for: finding)
        let referenced = finding.equipmentTags + finding.streamIDs
        return Button {
            selectedFinding = finding.id
            selectedEquipment = nil
            selectedStream = nil
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: finding.classification == "BLOCKER"
                      ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")
                    .foregroundStyle(finding.classification == "BLOCKER" ? AuroraTheme.bad : AuroraTheme.gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.code).font(.caption.monospaced().bold())
                        .foregroundStyle(.primary)
                    Text(referenced.isEmpty ? "No explicit equipment or stream reference" : referenced.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(linked.count) matched stream(s) · \(finding.sourcePath)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(selectedFinding == finding.id ? AuroraTheme.accent : .secondary)
            }
            .padding(9)
            .background(selectedFinding == finding.id ? AuroraTheme.accent.opacity(0.12)
                        : AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func streamRow(_ stream: EngineeringProcessTopology.Stream,
                           graph: EngineeringProcessTopology) -> some View {
        let affected = !graph.relatedFindings(to: stream).isEmpty
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                unitButton(stream.fromTag)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Button(stream.sourceID.isEmpty ? "Unreported stream ID" : stream.sourceID) {
                    selectedFinding = nil
                    selectedEquipment = nil
                    selectedStream = stream.id
                }
                .buttonStyle(.bordered)
                .tint(affected ? AuroraTheme.warn : AuroraTheme.accent)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                unitButton(stream.toTag)
                Spacer(minLength: 0)
                if affected {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(AuroraTheme.warn)
                }
            }
            .font(.caption)
            HStack(spacing: 12) {
                Text("Dry solids: \(amount(stream.solidsTph)) t/h")
                Text("Water: \(amount(stream.waterTph)) t/h")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            if selectedStream == stream.id && !stream.sourceID.isEmpty {
                Button {
                    onInspectStream(stream.sourceID)
                } label: {
                    Label("Inspect source stream in ledger", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
        }
        .padding(10)
        .background(selectedStream == stream.id ? AuroraTheme.accent.opacity(0.11)
                    : AuroraTheme.panel2, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func unitButton(_ tag: String?) -> some View {
        if let tag {
            Button(tag) {
                selectedFinding = nil
                selectedStream = nil
                selectedEquipment = tag
            }
            .buttonStyle(.bordered)
            .tint(selectedEquipment == tag ? AuroraTheme.accent : .secondary)
        } else {
            Text("Plant boundary").foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        }
    }

    private func amount(_ value: Double?) -> String {
        guard let value else { return "unreported" }
        return String(format: "%.3f", value)
    }
}
