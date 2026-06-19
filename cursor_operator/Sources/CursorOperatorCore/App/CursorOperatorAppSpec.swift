public struct CursorOperatorAppSpec: Equatable, Sendable {
    public let displayName: String
    public let bundleIdentifier: String
    public let minimumMacOS: String
    public let applicationSupportDirectoryName: String
    public let databaseFileName: String
    public let developmentCommands: [String]

    public static let mvp = CursorOperatorAppSpec(
        displayName: "Cursor Operator",
        bundleIdentifier: "com.focus.cursor-operator",
        minimumMacOS: "26.0",
        applicationSupportDirectoryName: "Cursor Operator",
        databaseFileName: "cursor-operator.sqlite",
        developmentCommands: [
            "swift build",
            "swift test",
            "./script/build_and_run.sh"
        ]
    )
}
