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

    static func defaultBranchLabel(for repository: OperatorRepository) -> String {
        "Default branch for \(repository.name)"
    }

    static func saveDefaultBranchLabel(for repository: OperatorRepository) -> String {
        "Save default branch for \(repository.name)"
    }
}
