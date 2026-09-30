import Foundation
import XCTest
@testable import ConureApp

@MainActor
final class QueueCollisionTests: XCTestCase {
    nonisolated(unsafe) private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var configuration: JobConfiguration {
        JobConfiguration(model: nil, language: nil, speakers: [], format: "md", timed: false, outputDirectory: nil)
    }

    private func makeStore(withJobs jobs: (String, JobStatus)...) -> QueueStore {
        let store = QueueStore(executableURL: directory.appendingPathComponent("unused-conure"))
        for (name, status) in jobs {
            var job = Job(input: directory.appendingPathComponent(name), configuration: configuration)
            job.status = status
            store.jobs.append(job)
        }
        return store
    }

    func testExistingOutputFileOnDiskIsDetected() throws {
        try Data("old transcript".utf8).write(to: directory.appendingPathComponent("meeting.md"))
        let store = makeStore()
        XCTAssertEqual(
            store.outputConflicts(inputs: [directory.appendingPathComponent("meeting.mp4")], configuration: configuration),
            ["meeting.md"]
        )
    }

    func testFreeOutputReportsNoConflicts() {
        let store = makeStore()
        XCTAssertEqual(
            store.outputConflicts(inputs: [directory.appendingPathComponent("meeting.mp4")], configuration: configuration),
            []
        )
    }

    func testDuplicateBasenamesWithinBatchAreDetected() {
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        var configuration = configuration
        configuration.outputDirectory = outputDirectory
        let store = makeStore()
        let inputs = [
            directory.appendingPathComponent("a/meeting.mp4"),
            directory.appendingPathComponent("b/meeting.mp4"),
        ]
        XCTAssertEqual(store.outputConflicts(inputs: inputs, configuration: configuration), ["meeting.md"])
    }

    func testOutputClaimedByQueuedJobIsDetected() {
        let store = makeStore(withJobs: ("meeting.mp4", .queued))
        XCTAssertEqual(
            store.outputConflicts(inputs: [directory.appendingPathComponent("meeting.mp4")], configuration: configuration),
            ["meeting.md"]
        )
    }

    func testOutputClaimedByRunningJobIsDetected() {
        let store = makeStore(withJobs: ("meeting.mp4", .running(stage: "asr", percent: 10)))
        XCTAssertEqual(
            store.outputConflicts(inputs: [directory.appendingPathComponent("meeting.mp4")], configuration: configuration),
            ["meeting.md"]
        )
    }

    func testFinishedJobReliesOnDiskState() {
        let store = makeStore(withJobs: ("meeting.mp4", .cancelled))
        XCTAssertEqual(
            store.outputConflicts(inputs: [directory.appendingPathComponent("meeting.mp4")], configuration: configuration),
            []
        )
    }

    func testMakeArgumentsMapsCollisionPolicies() {
        let base = CLI.shared.makeArguments(
            input: URL(fileURLWithPath: "/tmp/a.wav"),
            model: nil,
            language: nil,
            speakers: nil,
            format: "md",
            timed: false,
            output: nil
        )
        XCTAssertFalse(base.contains("--replace"))
        XCTAssertFalse(base.contains("--unique"))

        let replace = CLI.shared.makeArguments(
            input: URL(fileURLWithPath: "/tmp/a.wav"),
            model: nil,
            language: nil,
            speakers: nil,
            format: "md",
            timed: false,
            output: nil,
            collision: .replace
        )
        XCTAssertTrue(replace.contains("--replace"))

        let unique = CLI.shared.makeArguments(
            input: URL(fileURLWithPath: "/tmp/a.wav"),
            model: nil,
            language: nil,
            speakers: nil,
            format: "md",
            timed: false,
            output: nil,
            collision: .unique
        )
        XCTAssertTrue(unique.contains("--unique"))
    }
}
