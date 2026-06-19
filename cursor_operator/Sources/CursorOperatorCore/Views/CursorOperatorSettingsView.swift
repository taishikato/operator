import SwiftUI

public struct CursorOperatorSettingsView: View {
    private let appSpec: CursorOperatorAppSpec
    private let appDataURL: URL

    public init(
        appSpec: CursorOperatorAppSpec = .mvp,
        appDataURL: URL
    ) {
        self.appSpec = appSpec
        self.appDataURL = appDataURL
    }

    public var body: some View {
        Form {
            Section("Cursor Operator") {
                LabeledContent("App", value: appSpec.displayName)
                LabeledContent("Bundle ID", value: appSpec.bundleIdentifier)
                LabeledContent("Minimum macOS", value: appSpec.minimumMacOS)
                LabeledContent("App Data") {
                    Text(appDataURL.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(appDataURL.path)
                }
            }

            Section("Development") {
                ForEach(appSpec.developmentCommands, id: \.self) { command in
                    Text(command)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .containerBackground(.thickMaterial, for: .window)
    }
}
