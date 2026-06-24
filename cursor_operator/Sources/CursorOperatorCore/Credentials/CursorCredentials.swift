import Combine
import Foundation
import Security

public protocol CursorCredentialStoring: AnyObject, Sendable {
    func saveAPIKey(_ apiKey: String) throws
    func loadAPIKey() throws -> String?
    func deleteAPIKey() throws
}

public final class InMemoryCursorCredentialStore: CursorCredentialStoring, @unchecked Sendable {
    private var apiKey: String?

    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    public func saveAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
    }

    public func loadAPIKey() throws -> String? {
        apiKey
    }

    public func deleteAPIKey() throws {
        apiKey = nil
    }
}

public final class KeychainCursorCredentialStore: CursorCredentialStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.focus.cursor-operator",
        account: String = "Cursor API Key"
    ) {
        self.service = service
        self.account = account
    }

    public func saveAPIKey(_ apiKey: String) throws {
        try deleteAPIKey()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(apiKey.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CursorCredentialError.keychain(status)
        }
    }

    public func loadAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            throw CursorCredentialError.keychain(status)
        }
        return apiKey
    }

    public func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CursorCredentialError.keychain(status)
        }
    }
}

public enum CursorCredentialError: Error, Equatable, LocalizedError, Sendable {
    case keychain(OSStatus)

    public var errorDescription: String? {
        "Unable to access the Cursor API key in Keychain."
    }
}

public struct CursorCredentialProvider: Sendable {
    private let store: any CursorCredentialStoring
    private let environment: [String: String]

    public init(
        store: any CursorCredentialStoring,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.store = store
        self.environment = environment
    }

    public func apiKey() throws -> String? {
        if Self.credentialsIgnored(in: environment) {
            return nil
        }
        if let apiKey = environment["CURSOR_API_KEY"], !apiKey.isEmpty {
            return apiKey
        }
        if let stored = try store.loadAPIKey(), !stored.isEmpty {
            return stored
        }
        return nil
    }

    private static func credentialsIgnored(in environment: [String: String]) -> Bool {
        guard let value = environment["CURSOR_OPERATOR_IGNORE_CREDENTIALS"] else {
            return false
        }
        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}

public enum CursorCredentialPresenceStatus: Equatable, Sendable {
    case missing
    case present(maskedValue: String)
}

public enum CursorCredentialValidationStatus: Equatable, Sendable {
    case notValidated
    case validating
    case valid
    case invalid(String)

    public var displayMessage: String {
        switch self {
        case .notValidated:
            "Not validated"
        case .validating:
            "Validating..."
        case .valid:
            "Format looks valid"
        case let .invalid(message):
            message
        }
    }
}

public protocol CursorCredentialValidating: Sendable {
    func validate(apiKey: String) async -> CursorCredentialValidationStatus
}

public struct PrefixCursorCredentialValidator: CursorCredentialValidating {
    public init() {}

    public func validate(apiKey: String) async -> CursorCredentialValidationStatus {
        apiKey.hasPrefix("crsr_") ? .valid : .invalid("Cursor API key should start with crsr_.")
    }
}

@MainActor
public final class CursorCredentialSettingsModel: ObservableObject {
    public let provider: CursorCredentialProvider

    @Published public private(set) var status: CursorCredentialPresenceStatus
    @Published public private(set) var validationStatus: CursorCredentialValidationStatus
    @Published public private(set) var credentialErrorMessage: String?

    private let store: any CursorCredentialStoring
    private let validator: any CursorCredentialValidating

    public init(
        provider: CursorCredentialProvider,
        store: any CursorCredentialStoring,
        validator: any CursorCredentialValidating
    ) {
        self.provider = provider
        self.store = store
        self.validator = validator
        status = .missing
        validationStatus = .notValidated
        credentialErrorMessage = nil
        refreshStatus()
    }

    public convenience init(
        store: any CursorCredentialStoring = KeychainCursorCredentialStore(),
        validator: any CursorCredentialValidating = PrefixCursorCredentialValidator()
    ) {
        self.init(
            provider: CursorCredentialProvider(store: store),
            store: store,
            validator: validator
        )
    }

    public func saveAPIKey(_ apiKey: String) throws {
        try store.saveAPIKey(apiKey)
        validationStatus = .notValidated
        refreshStatus()
        NotificationCenter.default.post(name: .cursorOperatorCredentialsChanged, object: nil)
    }

    public func deleteAPIKey() throws {
        try store.deleteAPIKey()
        validationStatus = .notValidated
        refreshStatus()
        NotificationCenter.default.post(name: .cursorOperatorCredentialsChanged, object: nil)
    }

    @discardableResult
    public func saveAPIKeyReportingErrors(_ apiKey: String) -> Bool {
        do {
            try saveAPIKey(apiKey)
            return true
        } catch {
            credentialErrorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    public func deleteAPIKeyReportingErrors() -> Bool {
        do {
            try deleteAPIKey()
            return true
        } catch {
            credentialErrorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func validateAPIKey() async {
        let apiKey: String?
        do {
            apiKey = try provider.apiKey()
            credentialErrorMessage = nil
        } catch {
            validationStatus = .invalid(Self.userFacingMessage(for: error))
            credentialErrorMessage = Self.userFacingMessage(for: error)
            return
        }

        guard let apiKey, !apiKey.isEmpty else {
            validationStatus = .invalid("Cursor API key is missing.")
            return
        }

        validationStatus = .validating
        validationStatus = await validator.validate(apiKey: apiKey)
    }

    public func refreshStatus() {
        let apiKey: String?
        do {
            apiKey = try provider.apiKey()
            credentialErrorMessage = nil
        } catch {
            status = .missing
            credentialErrorMessage = Self.userFacingMessage(for: error)
            return
        }

        guard let apiKey, !apiKey.isEmpty else {
            status = .missing
            return
        }
        status = .present(maskedValue: Self.mask(apiKey))
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Cursor Operator could not update the Cursor API key."
    }

    private static func mask(_ apiKey: String) -> String {
        guard apiKey.count > 8 else {
            return "...."
        }
        return "\(apiKey.prefix(4))...\(apiKey.suffix(4))"
    }
}

public enum CursorCredentialState: Equatable, Sendable {
    case missing
    case ready
}

public struct CursorSendReadiness: Sendable {
    private let provider: CursorCredentialProvider

    public init(provider: CursorCredentialProvider) {
        self.provider = provider
    }

    public func credentialState() throws -> CursorCredentialState {
        guard let apiKey = try provider.apiKey(), !apiKey.isEmpty else {
            return .missing
        }
        return .ready
    }

    public func apiKeyForSending() throws -> String {
        guard let apiKey = try provider.apiKey(), !apiKey.isEmpty else {
            throw CursorTaskSendError.missingCredentials
        }
        return apiKey
    }
}
