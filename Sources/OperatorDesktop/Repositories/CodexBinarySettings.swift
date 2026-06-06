import Foundation

public struct CodexBinaryConfiguration: Equatable, Sendable {
    public let detectedBinaryURL: URL?
    public let overrideBinaryURL: URL?

    public init(detectedBinaryURL: URL?, overrideBinaryURL: URL?) {
        self.detectedBinaryURL = detectedBinaryURL
        self.overrideBinaryURL = overrideBinaryURL
    }

    public var effectiveBinaryURL: URL? {
        overrideBinaryURL ?? detectedBinaryURL
    }

    public var displayPath: String {
        effectiveBinaryURL?.path ?? "Not found"
    }
}

public enum CodexBinarySettingsError: Error, Equatable, LocalizedError, Sendable {
    case overrideMustBeAbsolute

    public var errorDescription: String? {
        switch self {
        case .overrideMustBeAbsolute:
            "Codex binary override must be an absolute path."
        }
    }
}

public enum CodexBinaryConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "Codex binary not found. Configure an absolute Codex binary path in Settings."
        }
    }
}

public protocol CodexBinarySettingsProviding: Sendable {
    func configuration() throws -> CodexBinaryConfiguration
}

public protocol CodexBinarySettingsManaging: CodexBinarySettingsProviding {
    func setOverridePath(_ path: String) throws
}

public protocol CodexBinarySettingsStoring: Sendable {
    func codexBinaryOverridePath() -> String?
    func setCodexBinaryOverridePath(_ path: String?)
}

public protocol CodexBinaryDetecting: Sendable {
    func detectedCodexBinaryURL() -> URL?
}

public struct CodexBinarySettings: CodexBinarySettingsManaging, Sendable {
    private let store: any CodexBinarySettingsStoring
    private let detector: any CodexBinaryDetecting

    public init(
        store: any CodexBinarySettingsStoring = UserDefaultsCodexBinarySettingsStore(),
        detector: any CodexBinaryDetecting = ProcessCodexBinaryDetector()
    ) {
        self.store = store
        self.detector = detector
    }

    public func configuration() throws -> CodexBinaryConfiguration {
        let overrideURL = try overrideBinaryURL()
        return CodexBinaryConfiguration(
            detectedBinaryURL: detector.detectedCodexBinaryURL(),
            overrideBinaryURL: overrideURL
        )
    }

    public func setOverridePath(_ path: String) throws {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            store.setCodexBinaryOverridePath(nil)
            return
        }

        guard URL(filePath: trimmedPath).path == trimmedPath, trimmedPath.hasPrefix("/") else {
            throw CodexBinarySettingsError.overrideMustBeAbsolute
        }
        store.setCodexBinaryOverridePath(trimmedPath)
    }

    private func overrideBinaryURL() throws -> URL? {
        guard let overridePath = store.codexBinaryOverridePath()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !overridePath.isEmpty else {
            return nil
        }
        guard overridePath.hasPrefix("/") else {
            throw CodexBinarySettingsError.overrideMustBeAbsolute
        }
        return URL(filePath: overridePath)
    }
}

public final class UserDefaultsCodexBinarySettingsStore: CodexBinarySettingsStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key = "operator.codex.binaryOverridePath"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func codexBinaryOverridePath() -> String? {
        userDefaults.string(forKey: key)
    }

    public func setCodexBinaryOverridePath(_ path: String?) {
        if let path {
            userDefaults.set(path, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}

public struct ProcessCodexBinaryDetector: CodexBinaryDetecting {
    public init() {}

    public func detectedCodexBinaryURL() -> URL? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["which", "codex"]
        process.environment = CodexProcessEnvironment.augmentedEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty else {
            return nil
        }
        return URL(filePath: path)
    }
}
