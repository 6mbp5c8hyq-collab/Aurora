import SwiftUI
import SwiftData
import Foundation

private actor AURORAAIClient {
    enum AIError: LocalizedError {
        case invalidResponse
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid AURORA AI response"
            case .http(let code, let body):
                return "AURORA AI HTTP \(code): \(body)"
            }
        }
    }

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: AppConfig.backend)!
    }

    func status() async throws -> JSONValue {
        var request = URLRequest(url: endpoint("/api/ai/status"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func chat(body: JSONValue) async throws -> JSONValue {
        var request = URLRequest(url: endpoint("/api/ai/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.httpBody = body.data()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
            let message = decoded?.firstString(["message", "error"]) ?? String(decoding: data, as: UTF8.self)
            throw AIError.http(http.statusCode, message)
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private struct CopilotMessage: Identifiable {
    enum Role { case user, assistant, system }
    let id = UUID()
    let role: Role
    let text: String
    let toolCount: Int

    init(role: Role, text: String, toolCount: Int = 0) {
        self.role = role
        self.text = text
        self.toolCount = toolCount
    }
}

struct AURORACopilotView: View {
    @EnvironmentObject private var app: AppModel
    @Query(sort: \AuroraProject.updatedAt, order: .reverse) private var projects: [AuroraProject]

    @State private var selectedProjectID: UUID?
    @State private var prompt = ""
    @State private var mode = "standard"
    @State private var allowActions = false
    @State private var messages: [CopilotMessage] = []
    @State private var status: JSONValue?
    @State private var isLoading = false
    @State private var errorText: String?

    private let client = AURORAAIClient()

    private var selectedProject: AuroraProject? {
        if let selectedProjectID,
           let project = projects.first(where: { $0.id == selectedProjectID }) {
            return project
        }
        return projects.first
    }

    private var configured: Bool {
        status?.recursiveFind("configured")?.boolValue == true
    }

    private var standardModel: String {
        status?.firstString(["standard_model"]) ?? "—"
    }

    private var deepModel: String {
        status?.firstString(["deep_model"]) ?? "—"
    }

    private var activeRunReference: JSONValue? {
        guard let result = app.activeResult else { return nil }
        if let id = result.firstString(["job_id", "jobId"]), !id.isEmpty {
            return .object(["kind": .string("job"), "id": .string(id)])
        }
        if let id = result.firstString(["run_id", "runId"]), !id.isEmpty {
            return .object(["kind": .string("dag"), "id": .string(id)])
        }
        if let id = app.activeJobID, !id.isEmpty {
            let kind = app.activeResultOrigin.lowercased().contains("engine") ? "job" : "dag"
            return .object(["kind": .string(kind), "id": .string(id)])
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            controlRail
                .frame(width: 310)
                .background(AuroraTheme.background)
            Divider()
            conversation
        }
        .background(AuroraTheme.background)
        .task {
            if selectedProjectID == nil { selectedProjectID = projects.first?.id }
            await refreshStatus()
            if messages.isEmpty {
                messages = [
                    CopilotMessage(
                        role: .system,
                        text: "AURORA Industrial Copilot interprets and orchestrates platform evidence. AI text is never promoted to measured, calibrated or AURORA-calculated output."
                    )
                ]
            }
        }
    }

    private var controlRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AuroraCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.title2)
                                .foregroundStyle(AuroraTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AURORA Copilot").font(.headline)
                                Text("Industrial Scientific AI").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        StatusBadge(text: configured ? "AI Gateway Ready" : "AI Gateway Needs Key")
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Project Context").font(.headline)
                        if projects.isEmpty {
                            Text("No project available. The Copilot can still explain platform state, but project-scoped execution tools remain unavailable.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Project", selection: $selectedProjectID) {
                                ForEach(projects) { project in
                                    Text(project.name).tag(Optional(project.id))
                                }
                            }
                            .pickerStyle(.menu)
                            if let project = selectedProject {
                                Text("\(project.declaredFamily.capitalized) · \(project.feedTPH.formatted()) t/h")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let ref = activeRunReference {
                            Divider()
                            Text("Active runtime context")
                                .font(.caption.bold())
                            Text(ref.prettyString())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AuroraTheme.good)
                        } else {
                            Text("No active run reference")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Model Routing").font(.headline)
                        Picker("Mode", selection: $mode) {
                            Text("Standard").tag("standard")
                            Text("Deep Scientific").tag("deep")
                        }
                        .pickerStyle(.segmented)
                        Text(mode == "deep" ? deepModel : standardModel)
                            .font(.caption.monospaced())
                            .foregroundStyle(AuroraTheme.accent)
                        Text("Deep Scientific uses higher reasoning effort. Numerical authority still remains with AURORA runtime outputs and source-tagged evidence.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $allowActions) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow AURORA Actions").font(.subheadline.bold())
                                Text("Expose start-engine / start-DAG tools for this request.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(selectedProject == nil)
                        if allowActions {
                            Label("Execution requests can create jobs/runs. Creation is not proof of successful scientific completion.", systemImage: "exclamationmark.shield.fill")
                                .font(.caption2)
                                .foregroundStyle(AuroraTheme.gold)
                        } else {
                            Label("Read / interpret only", systemImage: "lock.shield.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                AuroraCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Authority Boundary").font(.headline)
                        authorityLine("AI interpretation", "Language-model synthesis only")
                        authorityLine("AURORA calculated", "Runtime-returned values only")
                        authorityLine("Measured", "Source-tagged evidence only")
                        authorityLine("Component/resource use", "Runtime instrumentation only")
                    }
                }

                Button {
                    Task { await refreshStatus() }
                } label: {
                    Label("Refresh AI Gateway", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
    }

    private func authorityLine(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.bold())
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("AURORA Copilot is evaluating governed context…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(22)
                }
                .onChange(of: messages.count) { _, _ in
                    if let id = messages.last?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            if let errorText {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorText).font(.caption)
                    Spacer()
                    Button("Dismiss") { self.errorText = nil }
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }

            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask AURORA about the ore, flowsheet, active run, evidence or next action…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...7)
                    .onSubmit { submit() }
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 31))
                }
                .buttonStyle(.plain)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || !configured)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: CopilotMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 70) }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: icon(for: message.role))
                    Text(label(for: message.role)).font(.caption.bold())
                    if message.toolCount > 0 {
                        Text("\(message.toolCount) AURORA tool\(message.toolCount == 1 ? "" : "s")")
                            .font(.caption2.monospaced())
                            .foregroundStyle(AuroraTheme.good)
                    }
                }
                Text(message.text)
                    .textSelection(.enabled)
                    .font(.body)
                if message.role == .assistant {
                    Text("Authority: AI interpretation · verify numerical claims against returned AURORA evidence")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(13)
            .background(bubbleColor(for: message.role), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if message.role != .user { Spacer(minLength: 70) }
        }
    }

    private func icon(for role: CopilotMessage.Role) -> String {
        switch role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "checkmark.shield.fill"
        }
    }

    private func label(for role: CopilotMessage.Role) -> String {
        switch role {
        case .user: return "You"
        case .assistant: return "AURORA Copilot"
        case .system: return "Governance"
        }
    }

    private func bubbleColor(for role: CopilotMessage.Role) -> Color {
        switch role {
        case .user: return AuroraTheme.accent.opacity(0.14)
        case .assistant: return Color.secondary.opacity(0.10)
        case .system: return AuroraTheme.gold.opacity(0.10)
        }
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading, configured else { return }
        prompt = ""
        messages.append(CopilotMessage(role: .user, text: text))
        Task { await send(text) }
    }

    @MainActor
    private func send(_ text: String) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let historyRows: [JSONValue] = messages.dropLast().suffix(12).compactMap { message in
            switch message.role {
            case .user:
                return .object(["role": .string("user"), "content": .string(message.text)])
            case .assistant:
                return .object(["role": .string("assistant"), "content": .string(message.text)])
            case .system:
                return nil
            }
        }

        var fields: [String: JSONValue] = [
            "message": .string(text),
            "mode": .string(mode),
            "allow_execution": .bool(allowActions),
            "history": .array(historyRows)
        ]
        if let selectedProject {
            fields["project"] = selectedProject.payload
        }
        if let activeRunReference {
            fields["active_run"] = activeRunReference
        }

        do {
            let response = try await client.chat(body: .object(fields))
            let answer = response.firstString(["answer"]) ?? "No textual answer returned."
            let toolCount: Int
            if let tools = response.recursiveFind("tool_events"), case .array(let rows) = tools {
                toolCount = rows.count
            } else {
                toolCount = 0
            }
            messages.append(CopilotMessage(role: .assistant, text: answer, toolCount: toolCount))
            if allowActions, toolCount > 0 {
                await app.refreshServerState()
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func refreshStatus() async {
        do {
            status = try await client.status()
            errorText = nil
        } catch {
            status = nil
            errorText = error.localizedDescription
        }
    }
}
