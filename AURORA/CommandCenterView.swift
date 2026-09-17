import SwiftUI

struct CommandCenterView: View {
    @State private var showScientificProjectBasisV3 = false

    var body: some View {
        GovernedCommandCenterView()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScientificProjectBasisV3 = true
                    } label: {
                        Label("Project Basis V3", systemImage: "scope")
                    }
                }
            }
            .sheet(isPresented: $showScientificProjectBasisV3) {
                NavigationStack {
                    ScientificProjectBasisV3View()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showScientificProjectBasisV3 = false
                                }
                            }
                        }
                }
            }
    }
}
