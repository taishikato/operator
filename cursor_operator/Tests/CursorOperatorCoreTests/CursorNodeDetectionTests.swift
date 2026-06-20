import Foundation
import Testing
@testable import CursorOperatorCore

@Test func nodeResolverPrefersExplicitCompatibleNodePath() throws {
    let explicit = URL(filePath: "/custom/node")
    let homebrew = URL(filePath: "/opt/homebrew/bin/node")
    let resolver = CursorNodeExecutableResolver(
        environment: ["CURSOR_NODE_PATH": explicit.path],
        candidatePaths: [homebrew],
        fileSystem: FakeNodeFileSystem(existingFiles: [explicit, homebrew]),
        versionProvider: FakeNodeVersionProvider(versions: [
            explicit: "v22.14.0",
            homebrew: "v24.0.0"
        ])
    )

    let resolved = try resolver.resolve()

    #expect(resolved.executableURL == explicit)
    #expect(resolved.version == "v22.14.0")
}

@Test func nodeResolverSkipsOldNodeAndFallsBackToCompatibleCandidate() throws {
    let old = URL(filePath: "/usr/local/bin/node")
    let compatible = URL(filePath: "/opt/homebrew/bin/node")
    let resolver = CursorNodeExecutableResolver(
        environment: ["PATH": "/usr/local/bin:/opt/homebrew/bin"],
        candidatePaths: [],
        fileSystem: FakeNodeFileSystem(existingFiles: [old, compatible]),
        versionProvider: FakeNodeVersionProvider(versions: [
            old: "v20.11.1",
            compatible: "v22.13.0"
        ])
    )

    let resolved = try resolver.resolve()

    #expect(resolved.executableURL == compatible)
    #expect(resolved.version == "v22.13.0")
}

@Test func nodeResolverDiscoversNewestCompatibleNVMNode() throws {
    let old = URL(filePath: "/Users/example/.nvm/versions/node/v20.18.0/bin/node")
    let compatible = URL(filePath: "/Users/example/.nvm/versions/node/v22.14.0/bin/node")
    let newer = URL(filePath: "/Users/example/.nvm/versions/node/v24.1.0/bin/node")
    let resolver = CursorNodeExecutableResolver(
        environment: ["HOME": "/Users/example"],
        candidatePaths: [],
        fileSystem: FakeNodeFileSystem(existingFiles: [old, compatible, newer]),
        versionProvider: FakeNodeVersionProvider(versions: [
            old: "v20.18.0",
            compatible: "v22.14.0",
            newer: "v24.1.0"
        ])
    )

    let resolved = try resolver.resolve()

    #expect(resolved.executableURL == newer)
    #expect(resolved.version == "v24.1.0")
}

@Test func processSDKHelperRunnerReportsMissingCompatibleNode() async throws {
    let runner = ProcessCursorSDKHelperRunner(nodeResolver: MissingNodeResolver())

    await #expect(throws: CursorRuntimeFailure(message: "Node.js 22.13 or newer is required for the Cursor SDK helper.")) {
        _ = try await runner.run(
            helperScriptURL: URL(filePath: "/tmp/cursor-sdk-helper.mjs"),
            request: CursorSDKHelperRequest(action: .wait, apiKey: "crsr_test_key")
        )
    }
}

@Test func processSDKHelperRunnerDrainsLargeOutputBeforeWaitingForExit() async throws {
    let helperScriptURL = try temporaryHelperScript(contents: """
    dd if=/dev/zero bs=1024 count=128 2>/dev/null | tr '\\0' 'x'
    dd if=/dev/zero bs=1024 count=128 2>/dev/null | tr '\\0' 'y' >&2
    printf '{"ok":true}\\n'
    """)
    let runner = ProcessCursorSDKHelperRunner(
        nodeResolver: ShellNodeResolver(),
        timeout: 2
    )

    let output = try await runner.run(
        helperScriptURL: helperScriptURL,
        request: CursorSDKHelperRequest(action: .wait, apiKey: "crsr_test_key")
    )

    #expect(output.count > 128 * 1024)
}

@Test func processSDKHelperRunnerTimesOutHungHelper() async throws {
    let helperScriptURL = try temporaryHelperScript(contents: "sleep 5\n")
    let runner = ProcessCursorSDKHelperRunner(
        nodeResolver: ShellNodeResolver(),
        timeout: 0.1
    )

    await #expect(throws: CursorRuntimeFailure(message: "Cursor SDK helper timed out.")) {
        _ = try await runner.run(
            helperScriptURL: helperScriptURL,
            request: CursorSDKHelperRequest(action: .wait, apiKey: "crsr_test_key")
        )
    }
}

@Test func nodeSettingsProjectionReportsDetectedNodeAndMissingNode() {
    let detected = CursorNodeSettingsProjection(
        result: .success(CursorNodeResolution(
            executableURL: URL(filePath: "/opt/homebrew/bin/node"),
            version: "v22.14.0"
        ))
    )
    let missing = CursorNodeSettingsProjection(result: .failure(.missingCompatibleNode))

    #expect(detected.status == "Detected v22.14.0")
    #expect(detected.path == "/opt/homebrew/bin/node")
    #expect(missing.status == "Missing Node.js 22.13+")
    #expect(missing.path == "Set CURSOR_NODE_PATH or install Node.js 22.13 or newer.")
}

private struct FakeNodeFileSystem: CursorNodeFileSystem {
    let existingFiles: Set<URL>

    func isExecutableFile(at url: URL) -> Bool {
        existingFiles.contains(url)
    }

    func descendantFiles(under directory: URL) -> [URL] {
        existingFiles.filter { $0.path.hasPrefix(directory.path) }
    }
}

private struct FakeNodeVersionProvider: CursorNodeVersionProviding {
    let versions: [URL: String]

    func nodeVersion(executableURL: URL) -> String? {
        versions[executableURL]
    }
}

private struct MissingNodeResolver: CursorNodeResolving {
    func resolve() throws -> CursorNodeResolution {
        throw CursorNodeResolutionError.missingCompatibleNode
    }
}

private struct ShellNodeResolver: CursorNodeResolving {
    func resolve() throws -> CursorNodeResolution {
        CursorNodeResolution(executableURL: URL(filePath: "/bin/sh"), version: "v22.13.0")
    }
}

private func temporaryHelperScript(contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CursorSDKHelperRunnerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scriptURL = directory.appending(path: "helper.sh")
    try contents.data(using: .utf8)?.write(to: scriptURL)
    return scriptURL
}
