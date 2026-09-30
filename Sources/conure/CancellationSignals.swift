import Darwin
import Foundation

final class CancellationSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var cancelTask: (@Sendable () -> Void)?
    private let interrupt: DispatchSourceSignal
    private let terminate: DispatchSourceSignal

    init() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        interrupt.setEventHandler { [weak self] in self?.cancel() }
        terminate.setEventHandler { [weak self] in self?.cancel() }
        interrupt.resume()
        terminate.resume()
    }

    deinit {
        interrupt.cancel()
        terminate.cancel()
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)
    }

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let task = Task { try await operation() }
        register { task.cancel() }
        defer { register(nil) }
        let result = try await task.value
        if isCancelled { throw CancellationError() }
        return result
    }

    private func register(_ action: (@Sendable () -> Void)?) {
        lock.lock()
        cancelTask = action
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { action?() }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let cancelTask = cancelTask
        lock.unlock()
        cancelTask?()
    }
}
