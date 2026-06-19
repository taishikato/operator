import CursorOperatorCore
import SwiftUI

@main
struct CursorOperatorApp: App {
    private let appDataURL: URL
    private let store: CursorOperatorStore

    init() {
        do {
            appDataURL = try CursorOperatorAppBootstrap.applicationDataURL()
            try FileManager.default.createDirectory(
                at: appDataURL,
                withIntermediateDirectories: true
            )
            store = try CursorOperatorAppBootstrap.initializeStore(
                databaseURL: appDataURL.appending(path: CursorOperatorAppSpec.mvp.databaseFileName)
            )
            print("Cursor Operator app data: \(appDataURL.path)")
        } catch {
            fatalError("Unable to initialize Cursor Operator app data: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Cursor Operator") {
            CursorOperatorRootView(store: store, appDataURL: appDataURL)
                .frame(minWidth: 1_040, minHeight: 680)
        }
        .windowResizability(.contentMinSize)

        Settings {
            CursorOperatorSettingsView(appDataURL: appDataURL)
                .frame(width: 520)
        }
    }
}
