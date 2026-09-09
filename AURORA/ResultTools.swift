import Foundation
import UIKit

struct KPI: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let unit: String
}

struct EngineStage: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let detail: String?
}

struct ArtifactLink: Identifiable {
    let id = UUID()
    let label: String
    let raw: String
    let format: String
}

enum ResultTools {
    static func status(_ result: JSONValue?) -> String {
        result?.firstString(["platform_status", "status", "state"]) ?? "No result"
    }

    static func ceiling(_ result: JSONValue?) -> String? {
        result?.firstString(["claim_ceiling", "claimCeiling"])
    }

    static func kpis(_ result: JSONValue?) -> [KPI] {
        guard let result else { return [] }
        let candidates: [(String, [String], String)] = [
            ("Feed", ["feed_tph", "throughput_tph"], "t/h"),
            ("Product grade", ["product_grade", "grade_pct", "target_grade"], "%"),
            ("Recovery", ["recovery_pct", "recovery"], "%"),
            ("Mass recovery", ["mass_recovery_pct"], "%"),
            ("Power", ["power_kw"], "kW"),
            ("Water", ["water_m3_h"], "m³/h"),
            ("CAPEX", ["capex", "capex_usd"], ""),
            ("OPEX", ["opex", "opex_usd_t"], ""),
            ("NPV", ["npv", "npv_usd"], ""),
            ("IRR", ["irr", "irr_pct"], "%")
        ]

        var output: [KPI] = []
        for (label, keys, unit) in candidates {
            for key in keys {
                guard let value = result.recursiveFind(key) else { continue }
                if case .number(let number) = value {
                    output.append(.init(name: label, value: number, unit: unit))
                    break
                }
                if case .string(let text) = value,
                   let number = Double(text.replacingOccurrences(of: "%", with: "")) {
                    output.append(.init(name: label, value: number, unit: unit))
                    break
                }
            }
        }
        return Array(output.prefix(8))
    }

    static func stages(_ result: JSONValue?) -> [EngineStage] {
        guard let result else { return [] }
        for key in ["execution_stages", "engine_trace", "stages", "execution", "pipeline", "orchestration"] {
            guard let value = result.recursiveFind(key), case .array(let items) = value else { continue }
            let stages = items.compactMap { item -> EngineStage? in
                if case .object(let object) = item {
                    let name = object["name"]?.stringValue
                        ?? object["engine"]?.stringValue
                        ?? object["stage"]?.stringValue
                        ?? object["id"]?.stringValue
                        ?? "AURORA stage"
                    let status = object["status"]?.stringValue ?? object["state"]?.stringValue ?? "reported"
                    let detail = object["detail"]?.stringValue ?? object["message"]?.stringValue
                    return .init(name: name, status: status, detail: detail)
                }
                if let text = item.stringValue { return .init(name: text, status: "reported", detail: nil) }
                return nil
            }
            if !stages.isEmpty { return stages }
        }
        return []
    }

    static func artifacts(_ result: JSONValue?) -> [ArtifactLink] {
        guard let result else { return [] }
        let formats = ["pdf", "xlsx", "xls", "docx", "csv", "svg", "dxf", "png", "zip"]
        var output: [ArtifactLink] = []
        for (path, raw) in result.flattenedScalars(limit: 1000) {
            let lower = raw.lowercased()
            if let ext = formats.first(where: { lower.contains(".\($0)") }) {
                output.append(.init(label: path, raw: raw, format: ext.uppercased()))
            }
        }
        var seen = Set<String>()
        return output.filter { seen.insert($0.raw).inserted }
    }
}

enum NativeReport {
    static func makePDF(project: AuroraProject, result: JSONValue?) -> URL? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AURORA-Summary.pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                var y: CGFloat = 40
                let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 23, weight: .bold)]
                let body: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)]

                "AURORA — Industrial Project Summary".draw(at: CGPoint(x: 40, y: y), withAttributes: title)
                y += 42
                for line in [
                    project.name,
                    "Ore: \(project.declaredFamily)",
                    "Feed: \(project.feedTPH) t/h",
                    "Target: \(project.targetComponent) \(project.targetGrade)%"
                ] {
                    line.draw(at: CGPoint(x: 40, y: y), withAttributes: body)
                    y += 16
                }
                y += 14

                for (key, value) in result?.flattenedScalars(limit: 180) ?? [] {
                    if y > 805 { context.beginPage(); y = 40 }
                    "\(key): \(value)".draw(in: CGRect(x: 40, y: y, width: 515, height: 24), withAttributes: body)
                    y += 14
                }
            }
            return url
        } catch {
            return nil
        }
    }

    static func makeCSV(result: JSONValue?) -> URL? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AURORA-result.csv")

        func escape(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        let rows = result?.flattenedScalars(limit: 5000) ?? []
        let text = "path,value\n" + rows.map { "\(escape($0.0)),\(escape($0.1))" }.joined(separator: "\n")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
