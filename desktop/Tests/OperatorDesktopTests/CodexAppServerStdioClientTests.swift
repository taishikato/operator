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
        import select
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

    let startedThread = try await client.startThreadAndTurn(
        CodexThreadStartRequest(
            cwd: directory,
            model: "gpt-5.5",
            reasoningEffort: .medium,
            prompt: "Run after drain"
        )
    )

    #expect(startedThread.reference.id == "thread-drain")
    #expect(startedThread.reference.url == URL(string: "codex://threads/thread-drain"))
    #expect(await fileExists(at: completionURL, withinMilliseconds: 5_000))
}

@Test func codexAppServerStdioClientCompletesTurnWatcherFromCompletedNotification() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientTurnCompleted")
    let scriptURL = directory.appending(path: "server.py")
    let completionURL = directory.appending(path: "turn-completed")
    try writeScript(
        """
        import json
        import sys

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
        send({"jsonrpc": "2.0", "id": request["id"], "result": {"thread": {"id": "thread-complete"}}})

        request = read_request()
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        send({
            "jsonrpc": "2.0",
            "method": "turn/completed",
            "params": {
                "threadId": "thread-complete",
                "turn": {"id": "turn-complete"}
            }
        })
        """,
        to: scriptURL
    )
    let client = CodexAppServerStdioClient(
        executableURL: URL(filePath: "/usr/bin/env"),
        arguments: ["python3", scriptURL.path]
    )

    let startedThread = try await client.startThreadAndTurn(
        CodexThreadStartRequest(
            cwd: directory,
            model: "gpt-5.5",
            reasoningEffort: .medium,
            prompt: "Complete watcher"
        )
    )

    Task {
        await startedThread.turnCompletion.waitUntilCompleted()
        try? "done".write(to: completionURL, atomically: true, encoding: .utf8)
    }

    #expect(startedThread.reference.id == "thread-complete")
    #expect(await fileExists(at: completionURL, withinMilliseconds: 5_000))
}

@Test func codexAppServerStdioClientCompletesTurnWatcherFromAbortedNotification() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientTurnAborted")
    let scriptURL = directory.appending(path: "server.py")
    let completionURL = directory.appending(path: "turn-aborted")
    try writeScript(
        """
        import json
        import sys

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
        send({"jsonrpc": "2.0", "id": request["id"], "result": {"thread": {"id": "thread-abort"}}})

        request = read_request()
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        send({
            "jsonrpc": "2.0",
            "method": "codex/event",
            "params": {
                "threadId": "thread-abort",
                "event": {"type": "turn_aborted"}
            }
        })
        """,
        to: scriptURL
    )
    let client = CodexAppServerStdioClient(
        executableURL: URL(filePath: "/usr/bin/env"),
        arguments: ["python3", scriptURL.path]
    )

    let startedThread = try await client.startThreadAndTurn(
        CodexThreadStartRequest(
            cwd: directory,
            model: "gpt-5.5",
            reasoningEffort: .medium,
            prompt: "Abort watcher"
        )
    )

    Task {
        await startedThread.turnCompletion.waitUntilCompleted()
        try? "done".write(to: completionURL, atomically: true, encoding: .utf8)
    }

    #expect(startedThread.reference.id == "thread-abort")
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
        import select
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

@Test func codexAppServerStdioClientDoesNotArchiveActiveThread() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientThreadName")
    let scriptURL = directory.appending(path: "server.py")
    let methodsURL = directory.appending(path: "methods.json")
    try writeScript(
        """
        import json
        import pathlib
        import select
        import sys

        methods_path = pathlib.Path(sys.argv[1])
        methods = []

        def read_request():
            line = sys.stdin.readline()
            if not line:
                sys.exit(1)
            request = json.loads(line)
            methods.append({"method": request["method"], "params": request.get("params", {})})
            return request

        def send(message):
            sys.stdout.write(json.dumps(message) + "\\n")
            sys.stdout.flush()

        request = read_request()
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        request = read_request()
        send({"jsonrpc": "2.0", "id": request["id"], "result": {"thread": {"id": "thread-named"}}})

        request = read_request()
        methods_path.write_text(json.dumps(methods))
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        readable, _, _ = select.select([sys.stdin], [], [], 0.5)
        if readable:
            request = read_request()
            methods_path.write_text(json.dumps(methods))
            send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        request = read_request()
        methods_path.write_text(json.dumps(methods))
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})
        """,
        to: scriptURL
    )
    let client = CodexAppServerStdioClient(
        executableURL: URL(filePath: "/usr/bin/env"),
        arguments: ["python3", scriptURL.path, methodsURL.path]
    )

    _ = try await client.startThreadAndTurn(
        CodexThreadStartRequest(
            cwd: directory,
            model: "gpt-5.5",
            reasoningEffort: .medium,
            prompt: "Prompt body",
            displayName: "Operator task title"
        )
    )

    let methods = try await recordedMethods(at: methodsURL, minimumCount: 4)
    #expect(methods.map { $0["method"] as? String } == [
        "initialize",
        "thread/start",
        "thread/name/set",
        "turn/start"
    ])
    #expect(methods.count >= 4)
    guard methods.count >= 4 else {
        return
    }
    let nameParams = try #require(methods[2]["params"] as? [String: Any])
    #expect(nameParams["threadId"] as? String == "thread-named")
    #expect(nameParams["name"] as? String == "Operator task title")
}

@Test func codexAppServerStdioClientSeparatesThreadCwdFromTurnCwd() async throws {
    let directory = try temporaryDirectory(named: "CodexAppServerStdioClientSeparateCwd")
    let threadCwd = directory.appending(path: "repo", directoryHint: .isDirectory)
    let turnCwd = directory.appending(path: "worktree", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: threadCwd, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: turnCwd, withIntermediateDirectories: true)
    let scriptURL = directory.appending(path: "server.py")
    let cwdURL = directory.appending(path: "cwd.json")
    try writeScript(
        """
        import json
        import pathlib
        import sys

        cwd_path = pathlib.Path(sys.argv[1])
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
        captured["thread_start_cwd"] = request["params"]["cwd"]
        send({"jsonrpc": "2.0", "id": request["id"], "result": {"thread": {"id": "thread-cwd"}}})

        request = read_request()
        captured["turn_start_cwd"] = request["params"]["cwd"]
        cwd_path.write_text(json.dumps(captured))
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})

        request = read_request()
        send({"jsonrpc": "2.0", "id": request["id"], "result": {}})
        """,
        to: scriptURL
    )
    let client = CodexAppServerStdioClient(
        executableURL: URL(filePath: "/usr/bin/env"),
        arguments: ["python3", scriptURL.path, cwdURL.path]
    )

    _ = try await client.startThreadAndTurn(
        CodexThreadStartRequest(
            cwd: turnCwd,
            threadCwd: threadCwd,
            model: "gpt-5.5",
            reasoningEffort: .medium,
            prompt: "Prompt body"
        )
    )

    let cwdData = try Data(contentsOf: cwdURL)
    let captured = try #require(JSONSerialization.jsonObject(with: cwdData) as? [String: String])
    #expect(captured["thread_start_cwd"] == threadCwd.path)
    #expect(captured["turn_start_cwd"] == turnCwd.path)
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

private func recordedMethods(at url: URL, minimumCount: Int) async throws -> [[String: Any]] {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if
            let data = try? Data(contentsOf: url),
            let methods = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            methods.count >= minimumCount
        {
            return methods
        }
        try? await Task.sleep(for: .milliseconds(50))
    }

    let data = try Data(contentsOf: url)
    return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
}
