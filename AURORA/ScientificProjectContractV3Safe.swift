import Foundation

/// Migration-safe transport gate for Scientific Project Contract V3.
///
/// Legacy projects that have never explicitly saved a V3 basis pass through unchanged.
/// This prevents the client from silently classifying an existing wet/hybrid project as dry,
/// or assigning a beneficiation objective that the user never declared.
enum SafeScientificProjectContractV3 {
    private static let storagePrefix = "aurora.scientificProjectBasisV3."

    static func enrich(_ value: JSONValue) -> JSONValue {
        switch value {
        case .array(let values):
            return .array(values.map(enrich))
        case .object(let object):
            var result: [String: JSONValue] = [:]
            for (key, child) in object {
                result[key] = enrich(child)
            }

            guard let projectValue = result["project"],
                  case .object(let projectObject) = projectValue,
                  let rawID = projectObject["id"]?.stringValue,
                  let projectID = UUID(uuidString: rawID),
                  hasExplicitBasis(projectID: projectID) else {
                return .object(result)
            }

            // At this point V3 authority was explicitly saved for this project.
            // The canonical merger can safely attach objective/mode/targets/policy.
            return ScientificProjectContractV3.enrich(.object(result))

        default:
            return value
        }
    }

    static func hasExplicitBasis(projectID: UUID) -> Bool {
        UserDefaults.standard.data(forKey: storagePrefix + projectID.uuidString) != nil
    }
}
