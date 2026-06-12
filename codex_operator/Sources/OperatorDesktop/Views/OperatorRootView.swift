import SwiftUI

public struct OperatorRootView: View {
    private let store: OperatorStore
    private let shell: OperatorShellSpec
    private let codexTrigger: (any CodexTaskSending)?
    private let codexOpener: (any CodexAppOpening)?

    @State private var selection: OperatorSidebarSelection
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(
        store: OperatorStore,
        shell: OperatorShellSpec = .mvp,
        codexTrigger: (any CodexTaskSending)? = nil,
        codexOpener: (any CodexAppOpening)? = OSCodexAppOpener()
    ) {
        self.store = store
        self.shell = shell
        self.codexTrigger = codexTrigger
        self.codexOpener = codexOpener
        _selection = State(initialValue: OperatorSidebarSelection(destination: shell.launchDestination) ?? .board)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
            case .board:
                BoardView(store: store, codexTrigger: codexTrigger, codexOpener: codexOpener)
                    .navigationTitle("Board")
            case .archived:
                ArchivedView(store: store, codexOpener: codexOpener)
                    .navigationTitle("Archived")
            }
        }
        // Translucent window surface: mostly opaque, with just a hint of the
        // desktop bleeding through so the Liquid Glass chrome has depth to sample.
        .containerBackground(.thickMaterial, for: .window)
        .background {
            // Hidden control hosting the ⌘B shortcut to toggle the sidebar.
            Button("Toggle Sidebar", action: toggleSidebar)
                .keyboardShortcut("b", modifiers: .command)
                .hidden()
        }
    }

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: OperatorSidebarSelection

    var body: some View {
        List(selection: listSelection) {
            Label("Board", systemImage: "rectangle.grid.3x2")
                .tag(OperatorSidebarSelection.board)

            Label("Archived", systemImage: "archivebox")
                .tag(OperatorSidebarSelection.archived)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
    }

    // List selection is optional; ignore deselection so one destination is
    // always active.
    private var listSelection: Binding<OperatorSidebarSelection?> {
        Binding {
            selection
        } set: { newValue in
            if let newValue {
                selection = newValue
            }
        }
    }
}
