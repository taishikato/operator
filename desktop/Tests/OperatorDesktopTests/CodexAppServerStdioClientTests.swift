import Foundation
import Testing
@testable import OperatorDesktop

@Test func codexAppServerStdioClientDrainsNotificationsAfterTurnStarts() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientDrain")
    let scriptURL = directory.appending(path: "server.py")
    let completionURL = directory.appending(path: "notifications-drained")
    try writeScript(
        """
        import json
        import pathlib
        import sys

        done = pathlib.Path(sys.argv[1])
        payload = "x" * 4096

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
        send({"jsonrpc": "2.0", "id": request["id"], "result": {"thread": {"id": "thread-drain"}}})

        request = read_request()
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        for index in range(512):
            send({"jsonrpc": "2.0", "method": "codex/event", "params": {"index": index, "payload": payload}})

        done.write_text("done")
        """,
        to: scriptURL
    )
    let client = CodexAppServerStdioClient(
        executableURL: URL(filePath: "/usr/bin/env"),
        arguments: ["python3", scriptURL.path, completionURL.path]
    )

    let thread = try await client.startThreadAndTurn(
        CodexThreadStartRequest(
            cwd: directory,
            model: "gpt-5.5",
            reasoningEffort: .medium,
            prompt: "Run after drain"
        )
    )

    #expect(thread.id == "thread-drain")
    #expect(thread.url == URL(string: "codex://threads/thread-drain"))
    #expect(await fileExists(at: completionURL, withinMilliseconds: 5_000))
}

@Test func codexAppServerStdioClientSerializesConcurrentStartRequests() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientSerial")
    let scriptURL = directory.appending(path: "server.py")
    let overlapURL = directory.appending(path: "overlap")
    try writeScript(
        """
        import json
        import pathlib
        import select
        import sys
        import time

        overlap = pathlib.Path(sys.argv[1])

        def read_request():
            line = sys.stdin.readline()
            if not line:
                sys.exit(1)
            return json.loads(line)

        def send(message):
            sys.stdout.write(json.dumps(message) + "\\n")
            sys.stdout.flush()

        def handle_start(thread_id):
            thread_request = read_request()
            send({"jsonrpc": "2.0", "id": thread_request["id"], "result": {"thread": {"id": thread_id}}})
            turn_request = read_request()
            send({"jsonrpc": "2.0", "id": turn_request["id"], "result": {}})

        request = read_request()
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        handle_start("warmup")

        first_thread_request = read_request()
        readable, _, _ = select.select([sys.stdin], [], [], 0.4)
        buffered_thread_request = None
        if readable:
            overlap.write_text("overlap")
            buffered_thread_request = read_request()

        if buffered_thread_request:
            for _ in range(10):
                send({"jsonrpc": "2.0", "id": first_thread_request["id"], "result": {"thread": {"id": "thread-a"}}})
                send({"jsonrpc": "2.0", "id": buffered_thread_request["id"], "result": {"thread": {"id": "thread-b"}}})
            first_turn_request = read_request()
            second_turn_request = read_request()
            for _ in range(10):
                send({"jsonrpc": "2.0", "id": first_turn_request["id"], "result": {}})
                send({"jsonrpc": "2.0", "id": second_turn_request["id"], "result": {}})
        else:
            send({"jsonrpc": "2.0", "id": first_thread_request["id"], "result": {"thread": {"id": "thread-a"}}})
            first_turn_request = read_request()
            send({"jsonrpc": "2.0", "id": first_turn_request["id"], "result": {}})
            second_thread_request = read_request()
            send({"jsonrpc": "2.0", "id": second_thread_request["id"], "result": {"thread": {"id": "thread-b"}}})
            second_turn_request = read_request()
            send({"jsonrpc": "2.0", "id": second_turn_request["id"], "result": {}})
        time.sleep(0.1)
        """,
        to: scriptURL
    )
    let client = CodexAppServerStdioClient(
        executableURL: URL(filePath: "/usr/bin/env"),
        arguments: ["python3", scriptURL.path, overlapURL.path]
    )
    _ = try await client.startThreadAndTurn(
        CodexThreadStartRequest(cwd: directory, model: "gpt-5.5", reasoningEffort: .medium, prompt: "warmup")
    )

    async let first = client.startThreadAndTurn(
        CodexThreadStartRequest(cwd: directory, model: "gpt-5.5", reasoningEffort: .medium, prompt: "first")
    )
    async let second = client.startThreadAndTurn(
        CodexThreadStartRequest(cwd: directory, model: "gpt-5.5", reasoningEffort: .medium, prompt: "second")
    )
    _ = try await [first, second]

    #expect(!FileManager.default.fileExists(atPath: overlapURL.path))
}

@Test func codexAppServerStdioClientSendsCurrentTextUserInputShape() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientTextInput")
    let scriptURL = directory.appending(path: "server.py")
    let inputURL = directory.appending(path: "turn-input.json")
    try writeScript(
        """
        import json
        import pathlib
        import sys

        input_path = pathlib.Path(sys.argv[1])

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
        send({"jsonrpc": "2.0", "id": request["id"], "result": {"thread": {"id": "thread-input"}}})

        request = read_request()
        input_path.write_text(json.dumps(request["params"]["input"]))
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})
        """,
        to: scriptURL
    )
    let client = CodexAppServerStdioClient(
        executableURL: URL(filePath: "/usr/bin/env"),
        arguments: ["python3", scriptURL.path, inputURL.path]
    )

    _ = try await client.startThreadAndTurn(
        CodexThreadStartRequest(
            cwd: directory,
            model: "gpt-5.5",
            reasoningEffort: .medium,
            prompt: "Preserve this prompt"
        )
    )

    let inputData = try Data(contentsOf: inputURL)
    let input = try #require(JSONSerialization.jsonObject(with: inputData) as? [[String: Any]])
    let textInput = try #require(input.first)
    #expect(textInput["type"] as? String == "text")
    #expect(textInput["text"] as? String == "Preserve this prompt")
    #expect((textInput["text_elements"] as? [Any])?.isEmpty == true)
}

@Test func codexAppServerStdioClientReportsMissingExecutablePathClearly() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientMissingExecutable")
    let missingBinaryURL = directory.appending(path: "missing-codex")
    let client = CodexAppServerStdioClient(codexBinaryURL: missingBinaryURL)

    await #expect(throws: CodexAppServerClientError.binaryNotFound(path: missingBinaryURL.path)) {
        try await client.startThreadAndTurn(
            CodexThreadStartRequest(
                cwd: directory,
                model: "gpt-5.5",
                reasoningEffort: .medium,
                prompt: "Run with missing executable"
            )
        )
    }
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

private func fileExists(at url: URL, withinMilliseconds timeout: Int) async -> Bool {
    let deadline = Date().addingTimeInterval(TimeInterval(timeout) / 1_000)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return FileManager.default.fileExists(atPath: url.path)
}
