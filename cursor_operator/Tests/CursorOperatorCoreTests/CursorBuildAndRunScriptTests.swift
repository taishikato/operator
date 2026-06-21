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
