import OperatorDesktop
import SwiftUI

@main
struct OperatorApp: App {
    private let store: OperatorStore

    init() {
        do {
            store = try OperatorAppBootstrap.initializeStore()
        } catch {
            fatalError("Unable to initialize Operator store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Operator") {
            OperatorRootView(store: store, shell: .mvp)
                .frame(minWidth: 1_040, minHeight: 680)
        }
        .windowResizability(.contentMinSize)

        Settings {
            OperatorSettingsView(store: store)
                .frame(width: 480)
        }
    }
}
