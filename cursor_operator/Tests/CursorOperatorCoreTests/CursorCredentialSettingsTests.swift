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
