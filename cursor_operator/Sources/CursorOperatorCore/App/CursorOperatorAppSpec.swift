public struct CursorOperatorAppSpec: Equatable, Sendable {
    public let displayName: String
    public let bundleIdentifier: String
    public let applicationSupportDirectoryName: String
    public let databaseFileName: String

    public static let mvp = CursorOperatorAppSpec(
        displayName: "Cursor Operator",
        bundleIdentifier: "com.focus.cursor-operator",
        applicationSupportDirectoryName: "Cursor Operator",
        databaseFileName: "cursor-operator.sqlite"
    )
}
