import AppKit
import SwiftUI

public struct OperatorSettingsView: View {
    @StateObject private var model: RepositorySettingsModel

    public init(store: OperatorStore, appDataURL: URL? = nil) {
        _model = StateObject(wrappedValue: RepositorySettingsModel(store: store, appDataURL: appDataURL))
    }

    public var body: some View {
        Form {
            Section("Repositories") {
                if model.repositories.isEmpty {
                    Text("No repositories registered")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.repositories) { repository in
                        RepositorySettingsRow(model: model, repository: repository)
                    }
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Codex") {
                LabeledContent("Detected binary") {
                    PathText(model.codexDetectedBinaryPath)
                }
                LabeledContent("Active binary") {
                    PathText(model.codexBinaryPath)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.codexStatus.title)
                            .fontWeight(.medium)
                        Text(model.codexStatus.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        model.refreshCodexStatus()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityLabel(RepositorySettingsAccessibility.refreshCodexStatusLabel)
                }

                if let codexErrorMessage = model.codexErrorMessage {
                    Text(codexErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Agent Support") {
                if let agentSupportStatus = model.agentSupportStatus {
                    AgentSupportRow(
                        title: "CLI",
                        badge: "operator",
                        destinationText: displayPath(agentSupportStatus.cli.destination),
                        status: agentSupportStatus.cli.state,
                        installTitle: "Install CLI",
                        installAccessibilityLabel: RepositorySettingsAccessibility.installCLILabel
                    ) {
                        model.installCLIReportingErrors()
                    }

                    AgentSupportRow(
                        title: "Agent Skill",
                        badge: "/operator",
                        destinationText: skillDestinationText(agentSupportStatus.skills),
                        status: agentSupportStatus.skillsState,
                        installTitle: "Install Skill",
                        installAccessibilityLabel: RepositorySettingsAccessibility.installAgentSkillLabel,
                        revealAccessibilityLabel: RepositorySettingsAccessibility.revealAgentSkillLabel
                    ) {
                        model.installSkillsReportingErrors()
                    } reveal: {
                        revealAgentSkill(agentSupportStatus.skills)
                    }
                } else {
                    Text("Agent support unavailable")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let agentSupportErrorMessage = model.agentSupportErrorMessage {
                    Text(agentSupportErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Operator") {
                LabeledContent(RepositorySettingsAccessibility.appDataPathLabel) {
                    PathText(model.appDataPath)
                }
                LabeledContent("App", value: model.aboutAppName)
                LabeledContent("Minimum macOS", value: model.aboutMinimumMacOS)
            }

            Section(RepositorySettingsAccessibility.aboutLabel) {
                Text("Operator is a local Codex trigger and navigation surface. It does not collect Codex credentials or track Codex completion.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // Match the main window's translucent surface.
        .containerBackground(.thickMaterial, for: .window)
        .onAppear {
            model.loadRepositoriesReportingErrors()
        }
    }
}

private struct AgentSupportRow: View {
    let title: String
    let badge: String
    let destinationText: String
    let status: OperatorAgentSupportInstallState
    let installTitle: String
    let installAccessibilityLabel: String
    var revealAccessibilityLabel: String?
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(destinationText)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                if let reveal, let revealAccessibilityLabel {
                    Button("Reveal in Finder") {
                        reveal()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(!status.isInstalled)
                    .accessibilityLabel(revealAccessibilityLabel)
                }

                Button(installButtonTitle) {
                    install()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(!status.canInstall)
                .accessibilityLabel(installAccessibilityLabel)
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

/// A long filesystem path rendered as a single quiet line; the full value is
/// available on hover.
private struct PathText: View {
    let path: String

    init(_ path: String) {
        self.path = path
    }

    var body: some View {
        Text(path)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(path)
    }
}

private struct RepositorySettingsRow: View {
    @ObservedObject var model: RepositorySettingsModel
    let repository: OperatorRepository

    init(model: RepositorySettingsModel, repository: OperatorRepository) {
        self.model = model
        self.repository = repository
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(repository.name)
                    .fontWeight(.medium)

                Spacer()

                PathText(repository.path)
            }

            LabeledContent("Default branch") {
                HStack(spacing: 8) {
                    TextField("main", text: defaultBranchBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .accessibilityLabel(RepositorySettingsAccessibility.defaultBranchLabel(for: repository))

                    Button("Save") {
                        model.updateDefaultBranchReportingErrors(
                            repositoryID: repository.id,
                            defaultBranch: model.defaultBranchDraft(for: repository.id)
                        )
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityLabel(RepositorySettingsAccessibility.saveDefaultBranchLabel(for: repository))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var defaultBranchBinding: Binding<String> {
        Binding {
            model.defaultBranchDraft(for: repository.id)
        } set: { defaultBranch in
            model.setDefaultBranchDraft(defaultBranch, for: repository.id)
        }
    }
}

enum RepositorySettingsAccessibility {
    static let refreshCodexStatusLabel = "Refresh Codex status"
    static let appDataPathLabel = "Operator app data path"
    static let aboutLabel = "About Operator"
    static let installCLILabel = "Install Operator CLI"
    static let installAgentSkillLabel = "Install Operator agent skill"
    static let revealAgentSkillLabel = "Reveal Operator agent skill in Finder"

    static func defaultBranchLabel(for repository: OperatorRepository) -> String {
        "Default branch for \(repository.name)"
    }

    static func saveDefaultBranchLabel(for repository: OperatorRepository) -> String {
        "Save default branch for \(repository.name)"
    }
}

private extension OperatorSettingsView {
    func skillDestinationText(_ skills: [OperatorAgentSupportComponentStatus]) -> String {
        skills.map { displayPath($0.destination) }.joined(separator: ", ")
    }

    func displayPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        if url.path == home {
            return "~"
        }
        if url.path.hasPrefix(home + "/") {
            return "~" + String(url.path.dropFirst(home.count))
        }
        return url.path
    }

    func revealAgentSkill(_ skills: [OperatorAgentSupportComponentStatus]) {
        guard let destination = skills.first?.destination else {
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([destination.deletingLastPathComponent()])
        }
    }
}
