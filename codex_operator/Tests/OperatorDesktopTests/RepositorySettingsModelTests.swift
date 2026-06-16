import Foundation
import Testing
@testable import OperatorDesktop

@MainActor
@Test func repositorySettingsModelLoadsAndUpdatesDefaultBranch() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let model = RepositorySettingsModel(store: store)

    try model.loadRepositories()
    try model.updateDefaultBranch(repositoryID: repository.id, defaultBranch: "feature/desktop")

    #expect(model.repositories.map(\.id) == [repository.id])
    #expect(model.repositories.first?.defaultBranch == "feature/desktop")
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func repositorySettingsModelKeepsUpdatedBranchWhenReloadFailsAfterWrite() throws {
    let repository = OperatorRepository(
        id: UUID(),
        name: "operator",
        path: "/tmp/operator",
        defaultBranch: "main",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let store = ReloadFailingSettingsStore(repositories: [repository])
    let registrationStore = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let model = RepositorySettingsModel(
        store: store,
        registrationService: RepositoryRegistrationService(store: registrationStore)
    )

    try model.loadRepositories()
    store.failReads = true

    #expect(throws: SettingsStoreError.reloadFailed) {
        try model.updateDefaultBranch(repositoryID: repository.id, defaultBranch: "develop")
    }
    #expect(model.repositories.first?.defaultBranch == "develop")
}

@MainActor
@Test func repositorySettingsModelResyncsDefaultBranchDraftsWhenRepositoriesReload() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let model = RepositorySettingsModel(store: store)

    try model.loadRepositories()
    model.setDefaultBranchDraft("typed-but-not-saved", for: repository.id)
    _ = try store.updateRepositoryDefaultBranch(id: repository.id, defaultBranch: "develop")

    try model.loadRepositories()

    #expect(model.defaultBranchDraft(for: repository.id) == "develop")
}

@MainActor
@Test func repositorySettingsModelRegistersRepositoryAndReloadsList() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/operator")
    let service = RepositoryRegistrationService(
        store: store,
        inspector: StubRepositoryInspector(
            inspection: RepositoryInspection(name: "operator", path: repositoryURL.path, defaultBranch: "main")
        )
    )
    let model = RepositorySettingsModel(store: store, registrationService: service)

    try model.addRepository(at: repositoryURL)

    #expect(model.repositories.map(\.name) == ["operator"])
    #expect(model.repositories.first?.defaultBranch == "main")
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func repositorySettingsModelRequestsRepositoryOnboardingOnlyAfterLoadingAnEmptyList() throws {
    let emptyStore = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let emptyModel = RepositorySettingsModel(store: emptyStore)

    #expect(emptyModel.shouldShowRepositoryOnboarding == false)

    try emptyModel.loadRepositories()

    #expect(emptyModel.shouldShowRepositoryOnboarding)

    let populatedStore = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    _ = try populatedStore.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let populatedModel = RepositorySettingsModel(store: populatedStore)

    try populatedModel.loadRepositories()

    #expect(populatedModel.shouldShowRepositoryOnboarding == false)
}

@MainActor
@Test func repositorySettingsModelExposesCodexSettingsAppDataPathAndAboutInformation() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let binarySettings = CodexBinarySettings(
        store: InMemorySettingsBinaryStore(),
        detector: StubSettingsBinaryDetector(detectedURL: URL(filePath: "/opt/homebrew/bin/codex"))
    )
    let model = RepositorySettingsModel(
        store: store,
        appDataURL: URL(filePath: "/tmp/Operator", directoryHint: .isDirectory),
        codexBinarySettings: binarySettings,
        codexStatusChecker: CodexStatusChecker(runner: StubSettingsCodexStatusRunner(result: .success(.ready)))
    )

    try model.loadSettings()

    #expect(model.appDataPath == "/tmp/Operator")
    #expect(model.codexBinaryPath == "/opt/homebrew/bin/codex")
    #expect(model.codexStatus == .notChecked)
    #expect(model.aboutAppName == "Operator Desktop")
    #expect(model.aboutMinimumMacOS == "26.0 or newer")
}

@MainActor
@Test func repositorySettingsModelLoadsAndInstallsAgentSupport() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let fixture = try SettingsAgentSupportFixture()
    let model = RepositorySettingsModel(
        store: store,
        appDataURL: URL(filePath: "/tmp/Operator", directoryHint: .isDirectory),
        agentSupportInstaller: OperatorAgentSupportInstaller(
            source: fixture.source,
            homeDirectory: fixture.homeDirectory
        )
    )

    try model.loadSettings()

    #expect(model.agentSupportStatus?.cli.state == .missing)
    #expect(model.agentSupportStatus?.skills.allSatisfy { $0.state == .missing } == true)

    try model.installCLI()
    try model.installSkills()

    #expect(model.agentSupportStatus?.cli.state == .installed(targetPath: fixture.cliSource.path))
    #expect(model.agentSupportStatus?.skills.allSatisfy { $0.state == .installed(targetPath: fixture.skillSource.path) } == true)
    #expect(model.agentSupportErrorMessage == nil)
}

@MainActor
@Test func repositorySettingsModelKeepsCoreSettingsLoadedWhenAgentSupportStatusFails() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let binarySettings = CodexBinarySettings(
        store: InMemorySettingsBinaryStore(),
        detector: StubSettingsBinaryDetector(detectedURL: URL(filePath: "/opt/homebrew/bin/codex"))
    )
    let model = RepositorySettingsModel(
        store: store,
        appDataURL: URL(filePath: "/tmp/Operator", directoryHint: .isDirectory),
        codexBinarySettings: binarySettings,
        agentSupportInstaller: FailingSettingsAgentSupportInstaller(statusError: SettingsAgentSupportError.statusFailed)
    )

    try model.loadSettings()

    #expect(model.repositories.map(\.id) == [repository.id])
    #expect(model.codexBinaryPath == "/opt/homebrew/bin/codex")
    #expect(model.errorMessage == nil)
    #expect(model.agentSupportStatus == nil)
    #expect(model.agentSupportErrorMessage == "Unable to update agent support settings: status failed")
}

@MainActor
@Test func repositorySettingsModelReportsAgentSupportInstallErrorsInAgentSupportMessage() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let model = RepositorySettingsModel(
        store: store,
        agentSupportInstaller: FailingSettingsAgentSupportInstaller(installCLIError: SettingsAgentSupportError.installFailed)
    )

    model.installCLIReportingErrors()

    #expect(model.errorMessage == nil)
    #expect(model.agentSupportErrorMessage == "Unable to update agent support settings: install failed")
}

@MainActor
@Test func repositorySettingsModelAppliesAbsoluteCodexOverrideAndRejectsRelativeOverride() throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let binaryStore = InMemorySettingsBinaryStore()
    let binarySettings = CodexBinarySettings(
        store: binaryStore,
        detector: StubSettingsBinaryDetector(detectedURL: URL(filePath: "/opt/homebrew/bin/codex"))
    )
    let model = RepositorySettingsModel(
        store: store,
        appDataURL: URL(filePath: "/tmp/Operator", directoryHint: .isDirectory),
        codexBinarySettings: binarySettings,
        codexStatusChecker: CodexStatusChecker(runner: StubSettingsCodexStatusRunner(result: .success(.ready)))
    )

    try model.loadSettings()
    try model.setCodexBinaryOverride("/custom/bin/codex")

    #expect(binaryStore.overridePath == "/custom/bin/codex")
    #expect(model.codexBinaryPath == "/custom/bin/codex")
    #expect(model.errorMessage == nil)

    #expect(throws: CodexBinarySettingsError.overrideMustBeAbsolute) {
        try model.setCodexBinaryOverride("relative/codex")
    }

    #expect(binaryStore.overridePath == "/custom/bin/codex")
}

@MainActor
@Test func repositorySettingsModelRefreshesCodexStatusWithoutBlockingMainActor() async throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let binarySettings = CodexBinarySettings(
        store: InMemorySettingsBinaryStore(),
        detector: StubSettingsBinaryDetector(detectedURL: URL(filePath: "/opt/homebrew/bin/codex"))
    )
    let model = RepositorySettingsModel(
        store: store,
        appDataURL: URL(filePath: "/tmp/Operator", directoryHint: .isDirectory),
        codexBinarySettings: binarySettings,
        codexStatusChecker: CodexStatusChecker(runner: StubSettingsCodexStatusRunner(result: .success(.ready)))
    )

    try model.loadSettings()
    model.refreshCodexStatus()

    try await waitUntil {
        model.codexStatus == .ready(URL(filePath: "/opt/homebrew/bin/codex"))
    }
}

@MainActor
@Test func repositorySettingsModelIgnoresStaleCodexStatusRefreshResults() async throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let binaryStore = InMemorySettingsBinaryStore()
    let binarySettings = CodexBinarySettings(
        store: binaryStore,
        detector: StubSettingsBinaryDetector(detectedURL: URL(filePath: "/opt/homebrew/bin/codex"))
    )
    let statusRunner = SequencedSettingsCodexStatusRunner(results: [
        (.milliseconds(300), .success(.ready), URL(filePath: "/opt/homebrew/bin/codex")),
        (.milliseconds(0), .success(.ready), URL(filePath: "/custom/bin/codex"))
    ])
    let model = RepositorySettingsModel(
        store: store,
        appDataURL: URL(filePath: "/tmp/Operator", directoryHint: .isDirectory),
        codexBinarySettings: binarySettings,
        codexStatusChecker: CodexStatusChecker(runner: statusRunner)
    )

    try model.loadSettings()
    model.refreshCodexStatus()
    try model.setCodexBinaryOverride("/custom/bin/codex")
    model.refreshCodexStatus()

    try await waitUntil(timeout: .seconds(3)) {
        model.codexStatus == .ready(URL(filePath: "/custom/bin/codex"))
    }
    try await Task.sleep(for: .milliseconds(400))
    #expect(model.codexStatus == .ready(URL(filePath: "/custom/bin/codex")))
}

@MainActor
@Test func repositorySettingsModelReportsCodexConfigurationErrorDuringStatusRefresh() async throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let binarySettings = CodexBinarySettings(
        store: InMemorySettingsBinaryStore(overridePath: "relative/codex"),
        detector: StubSettingsBinaryDetector(detectedURL: URL(filePath: "/opt/homebrew/bin/codex"))
    )
    let model = RepositorySettingsModel(
        store: store,
        appDataURL: URL(filePath: "/tmp/Operator", directoryHint: .isDirectory),
        codexBinarySettings: binarySettings,
        codexStatusChecker: CodexStatusChecker(runner: StubSettingsCodexStatusRunner(result: .success(.ready)))
    )

    model.refreshCodexStatus()

    try await waitUntil {
        model.codexErrorMessage == "Codex binary override must be an absolute path."
    }
    #expect(model.codexStatus == .notFound)
}

@MainActor
@Test func repositorySettingsModelStartsRepositoryRegistrationWithoutBlockingMainActor() async throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let repositoryURL = URL(filePath: "/tmp/operator")
    let service = RepositoryRegistrationService(
        store: store,
        inspector: SlowRepositoryInspector(
            inspection: RepositoryInspection(name: "operator", path: repositoryURL.path, defaultBranch: "main")
        )
    )
    let model = RepositorySettingsModel(store: store, registrationService: service)

    let startedAt = Date()
    model.addRepositoryReportingErrors(at: repositoryURL)
    let elapsed = Date().timeIntervalSince(startedAt)

    #expect(elapsed < 0.1)
    try await waitUntil {
        model.repositories.map(\.name) == ["operator"]
    }
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func repositorySettingsModelKeepsListAndShowsRegistrationError() async throws {
    let store = try OperatorStore(databaseURL: temporarySettingsDatabaseURL())
    let existingRepository = try store.createRepository(name: "operator", path: "/tmp/operator", defaultBranch: "main")
    let invalidURL = URL(filePath: "/tmp/not-a-repo")
    let service = RepositoryRegistrationService(
        store: store,
        inspector: StubRepositoryInspector(error: .invalidGitRepository(path: invalidURL.path))
    )
    let model = RepositorySettingsModel(store: store, registrationService: service)

    model.loadRepositoriesReportingErrors()
    model.addRepositoryReportingErrors(at: invalidURL)

    try await waitUntil {
        model.errorMessage == "Selected folder is not a Git repository."
    }
    #expect(model.repositories.map(\.id) == [existingRepository.id])
    #expect(model.isAddingRepository == false)
}

private struct SlowRepositoryInspector: RepositoryInspecting {
    let inspection: RepositoryInspection

    func inspect(_ repositoryURL: URL) throws -> RepositoryInspection {
        Thread.sleep(forTimeInterval: 0.3)
        return inspection
    }
}

private final class ReloadFailingSettingsStore: RepositorySettingsStoring, @unchecked Sendable {
    var repositoriesValue: [OperatorRepository]
    var failReads = false

    init(repositories: [OperatorRepository]) {
        repositoriesValue = repositories
    }

    func repositories() throws -> [OperatorRepository] {
        if failReads {
            throw SettingsStoreError.reloadFailed
        }
        return repositoriesValue
    }

    func updateRepositoryDefaultBranch(
        id: UUID,
        defaultBranch: String,
        now: Date
    ) throws -> OperatorRepository {
        guard let index = repositoriesValue.firstIndex(where: { $0.id == id }) else {
            throw OperatorStoreError.repositoryNotFound
        }
        let existingRepository = repositoriesValue[index]
        let updatedRepository = OperatorRepository(
            id: existingRepository.id,
            name: existingRepository.name,
            path: existingRepository.path,
            defaultBranch: defaultBranch,
            createdAt: existingRepository.createdAt,
            updatedAt: now
        )
        repositoriesValue[index] = updatedRepository
        return updatedRepository
    }
}

private enum SettingsStoreError: Error, Equatable {
    case reloadFailed
}

private struct StubRepositoryInspector: RepositoryInspecting {
    let inspection: RepositoryInspection?
    let error: RepositoryRegistrationError?

    init(inspection: RepositoryInspection) {
        self.inspection = inspection
        error = nil
    }

    init(error: RepositoryRegistrationError) {
        inspection = nil
        self.error = error
    }

    func inspect(_ repositoryURL: URL) throws -> RepositoryInspection {
        if let error {
            throw error
        }
        return inspection!
    }
}

private struct SettingsAgentSupportFixture {
    let temporaryDirectory: URL
    let homeDirectory: URL
    let cliSource: URL
    let skillSource: URL
    let source: OperatorAgentSupportSource

    init() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "RepositorySettingsAgentSupportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        homeDirectory = temporaryDirectory.appending(path: "home", directoryHint: .isDirectory)
        cliSource = temporaryDirectory.appending(path: "bundle/Contents/Library/Helpers/operator-cli")
        skillSource = temporaryDirectory.appending(path: "bundle/Contents/Resources/skills/operator", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: cliSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillSource, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: cliSource, atomically: true, encoding: .utf8)
        try "name: operator\n".write(to: skillSource.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

        source = OperatorAgentSupportSource(cliURL: cliSource, skillURL: skillSource)
    }
}

private struct FailingSettingsAgentSupportInstaller: OperatorAgentSupportInstalling {
    var statusError: Error?
    var installCLIError: Error?
    var installSkillsError: Error?

    func status() throws -> OperatorAgentSupportStatus {
        if let statusError {
            throw statusError
        }
        return OperatorAgentSupportStatus(
            cli: OperatorAgentSupportComponentStatus(destination: URL(filePath: "/tmp/operator"), state: .missing),
            skills: []
        )
    }

    func installCLI() throws -> URL {
        if let installCLIError {
            throw installCLIError
        }
        return URL(filePath: "/tmp/operator")
    }

    func installSkills() throws -> [URL] {
        if let installSkillsError {
            throw installSkillsError
        }
        return []
    }
}

private enum SettingsAgentSupportError: Error, LocalizedError {
    case statusFailed
    case installFailed

    var errorDescription: String? {
        switch self {
        case .statusFailed:
            return "status failed"
        case .installFailed:
            return "install failed"
        }
    }
}

private final class InMemorySettingsBinaryStore: CodexBinarySettingsStoring, @unchecked Sendable {
    var overridePath: String?

    init(overridePath: String? = nil) {
        self.overridePath = overridePath
    }

    func codexBinaryOverridePath() -> String? {
        overridePath
    }

    func setCodexBinaryOverridePath(_ path: String?) {
        overridePath = path
    }
}

private struct StubSettingsBinaryDetector: CodexBinaryDetecting {
    let detectedURL: URL?

    func detectedCodexBinaryURL() -> URL? {
        detectedURL
    }
}

private struct StubSettingsCodexStatusRunner: CodexStatusRunning {
    let result: Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure>

    func runCodexStatus(binaryURL: URL) async -> Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure> {
        result
    }
}

private final class SequencedSettingsCodexStatusRunner: CodexStatusRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduledResults: [(Duration, Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure>, URL)]

    init(results: [(Duration, Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure>, URL)]) {
        scheduledResults = results
    }

    func runCodexStatus(binaryURL: URL) async -> Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure> {
        let scheduledResult: (Duration, Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure>, URL) = lock.withLock {
            scheduledResults.removeFirst()
        }
        try? await Task.sleep(for: scheduledResult.0)
        guard scheduledResult.2 == binaryURL else {
            return .failure(.notAuthenticatedOrUnavailable("Unexpected binary URL"))
        }
        return scheduledResult.1
    }
}

private func temporarySettingsDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "RepositorySettingsModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline {
            throw NSError(
                domain: "RepositorySettingsModelTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for condition."]
            )
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
