import ArgumentParser
import Foundation
import OperatorCLICore
import OperatorDesktop

@main
struct OperatorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "operator",
        abstract: "Drive the Operator task board from the command line.",
        discussion: """
            All domain rules (task lifecycle, one successful run per task, \
            no hard delete) are enforced by the same OperatorDesktop library \
            the app uses. Exit codes: 2 not found, 3 lifecycle violation, \
            4 Codex unavailable, 5 send failed, 6 timeout, 7 invalid \
            repository, 8 already registered, 70 internal.
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
        abstract: "Register a local Git repository (validates the path and infers the default branch)."
    )

    @Argument(help: "Path to a local Git repository (any path inside it works).", completion: .directory)
    var path: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: { try makeCommands().addRepository(path: path) }) { repository in
            "\(repository.name)  \(repository.id)  \(repository.path)  (\(repository.defaultBranch))"
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
                "\(repository.name)  \(repository.id)  \(repository.path)  (\(repository.defaultBranch))"
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
        subcommands: [TaskAdd.self, TaskList.self, TaskShow.self, TaskArchive.self, TaskSend.self]
    )
}

struct TaskAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create a new Ready task."
    )

    @Option(help: "Repository name or id the task belongs to.")
    var repo: String

    @Option(help: "Task title.")
    var title: String

    @Option(help: "Task prompt, sent to Codex verbatim.")
    var prompt: String?

    @Option(help: "Read the prompt from a file instead of --prompt.", completion: .file())
    var promptFile: String?

    @Option(help: "Reasoning effort: low, medium, high, or xhigh.")
    var effort: ReasoningEffort = .medium

    @OptionGroup var output: OutputOptions

    func validate() throws {
        guard (prompt == nil) != (promptFile == nil) else {
            throw ValidationError("Provide exactly one of --prompt or --prompt-file.")
        }
    }

    func run() throws {
        try output.render(running: {
            let promptText: String
            if let prompt {
                promptText = prompt
            } else {
                promptText = try String(contentsOfFile: promptFile ?? "", encoding: .utf8)
            }
            return try makeCommands().addTask(
                repository: repo,
                title: title,
                prompt: promptText,
                effort: effort
            )
        }, human: renderTaskLine)
    }
}

struct TaskList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List tasks, optionally filtered."
    )

    @Option(help: "Only tasks of this repository (name or id).")
    var repo: String?

    @Option(help: "Only tasks with this status: ready, review, done, or archived.")
    var status: TaskStatus?

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
            id:         \(task.id)
            title:      \(task.title)
            status:     \(task.status)
            repository: \(task.repositoryID)
            effort:     \(task.reasoningEffort)
            prompt:
            \(task.prompt)
            """
        }
    }
}

struct TaskArchive: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive a task (the only manual status change)."
    )

    @Argument(help: "Task id.")
    var id: String

    @OptionGroup var output: OutputOptions

    func run() throws {
        try output.render(running: { try makeCommands().archiveTask(id: id) }, human: renderTaskLine)
    }
}

struct TaskSend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send a Ready task to Codex and wait for the turn to finish.",
        discussion: """
            The Codex app-server runs as a child of this process, so exiting \
            early (Ctrl-C, --timeout) aborts the turn. There is deliberately \
            no --no-wait.
            """
    )

    @Argument(help: "Task id.")
    var id: String

    @Option(help: "Give up after this many seconds (aborts the turn on exit).")
    var timeout: Double?

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let store: OperatorStore
        do {
            store = try makeStore()
        } catch {
            throw output.failure(for: error)
        }

        let settings = CodexBinarySettings()
        let trigger = CodexTriggerService(
            store: store,
            worktreePreparer: WorktreePreparer(
                appDataURL: try OperatorAppBootstrap.applicationDataURL(),
                worktreeRootURL: OperatorAppBootstrap.codexWorktreesURL()
            ),
            appServerClientFactory: ConfiguredCodexAppServerClientFactory(settings: settings)
        )

        if !output.json {
            FileHandle.standardError.write(Data("Sending task to Codex; waiting for the turn to complete (Ctrl-C aborts the turn)...\n".utf8))
        }

        do {
            let run = try await OperatorCLICommands(store: store).sendTask(
                id: id,
                using: trigger,
                timeout: timeout
            )
            output.emit(run, human: renderRunLine)
        } catch {
            throw output.failure(for: error)
        }
    }
}

// MARK: - run

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Inspect trigger attempts.",
        subcommands: [RunList.self]
    )
}

struct RunList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the runs recorded for a task."
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

    /// Runs `body`, prints its result (JSON or human), and maps any thrown
    /// error to the documented exit-code contract.
    func render<T: Encodable>(running body: () throws -> T, human: (T) -> String) throws {
        do {
            emit(try body(), human: human)
        } catch {
            throw failure(for: error)
        }
    }

    func emit<T: Encodable>(_ value: T, human: (T) -> String) {
        if json {
            // Encoding our own Encodable DTOs cannot realistically fail.
            print((try? CLIJSONOutput.encode(value)) ?? "{}")
        } else {
            print(human(value))
        }
    }

    /// Prints the mapped failure (JSON to stdout, human text to stderr) and
    /// returns the exit code to throw.
    func failure(for error: Error) -> ExitCode {
        let failure = cliFailure(for: error)
        if json {
            print((try? CLIJSONOutput.encodeError(failure)) ?? "{\"error\":{\"code\":\"internal\",\"message\":\"unencodable\"}}")
        } else {
            FileHandle.standardError.write(Data("error: \(failure.message)\n".utf8))
        }
        return ExitCode(failure.exitCode)
    }
}

private func makeCommands() throws -> OperatorCLICommands {
    OperatorCLICommands(store: try makeStore())
}

func makeStore() throws -> OperatorStore {
    try OperatorAppBootstrap.initializeStore(
        databaseURL: OperatorCLIEnvironment.databaseURLOverride()
    )
}

private func renderTaskLine(_ task: CLITask) -> String {
    "[\(task.status)] \(task.title)  \(task.id)  repo=\(task.repositoryID)  effort=\(task.reasoningEffort)"
}

private func renderRunLine(_ run: CLIRun) -> String {
    var line = "[\(run.status)] \(run.id)  worktree=\(run.worktreePath)"
    if let thread = run.codexThreadID {
        line += "  thread=\(thread)"
    }
    if let message = run.errorMessage {
        line += "  error=\(message)"
    }
    return line
}

extension ReasoningEffort: ExpressibleByArgument {}
extension TaskStatus: ExpressibleByArgument {}
