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
            .scrollContentBackground(.hidden)
            .background(CursorTheme.bgChrome)
            .safeAreaInset(edge: .bottom) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .font(.body13)
                        .foregroundStyle(CursorTheme.textSecondary)
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
                CursorArchivedView(store: store)
                    .navigationTitle("Archived")
            }
        }
        .containerBackground(CursorTheme.bgContent, for: .window)
        .preferredColorScheme(.dark)
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
    @State private var showCreateTaskSheet = false
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
                    .foregroundStyle(CursorTheme.danger)
            }

            setupStatusView

            Text("Cursor Cloud Agent starts from the remote default branch and excludes local-only changes.")
                .font(.callout)
                .foregroundStyle(CursorTheme.textSecondary)

            HStack(alignment: .top, spacing: 16) {
                ForEach(shell.board.columns) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(column.title)
                            .font(.rowTitle)
                            .foregroundStyle(CursorTheme.textPrimary)

                        if projectionColumn(for: column.id).cards.isEmpty {
                            VStack(spacing: 8) {
                                Text(shell.board.emptyState.title)
                                    .font(.rowTitle)
                                    .foregroundStyle(CursorTheme.textPrimary)
                                Text(shell.board.emptyState.message)
                                    .font(.caption)
                                    .foregroundStyle(CursorTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .padding(12)
                            .background(CursorTheme.surfaceWash, in: RoundedRectangle(cornerRadius: CursorTheme.radiusLG))
                        .overlay(
                            RoundedRectangle(cornerRadius: CursorTheme.radiusLG)
                                .stroke(CursorTheme.borderSubtle, lineWidth: 1)
                        )
                        } else {
                            ForEach(projectionColumn(for: column.id).cards) { card in
                                CursorTaskCardView(card: card) {
                                    model.sendReportingErrors(taskID: card.id)
                                } edit: {
                                    presentEditTaskSheet(taskID: card.id)
                                } openInCursor: {
                                    model.openInCursorReportingErrors(taskID: card.id)
                                } markDone: {
                                    model.markDoneReportingErrors(taskID: card.id)
                                } archive: {
                                    model.archiveReportingErrors(taskID: card.id)
                                }
                                .sendDisabled(!model.setupStatus.canSend || model.isSending(taskID: card.id))
                                .sendDisabledReason(model.isSending(taskID: card.id) ? "Send already in progress." : model.setupStatus.sendDisabledReason)
                                .sendStatusText(model.sendStatusText(taskID: card.id))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Text("App data: \(appDataURL.path)")
                .font(.caption)
                .foregroundStyle(CursorTheme.textPlaceholder)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(appDataURL.path)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem {
                Button {
                    presentCreateTaskSheet()
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .help("New Task")
                .disabled(model.repositories.isEmpty)
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
            model.resumeRunMonitoringReportingErrors()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorOperatorNewTaskCommand)) { _ in
            presentCreateTaskSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorOperatorAddRepositoryCommand)) { _ in
            selectRepositoryFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorOperatorCredentialsChanged)) { _ in
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
        .sheet(isPresented: $showCreateTaskSheet) {
            CursorTaskCreationSheet(model: model, isPresented: $showCreateTaskSheet)
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

    private var setupStatusView: some View {
        HStack(spacing: 14) {
            setupStatusLabel(
                model.setupStatus.repositoryMessage,
                systemImage: model.setupStatus.repositoryIconName,
                isValid: isRepositoryValid
            )
            setupStatusLabel(
                model.setupStatus.credentialMessage,
                systemImage: model.setupStatus.credentialIconName,
                isValid: isCredentialValid
            )
            setupStatusLabel(
                model.setupStatus.nodeMessage,
                systemImage: model.setupStatus.nodeIconName,
                isValid: isNodeValid
            )
        }
        .font(.callout)
    }

    private var isRepositoryValid: Bool {
        switch model.setupStatus.repositoryState {
        case .missing:
            false
        case .registered:
            true
        }
    }

    private var isCredentialValid: Bool {
        model.setupStatus.credentialState == .ready
    }

    private var isNodeValid: Bool {
        switch model.setupStatus.nodeState {
        case .missing:
            false
        case .ready:
            true
        }
    }

    private func setupStatusLabel(
        _ title: String,
        systemImage: String,
        isValid: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(isValid ? CursorTheme.green : CursorTheme.orange)
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

    private func presentCreateTaskSheet() {
        showCreateTaskSheet = model.prepareCreateTaskDraftForPresentation()
    }

    private func presentEditTaskSheet(taskID: UUID) {
        showCreateTaskSheet = model.prepareEditTaskDraftForPresentation(taskID: taskID)
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
                .font(.pageTitle)
                .foregroundStyle(CursorTheme.textPrimary)

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
                .foregroundStyle(CursorTheme.textSecondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(CursorGhostButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button {
                    save()
                    dismiss()
                } label: {
                    Label("Save Repository", systemImage: "checkmark")
                }
                .buttonStyle(CursorPrimaryButtonStyle())
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
    let send: () -> Void
    let edit: () -> Void
    let openInCursor: () -> Void
    let markDone: () -> Void
    let archive: () -> Void
    @Environment(\.cursorOperatorSendDisabled) private var sendDisabled
    @Environment(\.cursorOperatorSendDisabledReason) private var sendDisabledReason
    @Environment(\.cursorOperatorSendStatusText) private var sendStatusText

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title)
                .font(.rowTitle)
                .foregroundStyle(CursorTheme.textPrimary)

            if let sendStatusText {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(sendStatusText)
                        .font(.caption)
                        .foregroundStyle(CursorTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            if let runStatusText = card.runStatusText {
                Label(runStatusText, systemImage: card.status == .done ? "checkmark.circle" : "clock")
                    .font(.caption)
                    .foregroundStyle(card.status == .done ? CursorTheme.green : CursorTheme.textSecondary)
            }

            if sendStatusText == nil, let failedSendMessage = card.failedSendMessage {
                Label(failedSendMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(CursorTheme.orange)
            }

            HStack(spacing: 8) {
                if card.status == .ready {
                    Button("Edit", action: edit)
                        .buttonStyle(CursorGhostButtonStyle())

                    Button(sendStatusText == nil ? "Send" : "Sending", action: send)
                        .buttonStyle(CursorPrimaryButtonStyle())
                        .disabled(sendDisabled)
                        .help(sendDisabled ? sendDisabledReason : "")
                }
                if card.canOpenInCursor {
                    Button("Open in Cursor", action: openInCursor)
                        .buttonStyle(CursorGhostButtonStyle())
                }
                if card.status == .running {
                    Button("Done", action: markDone)
                        .buttonStyle(CursorGhostButtonStyle())
                }
                if card.status != .archived {
                    Button("Archive", action: archive)
                        .buttonStyle(CursorGhostButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CursorTheme.surfaceWash, in: RoundedRectangle(cornerRadius: CursorTheme.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusLG)
                .stroke(CursorTheme.borderSubtle, lineWidth: 1)
        )
    }
}

private struct CursorOperatorSendDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct CursorOperatorSendDisabledReasonKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct CursorOperatorSendStatusTextKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private extension EnvironmentValues {
    var cursorOperatorSendDisabled: Bool {
        get { self[CursorOperatorSendDisabledKey.self] }
        set { self[CursorOperatorSendDisabledKey.self] = newValue }
    }

    var cursorOperatorSendDisabledReason: String {
        get { self[CursorOperatorSendDisabledReasonKey.self] }
        set { self[CursorOperatorSendDisabledReasonKey.self] = newValue }
    }

    var cursorOperatorSendStatusText: String? {
        get { self[CursorOperatorSendStatusTextKey.self] }
        set { self[CursorOperatorSendStatusTextKey.self] = newValue }
    }
}

private extension View {
    func sendDisabled(_ disabled: Bool) -> some View {
        environment(\.cursorOperatorSendDisabled, disabled)
    }

    func sendDisabledReason(_ reason: String) -> some View {
        environment(\.cursorOperatorSendDisabledReason, reason)
    }

    func sendStatusText(_ text: String?) -> some View {
        environment(\.cursorOperatorSendStatusText, text)
    }
}

private struct CursorTaskCreationSheet: View {
    @ObservedObject var model: CursorBoardModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Task title", text: titleBinding)
                .textFieldStyle(.plain)
                .font(.pageTitle)
                .foregroundStyle(CursorTheme.textPrimary)

            HStack {
                Picker("Repository", selection: repositoryBinding) {
                    ForEach(model.repositories) { repository in
                        Text(repository.name).tag(Optional(repository.id))
                    }
                }
                .pickerStyle(.menu)

                Toggle("Auto-create PR", isOn: autoCreatePRBinding)
                    .toggleStyle(.checkbox)
            }

            TextEditor(text: promptBinding)
                .font(.body)
                .frame(minHeight: 160)
                .accessibilityLabel("Task prompt")

            if let preview = preview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Send Preview")
                        .font(.rowTitle)
                        .foregroundStyle(CursorTheme.textPrimary)
                    Text("Repository: \(preview.repositoryURL.absoluteString)")
                    Text("Starting ref: \(preview.startingRef)")
                    Text("Model: \(preview.model)")
                    Text("Auto-create PR: \(preview.autoCreatePR ? "On" : "Off")")
                    Text(preview.prompt)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .font(.callout)
                .foregroundStyle(CursorTheme.textSecondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(CursorGhostButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button {
                    if model.saveTaskDraftReportingErrors() {
                        isPresented = false
                    }
                } label: {
                    Label(primaryActionTitle, systemImage: primaryActionIconName)
                }
                .buttonStyle(CursorPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var preview: CursorSendPreview? {
        guard let repositoryID = model.creationDraft.repositoryID,
              let repository = model.repositories.first(where: { $0.id == repositoryID }) else {
            return nil
        }
        let task = CursorTask.new(
            repositoryID: repository.id,
            title: model.creationDraft.title,
            prompt: model.creationDraft.prompt,
            autoCreatePR: model.creationDraft.autoCreatePR
        )
        return try? CursorSendPreview(task: task, repository: repository)
    }

    private var primaryActionTitle: String {
        model.editingTaskID == nil ? "Create Task" : "Save Changes"
    }

    private var primaryActionIconName: String {
        model.editingTaskID == nil ? "plus" : "checkmark"
    }

    private var titleBinding: Binding<String> {
        Binding {
            model.creationDraft.title
        } set: {
            model.creationDraft.title = $0
        }
    }

    private var promptBinding: Binding<String> {
        Binding {
            model.creationDraft.prompt
        } set: {
            model.creationDraft.prompt = $0
        }
    }

    private var repositoryBinding: Binding<UUID?> {
        Binding {
            model.creationDraft.repositoryID
        } set: {
            model.creationDraft.repositoryID = $0
        }
    }

    private var autoCreatePRBinding: Binding<Bool> {
        Binding {
            model.creationDraft.autoCreatePR
        } set: {
            model.creationDraft.autoCreatePR = $0
        }
    }
}

private struct CursorArchivedView: View {
    @StateObject private var model: CursorBoardModel

    init(store: CursorOperatorStore) {
        _model = StateObject(wrappedValue: CursorBoardModel(store: store))
    }

    var body: some View {
        Group {
            if model.projection.archivedCards.isEmpty {
                ContentUnavailableView(
                    "No Archived Tasks",
                    systemImage: "archivebox",
                    description: Text("Archived Cursor tasks stay out of the default board.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.projection.archivedCards) { card in
                            CursorTaskCardView(card: card) {
                            } edit: {
                            } openInCursor: {
                                model.openInCursorReportingErrors(taskID: card.id)
                            } markDone: {
                            } archive: {
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .onAppear {
            model.loadReportingErrors()
        }
    }
}
