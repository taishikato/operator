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

@Test func installCLIScriptInstallsCursorOperatorCommand() throws {
    let script = try packageScript(named: "install_cli.sh")

    #expect(script.contains("swift build -c release --product cursor-operator-cli"))
    #expect(script.contains(#"ln -sf "$BIN_PATH" "$INSTALL_DIR/cursor-operator""#))
}

@Test func installSkillsScriptLinksCursorSpecificSkill() throws {
    let script = try packageScript(named: "install_skills.sh")

    #expect(script.contains("cursor_operator/skills/cursor-operator"))
    #expect(script.contains(#""$HOME/.codex/skills""#))
    #expect(script.contains(#""$HOME/.cursor/skills""#))
}

@Test func cursorOperatorSkillDocumentsStableCLIContract() throws {
    let skill = packageRoot()
        .appending(path: "skills", directoryHint: .isDirectory)
        .appending(path: "cursor-operator", directoryHint: .isDirectory)
        .appending(path: "SKILL.md")
    let text = try String(contentsOf: skill, encoding: .utf8)

    #expect(text.contains("cursor-operator task add"))
    #expect(text.contains("cursor-operator task send"))
    #expect(text.contains("CURSOR_OPERATOR_DB"))
    #expect(text.contains("Do not read or write"))
}

private func packageScript(named name: String) throws -> String {
    let scriptURL = packageRoot()
        .appending(path: "script", directoryHint: .isDirectory)
        .appending(path: name)

    return try String(contentsOf: scriptURL, encoding: .utf8)
}

private func packageRoot() -> URL {
    let testFile = URL(fileURLWithPath: #filePath)
    return testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
