import Foundation

public struct CursorNodeResolution: Equatable, Sendable {
    public let executableURL: URL
    public let version: String

    public init(executableURL: URL, version: String) {
        self.executableURL = executableURL
        self.version = version
    }
}

public enum CursorNodeResolutionError: Error, Equatable, Sendable {
    case missingCompatibleNode
}

public struct CursorNodeSettingsProjection: Equatable, Sendable {
    public let status: String
    public let path: String

    public init(result: Result<CursorNodeResolution, CursorNodeResolutionError>) {
        switch result {
        case let .success(resolution):
            status = "Detected \(resolution.version)"
            path = resolution.executableURL.path
        case .failure:
            status = "Missing Node.js 22.13+"
            path = "Set CURSOR_NODE_PATH or install Node.js 22.13 or newer."
        }
    }
}

public protocol CursorNodeResolving: Sendable {
    func resolve() throws -> CursorNodeResolution
}

public protocol CursorNodeFileSystem: Sendable {
    func isExecutableFile(at url: URL) -> Bool
    func descendantFiles(under directory: URL) -> [URL]
}

public protocol CursorNodeVersionProviding: Sendable {
    func nodeVersion(executableURL: URL) -> String?
}

public struct CursorNodeExecutableResolver: CursorNodeResolving {
    public static let minimumVersion = CursorSemanticVersion(major: 22, minor: 13, patch: 0)

    private let environment: [String: String]
    private let candidatePaths: [URL]
    private let fileSystem: any CursorNodeFileSystem
    private let versionProvider: any CursorNodeVersionProviding

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        candidatePaths: [URL] = Self.defaultCandidatePaths(),
        fileSystem: any CursorNodeFileSystem = DefaultCursorNodeFileSystem(),
        versionProvider: any CursorNodeVersionProviding = ProcessCursorNodeVersionProvider()
    ) {
        self.environment = environment
        self.candidatePaths = candidatePaths
        self.fileSystem = fileSystem
        self.versionProvider = versionProvider
    }

    public func resolve() throws -> CursorNodeResolution {
        for candidate in orderedCandidates() {
            guard fileSystem.isExecutableFile(at: candidate),
                  let versionString = versionProvider.nodeVersion(executableURL: candidate),
                  let version = CursorSemanticVersion(nodeVersionOutput: versionString),
                  version >= Self.minimumVersion else {
                continue
            }

            return CursorNodeResolution(
                executableURL: candidate,
                version: versionString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        throw CursorNodeResolutionError.missingCompatibleNode
    }

    private func orderedCandidates() -> [URL] {
        var candidates: [URL] = []

        if let explicit = environment["CURSOR_NODE_PATH"], !explicit.isEmpty {
            candidates.append(URL(filePath: explicit))
        }

        candidates.append(contentsOf: pathCandidates())
        candidates.append(contentsOf: candidatePaths)
        candidates.append(contentsOf: nvmCandidates())

        var seen: Set<String> = []
        return candidates.filter { candidate in
            let key = candidate.standardizedFileURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func pathCandidates() -> [URL] {
        guard let path = environment["PATH"] else {
            return []
        }

        return path
            .split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: "node") }
    }

    private func nvmCandidates() -> [URL] {
        guard let home = environment["HOME"], !home.isEmpty else {
            return []
        }

        let nvmRoot = URL(filePath: home)
            .appending(path: ".nvm", directoryHint: .isDirectory)
            .appending(path: "versions", directoryHint: .isDirectory)
            .appending(path: "node", directoryHint: .isDirectory)

        return fileSystem.descendantFiles(under: nvmRoot)
            .filter { $0.lastPathComponent == "node" && $0.deletingLastPathComponent().lastPathComponent == "bin" }
            .sorted { lhs, rhs in
                let lhsVersion = CursorSemanticVersion(nvmNodeURL: lhs) ?? .zero
                let rhsVersion = CursorSemanticVersion(nvmNodeURL: rhs) ?? .zero
                return lhsVersion > rhsVersion
            }
    }

    public static func defaultCandidatePaths() -> [URL] {
        [
            URL(filePath: "/opt/homebrew/bin/node"),
            URL(filePath: "/usr/local/bin/node"),
            URL(filePath: "/usr/bin/node")
        ]
    }
}

public struct DefaultCursorNodeFileSystem: CursorNodeFileSystem {
    public init() {}

    public func isExecutableFile(at url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    public func descendantFiles(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { $0 as? URL }
    }
}

public struct ProcessCursorNodeVersionProvider: CursorNodeVersionProviding {
    public init() {}

    public func nodeVersion(executableURL: URL) -> String? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-v"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

public struct CursorSemanticVersion: Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public static let zero = CursorSemanticVersion(major: 0, minor: 0, patch: 0)

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(nodeVersionOutput: String) {
        let trimmed = nodeVersionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(versionString: trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed)
    }

    public init?(nvmNodeURL: URL) {
        let versionDirectory = nvmNodeURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
        let versionString = versionDirectory.hasPrefix("v") ? String(versionDirectory.dropFirst()) : versionDirectory
        self.init(versionString: versionString)
    }

    private init?(versionString: String) {
        let parts = versionString.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else {
            return nil
        }
        major = parts[0]
        minor = parts[1]
        patch = parts.count >= 3 ? parts[2] : 0
    }

    public static func < (lhs: CursorSemanticVersion, rhs: CursorSemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
