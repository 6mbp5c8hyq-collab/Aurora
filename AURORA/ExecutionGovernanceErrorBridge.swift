import Foundation

extension AURORAAPI.APIError {
    static func executionGovernanceBlocked(_ message: String) -> AURORAAPI.APIError {
        .http(422, "EXECUTION_GOVERNANCE_BLOCKED: \(message)")
    }
}
