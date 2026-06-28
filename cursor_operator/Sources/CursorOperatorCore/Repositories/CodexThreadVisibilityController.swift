import Foundation

public protocol CodexThreadVisibilityControlling: Sendable {
    @discardableResult
    func hideThread(id: String) async -> Bool

    @discardableResult
    func revealThread(id: String) async -> Bool
}

public protocol CodexCommandRunning: Sendable {
    func runCodex(binaryURL: URL, arguments: [String]) async -> Bool
}

public struct ProcessCodexCommandRunner: CodexCommandRunning {
    public init() {}

    public func runCodex(binaryURL: URL, arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = arguments
            process.environment = CodexProcessEnvironment.augmentedEnvironment(binaryURL: binaryURL)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
    }
}

public struct CodexCLIThreadVisibilityController: CodexThreadVisibilityControlling {
    public struct Timing: Sendable {
        public let hideAttemptInterval: Duration
        public let hideTimeout: Duration
        public let revealAttempts: Int
        public let revealRetryInterval: Duration

        public init(
            hideAttemptInterval: Duration = .milliseconds(150),
            hideTimeout: Duration = .seconds(15),
            revealAttempts: Int = 3,
            revealRetryInterval: Duration = .milliseconds(300)
        ) {
            self.hideAttemptInterval = hideAttemptInterval
            self.hideTimeout = hideTimeout
            self.revealAttempts = revealAttempts
            self.revealRetryInterval = revealRetryInterval
        }
    }

    private let settings: any CodexBinarySettingsProviding
    private let commandRunner: any CodexCommandRunning
    private let timing: Timing

    public init(
        settings: any CodexBinarySettingsProviding = CodexBinarySettings(),
        commandRunner: any CodexCommandRunning = ProcessCodexCommandRunner(),
        timing: Timing = Timing()
    ) {
        self.settings = settings
        self.commandRunner = commandRunner
        self.timing = timing
    }

    public func hideThread(id: String) async -> Bool {
        guard let binaryURL = effectiveBinaryURL() else {
            return false
        }

        let deadline = ContinuousClock.now + timing.hideTimeout
        while true {
            if await commandRunner.runCodex(binaryURL: binaryURL, arguments: ["archive", id]) {
                return true
            }
            if Task.isCancelled || ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: timing.hideAttemptInterval)
            if Task.isCancelled {
                return false
            }
        }
    }

    public func revealThread(id: String) async -> Bool {
        guard let binaryURL = effectiveBinaryURL() else {
            return false
        }

        let attempts = max(timing.revealAttempts, 1)
        for attempt in 1...attempts {
            if await commandRunner.runCodex(binaryURL: binaryURL, arguments: ["unarchive", id]) {
                return true
            }
            if attempt < attempts {
                try? await Task.sleep(for: timing.revealRetryInterval)
            }
        }
        return false
    }

    private func effectiveBinaryURL() -> URL? {
        (try? settings.configuration())?.effectiveBinaryURL
    }
}
