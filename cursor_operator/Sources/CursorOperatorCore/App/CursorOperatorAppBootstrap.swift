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
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let overridePath = environment["CURSOR_OPERATOR_APP_SUPPORT_DIR"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(filePath: overridePath)
        }

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
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        try applicationDataURL(appSpec: appSpec, fileManager: fileManager, environment: environment)
            .appending(path: appSpec.databaseFileName)
    }
}
