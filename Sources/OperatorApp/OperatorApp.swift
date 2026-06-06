import OperatorDesktop
import SwiftUI

@main
struct OperatorApp: App {
    private let store: OperatorStore
    private let codexTrigger: CodexTriggerService

    init() {
        do {
            store = try OperatorAppBootstrap.initializeStore()
            codexTrigger = CodexTriggerService(
                store: store,
                worktreePreparer: WorktreePreparer(appDataURL: try OperatorAppBootstrap.applicationDataURL()),
                appServerClient: CodexAppServerStdioClient()
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
            OperatorSettingsView(store: store)
                .frame(width: 480)
        }
    }
}
