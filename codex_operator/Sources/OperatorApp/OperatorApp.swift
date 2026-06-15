import OperatorDesktop
import SwiftUI

@main
struct OperatorApp: App {
    private let store: OperatorStore
    private let codexTrigger: CodexTriggerService
    private let appDataURL: URL

    init() {
        do {
            appDataURL = try OperatorAppBootstrap.applicationDataURL()
            store = try OperatorAppBootstrap.initializeStore(databaseURL: appDataURL.appending(path: "operator.sqlite"))
            let codexBinarySettings = CodexBinarySettings()
            codexTrigger = CodexTriggerService(
                store: store,
                worktreePreparer: WorktreePreparer(
                    appDataURL: appDataURL,
                    worktreeRootURL: OperatorAppBootstrap.codexWorktreesURL()
                ),
                appServerClientFactory: ConfiguredCodexAppServerClientFactory(settings: codexBinarySettings),
                threadVisibility: CodexCLIThreadVisibilityController(settings: codexBinarySettings)
            )
        } catch {
            fatalError("Unable to initialize Operator store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Operator") {
            OperatorRootView(store: store, shell: .mvp, codexTrigger: codexTrigger)
                .frame(minWidth: 1_040, minHeight: 680)
                .task { [store, codexTrigger] in
                    // Surface writes made by the operator CLI on a running board.
                    store.startExternalChangeMonitoring()
                    await codexTrigger.recoverInterruptedRuns()
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            OperatorSettingsView(store: store, appDataURL: appDataURL)
                .frame(width: 480)
        }
    }
}
