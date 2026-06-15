import Foundation
import Testing
@testable import OperatorDesktop

@Test func agentSupportInstallerReportsMissingDestinations() throws {
    let fixture = try AgentSupportInstallerFixture()
    let installer = OperatorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    let status = try installer.status()

    #expect(status.cli.destination.path == fixture.homeDirectory.appending(path: ".local/bin/operator").path)
    #expect(status.cli.state == .missing)
    #expect(status.skills.map(\.destination.path) == fixture.skillDestinations.map(\.path))
    #expect(status.skills.allSatisfy { $0.state == .missing })
}

@Test func agentSupportInstallerInstallsCLIAsSymlinkToBundledExecutable() throws {
    let fixture = try AgentSupportInstallerFixture()
    let installer = OperatorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    let installedURL = try installer.installCLI()

    #expect(installedURL.path == fixture.homeDirectory.appending(path: ".local/bin/operator").path)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installedURL.path) == fixture.cliSource.path)
    #expect(try installer.status().cli.state == .installed(targetPath: fixture.cliSource.path))
}

@Test func agentSupportInstallerInstallsSkillsAsSymlinksForCodexAndClaude() throws {
    let fixture = try AgentSupportInstallerFixture()
    let installer = OperatorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    let installedURLs = try installer.installSkills()

    #expect(installedURLs.map(\.path) == fixture.skillDestinations.map(\.path))
    for destination in fixture.skillDestinations {
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == fixture.skillSource.path)
    }
    #expect(try installer.status().skills.allSatisfy { $0.state == .installed(targetPath: fixture.skillSource.path) })
}

@Test func agentSupportInstallerRefusesToOverwriteUnmanagedCLIFile() throws {
    let fixture = try AgentSupportInstallerFixture()
    let destination = fixture.homeDirectory.appending(path: ".local/bin/operator")
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "existing".write(to: destination, atomically: true, encoding: .utf8)
    let installer = OperatorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    #expect(throws: OperatorAgentSupportInstallerError.destinationExists(destination.path)) {
        try installer.installCLI()
    }
}

private struct AgentSupportInstallerFixture {
    let temporaryDirectory: URL
    let homeDirectory: URL
    let cliSource: URL
    let skillSource: URL
    let source: OperatorAgentSupportSource

    var skillDestinations: [URL] {
        [
            homeDirectory.appending(path: ".codex/skills/operator"),
            homeDirectory.appending(path: ".claude/skills/operator")
        ]
    }

    init() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "OperatorAgentSupportInstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        homeDirectory = temporaryDirectory.appending(path: "home", directoryHint: .isDirectory)
        cliSource = temporaryDirectory.appending(path: "bundle/Contents/Library/Helpers/operator-cli")
        skillSource = temporaryDirectory.appending(path: "bundle/Contents/Resources/skills/operator", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: cliSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillSource, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: cliSource, atomically: true, encoding: .utf8)
        try "name: operator\n".write(to: skillSource.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

        source = OperatorAgentSupportSource(cliURL: cliSource, skillURL: skillSource)
    }
}
