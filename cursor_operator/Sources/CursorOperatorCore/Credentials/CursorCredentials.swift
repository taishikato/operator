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
        if let stored = try store.loadAPIKey(), !stored.isEmpty {
            return stored
        }
        return environment["CURSOR_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
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
    }

    public func deleteAPIKey() throws {
        try store.deleteAPIKey()
        validationStatus = .notValidated
        refreshStatus()
    }

    public func validateAPIKey() async {
        guard let apiKey = try? provider.apiKey(), !apiKey.isEmpty else {
            validationStatus = .invalid("Cursor API key is missing.")
            return
        }

        validationStatus = .validating
        validationStatus = await validator.validate(apiKey: apiKey)
    }

    public func refreshStatus() {
        guard let apiKey = try? provider.apiKey(), !apiKey.isEmpty else {
            status = .missing
            return
        }
        status = .present(maskedValue: Self.mask(apiKey))
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
}
