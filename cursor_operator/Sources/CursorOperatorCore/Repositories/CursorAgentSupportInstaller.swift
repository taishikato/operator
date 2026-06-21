import Foundation

public struct CursorAgentSupportSource: Equatable, Sendable {
    public let cliURL: URL
    public let skillURL: URL
    public let helperURL: URL

    public init(cliURL: URL, skillURL: URL, helperURL: URL) {
        self.cliURL = cliURL
        self.skillURL = skillURL
        self.helperURL = helperURL
    }

    public static func bundled(bundle: Bundle = .main) -> Self {
        Self(
            cliURL: bundle.cursorOperatorBundledCLIURL,
            skillURL: bundle.cursorOperatorBundledSkillURL,
            helperURL: bundle.cursorOperatorBundledHelperURL
        )
    }
}

public protocol CursorAgentSupportInstalling {
    func status() throws -> CursorAgentSupportStatus
    @discardableResult func installCLI() throws -> URL
    @discardableResult func installSkills() throws -> [URL]
}

public struct CursorAgentSupportInstaller: CursorAgentSupportInstalling {
    private let fileManager: FileManager
    private let source: CursorAgentSupportSource
    private let homeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        source: CursorAgentSupportSource,
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

    public func status() throws -> CursorAgentSupportStatus {
        try CursorAgentSupportStatus(
            cli: componentStatus(destination: cliDestination, source: source.cliURL),
            skills: skillDestinations.map { try componentStatus(destination: $0, source: source.skillURL) }
        )
    }

    @discardableResult
    public func installCLI() throws -> URL {
        try validateCLI()
        try validateHelper()
        try installSymlink(source: source.cliURL, destination: cliDestination)
        try installHelper()
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
        homeDirectory.appending(path: ".local/bin/cursor-operator")
    }

    public var skillDestinations: [URL] {
        [
            homeDirectory.appending(path: ".codex/skills/cursor-operator"),
            homeDirectory.appending(path: ".cursor/skills/cursor-operator"),
            homeDirectory.appending(path: ".claude/skills/cursor-operator")
        ]
    }

    private var helperDestination: URL {
        cliDestination.deletingLastPathComponent()
            .appending(path: "CursorSDKHelper", directoryHint: .isDirectory)
    }

    private func componentStatus(
        destination: URL,
        source: URL
    ) throws -> CursorAgentSupportComponentStatus {
        if let symlinkTarget = try symlinkDestination(at: destination) {
            if symlinkTarget == source.path {
                return CursorAgentSupportComponentStatus(destination: destination, state: .installed(targetPath: symlinkTarget))
            }
            guard isCursorOperatorManagedSymlink(targetPath: symlinkTarget, destination: destination) else {
                return CursorAgentSupportComponentStatus(destination: destination, state: .unmanaged)
            }
            return CursorAgentSupportComponentStatus(destination: destination, state: .stale(targetPath: symlinkTarget))
        }

        if fileManager.fileExists(atPath: destination.path) {
            return CursorAgentSupportComponentStatus(destination: destination, state: .unmanaged)
        }

        return CursorAgentSupportComponentStatus(destination: destination, state: .missing)
    }

    private func installSymlink(source: URL, destination: URL) throws {
        let status = try componentStatus(destination: destination, source: source)
        switch status.state {
        case .installed:
            return
        case .stale:
            try fileManager.removeItem(at: destination)
        case .unmanaged:
            throw CursorAgentSupportInstallerError.destinationExists(destination.path)
        case .missing:
            break
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
    }

    private func installHelper() throws {
        if fileManager.fileExists(atPath: helperDestination.path) {
            try fileManager.removeItem(at: helperDestination)
        }
        try fileManager.copyItem(at: source.helperURL, to: helperDestination)
    }

    private func isCursorOperatorManagedSymlink(targetPath: String, destination: URL) -> Bool {
        if destination == cliDestination {
            return targetPath.contains("/CursorOperator.app/Contents/Library/Helpers/cursor-operator-cli")
                || (targetPath.contains("/cursor_operator/.build/") && targetPath.hasSuffix("/cursor-operator-cli"))
        }

        if skillDestinations.contains(destination) {
            return targetPath.contains("/CursorOperator.app/Contents/Resources/skills/cursor-operator")
                || targetPath.contains("/cursor_operator/skills/cursor-operator")
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
            throw CursorAgentSupportInstallerError.sourceMissing(source.cliURL.path)
        }
    }

    private func validateSkill() throws {
        guard fileManager.fileExists(atPath: source.skillURL.appending(path: "SKILL.md").path) else {
            throw CursorAgentSupportInstallerError.sourceMissing(source.skillURL.path)
        }
    }

    private func validateHelper() throws {
        guard fileManager.fileExists(atPath: source.helperURL.appending(path: "cursor-sdk-helper.mjs").path) else {
            throw CursorAgentSupportInstallerError.sourceMissing(source.helperURL.path)
        }
    }
}

public struct CursorAgentSupportStatus: Equatable, Sendable {
    public let cli: CursorAgentSupportComponentStatus
    public let skills: [CursorAgentSupportComponentStatus]

    public init(cli: CursorAgentSupportComponentStatus, skills: [CursorAgentSupportComponentStatus]) {
        self.cli = cli
        self.skills = skills
    }

    public var skillsState: CursorAgentSupportInstallState {
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

public struct CursorAgentSupportComponentStatus: Equatable, Sendable {
    public let destination: URL
    public let state: CursorAgentSupportInstallState

    public init(destination: URL, state: CursorAgentSupportInstallState) {
        self.destination = destination
        self.state = state
    }
}

public enum CursorAgentSupportInstallState: Equatable, Sendable {
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

    public var canInstall: Bool {
        switch self {
        case .missing, .stale:
            return true
        case .installed, .unmanaged:
            return false
        }
    }
}

public enum CursorAgentSupportInstallerError: LocalizedError, Equatable, Sendable {
    case sourceMissing(String)
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case let .sourceMissing(path):
            return "Cursor Operator support file is missing: \(path)"
        case let .destinationExists(path):
            return "A file already exists at \(path). Move it before installing Cursor Operator support."
        }
    }
}

private extension Bundle {
    var cursorOperatorBundledCLIURL: URL {
        url(forAuxiliaryExecutable: "cursor-operator-cli")
            ?? bundleURL.appending(path: "Contents/Library/Helpers/cursor-operator-cli")
    }

    var cursorOperatorBundledSkillURL: URL {
        url(forResource: "cursor-operator", withExtension: nil, subdirectory: "skills")
            ?? bundleURL.appending(path: "Contents/Resources/skills/cursor-operator", directoryHint: .isDirectory)
    }

    var cursorOperatorBundledHelperURL: URL {
        url(forResource: "CursorSDKHelper", withExtension: nil)
            ?? bundleURL.appending(path: "Contents/Resources/CursorSDKHelper", directoryHint: .isDirectory)
    }
}
