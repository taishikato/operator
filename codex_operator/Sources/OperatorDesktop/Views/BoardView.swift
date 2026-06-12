import AppKit
import SwiftUI

public struct BoardView: View {
    @StateObject private var model: TaskBoardModel
    @StateObject private var repositorySettingsModel: RepositorySettingsModel
    @State private var showInspector = true
    @State private var showCreateSheet = false
    @State private var showRepositoryOnboarding = false
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
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage = model.errorMessage ?? repositorySettingsModel.errorMessage {
                ErrorBannerView(message: errorMessage)
            }

            HStack(alignment: .top, spacing: 24) {
                ForEach(model.projection.columns) { column in
                    BoardColumnView(model: model, column: column)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .inspector(isPresented: $showInspector) {
            InspectorPanelView(model: model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Picker("Repository", selection: repositoryFilterSelection) {
                        ForEach(model.projection.repositoryFilters) { filter in
                            Text(filter.name).tag(filter.id)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(selectedRepositoryName, systemImage: "line.3.horizontal.decrease")
                        .labelStyle(.titleAndIcon)
                }
            }

            ToolbarItem {
                Button(action: selectRepositoryFolder) {
                    Label("Add Repository", systemImage: "folder.badge.plus")
                }
                .help("Add Repository")
                .disabled(repositorySettingsModel.isAddingRepository)
            }

            ToolbarItem {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Ticket", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .help("New Ticket")
            }

            ToolbarItem {
                Button {
                    toggleInspector()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Inspector (⌥⌘B)")
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
        .sheet(isPresented: $showRepositoryOnboarding) {
            RepositoryOnboardingSheet(
                isPresented: $showRepositoryOnboarding,
                onAddRepository: selectRepositoryFolder
            )
        }
        .onAppear {
            loadBoardState()
        }
        .onReceive(store.changes) {
            model.loadReportingErrors()
            repositorySettingsModel.loadRepositoriesReportingErrors()
            syncRepositoryOnboardingPresentation()
        }
    }

    private var selectedRepositoryName: String {
        model.projection.repositoryFilters
            .first { $0.id == model.selectedRepositoryID }?
            .name ?? RepositoryFilterOption.allRepositories.name
    }

    private var repositoryFilterSelection: Binding<UUID?> {
        Binding {
            model.selectedRepositoryID
        } set: { repositoryID in
            model.selectRepository(repositoryID)
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

    private func loadBoardState() {
        model.loadReportingErrors()
        repositorySettingsModel.loadRepositoriesReportingErrors()
        syncRepositoryOnboardingPresentation()
    }

    private func syncRepositoryOnboardingPresentation() {
        showRepositoryOnboarding = repositorySettingsModel.shouldShowRepositoryOnboarding
    }
}

private struct ErrorBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
        }
        .font(.callout)
        .foregroundStyle(.red)
    }
}

private struct RepositoryOnboardingSheet: View {
    @Binding var isPresented: Bool
    let onAddRepository: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Repository")
                .font(.title3.weight(.semibold))

            Text("Register a Git repository before creating tickets or sending work to Codex.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("Later") {
                    isPresented = false
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

                Button {
                    isPresented = false
                    onAddRepository()
                } label: {
                    Label("Add Repository", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct TaskCreationSheet: View {
    @ObservedObject var model: TaskBoardModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Ticket")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                TextField("Task title", text: creationTitle)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Picker("Repository", selection: creationRepositorySelection) {
                        Text("Choose Repository").tag(UUID?.none)
                        ForEach(model.projection.repositoryFilters.filter { $0.id != nil }) { filter in
                            Text(filter.name).tag(filter.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Reasoning", selection: creationReasoningSelection) {
                        ForEach(ReasoningEffortOption.all) { option in
                            Text(option.label).tag(option.effort)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
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
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

                Button {
                    if model.createTaskReportingErrors() {
                        isPresented = false
                    }
                } label: {
                    Label("Create Task", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
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

    private var creationRepositorySelection: Binding<UUID?> {
        Binding {
            model.creationDraft.repositoryID
        } set: { repositoryID in
            model.creationDraft.repositoryID = repositoryID
        }
    }

    private var creationReasoningSelection: Binding<ReasoningEffort> {
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(column.title)
                    .font(.callout.weight(.semibold))

                Text("\(column.cards.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(.horizontal, 2)

            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    if column.cards.isEmpty {
                        EmptyColumnPlaceholder()
                    } else {
                        ForEach(column.cards) { card in
                            BoardCardView(model: model, card: card)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct EmptyColumnPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.separator.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(maxWidth: .infinity, minHeight: 96)
            .overlay {
                Text("No tasks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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
            TaskCardView(card: card, isSelected: model.selectedTaskID == card.id, isHovering: isHovering)
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
                CardTooltip(text: "Archive")
                    .padding(.trailing, 8)
                    .offset(y: 34)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Codex tooltip mirrors the archive one but sits under the codex
            // icon, which is one icon-slot to the left of the archive icon.
            if isHoveringCodexIcon, let codexHint {
                CardTooltip(text: codexHint)
                    .padding(.trailing, 34)
                    .offset(y: 34)
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
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .tint(.red)
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

private struct CardTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize()
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

private struct TaskCardView: View {
    let card: TaskCardProjection
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                BadgeView(text: card.repositoryBadge)
                BadgeView(text: card.reasoningBadge)
                if let triggerStateBadge = card.triggerStateBadge {
                    BadgeView(text: triggerStateBadge)
                }
                Spacer(minLength: 8)
                if card.showsRunningActivityIndicator {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                        .accessibilityLabel("Running")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Cards live in the content layer, so they use a quiet solid
            // surface instead of Liquid Glass (glass is reserved for chrome).
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.secondary.opacity(isSelected ? 1 : 0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.8))
                        : AnyShapeStyle(.separator.opacity(isHovering ? 0.9 : 0.5)),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
    }
}

private struct InspectorPanelView: View {
    @ObservedObject var model: TaskBoardModel

    var body: some View {
        Group {
            if
                let selectedTaskID = model.selectedTaskID,
                let inspector = model.projection.inspector(taskID: selectedTaskID)
            {
                ScrollView(.vertical) {
                    TaskInspectorView(model: model, inspector: inspector)
                        .padding(16)
                }
            } else {
                ContentUnavailableView {
                    Label("No Task Selected", systemImage: "sidebar.trailing")
                } description: {
                    Text("Select a card to see its details.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                Picker("Reasoning", selection: inspectorReasoningSelection) {
                    ForEach(ReasoningEffortOption.all) { option in
                        Text(option.label).tag(option.effort)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

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
                    .buttonStyle(.glass)

                    Button {
                        Task {
                            await model.sendSelectedInspectorTaskToCodexReportingErrors()
                        }
                    } label: {
                        Label(inspector.codexSendLabel, systemImage: "paperplane")
                    }
                    .buttonStyle(.glassProminent)
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
                    .buttonStyle(.glassProminent)
                }
            }

            Divider()

            archiveButton
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
            .buttonStyle(.glassProminent)
            .tint(.red)
            .accessibilityLabel("Confirm archive")
        } else {
            Button(role: .destructive) {
                isConfirmingArchive = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .buttonStyle(.glass)
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

    private var inspectorReasoningSelection: Binding<ReasoningEffort> {
        Binding {
            model.inspectorDraft?.reasoningEffort ?? inspector.reasoningEffort
        } set: { effort in
            model.inspectorDraft?.reasoningEffort = effort
        }
    }
}

private extension View {
    // A recessed input surface that sits quietly inside panels; semantic
    // styles keep it adaptive across light and dark appearances.
    func recessedFieldBackground(cornerRadius: CGFloat = 10) -> some View {
        background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5))
            }
    }
}

private struct BadgeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(.quaternary.opacity(0.7), in: Capsule())
    }
}
