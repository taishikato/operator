import AppKit
import SwiftUI

public struct BoardView: View {
    @StateObject private var model: TaskBoardModel
    @StateObject private var repositorySettingsModel: RepositorySettingsModel
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
        _repositorySettingsModel = StateObject(wrappedValue: RepositorySettingsModel(store: store))
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                BoardToolbarView(
                    model: model,
                    repositorySettingsModel: repositorySettingsModel,
                    onAddRepository: selectRepositoryFolder,
                    onNewTicket: { showCreateSheet = true }
                )

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

    private func selectRepositoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let repositoryURL = panel.url else {
            return
        }

        repositorySettingsModel.addRepositoryReportingErrors(at: repositoryURL)
    }
}

private struct BoardToolbarView: View {
    @ObservedObject var model: TaskBoardModel
    @ObservedObject var repositorySettingsModel: RepositorySettingsModel
    let onAddRepository: () -> Void
    let onNewTicket: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(model.projection.repositoryFilters) { filter in
                    Button(filter.name) {
                        model.selectRepository(filter.id)
                    }
                }
            } label: {
                DropdownLabel(title: selectedRepositoryName)
            }
            .menuStyle(.button)
            .buttonStyle(AddRepositoryButtonStyle())
            .frame(width: 200)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let errorMessage = repositorySettingsModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: onAddRepository) {
                    Label("Add Repository", systemImage: "plus")
                }
                .buttonStyle(AddRepositoryButtonStyle())
                .disabled(repositorySettingsModel.isAddingRepository)

                Button(action: onNewTicket) {
                    Label("New Ticket", systemImage: "plus")
                }
                .buttonStyle(NewTicketButtonStyle())
            }
        }
    }

    private var selectedRepositoryName: String {
        model.projection.repositoryFilters
            .first { $0.id == model.selectedRepositoryID }?
            .name ?? RepositoryFilterOption.allRepositories.name
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
                    Menu {
                        Button("Choose Repository") {
                            model.creationDraft.repositoryID = nil
                        }
                        ForEach(model.projection.repositoryFilters.filter { $0.id != nil }) { filter in
                            Button(filter.name) {
                                model.creationDraft.repositoryID = filter.id
                            }
                        }
                    } label: {
                        DropdownLabel(title: creationRepositoryName)
                    }
                    .menuStyle(.button)
                    .buttonStyle(AddRepositoryButtonStyle())
                    .frame(maxWidth: .infinity)

                    Menu {
                        ForEach(ReasoningEffortOption.all) { option in
                            Button(option.label) {
                                model.creationDraft.reasoningEffort = option.effort
                            }
                        }
                    } label: {
                        DropdownLabel(title: creationReasoningLabel)
                    }
                    .menuStyle(.button)
                    .buttonStyle(AddRepositoryButtonStyle())
                    .frame(width: 180)
                }

                TextEditor(text: creationPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
                    .recessedFieldBackground()
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
                .buttonStyle(AddRepositoryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button {
                    if model.createTaskReportingErrors() {
                        isPresented = false
                    }
                } label: {
                    Label("Create Task", systemImage: "plus")
                }
                .buttonStyle(NewTicketButtonStyle())
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

    private var creationPrompt: Binding<String> {
        Binding {
            model.creationDraft.prompt
        } set: { prompt in
            model.creationDraft.prompt = prompt
        }
    }

    private var creationRepositoryName: String {
        guard let repositoryID = model.creationDraft.repositoryID else {
            return "Choose Repository"
        }
        return model.projection.repositoryFilters
            .first { $0.id == repositoryID }?
            .name ?? "Choose Repository"
    }

    private var creationReasoningLabel: String {
        model.creationDraft.reasoningEffort.displayLabel
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
                            BoardCardView(model: model, card: card)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Deepen the glass with a faint dark tint so the column reads as a
        // distinct surface against the window background without glaring.
        .glassEffect(.regular.tint(.black.opacity(0.18)), in: .rect(cornerRadius: 12))
    }
}

private struct BoardCardView: View {
    @ObservedObject var model: TaskBoardModel
    let card: TaskCardProjection
    @State private var isHovering = false
    @State private var isConfirmingArchive = false
    @State private var isHoveringArchiveIcon = false
    @State private var isHoveringCodexIcon = false

    var body: some View {
        Button {
            model.selectTask(card.id)
        } label: {
            TaskCardView(card: card, isSelected: model.selectedTaskID == card.id)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                codexControl
                archiveControl
            }
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            // Tooltip lives on the card (always present) so showing/hiding it
            // doesn't recreate the icon button and flicker its hover tracking.
            if isHoveringArchiveIcon {
                Text("Archive")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .fixedSize()
                    .padding(.trailing, 8)
                    .offset(y: 34)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Codex tooltip mirrors the archive one but sits under the codex
            // icon, which is one icon-slot to the left of the archive icon.
            if isHoveringCodexIcon, let codexHint {
                Text(codexHint)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .fixedSize()
                    .padding(.trailing, 34)
                    .offset(y: 34)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: isHoveringArchiveIcon)
        .animation(.easeOut(duration: 0.1), value: isHoveringCodexIcon)
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
    private var codexControl: some View {
        // Codex actions live next to the archive icon and reveal on hover,
        // mirroring the archive control. The "Sending..." spinner stays
        // visible even after the pointer leaves so progress is never lost.
        if card.codexSendLabel == "Sending..." {
            ProgressView()
                .controlSize(.small)
        } else if isHovering && card.canSendToCodex {
            Button {
                Task {
                    await model.sendTaskToCodexReportingErrors(taskID: card.id)
                }
            } label: {
                Image(systemName: "paperplane")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Send to Codex")
            // Tooltip is drawn by the card overlay so toggling it never resets
            // this button's hover tracking.
            .onHover { isHoveringCodexIcon = $0 }
        } else if isHovering && card.canOpenInCodexApp {
            Button {
                Task {
                    await model.openTaskInCodexAppReportingErrors(taskID: card.id)
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(card.codexOpenLabel)
            .onHover { isHoveringCodexIcon = $0 }
        }
    }

    /// Label shown in the codex icon's tooltip, matching whichever action the
    /// icon currently offers.
    private var codexHint: String? {
        if card.canSendToCodex { return card.codexSendLabel }
        if card.canOpenInCodexApp { return card.codexOpenLabel }
        return nil
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
                Image(systemName: "archivebox")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Archive task")
            // Only track hover here; the tooltip itself is drawn by the card
            // overlay so toggling it never resets this button's hover tracking.
            .onHover { hovering in
                isHoveringArchiveIcon = hovering
            }
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
        .glassEffect(.regular.tint(.black.opacity(0.18)), in: .rect)
    }
}

private struct TaskInspectorView: View {
    @ObservedObject var model: TaskBoardModel
    let inspector: TaskInspectorProjection
    @State private var isConfirmingArchive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(inspector.repositoryName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if inspector.isEditable {
                TextField("Task title", text: inspectorTitle)
                    .textFieldStyle(.roundedBorder)

                Menu {
                    ForEach(ReasoningEffortOption.all) { option in
                        Button(option.label) {
                            model.inspectorDraft?.reasoningEffort = option.effort
                        }
                    }
                } label: {
                    DropdownLabel(title: inspectorReasoningLabel)
                }
                .menuStyle(.button)
                .buttonStyle(AddRepositoryButtonStyle())
                .frame(maxWidth: .infinity)

                TextEditor(text: inspectorPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 220)
                    .recessedFieldBackground()
                    .accessibilityLabel("Inspector prompt")

                HStack(spacing: 10) {
                    Button {
                        model.saveSelectedInspectorTaskReportingErrors()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(AddRepositoryButtonStyle())

                    Button {
                        Task {
                            await model.sendSelectedInspectorTaskToCodexReportingErrors()
                        }
                    } label: {
                        Label(inspector.codexSendLabel, systemImage: "paperplane")
                    }
                    .buttonStyle(NewTicketButtonStyle())
                    .disabled(!inspector.canSendToCodex)
                }
            } else {
                Text(inspector.title)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 6) {
                    BadgeView(text: inspector.reasoningEffort.displayLabel)
                }

                Text(inspector.prompt)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .recessedFieldBackground()
                    .accessibilityLabel("Read-only inspector prompt")

                if inspector.canOpenInCodexApp {
                    Button {
                        Task {
                            await model.openTaskInCodexAppReportingErrors(taskID: inspector.id)
                        }
                    } label: {
                        Label(inspector.codexOpenLabel, systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(NewTicketButtonStyle())
                }
            }

            Divider()

            archiveButton

            Spacer()
        }
        .onChange(of: inspector.id) {
            isConfirmingArchive = false
        }
    }

    @ViewBuilder
    private var archiveButton: some View {
        if isConfirmingArchive {
            Button(role: .destructive) {
                model.archiveTaskReportingErrors(taskID: inspector.id)
                isConfirmingArchive = false
            } label: {
                Label("Confirm", systemImage: "archivebox")
            }
            .buttonStyle(AddRepositoryButtonStyle(foreground: ArchiveConfirmStyle.foreground))
            .accessibilityLabel("Confirm archive")
        } else {
            Button(role: .destructive) {
                isConfirmingArchive = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .buttonStyle(AddRepositoryButtonStyle())
            .accessibilityLabel("Archive task")
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

    private var inspectorReasoningLabel: String {
        (model.inspectorDraft?.reasoningEffort ?? inspector.reasoningEffort).displayLabel
    }
}

private enum ArchiveConfirmStyle {
    static let foreground = Color(red: 0.93, green: 0.50, blue: 0.46)
    static let background = Color(red: 0.55, green: 0.24, blue: 0.23).opacity(0.42)
}

private extension View {
    // A recessed input surface that sits inside the dark glass panels instead
    // of floating as a bright box.
    func recessedFieldBackground(cornerRadius: CGFloat = 10) -> some View {
        background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.08))
            }
    }
}

private enum NewTicketButtonColors {
    // oklch(97% 0.001 106.424)
    static let background = Color(red: 0.960863, green: 0.960863, blue: 0.957902)
    // oklch(14.7% 0.004 49.25)
    static let foreground = Color(red: 0.046959, green: 0.039356, blue: 0.035544)
}

private struct NewTicketButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(NewTicketButtonColors.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        NewTicketButtonColors.background.opacity(configuration.isPressed ? 0.85 : 1)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DropdownLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AddRepositoryButtonStyle: ButtonStyle {
    var foreground: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.35 : 0.25))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
