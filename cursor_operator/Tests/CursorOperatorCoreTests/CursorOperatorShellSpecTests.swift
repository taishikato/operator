import Testing
@testable import CursorOperatorCore

@Test func cursorOperatorLaunchesDirectlyToBoard() {
    let shell = CursorOperatorShellSpec.mvp

    #expect(shell.launchDestination == .board)
}

@Test func boardShowsOnlyActiveCursorColumnsByDefault() {
    let shell = CursorOperatorShellSpec.mvp

    #expect(shell.board.columns.map(\.title) == ["Ready", "Running", "Failed", "Done"])
    #expect(!shell.board.columns.map(\.id).contains(.archived))
}

@Test func settingsAndArchivedAreAvailableButArchivedIsHiddenFromDefaultBoard() {
    let shell = CursorOperatorShellSpec.mvp

    #expect(shell.navigationDestinations.contains(.archived))
    #expect(shell.sceneDestinations.contains(.settings))
}

@Test func commonBoardActionsHaveToolbarMenuAndKeyboardPaths() {
    let shell = CursorOperatorShellSpec.mvp

    #expect(shell.board.commands.contains(CursorBoardCommandSpec(
        id: .newTask,
        title: "New Cursor Task",
        keyboardShortcut: "Command-N"
    )))
    #expect(shell.board.commands.contains(CursorBoardCommandSpec(
        id: .addRepository,
        title: "Add Repository",
        keyboardShortcut: "Command-O"
    )))
}

@Test func appMenuBoardCommandsReturnToBoardFromArchivedSelection() {
    #expect(CursorOperatorSidebarSelection.archived.selectionAfterAppMenuCommand(.newTask) == .board)
    #expect(CursorOperatorSidebarSelection.archived.selectionAfterAppMenuCommand(.addRepository) == .board)
    #expect(CursorOperatorSidebarSelection.board.selectionAfterAppMenuCommand(.newTask) == .board)
}

@Test func operatorUsesIsolatedIdentityAndDataRoot() {
    let app = CursorOperatorAppSpec.mvp

    #expect(app.displayName == "Operator")
    #expect(app.bundleIdentifier == "com.focus.operator")
    #expect(app.applicationSupportDirectoryName == "Operator")
    #expect(app.databaseFileName == "operator.sqlite")
}

@Test func mvpScopeKeepsCursorAndGitOrchestrationOutOfScope() {
    #expect(CursorOperatorMVPScope.outOfScope.contains(.localCursorRuntime))
    #expect(CursorOperatorMVPScope.outOfScope.contains(.branchOwnership))
    #expect(CursorOperatorMVPScope.outOfScope.contains(.rawLogs))
    #expect(CursorOperatorMVPScope.outOfScope.contains(.resultClassification))
    #expect(CursorOperatorMVPScope.disallowedAutomaticGitCommands == ["fetch", "pull", "push", "merge", "rebase"])
    #expect(CursorOperatorMVPScope.cursorContinuations == [.webURL, .copyRunID, .dashboard])
}

@Test func setupStatusUsesConservativeSFSymbolNames() {
    let ready = CursorSetupStatusProjection(
        repositoryState: .registered(count: 1),
        credentialState: .ready,
        nodeState: .ready(version: "v22.13.0")
    )

    #expect(ready.repositoryIconName == "folder")
    #expect(ready.credentialIconName == "key")
    #expect(ready.nodeIconName == "checkmark.circle")
}

@Test func setupStatusRequiresCompatibleNodeBeforeSending() {
    let missingNode = CursorSetupStatusProjection(
        repositoryState: .registered(count: 1),
        credentialState: .ready,
        nodeState: .missing
    )

    #expect(missingNode.canSend == false)
    #expect(missingNode.nodeMessage == "Node.js: 22.13+ required")
    #expect(missingNode.nodeIconName == "exclamationmark.triangle")
}

@Test func setupStatusUsesSelectedHarnessReadinessBeforeSending() {
    let codexReady = CursorSetupStatusProjection(
        repositoryState: .registered(count: 1),
        credentialState: .missing,
        nodeState: .missing,
        codexState: .ready(binaryPath: "/opt/homebrew/bin/codex"),
        selectedHarness: .codex
    )
    let cursorReady = CursorSetupStatusProjection(
        repositoryState: .registered(count: 1),
        credentialState: .ready,
        nodeState: .ready(version: "v22.13.0"),
        codexState: .notFound,
        selectedHarness: .cursor
    )
    let codexMissing = CursorSetupStatusProjection(
        repositoryState: .registered(count: 1),
        credentialState: .ready,
        nodeState: .ready(version: "v22.13.0"),
        codexState: .notFound,
        selectedHarness: .codex
    )

    #expect(codexReady.canSend)
    #expect(cursorReady.canSend)
    #expect(codexMissing.canSend == false)
    #expect(codexMissing.sendDisabledReason == "Codex must be ready before sending.")
}
