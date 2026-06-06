import Foundation
import Testing
@testable import OperatorDesktop

@Test func codexProcessEnvironmentAugmentsCommonMacOSBinarySearchPaths() {
    let environment = CodexProcessEnvironment.augmentedEnvironment(
        base: ["PATH": "/usr/bin:/bin"],
        binaryURL: nil
    )

    let pathEntries = Set((environment["PATH"] ?? "").split(separator: ":").map(String.init))

    #expect(pathEntries.contains("/usr/bin"))
    #expect(pathEntries.contains("/opt/homebrew/bin"))
    #expect(pathEntries.contains("/usr/local/bin"))
}

@Test func codexProcessEnvironmentPrependsBinaryDirectoryToPath() {
    let binaryURL = URL(filePath: "/Users/test/.nvm/versions/node/v22.0.0/bin/codex")
    let environment = CodexProcessEnvironment.augmentedEnvironment(
        base: ["PATH": "/usr/bin:/bin"],
        binaryURL: binaryURL
    )

    let path = environment["PATH"] ?? ""
    #expect(path.hasPrefix("/Users/test/.nvm/versions/node/v22.0.0/bin:"))
}
