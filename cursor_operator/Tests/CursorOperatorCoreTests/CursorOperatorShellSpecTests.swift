import Testing
@testable import CursorOperatorCore

@Test func cursorOperatorLaunchesDirectlyToBoard() {
    let shell = CursorOperatorShellSpec.mvp

    #expect(shell.launchDestination == .board)
}

@Test func boardShowsOnlyActiveCursorColumnsByDefault() {
    let shell = CursorOperatorShellSpec.mvp

    #expect(shell.board.columns.map(\.title) == ["Ready", "Running", "Done"])
    #expect(!shell.board.columns.map(\.id).contains(.archived))
}

@Test func settingsAndArchivedAreAvailableButArchivedIsHiddenFromDefaultBoard() {
    let shell = CursorOperatorShellSpec.mvp

    #expect(shell.navigationDestinations.contains(.archived))
    #expect(shell.sceneDestinations.contains(.settings))
}

@Test func cursorOperatorUsesIsolatedIdentityAndDataRoot() {
    let app = CursorOperatorAppSpec.mvp

    #expect(app.displayName == "Cursor Operator")
    #expect(app.bundleIdentifier == "com.focus.cursor-operator")
    #expect(app.applicationSupportDirectoryName == "Cursor Operator")
    #expect(app.databaseFileName == "cursor-operator.sqlite")
    #expect(app.applicationSupportDirectoryName != "Operator")
}

@Test func cursorOperatorDocumentsBasicBuildAndTestCommands() {
    let app = CursorOperatorAppSpec.mvp

    #expect(app.developmentCommands.contains("swift test"))
    #expect(app.developmentCommands.contains("swift build"))
    #expect(app.developmentCommands.contains("./script/build_and_run.sh"))
}
