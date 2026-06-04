import SwiftUI

public struct OperatorSettingsView: View {
    public init() {}

    public var body: some View {
        Form {
            Section("Operator") {
                LabeledContent("App", value: "Operator Desktop")
                LabeledContent("Minimum macOS", value: "15 Sequoia")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
