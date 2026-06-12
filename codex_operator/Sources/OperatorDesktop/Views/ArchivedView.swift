import Combine
import SwiftUI

public struct ArchivedView: View {
    @StateObject private var model: ArchivedTasksModel
    private let store: OperatorStore

    public init(store: OperatorStore, codexOpener: (any CodexAppOpening)? = OSCodexAppOpener()) {
        self.store = store
        _model = StateObject(wrappedValue: ArchivedTasksModel(store: store, codexOpener: codexOpener))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if model.projection.tasks.isEmpty {
                ContentUnavailableView {
                    Label("No archived tasks", systemImage: "archivebox")
                } description: {
                    Text("Archived tasks are hidden from the active board.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.projection.tasks) { task in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(.headline)

                            HStack(spacing: 6) {
                                ArchivedBadgeView(text: task.repositoryBadge)
                                ArchivedBadgeView(text: task.reasoningBadge)
                            }
                        }

                        Spacer()

                        if task.canOpenInCodexApp {
                            Button {
                                Task {
                                    await model.openTaskInCodexAppReportingErrors(taskID: task.id)
                                }
                            } label: {
                                Label(task.codexOpenLabel, systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Let the translucent window background show through the list.
                .scrollContentBackground(.hidden)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.loadReportingErrors()
        }
        // The store publishes from whichever thread committed (the external
        // change poller and turn completion run off the main thread), so hop
        // to the main queue before touching view state.
        .onReceive(store.changes.receive(on: DispatchQueue.main)) {
            model.loadReportingErrors()
        }
    }
}

private struct ArchivedBadgeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}
