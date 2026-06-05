import AppKit
import SwiftUI

public struct OperatorSettingsView: View {
    @StateObject private var model: RepositorySettingsModel

    public init(store: OperatorStore) {
        _model = StateObject(wrappedValue: RepositorySettingsModel(store: store))
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

                Button {
                    selectRepositoryFolder()
                } label: {
                    Label("Add Repository", systemImage: "plus")
                }
                .disabled(model.isAddingRepository)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Operator") {
                LabeledContent("App", value: "Operator Desktop")
                LabeledContent("Minimum macOS", value: "15 Sequoia")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            model.loadRepositoriesReportingErrors()
        }
    }

    private func selectRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let repositoryURL = panel.url else {
            return
        }

        model.addRepositoryReportingErrors(at: repositoryURL)
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

                Button {
                    model.updateDefaultBranchReportingErrors(
                        repositoryID: repository.id,
                        defaultBranch: model.defaultBranchDraft(for: repository.id)
                    )
                } label: {
                    Label("Save", systemImage: "checkmark")
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
