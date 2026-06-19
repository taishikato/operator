import SwiftUI

public struct CursorOperatorRootView: View {
    private let shell: CursorOperatorShellSpec
    private let appDataURL: URL

    @State private var selection: CursorOperatorSidebarSelection
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(
        shell: CursorOperatorShellSpec = .mvp,
        appDataURL: URL
    ) {
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
                CursorBoardView(shell: shell, appDataURL: appDataURL)
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
    let appDataURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cursor Cloud Agent starts from the remote default branch.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                ForEach(shell.board.columns) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(column.title)
                            .font(.headline)

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
