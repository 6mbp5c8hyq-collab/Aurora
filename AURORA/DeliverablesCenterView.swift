import SwiftUI

struct DeliverablesCenterView: View {
    @State private var section: ExportCenterSection = .deliverables

    private enum ExportCenterSection: String, CaseIterable, Identifiable {
        case deliverables = "Deliverables"
        case lineage = "Run Lineage"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Export Center section", selection: $section) {
                    ForEach(ExportCenterSection.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                Spacer()
                Text(section == .deliverables ? "GOVERNED SCOPE MANIFEST" : "EXECUTION LINEAGE ONLY")
                    .font(.caption2.bold())
                    .foregroundStyle(section == .deliverables ? AuroraTheme.accent : AuroraTheme.gold)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(AuroraTheme.background)

            switch section {
            case .deliverables:
                GovernedDeliverablesCenterView()
            case .lineage:
                RunLineageManifestView()
            }
        }
        .background(AuroraTheme.background)
    }
}
