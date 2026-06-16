import Foundation

public struct OperatorAgentSupportSource: Equatable, Sendable {
    public let cliURL: URL
    public let skillURL: URL

    public init(cliURL: URL, skillURL: URL) {
        self.cliURL = cliURL
        self.skillURL = skillURL
    }

    public static func bundled(bundle: Bundle = .main) -> Self {
        Self(cliURL: bundle.operatorBundledCLIURL, skillURL: bundle.operatorBundledSkillURL)
    }
}

public protocol OperatorAgentSupportInstalling {
    func status() throws -> OperatorAgentSupportStatus
    @discardableResult func installCLI() throws -> URL
    @discardableResult func installSkills() throws -> [URL]
}

public struct OperatorAgentSupportInstaller: OperatorAgentSupportInstalling {
    private let fileManager: FileManager
    private let source: OperatorAgentSupportSource
    private let homeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        source: OperatorAgentSupportSource,
        homeDirectory: URL = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    ) {
        self.fileManager = fileManager
        self.source = source
        self.homeDirectory = homeDirectory
    }

    public static func bundled(
        fileManager: FileManager = .default,
        homeDirectory: URL = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    ) -> Self {
        Self(fileManager: fileManager, source: .bundled(), homeDirectory: homeDirectory)
    }

    public func status() throws -> OperatorAgentSupportStatus {
        try OperatorAgentSupportStatus(
            cli: componentStatus(destination: cliDestination, source: source.cliURL),
            skills: skillDestinations.map { try componentStatus(destination: $0, source: source.skillURL) }
        )
    }

    @discardableResult
    public func installCLI() throws -> URL {
        try validateCLI()
        try installSymlink(source: source.cliURL, destination: cliDestination)
        return cliDestination
    }

    @discardableResult
    public func installSkills() throws -> [URL] {
        try validateSkill()
        var installedDestinations: [URL] = []
        for destination in skillDestinations {
            let status = try componentStatus(destination: destination, source: source.skillURL)
            guard status.state.canInstall else {
                continue
            }
            try installSymlink(source: source.skillURL, destination: destination)
            installedDestinations.append(destination)
        }
        return installedDestinations
    }

    public var cliDestination: URL {
        homeDirectory.appending(path: ".local/bin/operator")
    }

    public var skillDestinations: [URL] {
        [
            homeDirectory.appending(path: ".codex/skills/operator"),
            homeDirectory.appending(path: ".claude/skills/operator")
        ]
    }

    private func componentStatus(
        destination: URL,
        source: URL
    ) throws -> OperatorAgentSupportComponentStatus {
        if let symlinkTarget = try symlinkDestination(at: destination) {
            if symlinkTarget == source.path {
                return OperatorAgentSupportComponentStatus(destination: destination, state: .installed(targetPath: symlinkTarget))
            }
            guard isOperatorManagedSymlink(targetPath: symlinkTarget, destination: destination) else {
                return OperatorAgentSupportComponentStatus(destination: destination, state: .unmanaged)
            }
            return OperatorAgentSupportComponentStatus(destination: destination, state: .stale(targetPath: symlinkTarget))
        }

        if fileManager.fileExists(atPath: destination.path) {
            return OperatorAgentSupportComponentStatus(destination: destination, state: .unmanaged)
        }

        return OperatorAgentSupportComponentStatus(destination: destination, state: .missing)
    }

    private func installSymlink(source: URL, destination: URL) throws {
        let status = try componentStatus(destination: destination, source: source)
        switch status.state {
        case .installed:
            return
        case .stale:
            try fileManager.removeItem(at: destination)
        case .unmanaged:
            throw OperatorAgentSupportInstallerError.destinationExists(destination.path)
        case .missing:
            break
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    private func isOperatorManagedSymlink(targetPath: String, destination: URL) -> Bool {
        if destination == cliDestination {
            return targetPath.contains("/Operator.app/Contents/Library/Helpers/operator-cli")
                || (targetPath.contains("/codex_operator/.build/") && targetPath.hasSuffix("/operator-cli"))
        }

        if skillDestinations.contains(destination) {
            return targetPath.contains("/Operator.app/Contents/Resources/skills/operator")
                || targetPath.contains("/operator/skills/operator")
        }

        return false
    }

    private func symlinkDestination(at url: URL) throws -> String? {
        do {
            return try fileManager.destinationOfSymbolicLink(atPath: url.path)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadUnknownError {
            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
               underlyingError.domain == NSPOSIXErrorDomain,
               underlyingError.code == Int(EINVAL) {
                return nil
            }
            throw error
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return nil
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EINVAL) {
            return nil
        }
    }

    private func validateCLI() throws {
        guard fileManager.fileExists(atPath: source.cliURL.path) else {
            throw OperatorAgentSupportInstallerError.sourceMissing(source.cliURL.path)
        }
    }

    private func validateSkill() throws {
        guard fileManager.fileExists(atPath: source.skillURL.appending(path: "SKILL.md").path) else {
            throw OperatorAgentSupportInstallerError.sourceMissing(source.skillURL.path)
        }
    }
}

public struct OperatorAgentSupportStatus: Equatable, Sendable {
    public let cli: OperatorAgentSupportComponentStatus
    public let skills: [OperatorAgentSupportComponentStatus]

    public init(cli: OperatorAgentSupportComponentStatus, skills: [OperatorAgentSupportComponentStatus]) {
        self.cli = cli
        self.skills = skills
    }

    public var skillsState: OperatorAgentSupportInstallState {
        if let repairable = skills.first(where: { $0.state.canInstall }) {
            return repairable.state
        }
        if skills.allSatisfy({ $0.state.isInstalled }), let first = skills.first {
            return first.state
        }
        if skills.contains(where: { $0.state == .unmanaged }) {
            return .unmanaged
        }
        return .missing
    }
}

public struct OperatorAgentSupportComponentStatus: Equatable, Sendable {
    public let destination: URL
    public let state: OperatorAgentSupportInstallState

    public init(destination: URL, state: OperatorAgentSupportInstallState) {
        self.destination = destination
        self.state = state
    }
}

public enum OperatorAgentSupportInstallState: Equatable, Sendable {
    case missing
    case installed(targetPath: String)
    case stale(targetPath: String)
    case unmanaged

    public var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    public var isStale: Bool {
        if case .stale = self {
            return true
        }
        return false
    }

    public var canInstall: Bool {
        switch self {
        case .missing, .stale:
            return true
        case .installed, .unmanaged:
            return false
        }
    }
}

public enum OperatorAgentSupportInstallerError: LocalizedError, Equatable, Sendable {
    case sourceMissing(String)
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case let .sourceMissing(path):
            return "Operator support file is missing: \(path)"
        case let .destinationExists(path):
            return "A file already exists at \(path). Move it before installing Operator support."
        }
    }
}

private extension Bundle {
    var operatorBundledCLIURL: URL {
        url(forAuxiliaryExecutable: "operator-cli")
            ?? bundleURL.appending(path: "Contents/Library/Helpers/operator-cli")
    }

    var operatorBundledSkillURL: URL {
        url(forResource: "operator", withExtension: nil, subdirectory: "skills")
            ?? bundleURL.appending(path: "Contents/Resources/skills/operator", directoryHint: .isDirectory)
    }
}
