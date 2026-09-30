import Foundation
import SwiftUI
import Combine

@MainActor
final class SetupStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(model: String, percent: Double)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var missingRequiredModels: [CLIModelRow] = []

    private let coordinator: ModelCoordinator
    private let loadModels: @Sendable (@escaping @Sendable ([CLIModelRow]) -> Void) -> Void
    private var started = false
    private var cancellable: AnyCancellable?

    init(
        coordinator: ModelCoordinator = ModelCoordinator(),
        loadModels: (@Sendable (@escaping @Sendable ([CLIModelRow]) -> Void) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.loadModels = loadModels ?? { completion in CLI.shared.models(completion) }
    }

    var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    func ensureRequiredModelsIfNeeded() {
        guard !started else { return }
        started = true
        loadModels { rows in
            Task { @MainActor in
                self.missingRequiredModels = rows.filter { $0.required && !$0.downloaded }
                self.downloadNext()
            }
        }
    }

    func retry() {
        guard case .failed = phase, let next = missingRequiredModels.first else { return }
        coordinator.download(next.id)
    }

    private func downloadNext() {
        guard let next = missingRequiredModels.first else {
            cancellable = nil
            phase = .idle
            return
        }
        coordinator.download(next.id)
        phase = .downloading(model: next.name, percent: 0)
        cancellable = coordinator.$operations.sink { [weak self] operations in
            Task { @MainActor [weak self] in
                self?.refresh(next: next, operations: operations)
            }
        }
    }

    private func refresh(next: CLIModelRow, operations: [String: ModelCoordinator.Operation]) {
        guard let current = missingRequiredModels.first, current.id == next.id else { return }
        switch operations[next.id] {
        case .downloading(let percent):
            phase = .downloading(model: next.name, percent: percent)
        case .failed(let reason):
            phase = .failed(reason)
        case .removing:
            break
        case nil:
            missingRequiredModels.removeFirst()
            downloadNext()
        }
    }
}
