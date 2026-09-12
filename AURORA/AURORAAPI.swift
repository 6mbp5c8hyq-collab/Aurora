import Foundation

actor AURORAAPI {
    enum APIError: LocalizedError {
        case invalidResponse
        case http(Int, String)
        case missingJobID
        case missingRunID

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid AURORA response"
            case .http(let code, let body): return "AURORA HTTP \(code): \(body)"
            case .missingJobID: return "AURORA did not return a job identifier"
            case .missingRunID: return "AURORA did not return a DAG run identifier"
            }
        }
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: AppConfig.backend)!
    }

    private func call(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> JSONValue {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.data()
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        if data.isEmpty { return .object(["ok": .bool(true)]) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func terminalStatus(_ value: JSONValue) -> Bool {
        let status = (value.firstString(["status", "platform_status", "state"]) ?? "").lowercased()
        let terminal = ["completed", "success", "succeeded", "failed", "error", "blocked", "cancelled"]
        return terminal.contains(where: { status.contains($0) })
    }

    func health() async throws -> JSONValue {
        try await call("/api/health")
    }

    func audit() async throws -> JSONValue {
        try await call("/api/audit")
    }

    func vaultStatus() async throws -> JSONValue {
        try await call("/api/vault/status")
    }

    func validate(_ payload: JSONValue) async throws -> JSONValue {
        try await call("/api/validate", method: "POST", body: payload)
    }

    func createJob(_ payload: JSONValue) async throws -> (String, JSONValue) {
        let response = try await call("/api/jobs", method: "POST", body: payload)
        guard let id = response.firstString(["job_id", "jobId", "id"]), !id.isEmpty else {
            throw APIError.missingJobID
        }
        return (id, response)
    }

    func job(_ id: String) async throws -> JSONValue {
        try await call("/api/jobs/\(id)")
    }

    func recentJobs() async throws -> JSONValue {
        try await call("/api/jobs/recent")
    }

    func createDagRun(_ payload: JSONValue) async throws -> (String, JSONValue) {
        let body = JSONValue.object(["payload": payload])
        let response = try await call("/api/dag/runs", method: "POST", body: body)
        guard let id = response.firstString(["run_id", "runId", "id"]), !id.isEmpty else {
            throw APIError.missingRunID
        }
        return (id, response)
    }

    func dagRun(_ id: String) async throws -> JSONValue {
        try await call("/api/dag/runs/\(id)")
    }

    func recentDagRuns() async throws -> JSONValue {
        try await call("/api/dag/runs/recent")
    }

    func runProject(_ payload: JSONValue, onUpdate: @Sendable (JSONValue) async -> Void) async throws -> JSONValue {
        _ = try await validate(.object(["payload": payload]))
        let (id, created) = try await createDagRun(payload)
        await onUpdate(created)
        var latest = created

        for _ in 0..<900 {
            latest = try await dagRun(id)
            await onUpdate(latest)
            if terminalStatus(latest) { return latest }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return latest
    }

    func run(_ payload: JSONValue, onUpdate: @Sendable (JSONValue) async -> Void) async throws -> JSONValue {
        _ = try await validate(payload)
        let (id, created) = try await createJob(payload)
        await onUpdate(created)
        var latest = created

        for _ in 0..<900 {
            latest = try await job(id)
            await onUpdate(latest)
            if terminalStatus(latest) { return latest }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return latest
    }

    func importOre(data: Data, filename: String) async throws -> JSONValue {
        let body = JSONValue.object([
            "filename": .string(filename),
            "content_base64": .string(data.base64EncodedString())
        ])
        return try await call("/api/imports/ore", method: "POST", body: body)
    }

    func export(_ body: JSONValue, format: String) async throws -> (url: URL, name: String) {
        var request = URLRequest(url: endpoint("/api/exports"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let encoded = body.data() else { throw APIError.invalidResponse }
        request.httpBody = encoded

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }

        let fallback = "AURORA_Output." + (format == "bundle" ? "zip" : format)
        let disposition = http.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let name = disposition
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { $0.lowercased().hasPrefix("filename=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
            ?? fallback

        let target = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        try data.write(to: target, options: .atomic)
        return (target, name)
    }
}
