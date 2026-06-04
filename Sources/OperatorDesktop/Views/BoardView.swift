import SwiftUI

public struct BoardView: View {
    private let board: BoardSpec

    public init(board: BoardSpec) {
        self.board = board
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                BoardEmptyStateView(emptyState: board.emptyState)

                HStack(alignment: .top, spacing: 12) {
                    ForEach(board.columns) { column in
                        BoardColumnView(column: column)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if board.reservesInspectorPanel {
                Divider()

                InspectorReserveView()
                    .frame(width: 280)
            }
        }
    }
}

private struct BoardEmptyStateView: View {
    let emptyState: BoardEmptyState

    var body: some View {
        ContentUnavailableView {
            Label(emptyState.title, systemImage: "square.stack.3d.up")
        } description: {
            Text(emptyState.message)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BoardColumnView: View {
    let column: BoardColumnSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(column.title)
                    .font(.headline)

                Spacer()

                Text("0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            VStack(spacing: 8) {
                Text("Empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InspectorReserveView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No task selected")
                .font(.headline)

            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.bar)
    }
}
