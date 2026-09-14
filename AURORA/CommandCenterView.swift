import SwiftUI

struct CommandCenterView: View {
    var body: some View {
        GovernedCommandCenterView()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ChemistryWorkbenchView()
                    } label: {
                        Label("Chemistry Suite", systemImage: "atom")
                    }
                }
            }
    }
}
