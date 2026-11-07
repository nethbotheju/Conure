import Foundation
import XCTest
@testable import ConureApp

final class ModelLabelsTests: XCTestCase {
    private let rows = [
        CLIModelRow(
            id: "parakeet",
            name: "Parakeet TDT 0.6B (CoreML INT8)",
            repo: "aufklarer/Parakeet-TDT-v3-CoreML-INT8-30s",
            kind: "asr",
            engine: "speechSwift",
            downloaded: true,
            required: false,
            isDefault: true,
            sizeMB: 0,
            approxSizeMB: 0,
            notes: ""
        ),
        CLIModelRow(
            id: "parakeet-unified-en",
            name: "Parakeet Unified EN (punctuated)",
            repo: "FluidInference/parakeet-unified-en-0.6b-coreml",
            kind: "asr",
            engine: "fluidAudio",
            downloaded: true,
            required: false,
            isDefault: false,
            sizeMB: 0,
            approxSizeMB: 0,
            notes: ""
        ),
    ]

    func testResolvesRegistryID() {
        XCTAssertEqual(
            ModelCatalog.label(for: "parakeet", rows: rows),
            ModelLabel(name: "Parakeet TDT 0.6B (CoreML INT8)", engine: "speech-swift")
        )
    }

    func testResolvesHuggingFaceRepo() {
        XCTAssertEqual(
            ModelCatalog.label(for: "aufklarer/Parakeet-TDT-v3-CoreML-INT8-30s", rows: rows),
            ModelLabel(name: "Parakeet TDT 0.6B (CoreML INT8)", engine: "speech-swift")
        )
        XCTAssertEqual(
            ModelCatalog.label(for: "FluidInference/parakeet-unified-en-0.6b-coreml", rows: rows),
            ModelLabel(name: "Parakeet Unified EN (punctuated)", engine: "FluidAudio")
        )
    }

    func testShortNameDropsParentheticalQualifiers() {
        XCTAssertEqual(ModelCatalog.label(for: "parakeet", rows: rows).shortName, "Parakeet TDT 0.6B")
        XCTAssertEqual(ModelCatalog.label(for: "parakeet-unified-en", rows: rows).shortName, "Parakeet Unified EN")
        XCTAssertEqual(ModelLabel.shorten("Parakeet TDT v3 (multilingual)"), "Parakeet TDT v3")
        XCTAssertEqual(ModelLabel.shorten("NoQualifier"), "NoQualifier")
    }

    func testFallsBackToLastRepoComponentForUnknownModels() {
        XCTAssertEqual(
            ModelCatalog.label(for: "someone/some-model", rows: rows),
            ModelLabel(name: "some-model", engine: nil)
        )
    }
}

@MainActor
final class QueueCompletionTests: XCTestCase {
    func testClearCompletedRemovesOnlyFinishedJobs() {
        let store = QueueStore(executableURL: URL(fileURLWithPath: "/usr/bin/false"))
        let configuration = JobConfiguration(model: nil, language: nil, speakerCount: nil)

        var done = Job(input: URL(fileURLWithPath: "/tmp/done.wav"), configuration: configuration)
        done.status = .done(record: "/tmp/done.json")
        var failed = Job(input: URL(fileURLWithPath: "/tmp/failed.wav"), configuration: configuration)
        failed.status = .failed("boom")
        var queued = Job(input: URL(fileURLWithPath: "/tmp/queued.wav"), configuration: configuration)
        queued.status = .queued

        store.jobs = [done, failed, queued]
        store.clearCompleted()

        XCTAssertEqual(store.jobs.map(\.input.lastPathComponent), ["failed.wav", "queued.wav"])
        XCTAssertFalse(store.jobs.contains { job in
            if case .done = job.status { return true }
            return false
        })
    }
}
