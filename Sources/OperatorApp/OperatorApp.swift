import OperatorDesktop
import SwiftUI

@main
struct OperatorApp: App {
    var body: some Scene {
        WindowGroup("Operator") {
            OperatorRootView(shell: .mvp)
                .frame(minWidth: 1_040, minHeight: 680)
        }
        .windowResizability(.contentMinSize)

        Settings {
            OperatorSettingsView()
                .frame(width: 480)
        }
    }
}
