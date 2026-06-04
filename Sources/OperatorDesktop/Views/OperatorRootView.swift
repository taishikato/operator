import SwiftUI

public struct OperatorRootView: View {
    private let shell: OperatorShellSpec

    @State private var selection: OperatorDestination

    public init(shell: OperatorShellSpec = .mvp) {
        self.shell = shell
        _selection = State(initialValue: shell.launchDestination)
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
            case .board, .settings:
                BoardView(board: shell.board)
                    .navigationTitle("Board")
            case .archived:
                ArchivedView()
                    .navigationTitle("Archived")
            }
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: OperatorDestination

    var body: some View {
        List(selection: $selection) {
            Label("Board", systemImage: "rectangle.grid.3x2")
                .tag(OperatorDestination.board)

            Label("Archived", systemImage: "archivebox")
                .tag(OperatorDestination.archived)
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
