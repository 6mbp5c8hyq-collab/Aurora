import SwiftUI

struct CommandCenterView: View {
    @State private var showScientificProjectBasisV3 = false
    @State private var showExecutionEligibilityV3 = false

    var body: some View {
        GovernedCommandCenterView()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showExecutionEligibilityV3 = true
                    } label: {
                        Label("Execution Eligibility V3", systemImage: "point.3.connected.trianglepath.dotted")
                    }
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
                                Button("Done") { showScientificProjectBasisV3 = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showExecutionEligibilityV3) {
                NavigationStack {
                    ProcessGraphEligibilityV3View()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showExecutionEligibilityV3 = false }
                            }
                        }
                }
            }
    }
}
