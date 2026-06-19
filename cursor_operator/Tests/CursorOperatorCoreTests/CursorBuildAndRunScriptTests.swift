import Foundation
import Testing

@Test func buildAndRunLaunchesFreshAppWindow() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let packageRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = packageRoot.appending(path: "script/build_and_run.sh")

    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains(#"/usr/bin/open -n -F "$APP_BUNDLE""#))
}

@Test func buildAndRunCanCreateBundleWithoutLaunchingForSmokeTests() throws {
    let script = try packageScript(named: "build_and_run.sh")

    #expect(script.contains(#"--bundle|bundle)"#))
}

@Test func uiSendSmokeScriptClicksSendAndPollsDone() throws {
    let script = try packageScript(named: "ui_send_smoke.sh")

    #expect(script.contains("CURSOR_OPERATOR_APP_SUPPORT_DIR"))
    #expect(script.contains("preflight_accessibility"))
    #expect(script.contains("launchctl setenv CURSOR_API_KEY"))
    #expect(script.contains("swift run CursorOperatorSmokeSupport seed-ready"))
    #expect(script.contains(#"name of elementRef is "Send""#))
    #expect(script.contains("swift run CursorOperatorSmokeSupport wait-done"))
}

private func packageScript(named name: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let packageRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = packageRoot
        .appending(path: "script", directoryHint: .isDirectory)
        .appending(path: name)

    return try String(contentsOf: scriptURL, encoding: .utf8)
}
