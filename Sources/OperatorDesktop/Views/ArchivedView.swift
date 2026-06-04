import SwiftUI

public struct ArchivedView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView {
            Label("No archived tasks", systemImage: "archivebox")
        } description: {
            Text("Archived tasks are hidden from the active board.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
