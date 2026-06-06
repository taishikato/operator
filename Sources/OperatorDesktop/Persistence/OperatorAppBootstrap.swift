import Foundation

public enum OperatorAppBootstrap {
    public static func initializeStore(databaseURL: URL? = nil) throws -> OperatorStore {
        if let databaseURL {
            return try OperatorStore(databaseURL: databaseURL)
        }

        return try OperatorStore(databaseURL: applicationDataURL().appending(path: "operator.sqlite"))
    }

    public static func applicationDataURL(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL.appending(path: "Operator", directoryHint: .isDirectory)
    }
}
