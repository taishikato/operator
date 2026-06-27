import Foundation
import Testing
@testable import CursorOperatorCore

@Test func applicationDataURLCanBeOverriddenForUISmokeTests() throws {
    let override = URL(filePath: "/tmp/operator-ui-smoke")

    let dataURL = try CursorOperatorAppBootstrap.applicationDataURL(
        environment: ["CURSOR_OPERATOR_APP_SUPPORT_DIR": override.path]
    )
    let databaseURL = try CursorOperatorAppBootstrap.databaseURL(
        environment: ["CURSOR_OPERATOR_APP_SUPPORT_DIR": override.path]
    )

    #expect(dataURL == override)
    #expect(databaseURL == override.appending(path: "operator.sqlite"))
}
