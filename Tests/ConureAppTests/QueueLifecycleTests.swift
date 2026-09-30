import Foundation
import XCTest
@testable import ConureApp

@MainActor
final class QueueLifecycleTests: XCTestCase {
    func testFailureRetryAndFIFOCompletionWithFakeCLI() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("fake-cli.sh")
        let marker = directory.appendingPathComponent("attempted")
        let log = directory.appendingPathComponent("runs")
        try """
        #!/bin/sh
        echo "$2" >> "\(log.path)"
        if [ "$2" = "\(directory.path)/first.wav" ] && [ ! -f "\(marker.path)" ]; then
          touch "\(marker.path)"
          echo '{"type":"progress","stage":"asr","percent":42}'
          echo '{"type":"error","detail":"fake failure"}'
          echo 'diagnostic' >&2
          exit 7
        fi
        echo '{"type":"done","outputPath":"/tmp/completed.md"}'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let store = QueueStore(executableURL: script)
        let configuration = JobConfiguration(
            model: nil, language: nil, speakers: [], format: "md", timed: false, outputDirectory: nil)
        store.add(inputs: ["first.wav", "second.wav"].map { directory.appendingPathComponent($0) }, configuration: configuration)
        let ids = store.jobs.map(\.id)
        let failed = await awaitStatus(store, ids[0], .failed("fake failure"))
        XCTAssertTrue(failed, "jobs: \(store.jobs.map(\.status))")
        let secondDone = await awaitStatus(store, ids[1], .done(output: "/tmp/completed.md"))
        XCTAssertTrue(secondDone, "jobs: \(store.jobs.map(\.status))")
        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(try runs(log), ["first.wav", "second.wav"])

        store.retry(ids[0])
        let retryDone = await awaitStatus(store, ids[0], .done(output: "/tmp/completed.md"))
        XCTAssertTrue(retryDone, "jobs: \(store.jobs.map(\.status))")
        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(try runs(log), ["first.wav", "second.wav", "first.wav"])
        store.retry(ids[0])
        XCTAssertEqual(try runs(log), ["first.wav", "second.wav", "first.wav"], "completed job must not restart")
    }

    func testProcessLaunchFailureDoesNotBlockNextJob() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = QueueStore(executableURL: directory.appendingPathComponent("missing-cli"))
        let configuration = JobConfiguration(
            model: nil, language: nil, speakers: [], format: "md", timed: false, outputDirectory: nil)
        store.add(inputs: [directory.appendingPathComponent("one"), directory.appendingPathComponent("two")], configuration: configuration)
        XCTAssertEqual(store.jobs.count, 2)
        for job in store.jobs {
            guard case .failed(let detail) = job.status else { return XCTFail("expected launch failure for \(job.input): \(job.status)") }
            XCTAssertTrue(detail.contains("Could not start CLI"), detail)
        }
        XCTAssertFalse(store.isRunning)
    }

    private func runs(_ log: URL) throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map {
            URL(fileURLWithPath: String($0)).lastPathComponent
        }
    }

    private func awaitStatus(_ store: QueueStore, _ id: UUID, _ expected: JobStatus) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if store.jobs.first(where: { $0.id == id })?.status == expected { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
