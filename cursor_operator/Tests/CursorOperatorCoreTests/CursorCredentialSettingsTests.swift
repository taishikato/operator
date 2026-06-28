import Foundation
import Testing
@testable import CursorOperatorCore

@Test func credentialStoreSavesLoadsAndDeletesAPIKey() throws {
    let storage = InMemoryCursorCredentialStore()

    try storage.saveAPIKey("crsr_test_key")
    #expect(try storage.loadAPIKey() == "crsr_test_key")

    try storage.deleteAPIKey()
    #expect(try storage.loadAPIKey() == nil)
}

@Test func codexBinaryOverrideRejectsRelativePath() throws {
    let settings = CodexBinarySettings(
        store: InMemoryCodexBinarySettingsStore(),
        detector: StubCodexBinaryDetector(detectedBinaryURL: nil)
    )

    #expect(throws: CodexBinarySettingsError.overrideMustBeAbsolute) {
        try settings.setOverridePath("bin/codex")
    }
}

@Test func credentialProviderUsesEnvironmentFallbackWhenKeychainIsMissing() throws {
    let storage = InMemoryCursorCredentialStore()
    let provider = CursorCredentialProvider(
        store: storage,
        environment: ["CURSOR_API_KEY": "crsr_env_key"]
    )

    #expect(try provider.apiKey() == "crsr_env_key")
}

@Test func credentialProviderPrefersEnvironmentBeforeStoredKey() throws {
    let storage = InMemoryCursorCredentialStore(apiKey: "crsr_stored_key")
    let provider = CursorCredentialProvider(
        store: storage,
        environment: ["CURSOR_API_KEY": "crsr_env_key"]
    )

    #expect(try provider.apiKey() == "crsr_env_key")
}

@Test func credentialProviderIgnoresAllSourcesWhenTestHookIsEnabled() throws {
    let storage = InMemoryCursorCredentialStore(apiKey: "crsr_stored_key")
    let provider = CursorCredentialProvider(
        store: storage,
        environment: [
            "CURSOR_API_KEY": "crsr_env_key",
            "CURSOR_OPERATOR_IGNORE_CREDENTIALS": "1"
        ]
    )

    #expect(try provider.apiKey() == nil)
    #expect(try CursorSendReadiness(provider: provider).credentialState() == .missing)
}

@MainActor
@Test func settingsModelReportsMaskedStatusAndValidationResults() async throws {
    let storage = InMemoryCursorCredentialStore()
    let validator = FakeCursorCredentialValidator(result: .valid)
    let model = CursorCredentialSettingsModel(
        provider: CursorCredentialProvider(store: storage, environment: [:]),
        store: storage,
        validator: validator
    )

    try model.saveAPIKey("crsr_1234567890")
    #expect(model.status == .present(maskedValue: "crsr...7890"))

    await model.validateAPIKey()
    #expect(model.validationStatus == .valid)
    #expect(validator.validatedKeys == ["crsr_1234567890"])

    try model.deleteAPIKey()
    #expect(model.status == .missing)
}

@MainActor
@Test func settingsModelMapsValidationFailureAndSendReadiness() async throws {
    let storage = InMemoryCursorCredentialStore()
    let model = CursorCredentialSettingsModel(
        provider: CursorCredentialProvider(store: storage, environment: [:]),
        store: storage,
        validator: FakeCursorCredentialValidator(result: .invalid("Unauthorized"))
    )

    #expect(try CursorSendReadiness(provider: model.provider).credentialState() == .missing)

    try model.saveAPIKey("crsr_bad")
    await model.validateAPIKey()

    #expect(model.validationStatus == .invalid("Unauthorized"))
    #expect(try CursorSendReadiness(provider: model.provider).credentialState() == .ready)
}

@Test func credentialValidationStatusLabelsPrefixCheckAsFormatOnly() {
    #expect(CursorCredentialValidationStatus.valid.displayMessage == "Format looks valid")
    #expect(CursorCredentialValidationStatus.validating.displayMessage == "Validating...")
    #expect(CursorCredentialValidationStatus.notValidated.displayMessage == "Not validated")
    #expect(CursorCredentialValidationStatus.invalid("Unauthorized").displayMessage == "Unauthorized")
}

@MainActor
@Test func settingsModelSurfacesCredentialStoreFailures() throws {
    let storage = ThrowingCursorCredentialStore(saveError: CursorCredentialError.keychain(-25293))
    let model = CursorCredentialSettingsModel(
        provider: CursorCredentialProvider(store: storage, environment: [:]),
        store: storage,
        validator: FakeCursorCredentialValidator(result: .valid)
    )

    #expect(model.saveAPIKeyReportingErrors("crsr_secret") == false)
    #expect(model.credentialErrorMessage == "Unable to access the Cursor API key in Keychain.")
}

@MainActor
@Test func settingsModelPostsCredentialChangeNotificationAfterSuccessfulSave() throws {
    let storage = InMemoryCursorCredentialStore()
    let model = CursorCredentialSettingsModel(
        provider: CursorCredentialProvider(store: storage, environment: [:]),
        store: storage,
        validator: FakeCursorCredentialValidator(result: .valid)
    )
    let recorder = NotificationRecorder()
    let observer = NotificationCenter.default.addObserver(
        forName: .cursorOperatorCredentialsChanged,
        object: nil,
        queue: nil
    ) { notification in
        recorder.append(notification.name)
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    #expect(model.saveAPIKeyReportingErrors("crsr_secret") == true)

    #expect(recorder.names == [.cursorOperatorCredentialsChanged])
}

private final class FakeCursorCredentialValidator: CursorCredentialValidating, @unchecked Sendable {
    let result: CursorCredentialValidationStatus
    private(set) var validatedKeys: [String] = []

    init(result: CursorCredentialValidationStatus) {
        self.result = result
    }

    func validate(apiKey: String) async -> CursorCredentialValidationStatus {
        validatedKeys.append(apiKey)
        return result
    }
}

private final class ThrowingCursorCredentialStore: CursorCredentialStoring, @unchecked Sendable {
    private let saveError: Error?
    private let loadError: Error?
    private let deleteError: Error?

    init(saveError: Error? = nil, loadError: Error? = nil, deleteError: Error? = nil) {
        self.saveError = saveError
        self.loadError = loadError
        self.deleteError = deleteError
    }

    func saveAPIKey(_ apiKey: String) throws {
        if let saveError {
            throw saveError
        }
    }

    func loadAPIKey() throws -> String? {
        if let loadError {
            throw loadError
        }
        return nil
    }

    func deleteAPIKey() throws {
        if let deleteError {
            throw deleteError
        }
    }
}

private final class NotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedNames: [Notification.Name] = []

    var names: [Notification.Name] {
        lock.withLock { recordedNames }
    }

    func append(_ name: Notification.Name) {
        lock.withLock {
            recordedNames.append(name)
        }
    }
}

private final class InMemoryCodexBinarySettingsStore: CodexBinarySettingsStoring, @unchecked Sendable {
    private var overridePath: String?

    func codexBinaryOverridePath() -> String? {
        overridePath
    }

    func setCodexBinaryOverridePath(_ path: String?) {
        overridePath = path
    }
}

private struct StubCodexBinaryDetector: CodexBinaryDetecting {
    let detectedBinaryURL: URL?

    func detectedCodexBinaryURL() -> URL? {
        detectedBinaryURL
    }
}
