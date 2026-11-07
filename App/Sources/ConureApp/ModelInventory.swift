import Foundation

@MainActor
final class ModelInventory: ObservableObject {
    @Published private(set) var rows: [CLIModelRow] = []
    @Published private(set) var isLoading = false
    private var loaded = false

    func loadIfNeeded() {
        guard !loaded, !isLoading else { return }
        reload()
    }

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        CLI.shared.models { rows in
            Task { @MainActor [weak self] in
                self?.rows = rows
                self?.loaded = true
                self?.isLoading = false
            }
        }
    }
}
