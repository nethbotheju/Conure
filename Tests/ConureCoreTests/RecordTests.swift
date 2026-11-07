import Foundation
import XCTest
@testable import ConureCore

final class RecordTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("conure-record-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func record(
        id: UUID = UUID(),
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        title: String = "meeting.wav"
    ) -> TranscriptRecord {
        TranscriptRecord(
            id: id,
            createdAt: createdAt,
            title: title,
            sourcePath: "/tmp/meeting.wav",
            duration: 3661.8,
            model: "parakeet",
            requestedSpeakerCount: 2,
            speakers: [
                RecordSpeaker(id: 1, name: "Ada", talkSeconds: 12.5, segmentCount: 2),
                RecordSpeaker(id: 2, name: nil, talkSeconds: 3, segmentCount: 1),
            ],
            lines: [
                RecordLine(start: 1.234, end: 2.5, speakerId: 1, text: "Hello 🎧"),
                RecordLine(start: 3, end: 4, speakerId: 2, text: "Hi there"),
                RecordLine(start: 5, end: 6, speakerId: nil, text: "No speaker"),
            ]
        )
    }

    func testRecordRoundTrip() throws {
        let original = record()
        let data = try RecordIO.encode(original)
        let decoded = try RecordIO.decode(data)
        XCTAssertEqual(decoded, original)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(json.contains("\"sourcePath\" : \"/tmp/meeting.wav\""))
        XCTAssertFalse(json.contains("audio"))
    }

    func testSaveIsAtomicAndLoadable() throws {
        let target = directory.appendingPathComponent("nested/record.json")
        let original = record()
        try RecordIO.save(original, to: target)
        XCTAssertEqual(try RecordIO.load(target), original)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testNewerSchemaIsRefused() throws {
        let url = directory.appendingPathComponent("future.json")
        try """
        {"schemaVersion": 99, "id": "\(UUID().uuidString)"}
        """.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try RecordIO.load(url)) { error in
            guard case RecordError.unsupportedSchema(99, RecordSchema.current) = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testMalformedRecordFailsWithoutPartialWrite() throws {
        let url = directory.appendingPathComponent("record.json")
        let good = record()
        try RecordIO.save(good, to: url)

        var broken = record()
        broken.lines.append(RecordLine(start: 7, end: 8, speakerId: 42, text: "Ghost"))
        XCTAssertThrowsError(try RecordIO.save(broken, to: url))
        XCTAssertEqual(try RecordIO.load(url), good)
    }

    func testInvalidJSONFails() throws {
        let url = directory.appendingPathComponent("broken.json")
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try RecordIO.load(url))
    }

    func testRenamePersists() throws {
        let url = directory.appendingPathComponent("record.json")
        var entry = record()
        try RecordIO.save(entry, to: url)
        try entry.setName("Grace", for: 2)
        try RecordIO.save(entry, to: url)
        XCTAssertEqual(try RecordIO.load(url).speakers[1].name, "Grace")
    }

    func testRenameUnknownSpeakerThrows() {
        var entry = record()
        XCTAssertThrowsError(try entry.setName("Grace", for: 9)) { error in
            guard case RecordError.speakerNotFound(9) = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
        XCTAssertEqual(entry.speakers[0].name, "Ada")
    }

    func testResolvedNameFallsBackToSpeakerNumber() {
        let entry = record()
        XCTAssertEqual(entry.resolvedName(for: 1), "Ada")
        XCTAssertEqual(entry.resolvedName(for: 2), "Speaker 2")
        XCTAssertEqual(entry.resolvedName(for: nil), "")
    }

    func testLibraryDirectoryHonoursEnvironment() {
        let override = directory.appendingPathComponent("library").path
        let url = RecordLibrary.directoryURL(environment: [RecordLibrary.environmentVariable: override])
        XCTAssertEqual(url.path, override)
        let fallback = RecordLibrary.directoryURL(
            environment: [:],
            supportRoot: URL(fileURLWithPath: "/tmp/support")
        )
        XCTAssertEqual(fallback.path, "/tmp/support/Conure/library")
    }

    func testLibraryListsNewestFirstAndFlagsBrokenRecords() throws {
        let old = record(createdAt: Date(timeIntervalSince1970: 1_600_000_000), title: "old.wav")
        let new = record(createdAt: Date(timeIntervalSince1970: 1_700_000_000), title: "new.wav")
        try RecordLibrary.save(old, in: directory)
        try RecordLibrary.save(new, in: directory)
        try "{ broken".write(
            to: directory.appendingPathComponent("broken.json"),
            atomically: true,
            encoding: .utf8
        )

        let entries = RecordLibrary.list(in: directory)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].title, "new.wav")
        XCTAssertEqual(entries[1].title, "old.wav")
        XCTAssertEqual(entries[2].title, "broken")
        XCTAssertFalse(entries[2].isReadable)
        XCTAssertTrue(entries[0].isReadable)
    }

    func testLibrarySaveUsesRecordID() throws {
        let entry = record()
        let url = try RecordLibrary.save(entry, in: directory)
        XCTAssertEqual(url.lastPathComponent, "\(entry.id.uuidString).json")
        XCTAssertEqual(RecordLibrary.url(for: entry.id, in: directory), url)
    }

    func testRendererMarkdownUsesRecordNamesAndFallback() {
        let entry = record()
        let rendered = RecordRenderer.render(entry, format: .markdown, timed: true)
        XCTAssertEqual(rendered, """
        # meeting.wav

        - **Duration:** 1:01:01
        - **Attendees:** Ada
        - **Model:** parakeet

        ## Transcript

        [0:00:01] **Ada:** Hello 🎧
        [0:00:03] **Speaker 2:** Hi there
        [0:00:05] No speaker

        """)
    }

    func testRendererSRTUsesRecordNames() {
        let rendered = RecordRenderer.render(record(), format: .srt, timed: false)
        XCTAssertTrue(rendered.contains("00:00:01,234 --> 00:00:02,500"))
        XCTAssertTrue(rendered.contains("Ada: Hello 🎧"))
        XCTAssertTrue(rendered.contains("Speaker 2: Hi there"))
    }

    func testRendererDefaultOutputURLUsesSourceFolderAndTitle() {
        let sourceDirectory = directory.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        var entry = record()
        entry.sourcePath = sourceDirectory.appendingPathComponent("meeting.wav").path
        let url = RecordRenderer.defaultOutputURL(
            for: entry,
            format: .srt,
            fallbackDirectory: directory
        )
        XCTAssertEqual(url.path, sourceDirectory.appendingPathComponent("meeting.srt").path)
    }

    func testRendererDefaultOutputURLFallsBackWhenSourceMissing() {
        var entry = record()
        entry.sourcePath = directory.appendingPathComponent("gone/meeting.wav").path
        let url = RecordRenderer.defaultOutputURL(for: entry, format: .markdown, fallbackDirectory: directory)
        XCTAssertEqual(url.path, directory.appendingPathComponent("meeting.md").path)
    }
}
