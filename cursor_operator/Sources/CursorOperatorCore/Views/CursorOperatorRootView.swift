import AppKit
import SwiftUI

public struct CursorOperatorRootView: View {
    private let shell: CursorOperatorShellSpec
    private let appDataURL: URL
    private let store: CursorOperatorStore

    @State private var selection: CursorOperatorSidebarSelection
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(
        store: CursorOperatorStore,
        shell: CursorOperatorShellSpec = .mvp,
        appDataURL: URL
    ) {
        self.store = store
        self.shell = shell
        self.appDataURL = appDataURL
        _selection = State(initialValue: CursorOperatorSidebarSelection(destination: shell.launchDestination) ?? .board)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: selectionBinding) {
                Label("Board", systemImage: "rectangle.grid.3x2")
                    .tag(CursorOperatorSidebarSelection.board)

                Label("Archived", systemImage: "archivebox")
                    .tag(CursorOperatorSidebarSelection.archived)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch selection {
            case .board:
                CursorBoardView(shell: shell, store: store, appDataURL: appDataURL)
                    .navigationTitle("Board")
            case .archived:
                CursorArchivedView()
                    .navigationTitle("Archived")
            }
        }
        .containerBackground(.thickMaterial, for: .window)
        .background {
            Button("Toggle Sidebar", action: toggleSidebar)
                .keyboardShortcut("b", modifiers: .command)
                .hidden()
        }
    }

    private var selectionBinding: Binding<CursorOperatorSidebarSelection?> {
        Binding {
            selection
        } set: { newValue in
            if let newValue {
                selection = newValue
            }
        }
    }

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}

private struct CursorBoardView: View {
    let shell: CursorOperatorShellSpec
    @StateObject private var model: CursorBoardModel
    @State private var defaultBranchDraft = ""
    let appDataURL: URL

    init(shell: CursorOperatorShellSpec, store: CursorOperatorStore, appDataURL: URL) {
        self.shell = shell
        self.appDataURL = appDataURL
        _model = StateObject(wrappedValue: CursorBoardModel(store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Text("Cursor Cloud Agent starts from the remote default branch.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                ForEach(shell.board.columns) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(column.title)
                            .font(.headline)

                        if projectionColumn(for: column.id).cards.isEmpty {
                            VStack(spacing: 8) {
                                Text(shell.board.emptyState.title)
                                    .font(.callout.weight(.medium))
                                Text(shell.board.emptyState.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .padding(12)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        } else {
                            ForEach(projectionColumn(for: column.id).cards) { card in
                                CursorTaskCardView(card: card) {
                                    model.markDoneReportingErrors(taskID: card.id)
                                } archive: {
                                    model.archiveReportingErrors(taskID: card.id)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Text("App data: \(appDataURL.path)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(appDataURL.path)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem {
                Button {
                    model.createLocalTaskReportingErrors()
                } label: {
                    Label("New Local Task", systemImage: "plus")
                }
                .help("New Local Task")
            }

            ToolbarItem {
                Button(action: selectRepositoryFolder) {
                    Label("Add Repository", systemImage: "folder.badge.plus")
                }
                .help("Add Repository")
            }
        }
        .onAppear {
            model.loadReportingErrors()
        }
        .onChange(of: model.pendingRepositoryDraft) { _, draft in
            defaultBranchDraft = draft?.defaultBranch ?? ""
        }
        .sheet(item: pendingRepositoryDraftBinding) { draft in
            CursorRepositoryReviewSheet(
                draft: draft,
                defaultBranch: $defaultBranchDraft
            ) {
                model.savePendingRepositoryReportingErrors(defaultBranch: defaultBranchDraft)
            }
        }
    }

    private func projectionColumn(for id: CursorBoardColumnID) -> CursorBoardColumnProjection {
        model.projection.columns.first { $0.id == id } ?? CursorBoardColumnProjection(id: id, title: "", cards: [])
    }

    private var pendingRepositoryDraftBinding: Binding<CursorRepositoryRegistrationDraft?> {
        Binding {
            model.pendingRepositoryDraft
        } set: { _ in }
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

        model.prepareRepositoryRegistrationReportingErrors(at: repositoryURL)
    }
}

extension CursorRepositoryRegistrationDraft: Identifiable {
    public var id: String { localPath }
}

private struct CursorRepositoryReviewSheet: View {
    let draft: CursorRepositoryRegistrationDraft
    @Binding var defaultBranch: String
    let save: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Repository")
                .font(.title3.weight(.semibold))

            LabeledContent("GitHub") {
                Text(draft.githubURL.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(draft.githubURL.absoluteString)
            }

            LabeledContent("Local checkout") {
                Text(draft.localPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(draft.localPath)
            }

            LabeledContent("Default branch") {
                TextField("main", text: $defaultBranch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }

            Text("Cursor Cloud Agent starts from the remote default branch. Local-only dirty files and unpushed commits are not included.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    save()
                    dismiss()
                } label: {
                    Label("Save Repository", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct CursorTaskCardView: View {
    let card: CursorTaskCardProjection
    let markDone: () -> Void
    let archive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title)
                .font(.callout.weight(.medium))

            HStack {
                Button("Done", action: markDone)
                    .controlSize(.small)
                Button("Archive", action: archive)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CursorArchivedView: View {
    var body: some View {
        ContentUnavailableView(
            "No Archived Tasks",
            systemImage: "archivebox",
            description: Text("Archived Cursor tasks stay out of the default board.")
        )
    }
}
