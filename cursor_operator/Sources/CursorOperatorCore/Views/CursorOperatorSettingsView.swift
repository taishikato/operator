import AppKit
import SwiftUI

public struct CursorOperatorSettingsView: View {
    private let appSpec: CursorOperatorAppSpec
    private let appDataURL: URL
    private let nodeResolver: any CursorNodeResolving
    private let agentSupportInstaller: any CursorAgentSupportInstalling
    private let operatorSettings: OperatorSettingsManager
    private let codexBinarySettings: any CodexBinarySettingsManaging
    private let codexStatusChecker: any CodexStatusChecking
    @StateObject private var credentialModel: CursorCredentialSettingsModel
    @State private var apiKeyDraft = ""
    @State private var defaultHarness: CursorHarness = .cursor
    @State private var codexBinaryOverrideDraft = ""
    @State private var codexConfiguration = CodexBinaryConfiguration(detectedBinaryURL: nil, overrideBinaryURL: nil)
    @State private var codexStatus: CodexStatus = .notChecked
    @State private var codexSettingsErrorMessage: String?
    @State private var nodeProjection = CursorNodeSettingsProjection(result: .failure(.missingCompatibleNode))
    @State private var agentSupportStatus: CursorAgentSupportStatus?
    @State private var agentSupportErrorMessage: String?

    public init(
        appSpec: CursorOperatorAppSpec = .mvp,
        appDataURL: URL,
        credentialModel: CursorCredentialSettingsModel = CursorCredentialSettingsModel(),
        nodeResolver: any CursorNodeResolving = CursorNodeExecutableResolver(),
        agentSupportInstaller: any CursorAgentSupportInstalling = CursorAgentSupportInstaller.bundled(),
        operatorSettings: OperatorSettingsManager = OperatorSettingsManager(),
        codexBinarySettings: any CodexBinarySettingsManaging = CodexBinarySettings(),
        codexStatusChecker: any CodexStatusChecking = CodexStatusChecker()
    ) {
        self.appSpec = appSpec
        self.appDataURL = appDataURL
        self.nodeResolver = nodeResolver
        self.agentSupportInstaller = agentSupportInstaller
        self.operatorSettings = operatorSettings
        self.codexBinarySettings = codexBinarySettings
        self.codexStatusChecker = codexStatusChecker
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

            Section("Operator") {
                LabeledContent("App", value: appSpec.displayName)
                Picker("Default Harness", selection: $defaultHarness) {
                    Text("Cursor").tag(CursorHarness.cursor)
                    Text("Codex").tag(CursorHarness.codex)
                }
                .pickerStyle(.segmented)
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

            Section("Codex CLI") {
                LabeledContent("Binary", value: codexConfiguration.displayPath)
                LabeledContent("Status", value: codexStatus.title)
                Text(codexStatus.message)
                    .foregroundStyle(CursorTheme.textSecondary)

                TextField("Absolute Codex binary path", text: $codexBinaryOverrideDraft)

                HStack {
                    Button("Save Path") {
                        saveCodexBinaryOverrideReportingErrors()
                    }

                    Button("Clear Path") {
                        codexBinaryOverrideDraft = ""
                        saveCodexBinaryOverrideReportingErrors()
                    }

                    Button("Check Status") {
                        Task { await checkCodexStatusReportingErrors() }
                    }
                }

                if let codexSettingsErrorMessage {
                    Label(codexSettingsErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(CursorTheme.danger)
                }
            }

            Section("Agent Support") {
                if let agentSupportStatus {
                    CursorAgentSupportRow(
                        title: "CLI",
                        badge: "operator",
                        destinationText: displayPath(agentSupportStatus.cli.destination),
                        status: agentSupportStatus.cli.state,
                        installTitle: "Install CLI"
                    ) {
                        installCLIReportingErrors()
                    }

                    CursorAgentSupportRow(
                        title: "Agent Skill",
                        badge: "/operator",
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .containerBackground(CursorTheme.bgContent, for: .window)
        .preferredColorScheme(.dark)
        .onAppear {
            refreshDefaultHarness()
            refreshCodexConfiguration()
            refreshNodeProjection()
            refreshAgentSupportStatus()
        }
        .onChange(of: defaultHarness) { _, newValue in
            saveDefaultHarnessReportingErrors(newValue)
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

    private func refreshDefaultHarness() {
        defaultHarness = operatorSettings.defaultHarness()
    }

    private func saveDefaultHarnessReportingErrors(_ harness: CursorHarness) {
        do {
            try operatorSettings.setDefaultHarness(harness)
            codexSettingsErrorMessage = nil
        } catch {
            codexSettingsErrorMessage = userFacingSettingsMessage(for: error)
            refreshDefaultHarness()
        }
    }

    private func refreshCodexConfiguration() {
        do {
            codexConfiguration = try codexBinarySettings.configuration()
            codexBinaryOverrideDraft = codexConfiguration.overrideBinaryURL?.path ?? ""
            codexSettingsErrorMessage = nil
        } catch {
            codexConfiguration = CodexBinaryConfiguration(detectedBinaryURL: nil, overrideBinaryURL: nil)
            codexSettingsErrorMessage = userFacingSettingsMessage(for: error)
        }
    }

    private func saveCodexBinaryOverrideReportingErrors() {
        do {
            try codexBinarySettings.setOverridePath(codexBinaryOverrideDraft)
            refreshCodexConfiguration()
        } catch {
            codexSettingsErrorMessage = userFacingSettingsMessage(for: error)
        }
    }

    private func checkCodexStatusReportingErrors() async {
        do {
            let configuration = try codexBinarySettings.configuration()
            codexConfiguration = configuration
            codexStatus = await codexStatusChecker.checkStatus(binaryURL: configuration.effectiveBinaryURL)
            codexSettingsErrorMessage = nil
        } catch {
            codexStatus = .notFound
            codexSettingsErrorMessage = userFacingSettingsMessage(for: error)
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
        return "Operator could not update agent support."
    }

    private func userFacingSettingsMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Operator could not update settings."
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
