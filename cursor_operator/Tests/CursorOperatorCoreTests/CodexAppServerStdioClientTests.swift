import Foundation
import Testing
@testable import CursorOperatorCore

@Test func codexAppServerStdioClientSendsWorktreeCwdFixedModelEffortAndVerbatimPrompt() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientRequest")
    let worktreeURL = directory.appending(path: "worktree", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
    let scriptURL = directory.appending(path: "server.py")
    let capturedURL = directory.appending(path: "captured.json")
    try writeScript(
        """
        import json
        import pathlib
        import sys

        captured_path = pathlib.Path(sys.argv[1])
        captured = {}

        def read_request():
            line = sys.stdin.readline()
            if not line:
                sys.exit(1)
            return json.loads(line)

        def send(message):
            sys.stdout.write(json.dumps(message) + "\\n")
            sys.stdout.flush()

        request = read_request()
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        request = read_request()
        captured["thread_start"] = request["params"]
        send({"jsonrpc": "2.0", "id": request["id"], "result": {"thread": {"id": "thread-request"}}})

        request = read_request()
        captured["turn_start"] = request["params"]
        captured_path.write_text(json.dumps(captured))
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})
        """,
        to: scriptURL
    )
    let client = CodexAppServerStdioClient(
        executableURL: URL(filePath: "/usr/bin/env"),
        arguments: ["python3", scriptURL.path, capturedURL.path]
    )
    let prompt = "Do exactly this.\\nNo hidden additions."

    let started = try await client.startThreadAndTurn(
        CodexThreadStartRequest(
            cwd: worktreeURL,
            model: CodexModel.fixed,
            reasoningEffort: .high,
            prompt: prompt
        )
    )

    #expect(started.reference.id == "thread-request")
    #expect(started.reference.url == URL(string: "codex://threads/thread-request"))
    let data = try Data(contentsOf: capturedURL)
    let captured = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let threadStart = try #require(captured["thread_start"] as? [String: Any])
    let turnStart = try #require(captured["turn_start"] as? [String: Any])
    #expect(threadStart["cwd"] as? String == worktreeURL.path)
    #expect(threadStart["model"] as? String == CodexModel.fixed)
    #expect(turnStart["cwd"] as? String == worktreeURL.path)
    #expect(turnStart["model"] as? String == CodexModel.fixed)
    #expect(turnStart["effort"] as? String == CursorReasoningEffort.high.rawValue)
    let input = try #require(turnStart["input"] as? [[String: Any]])
    let textInput = try #require(input.first)
    #expect(textInput["text"] as? String == prompt)
    #expect((textInput["text_elements"] as? [Any])?.isEmpty == true)
}

private func writeScript(_ body: String, to url: URL) throws {
    try body.write(to: url, atomically: true, encoding: .utf8)
}

private func temporaryDirectory(named prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
