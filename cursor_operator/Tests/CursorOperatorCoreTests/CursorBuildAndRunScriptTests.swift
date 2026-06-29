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

@Test func buildAndRunWritesDistributionBundleMetadata() throws {
    let script = try packageScript(named: "build_and_run.sh")

    #expect(script.contains("CURSOR_OPERATOR_VERSION"))
    #expect(script.contains("CURSOR_OPERATOR_BUILD_NUMBER"))
    #expect(script.contains("CFBundleShortVersionString"))
    #expect(script.contains("CFBundleVersion"))
}

@Test func buildAndRunBundlesAppIconForDistributionDMG() throws {
    let script = try packageScript(named: "build_and_run.sh")

    #expect(script.contains("Resources/AppIcon.icns"))
    #expect(script.contains(#"cp "$APP_ICON_SRC" "$APP_RESOURCES/$APP_ICON_FILE""#))
    #expect(script.contains("CFBundleIconFile"))
    #expect(script.contains("<string>AppIcon</string>"))
}

@Test func buildAndRunSupportsReleaseConfigurationForPackaging() throws {
    let script = try packageScript(named: "build_and_run.sh")

    #expect(script.contains("CURSOR_OPERATOR_SWIFT_CONFIGURATION"))
    #expect(script.contains(#"swift build -c "$SWIFT_CONFIGURATION""#))
}

@Test func buildAndRunBundlesCLIAndAgentSkillForDMGInstalls() throws {
    let script = try packageScript(named: "build_and_run.sh")

    #expect(script.contains("APP_HELPERS"))
    #expect(script.contains("cursor-operator-cli"))
    #expect(script.contains(#"cp "$BUILD_CLI" "$APP_CLI""#))
    #expect(script.contains("skills/cursor-operator"))
    #expect(script.contains(#"cp -R "$SKILL_SOURCE" "$APP_SKILLS_DIR/cursor-operator""#))
}

@Test func buildAndRunBundlesSparkleFrameworkAndUpdateMetadata() throws {
    let script = try packageScript(named: "build_and_run.sh")

    #expect(script.contains("APP_FRAMEWORKS"))
    #expect(script.contains("Sparkle.framework"))
    #expect(script.contains(#"/usr/bin/ditto "$framework_src" "$APP_FRAMEWORKS/$SPARKLE_FRAMEWORK_NAME""#))
    #expect(script.contains("CURSOR_OPERATOR_APPCAST_URL"))
    #expect(script.contains("CURSOR_OPERATOR_SPARKLE_PUBLIC_ED_KEY"))
    #expect(script.contains("SUFeedURL"))
    #expect(script.contains("SUPublicEDKey"))
    #expect(script.contains("SUEnableAutomaticChecks"))
}

@Test func packageDistributionBuildsSignedNotarizableDMG() throws {
    let script = try packageScript(named: "package_distribution.sh")

    #expect(script.contains("CURSOR_OPERATOR_SWIFT_CONFIGURATION=release"))
    #expect(script.contains("/usr/bin/hdiutil create"))
    #expect(script.contains("CURSOR_OPERATOR_CODESIGN_IDENTITY"))
    #expect(script.contains("--options runtime"))
    #expect(script.contains("CURSOR_OPERATOR_NOTARIZE=1"))
    #expect(script.contains("/usr/bin/xcrun notarytool submit"))
    #expect(script.contains("/usr/bin/xcrun stapler staple"))
    #expect(script.contains("/usr/bin/shasum -a 256"))
}

@Test func packageDistributionCanGenerateSparkleAppcast() throws {
    let script = try packageScript(named: "package_distribution.sh")

    #expect(script.contains("CURSOR_OPERATOR_GENERATE_APPCAST=1"))
    #expect(script.contains("CURSOR_OPERATOR_APPCAST_URL and CURSOR_OPERATOR_SPARKLE_PUBLIC_ED_KEY must be set when CURSOR_OPERATOR_GENERATE_APPCAST=1."))
    #expect(script.contains("generate_appcast"))
    #expect(script.contains(#""$generate_appcast" "$RELEASE_DIR""#))
}

@Test func homebrewCaskRendererDocumentsRuntimeRequirements() throws {
    let script = try packageScript(named: "render_homebrew_cask.sh")

    #expect(script.contains(#"cask "cursor-operator" do"#))
    #expect(script.contains(#"depends_on formula: "node""#))
    #expect(script.contains(#"depends_on macos: ">= :tahoe""#))
    #expect(script.contains(#"app "CursorOperator.app""#))
    #expect(script.contains("Node.js 22.13 or newer"))
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

@Test func installCLIScriptCopiesCursorSDKHelperNextToBuiltCLI() throws {
    let script = try packageScript(named: "install_cli.sh")

    #expect(script.contains("Resources/CursorSDKHelper"))
    #expect(script.contains(#"cp -R "$HELPER_SRC" "$HELPER_DEST""#))
}

@Test func installCLIScriptCopiesCursorSDKHelperNextToInstalledSymlink() throws {
    let script = try packageScript(named: "install_cli.sh")

    #expect(script.contains(#"HELPER_INSTALL_DEST="$INSTALL_DIR/CursorSDKHelper""#))
    #expect(script.contains(#"cp -R "$HELPER_SRC" "$HELPER_INSTALL_DEST""#))
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
