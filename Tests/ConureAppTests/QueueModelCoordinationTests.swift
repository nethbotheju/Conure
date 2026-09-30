import Foundation
import XCTest
@testable import ConureApp

@MainActor
final class QueueModelCoordinationTests: XCTestCase {
    nonisolated(unsafe) private var directory: URL!
    nonisolated(unsafe) private var fastCLI: URL!
    nonisolated(unsafe) private var slowCLI: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fastCLI = try Self.writeScript(
            in: directory,
            name: "fast-cli.sh",
            contents: """
            #!/bin/sh
            echo '{"type":"done","outputPath":"/tmp/out.md"}'
            """
        )
        slowCLI = try Self.writeScript(
            in: directory,
            name: "slow-cli.sh",
            contents: """
            #!/bin/sh
            if [ "$2" = "\(directory.path)/slow" ]; then
              trap 'exit 130' TERM INT
              echo '{"type":"progress","stage":"asr","percent":10}'
              while :; do sleep 0.05; done
            fi
            echo '{"type":"done","outputPath":"/tmp/next.md"}'
            """
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private nonisolated static func writeScript(in directory: URL, name: String, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func configuration(model: String? = nil) -> JobConfiguration {
        JobConfiguration(
            model: model,
            language: nil,
            speakers: [],
            format: "md",
            timed: false,
            outputDirectory: nil
        )
    }

    func testJobWaitsForRequiredModelDownloadToFinish() async throws {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        coordinator.download("silero")

        let store = QueueStore(executableURL: fastCLI, coordinator: coordinator)
        store.add(inputs: [directory.appendingPathComponent("meeting.mp4")], configuration: configuration())

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.jobs.first?.status, .queued)
        XCTAssertFalse(store.isRunning)

        executor.finish("silero")
        let finished = await waitUntil { store.jobs.first?.status == .done(output: "/tmp/out.md") }
        XCTAssertTrue(finished, "\(store.jobs.map { ($0.input.lastPathComponent, $0.status) })")
    }

    func testJobWaitsForItsASRModelDownloadToFinish() async throws {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        coordinator.download("parakeet-unified-en")

        let store = QueueStore(executableURL: fastCLI, coordinator: coordinator)
        store.add(
            inputs: [directory.appendingPathComponent("meeting.mp4")],
            configuration: configuration(model: "parakeet-unified-en")
        )

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.jobs.first?.status, .queued)

        executor.finish("parakeet-unified-en")
        let finished = await waitUntil { store.jobs.first?.status == .done(output: "/tmp/out.md") }
        XCTAssertTrue(finished)
    }

    func testUnrelatedModelDownloadDoesNotDeferJob() async throws {
        let executor = FakeModelExecutor()
        let coordinator = ModelCoordinator(executor: executor)
        coordinator.download("parakeet-unified-en")

        let store = QueueStore(executableURL: fastCLI, coordinator: coordinator)
        store.add(inputs: [directory.appendingPathComponent("meeting.mp4")], configuration: configuration())

        let finished = await waitUntil { store.jobs.first?.status == .done(output: "/tmp/out.md") }
        XCTAssertTrue(finished)
    }

    func testQueuePublishesModelUsageAndClearsItWhenJobsFinish() async throws {
        let coordinator = ModelCoordinator(executor: FakeModelExecutor())
        let store = QueueStore(executableURL: slowCLI, coordinator: coordinator)
        store.add(
            inputs: [directory.appendingPathComponent("slow"), directory.appendingPathComponent("waiting")],
            configuration: configuration(model: "parakeet")
        )

        let ids = store.jobs.map(\.id)
        let running = await waitUntil {
            if case .running = store.jobs.first?.status { return true }
            return false
        }
        XCTAssertTrue(running)
        XCTAssertEqual(coordinator.inUse["parakeet"], ModelCoordinator.Usage(activeJobs: 1, queuedJobs: 1))

        store.cancel(ids[1])
        XCTAssertEqual(coordinator.inUse["parakeet"], ModelCoordinator.Usage(activeJobs: 1, queuedJobs: 0))

        store.cancel(ids[0])
        let cleared = await waitUntil { coordinator.inUse["parakeet"] == nil }
        XCTAssertTrue(cleared)
    }
}
