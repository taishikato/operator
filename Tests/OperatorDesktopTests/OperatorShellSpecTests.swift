import Testing
@testable import OperatorDesktop

@Test func defaultShellLaunchesDirectlyToBoard() {
    let shell = OperatorShellSpec.mvp

    #expect(shell.launchDestination == .board)
}

@Test func defaultBoardShowsOnlyActiveMVPColumns() {
    let shell = OperatorShellSpec.mvp

    #expect(shell.board.columns.map(\.title) == ["Ready", "Review", "Done"])
    #expect(!shell.board.columns.map(\.id).contains(.archived))
}

@Test func shellExposesArchivedAndSettingsNavigationPaths() {
    let shell = OperatorShellSpec.mvp

    #expect(shell.navigationDestinations.contains(.archived))
    #expect(shell.navigationDestinations.contains(.settings))
}

@Test func sidebarSelectionsOnlyExposeBoardAndArchivedDestinations() {
    #expect(OperatorSidebarSelection.allCases == [.board, .archived])
}

@Test func settingsDestinationIsNotSelectableFromSidebar() {
    #expect(OperatorSidebarSelection(destination: .settings) == nil)
}

@Test func emptyBoardProvidesEmptyStateAndInspectorReserve() {
    let shell = OperatorShellSpec.mvp

    #expect(shell.board.emptyState.title == "No repositories or tasks yet")
    #expect(shell.board.emptyState.message == "Ready, Review, and Done are empty right now.")
    #expect(shell.board.reservesInspectorPanel)
}
