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

@Test func agentSupportInstallerRefusesToOverwriteUnmanagedCLISymlink() throws {
    let fixture = try AgentSupportInstallerFixture()
    let destination = fixture.homeDirectory.appending(path: ".local/bin/operator")
    let otherTool = fixture.temporaryDirectory.appending(path: "other/bin/operator")
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: otherTool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\n".write(to: otherTool, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: otherTool)
    let installer = OperatorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    #expect(try installer.status().cli.state == .unmanaged)
    #expect(throws: OperatorAgentSupportInstallerError.destinationExists(destination.path)) {
        try installer.installCLI()
    }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == otherTool.path)
}

@Test func agentSupportInstallerInstallsMissingSkillDestinationWithoutOverwritingUnmanagedSibling() throws {
    let fixture = try AgentSupportInstallerFixture()
    let unmanagedDestination = fixture.homeDirectory.appending(path: ".codex/skills/operator")
    let missingDestination = fixture.homeDirectory.appending(path: ".claude/skills/operator")
    let otherSkill = fixture.temporaryDirectory.appending(path: "other/skills/operator", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: unmanagedDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: otherSkill, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: unmanagedDestination, withDestinationURL: otherSkill)
    let installer = OperatorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    try installer.installSkills()

    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: unmanagedDestination.path) == otherSkill.path)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: missingDestination.path) == fixture.skillSource.path)
}

@Test func agentSupportStatusAggregatesSkillStateTowardRepairableDestinations() {
    let home = URL(filePath: "/tmp/home", directoryHint: .isDirectory)
    let installed = OperatorAgentSupportComponentStatus(
        destination: home.appending(path: ".codex/skills/operator"),
        state: .installed(targetPath: "/Operator.app/Contents/Resources/skills/operator")
    )
    let missing = OperatorAgentSupportComponentStatus(
        destination: home.appending(path: ".claude/skills/operator"),
        state: .missing
    )
    let unmanaged = OperatorAgentSupportComponentStatus(
        destination: home.appending(path: ".codex/skills/operator"),
        state: .unmanaged
    )

    #expect(OperatorAgentSupportStatus(cli: installed, skills: [installed, missing]).skillsState == .missing)
    #expect(OperatorAgentSupportStatus(cli: installed, skills: [unmanaged, missing]).skillsState == .missing)
    #expect(OperatorAgentSupportStatus(cli: installed, skills: [installed, installed]).skillsState.isInstalled)
    #expect(OperatorAgentSupportStatus(cli: installed, skills: [unmanaged, installed]).skillsState == .unmanaged)
    #expect(OperatorAgentSupportInstallState.missing.canInstall)
    #expect(OperatorAgentSupportInstallState.stale(targetPath: "/old").canInstall)
    #expect(!OperatorAgentSupportInstallState.unmanaged.canInstall)
}

@Test func agentSupportInstallerReportsMissingSources() throws {
    let fixture = try AgentSupportInstallerFixture()
    let installer = OperatorAgentSupportInstaller(
        source: OperatorAgentSupportSource(
            cliURL: fixture.temporaryDirectory.appending(path: "missing/operator-cli"),
            skillURL: fixture.temporaryDirectory.appending(path: "missing/skill", directoryHint: .isDirectory)
        ),
        homeDirectory: fixture.homeDirectory
    )

    #expect(throws: OperatorAgentSupportInstallerError.sourceMissing(fixture.temporaryDirectory.appending(path: "missing/operator-cli").path)) {
        try installer.installCLI()
    }
    #expect(throws: OperatorAgentSupportInstallerError.sourceMissing(fixture.temporaryDirectory.appending(path: "missing/skill").path)) {
        try installer.installSkills()
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
