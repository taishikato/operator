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
