import Foundation
import XCTest
@testable import ConureApp

@MainActor
final class QueueCancellationTests: XCTestCase {
    func testCancellingActiveAndQueuedJobsOnlyStopsActiveThenStartsNext() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("fake-cli.sh")
        try """
        #!/bin/sh
        if [ "$2" = "\(directory.path)/slow" ]; then
          trap 'exit 130' TERM INT
          echo '{"type":"progress","stage":"asr","percent":10}'
          while :; do sleep 0.05; done
        fi
        echo '{"type":"done","outputPath":"/tmp/next.md"}'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let store = QueueStore(executableURL: script)
        let configuration = JobConfiguration(model: nil, language: nil, speakers: [], format: "md", timed: false, outputDirectory: nil)
        store.add(inputs: ["slow", "skip", "remove", "next"].map { directory.appendingPathComponent($0) }, configuration: configuration)
        let ids = store.jobs.map(\.id)
        let started = await awaitStatus(store, ids[0]) { if case .running = $0 { true } else { false } }
        XCTAssertTrue(started)
        store.cancel(ids[1])
        store.remove(ids[2])
        XCTAssertEqual(store.jobs.first { $0.id == ids[1] }?.status, .cancelled)
        XCTAssertFalse(store.jobs.contains { $0.id == ids[2] })
        XCTAssertTrue(store.isRunning)
        XCTAssertEqual(store.jobs.first { $0.id == ids[3] }?.status, .queued)

        store.cancel(ids[0])
        XCTAssertEqual(store.jobs.first { $0.id == ids[0] }?.status, .cancelled)
        let finished = await awaitStatus(store, ids[3]) { $0 == .done(output: "/tmp/next.md") }
        XCTAssertTrue(finished, "\(store.jobs.map { ($0.input.lastPathComponent, $0.status) })")
        XCTAssertEqual(store.jobs.first { $0.id == ids[0] }?.status, .cancelled)
        XCTAssertEqual(store.jobs.first { $0.id == ids[1] }?.status, .cancelled)
        XCTAssertFalse(store.isRunning)
    }

    private func awaitStatus(_ store: QueueStore, _ id: UUID, matching: (JobStatus) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let status = store.jobs.first(where: { $0.id == id })?.status, matching(status) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
