import Foundation
import Testing
@testable import CursorOperatorCore

@Test func cursorAgentSupportInstallerReportsMissingDestinations() throws {
    let fixture = try CursorAgentSupportInstallerFixture()
    let installer = CursorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    let status = try installer.status()

    #expect(status.cli.destination.path == fixture.homeDirectory.appending(path: ".local/bin/operator").path)
    #expect(status.cli.state == .missing)
    #expect(status.skills.map(\.destination.path) == fixture.skillDestinations.map(\.path))
    #expect(status.skills.allSatisfy { $0.state == .missing })
}

@Test func cursorAgentSupportInstallerInstallsCLIAndHelperFromBundle() throws {
    let fixture = try CursorAgentSupportInstallerFixture()
    let installer = CursorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    let installedURL = try installer.installCLI()

    #expect(installedURL.path == fixture.homeDirectory.appending(path: ".local/bin/operator").path)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installedURL.path) == fixture.cliSource.path)
    #expect(FileManager.default.fileExists(atPath: fixture.installedHelper.appending(path: "cursor-sdk-helper.mjs").path))
    #expect(try installer.status().cli.state == .installed(targetPath: fixture.cliSource.path))
}

@Test func cursorAgentSupportInstallerInstallsSkillsForCodexCursorAndClaude() throws {
    let fixture = try CursorAgentSupportInstallerFixture()
    let installer = CursorAgentSupportInstaller(
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

@Test func cursorAgentSupportInstallerRefusesToOverwriteUnmanagedCLIFile() throws {
    let fixture = try CursorAgentSupportInstallerFixture()
    let destination = fixture.homeDirectory.appending(path: ".local/bin/operator")
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "existing".write(to: destination, atomically: true, encoding: .utf8)
    let installer = CursorAgentSupportInstaller(
        source: fixture.source,
        homeDirectory: fixture.homeDirectory
    )

    #expect(throws: CursorAgentSupportInstallerError.destinationExists(destination.path)) {
        try installer.installCLI()
    }
}

@Test func cursorAgentSupportStatusAggregatesSkillStateTowardRepairableDestinations() {
    let home = URL(filePath: "/tmp/home", directoryHint: .isDirectory)
    let installed = CursorAgentSupportComponentStatus(
        destination: home.appending(path: ".codex/skills/operator"),
        state: .installed(targetPath: "/Operator.app/Contents/Resources/skills/operator")
    )
    let missing = CursorAgentSupportComponentStatus(
        destination: home.appending(path: ".cursor/skills/operator"),
        state: .missing
    )
    let unmanaged = CursorAgentSupportComponentStatus(
        destination: home.appending(path: ".claude/skills/operator"),
        state: .unmanaged
    )

    #expect(CursorAgentSupportStatus(cli: installed, skills: [installed, missing]).skillsState == .missing)
    #expect(CursorAgentSupportStatus(cli: installed, skills: [unmanaged, missing]).skillsState == .missing)
    #expect(CursorAgentSupportStatus(cli: installed, skills: [installed, installed]).skillsState.isInstalled)
    #expect(CursorAgentSupportStatus(cli: installed, skills: [unmanaged, installed]).skillsState == .unmanaged)
    #expect(CursorAgentSupportInstallState.missing.canInstall)
    #expect(CursorAgentSupportInstallState.stale(targetPath: "/old").canInstall)
    #expect(!CursorAgentSupportInstallState.unmanaged.canInstall)
}

@Test func cursorAgentSupportInstallerReportsMissingSources() throws {
    let fixture = try CursorAgentSupportInstallerFixture()
    let installer = CursorAgentSupportInstaller(
        source: CursorAgentSupportSource(
            cliURL: fixture.temporaryDirectory.appending(path: "missing/operator-cli"),
            skillURL: fixture.temporaryDirectory.appending(path: "missing/skill", directoryHint: .isDirectory),
            helperURL: fixture.temporaryDirectory.appending(path: "missing/CursorSDKHelper", directoryHint: .isDirectory)
        ),
        homeDirectory: fixture.homeDirectory
    )

    #expect(throws: CursorAgentSupportInstallerError.sourceMissing(fixture.temporaryDirectory.appending(path: "missing/operator-cli").path)) {
        try installer.installCLI()
    }
    #expect(throws: CursorAgentSupportInstallerError.sourceMissing(fixture.temporaryDirectory.appending(path: "missing/skill").path)) {
        try installer.installSkills()
    }
}

@Test func operatorSkillDocumentsThinCursorAndCodexCLISurface() throws {
    let skillText = try String(contentsOf: packageRoot().appending(path: "skills/operator/SKILL.md"), encoding: .utf8)

    #expect(skillText.contains("operator task send <task-id> --json"))
    #expect(skillText.contains("--harness codex"))
    #expect(skillText.contains("Cursor"))
    #expect(skillText.contains("Codex"))
    #expect(skillText.contains("wait"))
    #expect(!skillText.localizedCaseInsensitiveContains("sqlite"))
    #expect(!skillText.localizedCaseInsensitiveContains("select "))
    #expect(!skillText.localizedCaseInsensitiveContains("insert "))
    #expect(!skillText.localizedCaseInsensitiveContains("secret"))
}

private func packageRoot() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private struct CursorAgentSupportInstallerFixture {
    let temporaryDirectory: URL
    let homeDirectory: URL
    let cliSource: URL
    let skillSource: URL
    let helperSource: URL
    let source: CursorAgentSupportSource

    var installedHelper: URL {
        homeDirectory.appending(path: ".local/bin/CursorSDKHelper", directoryHint: .isDirectory)
    }

    var skillDestinations: [URL] {
        [
            homeDirectory.appending(path: ".codex/skills/operator"),
            homeDirectory.appending(path: ".cursor/skills/operator"),
            homeDirectory.appending(path: ".claude/skills/operator")
        ]
    }

    init() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CursorAgentSupportInstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        homeDirectory = temporaryDirectory.appending(path: "home", directoryHint: .isDirectory)
        cliSource = temporaryDirectory.appending(path: "bundle/Contents/Library/Helpers/operator-cli")
        skillSource = temporaryDirectory.appending(path: "bundle/Contents/Resources/skills/operator", directoryHint: .isDirectory)
        helperSource = temporaryDirectory.appending(path: "bundle/Contents/Resources/CursorSDKHelper", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: cliSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helperSource, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: cliSource, atomically: true, encoding: .utf8)
        try "name: operator\n".write(to: skillSource.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "console.log('helper')\n".write(to: helperSource.appending(path: "cursor-sdk-helper.mjs"), atomically: true, encoding: .utf8)

        source = CursorAgentSupportSource(
            cliURL: cliSource,
            skillURL: skillSource,
            helperURL: helperSource
        )
    }
}
