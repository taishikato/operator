import ArgumentParser
import CursorOperatorCLICore
import CursorOperatorCore
import Foundation

@main
enum CursorOperatorCLIMain {
    static func main() async {
        do {
            var command = try CursorOperatorCommand.parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            let exitCode = CursorOperatorCommand.exitCode(for: error)
            if !(error is ExitCode), !exitCode.isSuccess, CommandLine.arguments.contains("--json") {
                let failure = CursorCLIFailure(
                    exitCode: exitCode.rawValue,
                    code: "usage",
                    message: CursorOperatorCommand.message(for: error)
                )
                print((try? CursorCLIJSONOutput.encodeError(failure)) ?? "{\"error\":{\"code\":\"usage\",\"message\":\"unencodable\"}}")
                Foundation.exit(failure.exitCode)
            }
            CursorOperatorCommand.exit(withError: error)
        }
    }
}

struct CursorOperatorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "operator",
        abstract: "Drive the Operator task board from the command line.",
        discussion: """
            All domain rules are enforced by CursorOperatorCore. Exit codes: \
            2 not found, 3 lifecycle violation, 4 Cursor unavailable, \
            5 send failed, 7 invalid repository, 8 already registered, \
            70 internal.
            """,
        subcommands: [RepoCommand.self, TaskCommand.self, RunCommand.self]
    )
}

// MARK: - repo

struct RepoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repo",
        abstract: "Register and inspect repositories.",
        subcommands: [RepoList.self, RepoAdd.self]
    )
}

struct RepoAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Register a local GitHub repository."
    )

    @Argument(help: "Path to a local Git repository with a GitHub origin.", completion: .directory)
    var path: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: { try makeCommands().addRepository(path: path) }) { repository in
            "\(repository.name)  \(repository.id)  \(repository.localPath)  \(repository.githubURL)  (\(repository.defaultBranch))"
        }
    }
}

struct RepoList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List registered repositories."
    )

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: { try makeCommands().listRepositories() }) { repositories in
            repositories.map { repository in
                "\(repository.name)  \(repository.id)  \(repository.localPath)  \(repository.githubURL)  (\(repository.defaultBranch))"
            }
            .joined(separator: "\n")
        }
    }
}

// MARK: - task

struct TaskCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task",
        abstract: "Create, inspect, archive, and send tasks.",
        subcommands: [TaskAdd.self, TaskList.self, TaskShow.self, TaskArchive.self, TaskRecover.self, TaskSend.self]
    )
}

struct TaskAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create a new Ready task."
    )

    @Option(help: "Repository name or id the task belongs to.")
    var repo: String

    @Option(help: "Task title.")
    var title: String

    @Option(help: "Prompt sent to Cursor Cloud Agent verbatim.")
    var prompt: String?

    @Option(help: "Read the prompt from a file instead of --prompt.", completion: .file())
    var promptFile: String?

    @Flag(help: "Ask Cursor to create a pull request automatically.")
    var autoCreatePR = false

    @Option(help: "Harness to send this task with: cursor or codex.")
    var harness: CursorHarness = .cursor

    @Flag(help: "Send the task to Cursor Cloud Agent immediately after creating it.")
    var autoSend = false

    @OptionGroup var output: OutputOptions

    func validate() throws {
        guard (prompt == nil) != (promptFile == nil) else {
            throw ValidationError("Provide exactly one of --prompt or --prompt-file.")
        }
    }

    func run() async throws {
        do {
            let promptText: String
            if let prompt {
                promptText = prompt
            } else {
                promptText = try String(contentsOfFile: promptFile ?? "", encoding: .utf8)
            }

            let commands = try makeCommands()
            if autoSend {
                let result = try await commands.addTask(
                    repository: repo,
                    title: title,
                    prompt: promptText,
                    autoCreatePR: autoCreatePR,
                    harness: harness,
                    autoSend: true
                )
                output.emit(result) { result in
                    result.runAttempt.map(renderRunLine) ?? renderTaskLine(result.task)
                }
            } else {
                output.emit(
                    try commands.addTask(
                        repository: repo,
                        title: title,
                        prompt: promptText,
                        autoCreatePR: autoCreatePR,
                        harness: harness
                    ),
                    human: renderTaskLine
                )
            }
        } catch {
            throw output.failure(for: error)
        }
    }
}

struct TaskList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List tasks, optionally filtered."
    )

    @Option(help: "Only tasks of this repository (name or id).")
    var repo: String?

    @Option(help: "Only tasks with this status: ready, running, failed, done, or archived.")
    var status: CursorTaskStatus?

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: {
            try makeCommands().listTasks(repository: repo, status: status)
        }) { tasks in
            tasks.map(renderTaskLine).joined(separator: "\n")
        }
    }
}

struct TaskShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show one task, including its prompt."
    )

    @Argument(help: "Task id.")
    var id: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: { try makeCommands().showTask(id: id) }) { task in
            """
            id:          \(task.id)
            title:       \(task.title)
            status:      \(task.status)
            repository:  \(task.repositoryID)
            autoCreatePR:\(task.autoCreatePR)
            prompt:
            \(task.prompt)
            """
        }
    }
}

struct TaskArchive: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive a task."
    )

    @Argument(help: "Task id.")
    var id: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: { try makeCommands().archiveTask(id: id) }, human: renderTaskLine)
    }
}

struct TaskRecover: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recover",
        abstract: "Move a failed task back to Ready for retry."
    )

    @Argument(help: "Task id.")
    var id: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: { try makeCommands().recoverTask(id: id) }, human: renderTaskLine)
    }
}

struct TaskSend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send a Ready task to Cursor Cloud Agent.",
        discussion: "Use --wait to block until Cursor reports completion or failure."
    )

    @Argument(help: "Task id.")
    var id: String

    @Flag(help: "Wait for the Cursor run to complete after it starts.")
    var wait = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        do {
            if !output.json {
                let message = wait
                    ? "Sending task to Cursor; waiting for the run to complete...\n"
                    : "Sending task to Cursor...\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
            let attempt = try await makeCommands().sendTask(id: id, wait: wait)
            output.emit(attempt, human: renderRunLine)
        } catch {
            throw output.failure(for: error)
        }
    }
}

// MARK: - run

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Inspect Cursor run attempts.",
        subcommands: [RunList.self]
    )
}

struct RunList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the run attempts recorded for a task."
    )

    @Option(help: "Task id.")
    var task: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: { try makeCommands().listRuns(taskID: task) }) { runs in
            runs.map(renderRunLine).joined(separator: "\n")
        }
    }
}

// MARK: - shared plumbing

struct OutputOptions: ParsableArguments {
    @Flag(help: "Emit machine-readable JSON on stdout.")
    var json = false

    func render<T: Encodable>(running body: () throws -> T, human: (T) -> String) throws {
        do {
            emit(try body(), human: human)
        } catch {
            throw failure(for: error)
        }
    }

    func emit<T: Encodable>(_ value: T, human: (T) -> String) {
        if json {
            print((try? CursorCLIJSONOutput.encode(value)) ?? "{}")
        } else {
            print(human(value))
        }
    }

    func failure(for error: Error) -> ExitCode {
        let failure = cursorCLIFailure(for: error)
        if json {
            print((try? CursorCLIJSONOutput.encodeError(failure)) ?? "{\"error\":{\"code\":\"internal\",\"message\":\"unencodable\"}}")
        } else {
            FileHandle.standardError.write(Data("error: \(failure.message)\n".utf8))
        }
        return ExitCode(failure.exitCode)
    }
}

private func makeCommands() throws -> CursorOperatorCLICommands {
    CursorOperatorCLICommands(store: try makeStore())
}

func makeStore() throws -> CursorOperatorStore {
    try CursorOperatorAppBootstrap.initializeStore(
        databaseURL: CursorOperatorCLIEnvironment.databaseURLOverride()
    )
}

private func renderTaskLine(_ task: CursorCLITask) -> String {
    [
        "[\(task.status)] \(task.title)",
        task.id,
        "repo=\(task.repositoryID)",
        "harness=\(task.harness)",
        "reasoning=\(task.reasoningEffort)",
        "fastModel=\(task.useFastModel)",
        "autoCreatePR=\(task.autoCreatePR)"
    ].joined(separator: "  ")
}

private func renderRunLine(_ run: CursorCLIRunAttempt) -> String {
    var line = "[\(run.status)] \(run.id)  run=\(run.cursorRunID ?? "-")"
    if let url = run.cursorURL {
        line += "  url=\(url)"
    }
    if let message = run.errorMessage {
        line += "  error=\(message)"
    }
    return line
}

extension CursorTaskStatus: ExpressibleByArgument {}

extension CursorHarness: ExpressibleByArgument {}
