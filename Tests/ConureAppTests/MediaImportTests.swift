import Foundation
import XCTest
@testable import ConureApp

final class MediaImportTests: XCTestCase {
    nonisolated(unsafe) private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func makeFile(_ name: String, contents: String = "") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testAcceptanceCoversAdvertisedFormats() throws {
        for name in ["a.mp4", "a.mov", "a.m4a", "a.mp3", "a.wav", "a.aac", "a.aiff", "a.aif"] {
            let url = try makeFile(name)
            XCTAssertTrue(MediaImport.isSupported(url), name)
        }
    }

    func testExtensionMatchingIsCaseInsensitive() throws {
        XCTAssertTrue(MediaImport.isSupported(try makeFile("MEETING.MP3")))
    }

    func testUnsupportedExtensionsAreRejected() throws {
        for name in ["notes.txt", "cover.png", "archive.zip"] {
            XCTAssertFalse(MediaImport.isSupported(try makeFile(name)), name)
        }
    }

    func testMissingFilesAreRejected() {
        XCTAssertFalse(MediaImport.isSupported(directory.appendingPathComponent("missing.mp3")))
    }

    func testDirectoriesAreRejectedEvenWithMediaExtension() throws {
        let url = directory.appendingPathComponent("folder.wav")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertFalse(MediaImport.isSupported(url))
    }

    func testRequestSplitsAcceptedAndRejected() throws {
        let audio = try makeFile("meeting.mp3")
        let video = try makeFile("call.mov")
        let notes = try makeFile("notes.txt")

        let request = MediaImport.request(for: [audio, notes, video])

        XCTAssertEqual(request.accepted, [video, audio].sorted { $0.path < $1.path })
        XCTAssertEqual(request.rejected, [notes])
    }

    func testDuplicatePathsCollapseToOneEntry() throws {
        let audio = try makeFile("meeting.mp3")
        let alias = directory.appendingPathComponent("sub/../meeting.mp3")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("sub"),
            withIntermediateDirectories: true
        )

        let request = MediaImport.request(for: [audio, audio, alias])

        XCTAssertEqual(request.accepted, [audio])
        XCTAssertTrue(request.rejected.isEmpty)
    }

    func testDuplicatesAreCollapsedEvenWhenUnsupported() throws {
        let notes = try makeFile("notes.txt")
        let request = MediaImport.request(for: [notes, notes])
        XCTAssertEqual(request.rejected, [notes])
    }

    func testAcceptedOrderIsDeterministicRegardlessOfDropOrder() throws {
        let paths = try ["c.wav", "a.mp4", "b.m4a"].map { try makeFile($0) }
        let expected = paths.sorted { $0.path < $1.path }

        XCTAssertEqual(MediaImport.request(for: paths).accepted, expected)
        XCTAssertEqual(MediaImport.request(for: paths.reversed()).accepted, expected)
    }

    func testEmptyRequest() {
        XCTAssertEqual(MediaImport.request(for: []), .empty)
    }

    func testRejectionSummaryNamesFilesAndFormats() throws {
        let notes = try makeFile("notes.txt")
        let summary = MediaImport.rejectionSummary(for: [notes])
        XCTAssertTrue(summary.contains("notes.txt"))
        XCTAssertTrue(summary.contains(MediaImport.formatDescription))
    }

    func testRejectionSummaryTruncatesLongLists() throws {
        let files = try (1...5).map { try makeFile("skip\($0).txt") }
        let summary = MediaImport.rejectionSummary(for: files)
        XCTAssertTrue(summary.contains("5 unsupported files"))
        XCTAssertTrue(summary.contains("and 2 more"))
    }

    func testRejectionSummaryOfNothingIsEmpty() {
        XCTAssertEqual(MediaImport.rejectionSummary(for: []), "")
    }

    func testAppBundleDeclarationsMatchSupportedMedia() throws {
        let script = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("scripts/make-app.sh"),
            encoding: .utf8
        )
        XCTAssertEqual(
            Set(Self.scriptArray("DOCUMENT_EXTENSIONS", in: script) ?? []),
            Set(MediaImport.supportedExtensions)
        )
        XCTAssertEqual(
            Set(Self.scriptArray("DOCUMENT_UTIS", in: script) ?? []),
            Set(MediaImport.supportedContentTypes.map(\.identifier))
        )
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func scriptArray(_ name: String, in script: String) -> [String]? {
        guard let start = script.range(of: "\(name)=("),
              let end = script[start.upperBound...].firstIndex(of: ")") else { return nil }
        return script[start.upperBound..<end].split(separator: "\n").flatMap { line -> [String] in
            let code = line.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            return code.split(whereSeparator: \.isWhitespace).map(String.init)
        }
    }
}
