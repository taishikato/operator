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
        VStack(alignment: .leading, spacing: 2) {
            SidebarItemButton(
                title: "Board",
                systemImage: "rectangle.grid.3x2",
                isSelected: selection == .board
            ) {
                selection = .board
            }

            SidebarItemButton(
                title: "Archived",
                systemImage: "archivebox",
                isSelected: selection == .archived
            ) {
                selection = .archived
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

private struct SidebarItemButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(SidebarItemButtonStyle(isSelected: isSelected))
    }
}

private struct SidebarItemButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                } else if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(0.5))
                }
            }
    }
}
