import Foundation

/// Controls whether an Operator-triggered Codex thread is visible in the
/// Codex App sidebar while its turn is still running.
///
/// Hiding runs `codex archive <thread-id>` in a separate process. A separate
/// process is required: archiving through Operator's own app-server connection
/// shuts down the loaded thread and kills the running turn, while an external
/// `codex archive` only moves the rollout file into `archived_sessions` and
/// flags the state DB row, leaving the in-process turn untouched.
///
/// The thread's rollout file is created lazily when the first turn starts, so
/// hiding must poll until the archive command finds something to archive.
public protocol CodexThreadVisibilityControlling: Sendable {
    /// Repeatedly attempts to hide the thread until its rollout exists.
    /// Returns true when the thread was hidden. Honors task cancellation,
    /// but a hide attempt already in flight still reports success so the
    /// caller knows an unhide is required.
    @discardableResult
    func hideThread(id: String) async -> Bool

    /// Attempts to reveal a previously hidden thread. Returns true on success.
    @discardableResult
    func revealThread(id: String) async -> Bool
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
    private let timing: Timing

    public init(
        settings: any CodexBinarySettingsProviding = CodexBinarySettings(),
        timing: Timing = Timing()
    ) {
        self.settings = settings
        self.timing = timing
    }

    public func hideThread(id: String) async -> Bool {
        guard let binaryURL = effectiveBinaryURL() else {
            return false
        }

        let deadline = ContinuousClock.now + timing.hideTimeout
        while true {
            if await Self.runCodex(binaryURL: binaryURL, arguments: ["archive", id]) {
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
            if await Self.runCodex(binaryURL: binaryURL, arguments: ["unarchive", id]) {
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

    private static func runCodex(binaryURL: URL, arguments: [String]) async -> Bool {
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
