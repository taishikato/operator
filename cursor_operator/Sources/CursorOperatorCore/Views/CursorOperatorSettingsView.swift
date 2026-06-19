import SwiftUI

public struct CursorOperatorSettingsView: View {
    private let appSpec: CursorOperatorAppSpec
    private let appDataURL: URL
    @StateObject private var credentialModel: CursorCredentialSettingsModel
    @State private var apiKeyDraft = ""

    public init(
        appSpec: CursorOperatorAppSpec = .mvp,
        appDataURL: URL,
        credentialModel: CursorCredentialSettingsModel = CursorCredentialSettingsModel()
    ) {
        self.appSpec = appSpec
        self.appDataURL = appDataURL
        _credentialModel = StateObject(wrappedValue: credentialModel)
    }

    public var body: some View {
        Form {
            Section("Cursor API Key") {
                LabeledContent("Status", value: credentialStatusText)
                LabeledContent("Validation", value: validationStatusText)

                SecureField("Paste API key", text: $apiKeyDraft)

                HStack {
                    Button("Save") {
                        try? credentialModel.saveAPIKey(apiKeyDraft)
                        apiKeyDraft = ""
                    }
                    .disabled(apiKeyDraft.isEmpty)

                    Button("Validate") {
                        Task { await credentialModel.validateAPIKey() }
                    }

                    Button("Delete") {
                        try? credentialModel.deleteAPIKey()
                    }
                }
            }

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

    private var credentialStatusText: String {
        switch credentialModel.status {
        case .missing:
            "Missing"
        case let .present(maskedValue):
            "Present (\(maskedValue))"
        }
    }

    private var validationStatusText: String {
        switch credentialModel.validationStatus {
        case .notValidated:
            "Not validated"
        case .validating:
            "Validating..."
        case .valid:
            "Valid"
        case let .invalid(message):
            message
        }
    }
}
