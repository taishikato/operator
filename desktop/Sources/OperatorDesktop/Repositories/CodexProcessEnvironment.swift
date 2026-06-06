import Foundation

enum CodexProcessEnvironment {
    private static let commonSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/local/opt/node/bin",
        "\(NSHomeDirectory())/.nvm/versions/node/current/bin",
        "\(NSHomeDirectory())/.volta/bin",
        "\(NSHomeDirectory())/.local/bin"
    ]

    static func augmentedEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        binaryURL: URL? = nil
    ) -> [String: String] {
        var environment = base
        var pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        var additions = commonSearchPaths
        if let binaryURL {
            additions.insert(binaryURL.deletingLastPathComponent().path, at: 0)
        }

        for addition in additions.reversed() where !addition.isEmpty && !pathEntries.contains(addition) {
            pathEntries.insert(addition, at: 0)
        }

        environment["PATH"] = pathEntries.joined(separator: ":")
        return environment
    }
}
