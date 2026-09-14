import SwiftUI

struct CommandCenterView: View {
    var body: some View {
        GovernedCommandCenterView()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            ChemistryWorkbenchView()
                        } label: {
                            Label("Chemistry Suite", systemImage: "atom")
                        }

                        NavigationLink {
                            ChemistryAuthorityInspectorView()
                        } label: {
                            Label("Chemistry Authority", systemImage: "checkmark.shield")
                        }
                    } label: {
                        Label("Chemistry", systemImage: "atom")
                    }
                }
            }
    }
}
