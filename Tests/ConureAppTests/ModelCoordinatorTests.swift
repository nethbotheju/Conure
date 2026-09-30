import Foundation
import XCTest
@testable import ConureApp

final class FakeModelExecutor: ModelOperationExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var downloadCalls: [String] = []
    private var removeCalls: [String] = []
    private var eventSinks: [String: @Sendable (CLIEvent) -> Void] = [:]
    private var endSinks: [String: @Sendable () -> Void] = [:]

    func download(
        _ modelId: String,
        onEvent: @escaping @Sendable (CLIEvent) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        downloadCalls.append(modelId)
        eventSinks[modelId] = onEvent
        endSinks[modelId] = onEnd
    }

    func remove(
        _ modelId: String,
        onEvent: @escaping @Sendable (CLIEvent) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        removeCalls.append(modelId)
        eventSinks[modelId] = onEvent
        endSinks[modelId] = onEnd
    }

    var downloadsStarted: [String] { lock.withLock { downloadCalls } }
    var removesStarted: [String] { lock.withLock { removeCalls } }

    func emitProgress(_ percent: Double, for id: String) {
        let sink = lock.withLock { eventSinks[id] }
        sink?(CLIEvent(type: .progress, stage: nil, percent: percent, detail: nil, outputPath: nil))
    }

    func emitError(_ detail: String, for id: String) {
        let sink = lock.withLock { eventSinks[id] }
        sink?(CLIEvent(type: .error, stage: nil, percent: nil, detail: detail, outputPath: nil))
    }

    func finish(_ id: String) {
        let sink = lock.withLock { endSinks[id] }
        sink?()
    }
}

@MainActor
final class ModelCoordinatorTests: XCTestCase {
    func testRepeatedDownloadRequestsStartSingleDownload() {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)

        coordinator.download("silero")
        coordinator.download("silero")
        coordinator.download("silero")

        XCTAssertEqual(executor.downloadsStarted, ["silero"])
        XCTAssertEqual(coordinator.operations["silero"], .downloading(percent: 0))
    }

    func testDownloadProgressAndCompletionTransitions() async {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)

        coordinator.download("silero")
        executor.emitProgress(42, for: "silero")
        let progressing = await waitUntil { coordinator.operations["silero"] == .downloading(percent: 42) }
        XCTAssertTrue(progressing)

        executor.finish("silero")
        let settled = await waitUntil { coordinator.operations["silero"] == nil }
        XCTAssertTrue(settled)
        XCTAssertFalse(coordinator.isMutatingAny(of: ["silero"]))
    }

    func testFailedDownloadIsRecordedAndRetryStartsNewDownload() async {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)

        coordinator.download("silero")
        executor.emitError("network down", for: "silero")
        executor.finish("silero")
        let failed = await waitUntil { coordinator.operations["silero"] == .failed("network down") }
        XCTAssertTrue(failed)
        XCTAssertFalse(coordinator.isMutatingAny(of: ["silero"]))

        coordinator.download("silero")
        XCTAssertEqual(executor.downloadsStarted.count, 2)
        XCTAssertEqual(coordinator.operations["silero"], .downloading(percent: 0))
    }

    func testRemoveIsBlockedWhileModelIsUsedByActiveJob() {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        coordinator.setInUse(["parakeet": ModelCoordinator.Usage(activeJobs: 1)])

        XCTAssertFalse(coordinator.remove("parakeet"))
        XCTAssertEqual(executor.removesStarted, [])
        XCTAssertNotNil(coordinator.lastErrorMessage)
    }

    func testRemoveIsBlockedWhileDownloadIsInProgress() {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        coordinator.download("parakeet")

        XCTAssertFalse(coordinator.remove("parakeet"))
        XCTAssertEqual(executor.removesStarted, [])
        XCTAssertNotNil(coordinator.lastErrorMessage)
    }

    func testDownloadIsIgnoredWhileRemovalIsInProgress() {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)

        XCTAssertTrue(coordinator.remove("parakeet"))
        coordinator.download("parakeet")

        XCTAssertEqual(executor.removesStarted, ["parakeet"])
        XCTAssertEqual(executor.downloadsStarted, [])
        XCTAssertEqual(coordinator.operations["parakeet"], .removing)
    }

    func testSuccessfulRemoveClearsOperationState() async {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)

        XCTAssertTrue(coordinator.remove("parakeet"))
        XCTAssertEqual(coordinator.operations["parakeet"], .removing)

        executor.finish("parakeet")
        let settled = await waitUntil { coordinator.operations["parakeet"] == nil }
        XCTAssertTrue(settled)
        XCTAssertEqual(executor.removesStarted, ["parakeet"])
    }

    func testQueuedOnlyUsageStillAllowsRemoval() {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        coordinator.setInUse(["parakeet": ModelCoordinator.Usage(queuedJobs: 2)])

        XCTAssertTrue(coordinator.remove("parakeet"))
        XCTAssertEqual(executor.removesStarted, ["parakeet"])
    }
}

@MainActor
final class SetupStoreCoordinationTests: XCTestCase {
    private func makeRow(_ id: String, required: Bool, downloaded: Bool) -> CLIModelRow {
        CLIModelRow(
            id: id,
            name: id,
            repo: "test/\(id)",
            kind: required ? "vad" : "asr",
            engine: "speech-swift",
            downloaded: downloaded,
            required: required,
            isDefault: id == "parakeet",
            sizeMB: 1,
            approxSizeMB: 1,
            notes: ""
        )
    }

    func testSetupDownloadsMissingModelsSequentiallyAndRecoversFromFailure() async {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        let rows = [
            makeRow("silero", required: true, downloaded: false),
            makeRow("sortformer", required: true, downloaded: false),
        ]
        let setup = SetupStore(coordinator: coordinator, loadModels: { completion in completion(rows) })

        setup.ensureRequiredModelsIfNeeded()
        let startedSilero = await waitUntil { executor.downloadsStarted == ["silero"] }
        XCTAssertTrue(startedSilero)

        executor.emitProgress(50, for: "silero")
        let progressing = await waitUntil {
            setup.phase == .downloading(model: "silero", percent: 50)
        }
        XCTAssertTrue(progressing)

        executor.finish("silero")
        let startedSortformer = await waitUntil {
            executor.downloadsStarted == ["silero", "sortformer"]
        }
        XCTAssertTrue(startedSortformer)

        executor.emitError("network unreachable", for: "sortformer")
        executor.finish("sortformer")
        let failed = await waitUntil { setup.phase == .failed("network unreachable") }
        XCTAssertTrue(failed)
        XCTAssertTrue(setup.isActive)

        setup.retry()
        let retried = await waitUntil { executor.downloadsStarted.count == 3 }
        XCTAssertTrue(retried)

        executor.finish("sortformer")
        let idle = await waitUntil { !setup.isActive }
        XCTAssertTrue(idle)
        XCTAssertEqual(setup.missingRequiredModels.map(\.id), [])
        XCTAssertEqual(executor.downloadsStarted, ["silero", "sortformer", "sortformer"])
    }

    func testSetupSharesInProgressDownloadStartedElsewhere() async {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        let rows = [makeRow("silero", required: true, downloaded: false)]
        let setup = SetupStore(coordinator: coordinator, loadModels: { completion in completion(rows) })

        coordinator.download("silero")
        executor.emitProgress(70, for: "silero")

        setup.ensureRequiredModelsIfNeeded()
        let attached = await waitUntil {
            setup.phase == .downloading(model: "silero", percent: 70)
        }
        XCTAssertTrue(attached)

        executor.finish("silero")
        let idle = await waitUntil { !setup.isActive }
        XCTAssertTrue(idle)
        XCTAssertEqual(executor.downloadsStarted, ["silero"])
    }

    func testNoMissingRequiredModelsLeavesSetupIdle() async {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        let rows = [makeRow("silero", required: true, downloaded: true)]
        let setup = SetupStore(coordinator: coordinator, loadModels: { completion in completion(rows) })

        setup.ensureRequiredModelsIfNeeded()
        let checked = await waitUntil { setup.missingRequiredModels.isEmpty && !setup.isActive }
        XCTAssertTrue(checked)
        XCTAssertEqual(executor.downloadsStarted, [])
    }
}

extension XCTestCase {
    @MainActor
    func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
