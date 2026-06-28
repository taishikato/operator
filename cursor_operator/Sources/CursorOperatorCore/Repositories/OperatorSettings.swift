import Foundation

public enum OperatorSettingsError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedDefaultHarness

    public var errorDescription: String? {
        switch self {
        case .unsupportedDefaultHarness:
            "Default harness must be Cursor or Codex."
        }
    }
}

public protocol OperatorSettingsStoring: Sendable {
    func defaultHarnessRawValue() -> String?
    func setDefaultHarnessRawValue(_ rawValue: String?)
}

public struct OperatorSettingsManager: Sendable {
    private let store: any OperatorSettingsStoring

    public init(store: any OperatorSettingsStoring = UserDefaultsOperatorSettingsStore()) {
        self.store = store
    }

    public func defaultHarness() -> CursorHarness {
        guard let rawValue = store.defaultHarnessRawValue(),
              let harness = CursorHarness(rawValue: rawValue),
              Self.isSupportedDefaultHarness(harness) else {
            return .cursor
        }
        return harness
    }

    public func setDefaultHarness(_ harness: CursorHarness) throws {
        guard Self.isSupportedDefaultHarness(harness) else {
            throw OperatorSettingsError.unsupportedDefaultHarness
        }
        store.setDefaultHarnessRawValue(harness.rawValue)
    }

    private static func isSupportedDefaultHarness(_ harness: CursorHarness) -> Bool {
        switch harness {
        case .cursor, .codex:
            true
        case .claudeCode:
            false
        }
    }
}

public final class UserDefaultsOperatorSettingsStore: OperatorSettingsStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let defaultHarnessKey = "operator.defaultHarness"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func defaultHarnessRawValue() -> String? {
        userDefaults.string(forKey: defaultHarnessKey)
    }

    public func setDefaultHarnessRawValue(_ rawValue: String?) {
        if let rawValue {
            userDefaults.set(rawValue, forKey: defaultHarnessKey)
        } else {
            userDefaults.removeObject(forKey: defaultHarnessKey)
        }
    }
}
