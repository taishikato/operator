import SwiftUI

public struct BoardView: View {
    @StateObject private var model: TaskBoardModel
    @State private var showInspector = true
    @State private var showCreateSheet = false
    private let store: OperatorStore

    public init(
        store: OperatorStore,
        codexTrigger: (any CodexTaskSending)? = nil,
        codexOpener: (any CodexAppOpening)? = OSCodexAppOpener()
    ) {
        self.store = store
        _model = StateObject(wrappedValue: TaskBoardModel(
            store: store,
            codexTrigger: codexTrigger,
            codexOpener: codexOpener
        ))
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                BoardToolbarView(model: model, onNewTicket: { showCreateSheet = true })

                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.projection.columns) { column in
                        BoardColumnView(model: model, column: column)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if showInspector {
                Divider()

                InspectorPanelView(model: model)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing))
            }
        }
        .background {
            // Hidden control hosting the ⌥⌘B shortcut to toggle the inspector panel.
            Button("Toggle Inspector", action: toggleInspector)
                .keyboardShortcut("b", modifiers: [.command, .option])
                .hidden()
        }
        .sheet(isPresented: $showCreateSheet) {
            TaskCreationSheet(model: model, isPresented: $showCreateSheet)
        }
        .onAppear {
            model.loadReportingErrors()
        }
        .onReceive(store.changes) {
            model.loadReportingErrors()
        }
    }

    private func toggleInspector() {
        withAnimation {
            showInspector.toggle()
        }
    }
}

private struct BoardToolbarView: View {
    @ObservedObject var model: TaskBoardModel
    let onNewTicket: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Picker("Filter by repository", selection: repositorySelection) {
                ForEach(model.projection.repositoryFilters) { filter in
                    Text(filter.name).tag(filter.id)
                }
            }
            .frame(width: 240)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button(action: onNewTicket) {
                Label("New Ticket", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var repositorySelection: Binding<UUID?> {
        Binding {
            model.selectedRepositoryID
        } set: { repositoryID in
            model.selectRepository(repositoryID)
        }
    }
}

private struct TaskCreationSheet: View {
    @ObservedObject var model: TaskBoardModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Ticket")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                TextField("Task title", text: creationTitle)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Picker("Task repository", selection: creationRepository) {
                        Text("Choose Repository").tag(Optional<UUID>.none)
                        ForEach(model.projection.repositoryFilters.filter { $0.id != nil }) { filter in
                            Text(filter.name).tag(filter.id)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Picker("Reasoning", selection: creationReasoning) {
                        ForEach(ReasoningEffortOption.all) { option in
                            Text(option.label).tag(option.effort)
                        }
                    }
                    .frame(width: 180)
                }

                TextEditor(text: creationPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    }
                    .accessibilityLabel("Task prompt")
            }

            HStack {
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    if model.createTaskReportingErrors() {
                        isPresented = false
                    }
                } label: {
                    Label("Create Task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var creationTitle: Binding<String> {
        Binding {
            model.creationDraft.title
        } set: { title in
            model.creationDraft.title = title
        }
    }

    private var creationRepository: Binding<UUID?> {
        Binding {
            model.creationDraft.repositoryID
        } set: { repositoryID in
            model.creationDraft.repositoryID = repositoryID
        }
    }

    private var creationPrompt: Binding<String> {
        Binding {
            model.creationDraft.prompt
        } set: { prompt in
            model.creationDraft.prompt = prompt
        }
    }

    private var creationReasoning: Binding<ReasoningEffort> {
        Binding {
            model.creationDraft.reasoningEffort
        } set: { effort in
            model.creationDraft.reasoningEffort = effort
        }
    }
}

private struct BoardColumnView: View {
    @ObservedObject var model: TaskBoardModel
    let column: TaskBoardColumnProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(column.title)
                    .font(.headline)

                Spacer()

                Text("\(column.cards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    if column.cards.isEmpty {
                        Text("Empty")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(column.cards) { card in
                        VStack(spacing: 6) {
                            BoardCardView(model: model, card: card)

                            if card.canSendToCodex || card.codexSendLabel == "Sending..." {
                                Button {
                                    Task {
                                        await model.sendTaskToCodexReportingErrors(taskID: card.id)
                                    }
                                } label: {
                                    Label(card.codexSendLabel, systemImage: "paperplane")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!card.canSendToCodex)
                            }

                            if card.codexOpenTarget != nil {
                                Button {
                                    Task {
                                        await model.openTaskInCodexAppReportingErrors(taskID: card.id)
                                    }
                                } label: {
                                    Label(card.codexOpenLabel, systemImage: "arrow.up.forward.app")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!card.canOpenInCodexApp)
                            }
                        }
                    }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BoardCardView: View {
    @ObservedObject var model: TaskBoardModel
    let card: TaskCardProjection
    @State private var isHovering = false
    @State private var isConfirmingArchive = false

    var body: some View {
        Button {
            model.selectTask(card.id)
        } label: {
            TaskCardView(card: card, isSelected: model.selectedTaskID == card.id)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            archiveControl
                .padding(8)
        }
        .onHover { hovering in
            isHovering = hovering
            // Reset the confirmation prompt once the pointer leaves the card.
            if !hovering {
                isConfirmingArchive = false
            }
        }
        .contextMenu {
            Button {
                model.archiveTaskReportingErrors(taskID: card.id)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
    }

    @ViewBuilder
    private var archiveControl: some View {
        if isConfirmingArchive {
            Button {
                model.archiveTaskReportingErrors(taskID: card.id)
                isConfirmingArchive = false
            } label: {
                Text("Confirm")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ArchiveConfirmStyle.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ArchiveConfirmStyle.background, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Confirm archive")
        } else if isHovering {
            Button {
                isConfirmingArchive = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Archive task")
        }
    }
}

private struct TaskCardView: View {
    let card: TaskCardProjection
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                BadgeView(text: card.repositoryBadge)
                BadgeView(text: card.reasoningBadge)
                if let triggerStateBadge = card.triggerStateBadge {
                    BadgeView(text: triggerStateBadge)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
        }
    }
}

private struct InspectorPanelView: View {
    @ObservedObject var model: TaskBoardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if
                let selectedTaskID = model.selectedTaskID,
                let inspector = model.projection.inspector(taskID: selectedTaskID)
            {
                TaskInspectorView(model: model, inspector: inspector)
            } else {
                Text("No task selected")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.bar)
    }
}

private struct TaskInspectorView: View {
    @ObservedObject var model: TaskBoardModel
    let inspector: TaskInspectorProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(inspector.repositoryName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if inspector.isEditable {
                TextField("Task title", text: inspectorTitle)
                    .textFieldStyle(.roundedBorder)

                Picker("Reasoning", selection: inspectorReasoning) {
                    ForEach(ReasoningEffortOption.all) { option in
                        Text(option.label).tag(option.effort)
                    }
                }

                TextEditor(text: inspectorPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 220)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    }
                    .accessibilityLabel("Inspector prompt")

                HStack {
                    Button {
                        model.saveSelectedInspectorTaskReportingErrors()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            await model.sendSelectedInspectorTaskToCodexReportingErrors()
                        }
                    } label: {
                        Label(inspector.codexSendLabel, systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!inspector.canSendToCodex)
                }
            } else {
                Text(inspector.title)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 6) {
                    BadgeView(text: inspector.reasoningEffort.displayLabel)
                    BadgeView(text: "Read-only")
                }

                Text(inspector.prompt)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    }

                if inspector.codexOpenTarget != nil {
                    Button {
                        Task {
                            await model.openTaskInCodexAppReportingErrors(taskID: inspector.id)
                        }
                    } label: {
                        Label(inspector.codexOpenLabel, systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!inspector.canOpenInCodexApp)
                }
            }

            Divider()

            Button(role: .destructive) {
                model.archiveTaskReportingErrors(taskID: inspector.id)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private var inspectorTitle: Binding<String> {
        Binding {
            model.inspectorDraft?.title ?? inspector.title
        } set: { title in
            model.inspectorDraft?.title = title
        }
    }

    private var inspectorPrompt: Binding<String> {
        Binding {
            model.inspectorDraft?.prompt ?? inspector.prompt
        } set: { prompt in
            model.inspectorDraft?.prompt = prompt
        }
    }

    private var inspectorReasoning: Binding<ReasoningEffort> {
        Binding {
            model.inspectorDraft?.reasoningEffort ?? inspector.reasoningEffort
        } set: { effort in
            model.inspectorDraft?.reasoningEffort = effort
        }
    }
}

private enum ArchiveConfirmStyle {
    static let foreground = Color(red: 0.93, green: 0.50, blue: 0.46)
    static let background = Color(red: 0.55, green: 0.24, blue: 0.23).opacity(0.42)
}

private struct BadgeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}
