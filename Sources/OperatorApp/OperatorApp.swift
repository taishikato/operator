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
            codexTrigger = CodexTriggerService(
                store: store,
                worktreePreparer: WorktreePreparer(appDataURL: appDataURL),
                appServerClientFactory: ConfiguredCodexAppServerClientFactory()
            )
        } catch {
            fatalError("Unable to initialize Operator store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Operator") {
            OperatorRootView(store: store, shell: .mvp, codexTrigger: codexTrigger)
                .frame(minWidth: 1_040, minHeight: 680)
        }
        .windowResizability(.contentMinSize)

        Settings {
            OperatorSettingsView(store: store, appDataURL: appDataURL)
                .frame(width: 480)
        }
    }
}
