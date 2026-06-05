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

    @State private var defaultBranch: String

    init(model: RepositorySettingsModel, repository: OperatorRepository) {
        self.model = model
        self.repository = repository
        _defaultBranch = State(initialValue: repository.defaultBranch)
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
                TextField("Default branch", text: $defaultBranch)
                    .textFieldStyle(.roundedBorder)

                Button {
                    model.updateDefaultBranchReportingErrors(
                        repositoryID: repository.id,
                        defaultBranch: defaultBranch
                    )
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
            }
        }
        .padding(.vertical, 4)
    }
}
