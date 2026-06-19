import CursorOperatorCore
import Foundation

@main
struct CursorOperatorSmokeSupport {
    static func main() throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            throw SmokeSupportError.usage
        }
        arguments.removeFirst()

        switch command {
        case "seed-ready":
            let options = try SmokeOptions(arguments)
            let taskID = try seedReadyTask(options: options)
            print(taskID.uuidString)
        case "wait-done":
            let options = try SmokeOptions(arguments)
            try waitDone(options: options)
            print("done")
        case "cleanup":
            let options = try SmokeOptions(arguments)
            try FileManager.default.removeItem(at: options.databaseURL.deletingLastPathComponent())
        default:
            throw SmokeSupportError.usage
        }
    }

    private static func seedReadyTask(options: SmokeOptions) throws -> UUID {
        let store = try CursorOperatorStore(databaseURL: options.databaseURL)
        let repository = try store.createRepository(
            name: "ui-send-smoke",
            localPath: options.localPath,
            githubURL: options.repositoryURL,
            defaultBranch: options.startingRef
        )
        let task = try store.createTask(
            repositoryID: repository.id,
            title: "UI Send smoke",
            prompt: options.prompt
        )
        return task.id
    }

    private static func waitDone(options: SmokeOptions) throws {
        guard let taskID = options.taskID else {
            throw SmokeSupportError.missingOption("--task-id")
        }

        let deadline = Date().addingTimeInterval(options.timeout)
        let store = try CursorOperatorStore(databaseURL: options.databaseURL)
        while Date() < deadline {
            if try store.task(id: taskID)?.status == .done {
                return
            }
            Thread.sleep(forTimeInterval: 2)
        }

        let status = try store.task(id: taskID)?.status.rawValue ?? "missing"
        throw SmokeSupportError.timedOut(status: status)
    }
}

private struct SmokeOptions {
    let databaseURL: URL
    let repositoryURL: URL
    let startingRef: String
    let localPath: String
    let prompt: String
    let taskID: UUID?
    let timeout: TimeInterval

    init(_ arguments: [String]) throws {
        let values = try Self.parse(arguments)
        guard let databasePath = values["--database"] else {
            throw SmokeSupportError.missingOption("--database")
        }
        guard let repositoryURLString = values["--repository-url"],
              let repositoryURL = URL(string: repositoryURLString) else {
            throw SmokeSupportError.missingOption("--repository-url")
        }
        guard let startingRef = values["--starting-ref"], !startingRef.isEmpty else {
            throw SmokeSupportError.missingOption("--starting-ref")
        }

        databaseURL = URL(filePath: databasePath)
        self.repositoryURL = repositoryURL
        self.startingRef = startingRef
        localPath = values["--local-path"] ?? FileManager.default.temporaryDirectory
            .appending(path: "cursor-operator-ui-smoke-repo", directoryHint: .isDirectory)
            .path
        prompt = values["--prompt"] ?? "Please reply with exactly: cursor operator ui send smoke ok. Do not modify files or create a pull request."
        taskID = values["--task-id"].flatMap(UUID.init(uuidString:))
        timeout = values["--timeout"].flatMap(TimeInterval.init) ?? 600
    }

    private static func parse(_ arguments: [String]) throws -> [String: String] {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw SmokeSupportError.usage
            }
            values[key] = arguments[index + 1]
            index += 2
        }
        return values
    }
}

private enum SmokeSupportError: Error, CustomStringConvertible {
    case usage
    case missingOption(String)
    case timedOut(status: String)

    var description: String {
        switch self {
        case .usage:
            "usage: CursorOperatorSmokeSupport seed-ready|wait-done|cleanup --database PATH --repository-url URL --starting-ref REF [--task-id UUID] [--timeout SECONDS]"
        case let .missingOption(option):
            "missing required option \(option)"
        case let .timedOut(status):
            "timed out waiting for task to reach done; current status: \(status)"
        }
    }
}
