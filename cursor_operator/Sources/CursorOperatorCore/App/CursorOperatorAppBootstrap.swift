import Foundation

public enum CursorOperatorAppBootstrap {
    public static func initializeStore(databaseURL: URL? = nil) throws -> CursorOperatorStore {
        if let databaseURL {
            return try CursorOperatorStore(databaseURL: databaseURL)
        }

        return try CursorOperatorStore(databaseURL: Self.databaseURL())
    }

    public static func applicationDataURL(
        appSpec: CursorOperatorAppSpec = .mvp,
        fileManager: FileManager = .default
    ) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return baseURL.appending(path: appSpec.applicationSupportDirectoryName, directoryHint: .isDirectory)
    }

    public static func databaseURL(
        appSpec: CursorOperatorAppSpec = .mvp,
        fileManager: FileManager = .default
    ) throws -> URL {
        try applicationDataURL(appSpec: appSpec, fileManager: fileManager)
            .appending(path: appSpec.databaseFileName)
    }
}
