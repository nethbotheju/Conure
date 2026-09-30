import Foundation
import Combine

protocol ModelOperationExecuting: Sendable {
    func download(
        _ modelId: String,
        onEvent: @escaping @Sendable (CLIEvent) -> Void,
        onEnd: @escaping @Sendable () -> Void
    )
    func remove(
        _ modelId: String,
        onEvent: @escaping @Sendable (CLIEvent) -> Void,
        onEnd: @escaping @Sendable () -> Void
    )
}

extension CLI: ModelOperationExecuting {
    static let defaultModelID = "parakeet"
}

@MainActor
final class ModelCoordinator: ObservableObject {
    enum Operation: Equatable {
        case downloading(percent: Double)
        case removing
        case failed(String)
    }

    struct Usage: Equatable {
        var activeJobs = 0
        var queuedJobs = 0
    }

    @Published private(set) var operations: [String: Operation] = [:]
    @Published private(set) var inUse: [String: Usage] = [:]
    @Published var lastErrorMessage: String?

    private let executor: any ModelOperationExecuting
    private var mutatingIDs: Set<String> = []
    private var failures: [String: String] = [:]

    init(executor: (any ModelOperationExecuting)? = nil) {
        self.executor = executor ?? CLI.shared
    }

    func isMutatingAny(of ids: [String]) -> Bool {
        ids.contains { mutatingIDs.contains($0) }
    }

    func download(_ id: String) {
        guard !mutatingIDs.contains(id) else { return }
        mutatingIDs.insert(id)
        failures[id] = nil
        operations[id] = .downloading(percent: 0)
        executor.download(id, onEvent: { event in
            Task { @MainActor [weak self] in
                self?.receive(event, for: id)
            }
        }, onEnd: {
            Task { @MainActor [weak self] in
                self?.finishDownload(id)
            }
        })
    }

    @discardableResult
    func remove(_ id: String) -> Bool {
        if let usage = inUse[id], usage.activeJobs > 0 {
            lastErrorMessage = "This model is in use by a running transcription and cannot be removed."
            return false
        }
        guard !mutatingIDs.contains(id) else {
            lastErrorMessage = "Another operation is already in progress for this model."
            return false
        }
        mutatingIDs.insert(id)
        failures[id] = nil
        operations[id] = .removing
        executor.remove(id, onEvent: { event in
            Task { @MainActor [weak self] in
                guard let self, event.type == .error else { return }
                self.failures[id] = event.detail ?? "Removal failed"
            }
        }, onEnd: {
            Task { @MainActor [weak self] in
                self?.finishRemove(id)
            }
        })
        return true
    }

    func setInUse(_ usage: [String: Usage]) {
        inUse = usage
    }

    private func receive(_ event: CLIEvent, for id: String) {
        guard mutatingIDs.contains(id) else { return }
        switch event.type {
        case .progress:
            if let percent = event.percent {
                operations[id] = .downloading(percent: percent)
            }
        case .error:
            failures[id] = event.detail ?? "Download failed"
        case .done:
            break
        }
    }

    private func finishDownload(_ id: String) {
        guard mutatingIDs.contains(id) else { return }
        mutatingIDs.remove(id)
        if let reason = failures.removeValue(forKey: id) {
            operations[id] = .failed(reason)
        } else {
            operations[id] = nil
        }
    }

    private func finishRemove(_ id: String) {
        guard mutatingIDs.contains(id) else { return }
        mutatingIDs.remove(id)
        if let reason = failures.removeValue(forKey: id) {
            lastErrorMessage = reason
        }
        operations[id] = nil
    }
}
