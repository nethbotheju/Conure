import Foundation
import SwiftUI

@MainActor
final class SetupStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(model: String, percent: Double)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var missingRequiredModels: [CLIModelRow] = []

    private var started = false

    var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    func ensureRequiredModelsIfNeeded() {
        guard !started else { return }
        started = true
        CLI.shared.models { rows in
            Task { @MainActor in
                let missing = rows.filter { $0.required && !$0.downloaded }
                self.missingRequiredModels = missing
                guard !missing.isEmpty else { return }
                self.downloadNext()
            }
        }
    }

    private func downloadNext() {
        guard let next = missingRequiredModels.first else {
            phase = .idle
            return
        }
        phase = .downloading(model: next.name, percent: 0)
        CLI.shared.download(next.id) { [weak self] event in
            Task { @MainActor in
                if case .downloading(let name, _) = self?.phase,
                   event.type == .progress, let percent = event.percent {
                    self?.phase = .downloading(model: name, percent: percent)
                } else if event.type == .error {
                    self?.phase = .failed(event.detail ?? "Required model download failed")
                }
            }
        } onEnd: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if case .failed = self.phase { return }
                self.missingRequiredModels.removeFirst()
                self.downloadNext()
            }
        }
    }
}
