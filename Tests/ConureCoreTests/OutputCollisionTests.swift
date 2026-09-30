import XCTest
@testable import ConureCore

final class OutputCollisionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func touch(_ name: String) throws {
        try Data("existing".utf8).write(to: directory.appendingPathComponent(name))
    }

    private var desiredMd: URL { directory.appendingPathComponent("meeting.md") }

    func testResolveReturnsDesiredWhenFree() throws {
        for policy in [OutputCollisionPolicy.fail, .replace, .unique] {
            XCTAssertEqual(
                try OutputPlanner.resolve(desired: desiredMd, policy: policy),
                desiredMd
            )
        }
    }

    func testFailPolicyThrowsWhenFileExists() throws {
        try touch("meeting.md")
        XCTAssertThrowsError(try OutputPlanner.resolve(desired: desiredMd, policy: .fail)) { error in
            guard case ConureError.outputExists(let url) = error else {
                return XCTFail("expected outputExists, got \(error)")
            }
            XCTAssertEqual(url.path, desiredMd.path)
            XCTAssertTrue(error.localizedDescription.contains("--replace"))
            XCTAssertTrue(error.localizedDescription.contains("--unique"))
        }
    }

    func testFailPolicyThrowsWhenPathClaimedByBatch() {
        XCTAssertThrowsError(
            try OutputPlanner.resolve(desired: desiredMd, policy: .fail, claimedPaths: [desiredMd.path])
        ) { error in
            guard case ConureError.outputExists = error else {
                return XCTFail("expected outputExists, got \(error)")
            }
        }
    }

    func testReplacePolicyReturnsExistingPath() throws {
        try touch("meeting.md")
        XCTAssertEqual(try OutputPlanner.resolve(desired: desiredMd, policy: .replace), desiredMd)
    }

    func testUniquePolicyBumpsToNumberedNameRetainingExtension() throws {
        try touch("meeting.md")
        XCTAssertEqual(
            try OutputPlanner.resolve(desired: desiredMd, policy: .unique),
            directory.appendingPathComponent("meeting 2.md")
        )
        try touch("meeting 2.md")
        XCTAssertEqual(
            try OutputPlanner.resolve(desired: desiredMd, policy: .unique),
            directory.appendingPathComponent("meeting 3.md")
        )
    }

    func testUniquePolicyRetainsSrtExtension() throws {
        try touch("meeting.srt")
        let desired = directory.appendingPathComponent("meeting.srt")
        XCTAssertEqual(
            try OutputPlanner.resolve(desired: desired, policy: .unique),
            directory.appendingPathComponent("meeting 2.srt")
        )
    }

    func testUniquePolicySkipsClaimedBatchPaths() throws {
        let claimed = [desiredMd.path, directory.appendingPathComponent("meeting 2.md").path]
        XCTAssertEqual(
            try OutputPlanner.resolve(desired: desiredMd, policy: .unique, claimedPaths: Set(claimed)),
            directory.appendingPathComponent("meeting 3.md")
        )
    }

    func testBatchDuplicateBasenamesInCustomOutputDirectoryFailByDefault() {
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        let sources = [
            directory.appendingPathComponent("a/meeting.mp4"),
            directory.appendingPathComponent("b/meeting.mp4"),
        ]
        XCTAssertThrowsError(
            try OutputPlanner.resolveBatch(
                sources: sources, format: .markdown, overrideDirectory: outputDirectory, policy: .fail
            )
        ) { error in
            guard case ConureError.outputExists(let url) = error else {
                return XCTFail("expected outputExists, got \(error)")
            }
            XCTAssertEqual(url.lastPathComponent, "meeting.md")
        }
    }

    func testBatchDuplicateBasenamesGetDistinctDeterministicNames() throws {
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        let sources = [
            directory.appendingPathComponent("a/meeting.mp4"),
            directory.appendingPathComponent("b/meeting.mp4"),
            directory.appendingPathComponent("c/meeting.mp4"),
        ]
        let resolved = try OutputPlanner.resolveBatch(
            sources: sources, format: .markdown, overrideDirectory: outputDirectory, policy: .unique
        )
        XCTAssertEqual(
            resolved.map(\.lastPathComponent),
            ["meeting.md", "meeting 2.md", "meeting 3.md"]
        )
        XCTAssertEqual(Set(resolved.map(\.path)).count, resolved.count)
    }

    func testBatchExistingFileInCustomOutputDirectoryDetected() throws {
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try touch("out/meeting.srt")
        XCTAssertThrowsError(
            try OutputPlanner.resolveBatch(
                sources: [directory.appendingPathComponent("meeting.mp4")],
                format: .srt,
                overrideDirectory: outputDirectory,
                policy: .fail
            )
        )
        let resolved = try OutputPlanner.resolveBatch(
            sources: [directory.appendingPathComponent("meeting.mp4")],
            format: .srt,
            overrideDirectory: outputDirectory,
            policy: .unique
        )
        XCTAssertEqual(resolved.map(\.lastPathComponent), ["meeting 2.srt"])
    }

    func testBatchReplacePolicyKeepsCollidingPaths() throws {
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        let sources = [
            directory.appendingPathComponent("a/meeting.mp4"),
            directory.appendingPathComponent("b/meeting.mp4"),
        ]
        let resolved = try OutputPlanner.resolveBatch(
            sources: sources, format: .markdown, overrideDirectory: outputDirectory, policy: .replace
        )
        XCTAssertEqual(resolved.map(\.path), [resolved[0].path, resolved[0].path])
    }
}
