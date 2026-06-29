import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
enum CursorOperatorSparkleUpdater {
    static func makeUpdaterController(bundle: Bundle = .main) -> SPUStandardUpdaterController? {
        guard hasConfiguredSparkleFeed(in: bundle) else {
            return nil
        }
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private static func hasConfiguredSparkleFeed(in bundle: Bundle) -> Bool {
        guard let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct CursorOperatorCheckForUpdatesView: View {
    @StateObject private var viewModel: CursorOperatorCheckForUpdatesViewModel
    private let updater: SPUUpdater?
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(updater: SPUUpdater?) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CursorOperatorCheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates...") {
            updater?.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
        .onAppear {
            viewModel.refresh()
        }
        .onReceive(refreshTimer) { _ in
            viewModel.refresh()
        }
    }
}

@MainActor
private final class CursorOperatorCheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater?

    init(updater: SPUUpdater?) {
        self.updater = updater
        refresh()
    }

    func refresh() {
        canCheckForUpdates = updater?.canCheckForUpdates ?? false
    }
}
