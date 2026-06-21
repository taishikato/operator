import SwiftUI

public struct CursorOperatorSettingsView: View {
    private let appSpec: CursorOperatorAppSpec
    private let appDataURL: URL
    private let nodeResolver: any CursorNodeResolving
    @StateObject private var credentialModel: CursorCredentialSettingsModel
    @State private var apiKeyDraft = ""
    @State private var nodeProjection = CursorNodeSettingsProjection(result: .failure(.missingCompatibleNode))

    public init(
        appSpec: CursorOperatorAppSpec = .mvp,
        appDataURL: URL,
        credentialModel: CursorCredentialSettingsModel = CursorCredentialSettingsModel(),
        nodeResolver: any CursorNodeResolving = CursorNodeExecutableResolver()
    ) {
        self.appSpec = appSpec
        self.appDataURL = appDataURL
        self.nodeResolver = nodeResolver
        _credentialModel = StateObject(wrappedValue: credentialModel)
    }

    public var body: some View {
        Form {
            Section("Cursor API Key") {
                LabeledContent("Status", value: credentialStatusText)
                LabeledContent("Validation", value: validationStatusText)
                if let credentialErrorMessage = credentialModel.credentialErrorMessage {
                    Label(credentialErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                SecureField("Paste API key", text: $apiKeyDraft)

                HStack {
                    Button("Save") {
                        if credentialModel.saveAPIKeyReportingErrors(apiKeyDraft) {
                            apiKeyDraft = ""
                        }
                    }
                    .disabled(apiKeyDraft.isEmpty)

                    Button("Validate") {
                        Task { await credentialModel.validateAPIKey() }
                    }

                    Button("Delete") {
                        credentialModel.deleteAPIKeyReportingErrors()
                    }
                }
            }

            Section("Cursor Operator") {
                LabeledContent("App", value: appSpec.displayName)
                LabeledContent("Bundle ID", value: appSpec.bundleIdentifier)
                LabeledContent("Minimum macOS", value: appSpec.minimumMacOS)
                LabeledContent("Node.js", value: nodeProjection.status)
                LabeledContent("Node Path") {
                    Text(nodeProjection.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(nodeProjection.path)
                }
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
        .containerBackground(CursorTheme.bgContent, for: .window)
        .preferredColorScheme(.dark)
        .onAppear(perform: refreshNodeProjection)
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
        credentialModel.validationStatus.displayMessage
    }

    private func refreshNodeProjection() {
        do {
            nodeProjection = CursorNodeSettingsProjection(result: .success(try nodeResolver.resolve()))
        } catch CursorNodeResolutionError.missingCompatibleNode {
            nodeProjection = CursorNodeSettingsProjection(result: .failure(.missingCompatibleNode))
        } catch {
            nodeProjection = CursorNodeSettingsProjection(result: .failure(.missingCompatibleNode))
        }
    }
}
