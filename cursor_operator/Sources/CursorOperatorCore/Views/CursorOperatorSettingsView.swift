import AppKit
import SwiftUI

public struct CursorOperatorSettingsView: View {
    private let appSpec: CursorOperatorAppSpec
    private let appDataURL: URL
    private let nodeResolver: any CursorNodeResolving
    private let agentSupportInstaller: any CursorAgentSupportInstalling
    @StateObject private var credentialModel: CursorCredentialSettingsModel
    @State private var apiKeyDraft = ""
    @State private var nodeProjection = CursorNodeSettingsProjection(result: .failure(.missingCompatibleNode))
    @State private var agentSupportStatus: CursorAgentSupportStatus?
    @State private var agentSupportErrorMessage: String?

    public init(
        appSpec: CursorOperatorAppSpec = .mvp,
        appDataURL: URL,
        credentialModel: CursorCredentialSettingsModel = CursorCredentialSettingsModel(),
        nodeResolver: any CursorNodeResolving = CursorNodeExecutableResolver(),
        agentSupportInstaller: any CursorAgentSupportInstalling = CursorAgentSupportInstaller.bundled()
    ) {
        self.appSpec = appSpec
        self.appDataURL = appDataURL
        self.nodeResolver = nodeResolver
        self.agentSupportInstaller = agentSupportInstaller
        _credentialModel = StateObject(wrappedValue: credentialModel)
    }

    public var body: some View {
        Form {
            Section("Cursor API Key") {
                LabeledContent("Status", value: credentialStatusText)
                LabeledContent("Validation", value: validationStatusText)
                if let credentialErrorMessage = credentialModel.credentialErrorMessage {
                    Label(credentialErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(CursorTheme.danger)
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
                        .foregroundStyle(CursorTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(nodeProjection.path)
                }
                LabeledContent("App Data") {
                    Text(appDataURL.path)
                        .foregroundStyle(CursorTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(appDataURL.path)
                }
            }

            Section("Agent Support") {
                if let agentSupportStatus {
                    CursorAgentSupportRow(
                        title: "CLI",
                        badge: "cursor-operator",
                        destinationText: displayPath(agentSupportStatus.cli.destination),
                        status: agentSupportStatus.cli.state,
                        installTitle: "Install CLI"
                    ) {
                        installCLIReportingErrors()
                    }

                    CursorAgentSupportRow(
                        title: "Agent Skill",
                        badge: "/cursor-operator",
                        destinationText: skillDestinationText(agentSupportStatus.skills),
                        status: agentSupportStatus.skillsState,
                        installTitle: "Install Skills"
                    ) {
                        installSkillsReportingErrors()
                    } reveal: {
                        revealAgentSkill(agentSupportStatus.skills)
                    }
                } else {
                    Text("Agent support unavailable")
                        .foregroundStyle(CursorTheme.textSecondary)
                }

                if let agentSupportErrorMessage {
                    Label(agentSupportErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(CursorTheme.danger)
                }
            }

            Section("Development") {
                ForEach(appSpec.developmentCommands, id: \.self) { command in
                    Text(command)
                        .font(.codeInline)
                        .foregroundStyle(CursorTheme.blue)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .containerBackground(CursorTheme.bgContent, for: .window)
        .preferredColorScheme(.dark)
        .onAppear {
            refreshNodeProjection()
            refreshAgentSupportStatus()
        }
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

    private func refreshAgentSupportStatus() {
        do {
            agentSupportStatus = try agentSupportInstaller.status()
            agentSupportErrorMessage = nil
        } catch {
            agentSupportStatus = nil
            agentSupportErrorMessage = userFacingAgentSupportMessage(for: error)
        }
    }

    private func installCLIReportingErrors() {
        do {
            try agentSupportInstaller.installCLI()
            refreshAgentSupportStatus()
        } catch {
            agentSupportErrorMessage = userFacingAgentSupportMessage(for: error)
        }
    }

    private func installSkillsReportingErrors() {
        do {
            try agentSupportInstaller.installSkills()
            refreshAgentSupportStatus()
        } catch {
            agentSupportErrorMessage = userFacingAgentSupportMessage(for: error)
        }
    }

    private func userFacingAgentSupportMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Cursor Operator could not update agent support."
    }
}

private struct CursorAgentSupportRow: View {
    let title: String
    let badge: String
    let destinationText: String
    let status: CursorAgentSupportInstallState
    let installTitle: String
    let install: () -> Void
    var reveal: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(badge)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                Text("to \(destinationText).")
                    .font(.callout)
                    .foregroundStyle(CursorTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(destinationText)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                if let reveal {
                    Button("Reveal in Finder") {
                        reveal()
                    }
                    .controlSize(.small)
                    .disabled(!status.isInstalled)
                }

                Button(installButtonTitle) {
                    install()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!status.canInstall)
            }
        }
        .padding(.vertical, 4)
    }

    private var installButtonTitle: String {
        switch status {
        case .installed:
            return "Installed"
        case .unmanaged:
            return "Manual"
        case .missing:
            return installTitle
        case .stale:
            return "Repair"
        }
    }
}

private func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if url.path.hasPrefix(home) {
        return "~" + url.path.dropFirst(home.count)
    }
    return url.path
}

private func skillDestinationText(_ statuses: [CursorAgentSupportComponentStatus]) -> String {
    statuses.map { displayPath($0.destination) }.joined(separator: ", ")
}

private func revealAgentSkill(_ statuses: [CursorAgentSupportComponentStatus]) {
    guard let installed = statuses.first(where: { $0.state.isInstalled }) else {
        return
    }
    NSWorkspace.shared.activateFileViewerSelecting([installed.destination])
}
