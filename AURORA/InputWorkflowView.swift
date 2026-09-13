import SwiftUI

/// Stable navigation entry point for the governed project intake experience.
/// The implementation lives in `GovernedInputWorkflowView` so the legacy
/// screen can be replaced without changing RootView routing.
struct InputWorkflowView: View {
    var body: some View {
        GovernedInputWorkflowView()
    }
}
