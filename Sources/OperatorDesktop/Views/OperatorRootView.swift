import SwiftUI

public struct OperatorRootView: View {
    private let store: OperatorStore
    private let shell: OperatorShellSpec
    private let codexTrigger: (any CodexTaskSending)?
    private let codexOpener: (any CodexAppOpening)?

    @State private var selection: OperatorSidebarSelection

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
        NavigationSplitView {
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
    }
}

private struct SidebarView: View {
    @Binding var selection: OperatorSidebarSelection

    var body: some View {
        List(selection: $selection) {
            Label("Board", systemImage: "rectangle.grid.3x2")
                .tag(OperatorSidebarSelection.board)

            Label("Archived", systemImage: "archivebox")
                .tag(OperatorSidebarSelection.archived)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    }
}
