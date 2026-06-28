public struct CursorOperatorAppSpec: Equatable, Sendable {
    public let displayName: String
    public let bundleIdentifier: String
    public let applicationSupportDirectoryName: String
    public let databaseFileName: String

    public static let mvp = CursorOperatorAppSpec(
        displayName: "Operator",
        bundleIdentifier: "com.focus.operator",
        applicationSupportDirectoryName: "Operator",
        databaseFileName: "operator.sqlite"
    )
}
