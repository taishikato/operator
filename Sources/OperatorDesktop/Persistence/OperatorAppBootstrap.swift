import Foundation

public enum OperatorAppBootstrap {
    public static func initializeStore(databaseURL: URL? = nil) throws -> OperatorStore {
        if let databaseURL {
            return try OperatorStore(databaseURL: databaseURL)
        }

        return try OperatorStore.applicationSupportStore()
    }
}
