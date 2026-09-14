import SwiftUI

struct ChemistryAuthorityInspectorView: View {
    private let api = AURORAAPI()

    @State private var statusText = "Authority status has not been queried."
    @State private var selftestText = "Self-test has not been run."
    @State private var isLoadingStatus = false
    @State private var isRunningSelftest = false
    @State private var statusOK: Bool?
    @State private var selftestOK: Bool?
    @State private var lastError = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                controlPanel
                resultPanel(
                    title: "Authority / Capability Status",
                    icon: "point.3.connected.trianglepath.dotted",
                    ok: statusOK,
                    text: statusText
                )
                resultPanel(
                    title: "Chemistry Self-Test Certificate",
                    icon: "checkmark.shield",
                    ok: selftestOK,
                    text: selftestText
                )
                policyPanel
            }
            .padding(20)
        }
        .navigationTitle("Chemistry Authority")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await refreshStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE NUMERICAL AUTHORITY")
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(AuroraTheme.accent)
            Text("Native Chemistry + PHREEQC Authority Routing")
                .font(.title2.bold())
            Text("This inspector queries the production chemistry API directly. It reports what the runtime can execute now, rather than inferring capability from UI labels or engine names.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    Task { await refreshStatus() }
                } label: {
                    Label(isLoadingStatus ? "Checking…" : "Refresh authority", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingStatus)

                Button {
                    Task { await runSelftest() }
                } label: {
                    Label(isRunningSelftest ? "Testing…" : "Run chemistry self-test", systemImage: "testtube.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRunningSelftest)
            }

            if !lastError.isEmpty {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func resultPanel(title: String, icon: String, ok: Bool?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                stateBadge(ok)
            }

            ScrollView(.horizontal) {
                Text(text)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func stateBadge(_ ok: Bool?) -> some View {
        switch ok {
        case .some(true):
            Text("PASS")
                .font(.caption2.bold())
                .foregroundStyle(AuroraTheme.good)
        case .some(false):
            Text("FAIL")
                .font(.caption2.bold())
                .foregroundStyle(.red)
        case .none:
            Text("UNVERIFIED")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
    }

    private var policyPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Authority policy", systemImage: "lock.shield")
                .font(.headline)
            Text("Native authority is permitted for governed aqueous speciation, Davies/SIT/extended Debye-Hückel, saturation-index and explicit Nernst calculations. Requests for full Pitzer, high-salinity chemistry, surface complexation/CD-MUSIC, ion exchange, gas/solid-solution equilibrium, kinetics, reaction paths or reactive transport are routed to the PHREEQC authority. If that authority is unavailable, AURORA must fail closed; it must not silently substitute a simpler model.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func refreshStatus() async {
        guard !isLoadingStatus else { return }
        isLoadingStatus = true
        lastError = ""
        defer { isLoadingStatus = false }
        do {
            let value = try await api.chemistryStatus()
            statusText = value.prettyString()
            statusOK = boolValue(value.recursiveFind("ok")) ?? true
        } catch {
            statusOK = false
            lastError = error.localizedDescription
            statusText = "Status request failed:\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func runSelftest() async {
        guard !isRunningSelftest else { return }
        isRunningSelftest = true
        lastError = ""
        defer { isRunningSelftest = false }
        do {
            let value = try await api.chemistrySelftest()
            selftestText = value.prettyString()
            selftestOK = boolValue(value.recursiveFind("ok")) ?? false
        } catch {
            selftestOK = false
            lastError = error.localizedDescription
            selftestText = "Self-test request failed:\n\(error.localizedDescription)"
        }
    }

    private func boolValue(_ value: JSONValue?) -> Bool? {
        guard let value else { return nil }
        switch value {
        case .bool(let flag): return flag
        case .string(let text):
            if text.lowercased() == "true" { return true }
            if text.lowercased() == "false" { return false }
            return nil
        default:
            return nil
        }
    }
}
