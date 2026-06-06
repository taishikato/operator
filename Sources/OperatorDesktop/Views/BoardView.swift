import SwiftUI

public struct BoardView: View {
    @StateObject private var model: TaskBoardModel
    private let store: OperatorStore

    public init(store: OperatorStore) {
        self.store = store
        _model = StateObject(wrappedValue: TaskBoardModel(store: store))
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                BoardToolbarView(model: model)

                TaskCreationFormView(model: model)

                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.projection.columns) { column in
                        BoardColumnView(model: model, column: column)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            InspectorPanelView(model: model)
                .frame(width: 320)
        }
        .onAppear {
            model.loadReportingErrors()
        }
        .onReceive(store.changes) {
            model.loadReportingErrors()
        }
    }
}

private struct BoardToolbarView: View {
    @ObservedObject var model: TaskBoardModel

    var body: some View {
        HStack(spacing: 12) {
            Picker("Filter by repository", selection: repositorySelection) {
                ForEach(model.projection.repositoryFilters) { filter in
                    Text(filter.name).tag(filter.id)
                }
            }
            .frame(width: 240)

            Spacer()

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
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

private struct TaskCreationFormView: View {
    @ObservedObject var model: TaskBoardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Task title", text: creationTitle)
                    .textFieldStyle(.roundedBorder)

                Picker("Task repository", selection: creationRepository) {
                    Text("Choose Repository").tag(Optional<UUID>.none)
                    ForEach(model.projection.repositoryFilters.filter { $0.id != nil }) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .frame(width: 220)

                Picker("Reasoning", selection: creationReasoning) {
                    ForEach(ReasoningEffortOption.all) { option in
                        Text(option.label).tag(option.effort)
                    }
                }
                .frame(width: 160)

                Button {
                    model.createTaskReportingErrors()
                } label: {
                    Label("Create Task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            TextEditor(text: creationPrompt)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 96)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }
                .accessibilityLabel("Task prompt")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

            VStack(spacing: 8) {
                if column.cards.isEmpty {
                    Text("Empty")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(column.cards) { card in
                        Button {
                            model.selectTask(card.id)
                        } label: {
                            TaskCardView(card: card, isSelected: model.selectedTaskID == card.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

                Button {
                    model.saveSelectedInspectorTaskReportingErrors()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
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
            }

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
