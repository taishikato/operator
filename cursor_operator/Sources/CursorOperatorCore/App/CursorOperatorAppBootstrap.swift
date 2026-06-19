import Foundation

public enum CursorOperatorAppBootstrap {
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
