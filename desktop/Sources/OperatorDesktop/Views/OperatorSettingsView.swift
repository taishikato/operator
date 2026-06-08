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
                LabeledContent("Detected binary", value: model.codexDetectedBinaryPath)
                LabeledContent("Active binary", value: model.codexBinaryPath)

                HStack(spacing: 8) {
                    TextField("Absolute Codex binary path", text: $model.codexBinaryOverrideDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(RepositorySettingsAccessibility.codexBinaryOverrideLabel)

                    Button {
                        model.saveCodexBinaryOverrideReportingErrors()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .accessibilityLabel(RepositorySettingsAccessibility.saveCodexBinaryOverrideLabel)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.codexStatus.title)
                            .font(.headline)
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
                    .accessibilityLabel(RepositorySettingsAccessibility.refreshCodexStatusLabel)
                }

                if let codexErrorMessage = model.codexErrorMessage {
                    Text(codexErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Operator") {
                LabeledContent(RepositorySettingsAccessibility.appDataPathLabel, value: model.appDataPath)
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
        .padding()
        .onAppear {
            model.loadRepositoriesReportingErrors()
        }
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
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(repository.name) {
                Text(repository.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                TextField("Default branch", text: defaultBranchBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(RepositorySettingsAccessibility.defaultBranchLabel(for: repository))

                Button {
                    model.updateDefaultBranchReportingErrors(
                        repositoryID: repository.id,
                        defaultBranch: model.defaultBranchDraft(for: repository.id)
                    )
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .accessibilityLabel(RepositorySettingsAccessibility.saveDefaultBranchLabel(for: repository))
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
    static let codexBinaryOverrideLabel = "Codex binary override"
    static let saveCodexBinaryOverrideLabel = "Save Codex binary override"
    static let refreshCodexStatusLabel = "Refresh Codex status"
    static let appDataPathLabel = "Operator app data path"
    static let aboutLabel = "About Operator"

    static func defaultBranchLabel(for repository: OperatorRepository) -> String {
        "Default branch for \(repository.name)"
    }

    static func saveDefaultBranchLabel(for repository: OperatorRepository) -> String {
        "Save default branch for \(repository.name)"
    }
}
