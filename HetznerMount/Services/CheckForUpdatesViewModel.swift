import Combine
import Sparkle
import SwiftUI

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        self.updater = updater
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
