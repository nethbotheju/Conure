import XCTest
import AudioCommon
import FluidAudio
@testable import ConureCore

final class ModelStoreTests: XCTestCase {
    func testEngineRoutingAndCacheDirectories() {
        XCTAssertEqual(ModelStore.parakeet.engine, .speechSwift)
        XCTAssertEqual(ModelStore.sortformer.engine, .speechSwift)
        XCTAssertEqual(ModelStore.descriptor(for: ModelStore.unified.hfRepo)?.id, ModelStore.unified.id)
        XCTAssertEqual(ModelStore.descriptor(for: ModelStore.multilingual.id)?.engine, .fluidAudio)
        XCTAssertEqual(ModelStore.directory(for: ModelStore.unified).lastPathComponent, "parakeet-unified-en-0.6b")
        XCTAssertEqual(ModelStore.directory(for: ModelStore.multilingual).lastPathComponent, "parakeet-tdt-0.6b-v3")
        XCTAssertFalse(ModelStore.unified.isRequired)
        XCTAssertTrue(ModelStore.parakeet.isDefault)
    }
}

final class ModelInstallStateTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conure-install-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func modelDir(_ descriptor: ModelDescriptor) -> URL {
        ModelStore.directory(for: descriptor, base: root)
    }

    @discardableResult
    private func makeBundle(_ name: String, in dir: URL, coremldata: Bool = true) throws -> URL {
        let bundle = dir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("weights", isDirectory: true),
            withIntermediateDirectories: true
        )
        if coremldata {
            try Data("coreml".utf8).write(to: bundle.appendingPathComponent("coremldata.bin"))
        }
        return bundle
    }

    private func makeFile(_ name: String, in dir: URL) throws {
        try Data("{}".utf8).write(to: dir.appendingPathComponent(name))
    }

    private func buildReady(_ descriptor: ModelDescriptor) throws -> URL {
        let dir = modelDir(descriptor)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (bundles, files) = ModelStore.requiredContents(of: descriptor)
        for bundle in bundles { try makeBundle(bundle, in: dir) }
        for file in files { try makeFile(file, in: dir) }
        return dir
    }

    func testMissingWhenDirectoryAbsentOrEmpty() throws {
        for descriptor in ModelStore.registry {
            XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .missing, descriptor.id)
            let dir = modelDir(descriptor)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .missing, descriptor.id)
        }
    }

    func testSpeechSwiftStates() throws {
        let dir = try buildReady(ModelStore.parakeet)
        XCTAssertEqual(ModelStore.installState(of: ModelStore.parakeet, base: root), .ready)
        XCTAssertTrue(ModelStore.isDownloaded(ModelStore.parakeet, base: root))

        try FileManager.default.removeItem(at: dir.appendingPathComponent("joint.mlmodelc"))
        XCTAssertEqual(ModelStore.installState(of: ModelStore.parakeet, base: root), .incomplete)

        try makeBundle("joint.mlmodelc", in: dir, coremldata: false)
        XCTAssertEqual(ModelStore.installState(of: ModelStore.parakeet, base: root), .incomplete)

        try makeBundle("joint.mlmodelc", in: dir)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("vocab.json"))
        XCTAssertEqual(ModelStore.installState(of: ModelStore.parakeet, base: root), .incomplete)

        try makeFile("vocab.json", in: dir)
        XCTAssertEqual(ModelStore.installState(of: ModelStore.parakeet, base: root), .ready)
    }

    func testBundleWithPartialDownloadIsIncomplete() throws {
        let dir = try buildReady(ModelStore.parakeet)
        try Data("half".utf8).write(
            to: dir.appendingPathComponent("encoder.mlmodelc/weights/weight.bin.partial"))
        XCTAssertEqual(ModelStore.installState(of: ModelStore.parakeet, base: root), .incomplete)
    }

    func testStagingOnlyDirectoryIsIncompleteNotMissing() throws {
        let dir = modelDir(ModelStore.parakeet)
        let staging = dir.appendingPathComponent(".incomplete", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: staging.appendingPathComponent("abc-joint.mlmodelc"))
        XCTAssertEqual(ModelStore.installState(of: ModelStore.parakeet, base: root), .incomplete)
    }

    func testReadyIgnoresStagingDirectory() throws {
        let dir = try buildReady(ModelStore.parakeet)
        let staging = dir.appendingPathComponent(".incomplete", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: staging.appendingPathComponent("abc-joint.mlmodelc"))
        XCTAssertEqual(ModelStore.installState(of: ModelStore.parakeet, base: root), .ready)
    }

    func testRequiredModelsValidateTheirOwnFileSets() throws {
        for descriptor in [ModelStore.sortformer, ModelStore.silero] {
            _ = try buildReady(descriptor)
            XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .ready, descriptor.id)
            let (bundles, files) = ModelStore.requiredContents(of: descriptor)
            try FileManager.default.removeItem(
                at: modelDir(descriptor).appendingPathComponent(files[0]))
            XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .incomplete, descriptor.id)
            XCTAssertEqual(bundles.isEmpty, false)
        }
    }

    func testFluidAudioUnifiedStates() throws {
        let descriptor = ModelStore.unified
        let dir = try buildReady(descriptor)
        XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .ready)

        try FileManager.default.removeItem(
            at: dir.appendingPathComponent(ModelNames.ParakeetUnified.offlineEncoderInt8File))
        XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .incomplete)

        try makeBundle(ModelNames.ParakeetUnified.offlineEncoderInt8File, in: dir, coremldata: false)
        XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .incomplete)

        try makeBundle(ModelNames.ParakeetUnified.offlineEncoderInt8File, in: dir)
        XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .ready)
    }

    func testFluidAudioMultilingualStates() throws {
        let descriptor = ModelStore.multilingual
        let dir = try buildReady(descriptor)
        XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .ready)

        try FileManager.default.removeItem(
            at: dir.appendingPathComponent(ModelNames.ASR.requiredModelsV3(precision: .int8).sorted()[0]))
        XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .incomplete)

        try FileManager.default.removeItem(at: dir)
        XCTAssertEqual(ModelStore.installState(of: descriptor, base: root), .missing)
    }

    func testPruneStagingRemovesDeadDataAndKeepsResumePoints() throws {
        let dir = try buildReady(ModelStore.parakeet)

        let staging = dir.appendingPathComponent(".incomplete", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: staging.appendingPathComponent("abc-dead"))

        try Data("half".utf8).write(to: dir.appendingPathComponent("config.json.partial"))
        try Data("half".utf8).write(to: dir.appendingPathComponent("extra.bin.partial"))

        ModelStore.pruneStaging(in: dir, whenReady: .ready)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("config.json.partial").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("extra.bin.partial").path))

        ModelStore.pruneStaging(in: dir, whenReady: .incomplete)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("extra.bin.partial").path))
    }

    func testDiskSpaceFailure() {
        XCTAssertNil(ModelStore.diskSpaceFailure(requiredBytes: 0, availableBytes: 10))
        XCTAssertNil(ModelStore.diskSpaceFailure(requiredBytes: 100, availableBytes: 100))
        XCTAssertNil(ModelStore.diskSpaceFailure(requiredBytes: 100, availableBytes: 1_000))
        if case .insufficientDiskSpace(let required, let available)? =
            ModelStore.diskSpaceFailure(requiredBytes: 500, availableBytes: 499) {
            XCTAssertEqual(required, 500)
            XCTAssertEqual(available, 499)
        } else {
            XCTFail("expected insufficientDiskSpace")
        }
    }

    func testAvailableDiskCapacityResolvesThroughMissingAncestors() throws {
        let deep = root.appendingPathComponent("a/b/c/d", isDirectory: true)
        let capacity = ModelStore.availableDiskCapacity(at: deep)
        XCTAssertNotNil(capacity)
        XCTAssertGreaterThan(capacity!, 0)
        XCTAssertEqual(
            ModelStore.availableDiskCapacity(at: deep),
            ModelStore.availableDiskCapacity(at: FileManager.default.temporaryDirectory)
        )
    }

    func testErrorCategorization() {
        XCTAssertEqual(
            ModelStoreError.categorize(URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(
            ModelStoreError.categorize(URLError(.timedOut)), .network)
        XCTAssertEqual(
            ModelStoreError.categorize(
                AudioCommon.DownloadError.networkUnavailable(modelId: "parakeet", detail: "offline")),
            .network)
        XCTAssertEqual(
            ModelStoreError.categorize(
                AudioCommon.DownloadError.checksumMismatch(file: "weights", expected: "a", actual: "b")),
            .validation)
        XCTAssertEqual(
            ModelStoreError.categorize(
                FluidAudioDownloadError.stalled(path: "weights", window: 30)),
            .network)
        XCTAssertEqual(
            ModelStoreError.categorize(
                FluidAudioDownloadError.modelNotFound(path: "encoder.mlmodelc")),
            .validation)
        XCTAssertEqual(
            ModelStoreError.categorize(
                NSError(domain: NSCocoaErrorDomain, code: 660)), .diskSpace)
        XCTAssertEqual(
            ModelStoreError.categorize(CocoaError(.fileWriteNoPermission)), .permission)
        XCTAssertEqual(
            ModelStoreError.categorize(
                NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))), .diskSpace)
        XCTAssertEqual(
            ModelStoreError.categorize(
                NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))), .permission)
        XCTAssertEqual(
            ModelStoreError.categorize(
                NSError(domain: NSCocoaErrorDomain, code: 42)), .other)
    }

    func testInsufficientDiskSpaceMessageMentionsGigabyteScale() {
        let error = ModelStoreError.insufficientDiskSpace(
            requiredBytes: 611 * 1_048_576, availableBytes: 100 * 1_048_576)
        XCTAssertTrue(error.localizedDescription.contains("611 MB"))
        XCTAssertTrue(error.localizedDescription.contains("100 MB"))
    }
}
