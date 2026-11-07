import Foundation
import XCTest
@testable import ConureApp

private final class StubLibraryCLI: LibraryCLI, @unchecked Sendable {
    enum Behavior {
        case success
        case failure(String)
    }

    private let lock = NSLock()
    private var storedRenameCalls: [(id: Int, name: String)] = []
    private var storedClearCalls: [Int] = []
    private var storedExports: [(format: String, timed: Bool, output: URL)] = []
    private var storedRenameAction: (@Sendable (URL, Int, String) throws -> Void)?
    private var renameBehavior: Behavior = .success
    private var exportBehavior: Behavior = .success

    var renameCalls: [(id: Int, name: String)] {
        lock.withLock { storedRenameCalls }
    }

    var clearCalls: [Int] {
        lock.withLock { storedClearCalls }
    }

    var exports: [(format: String, timed: Bool, output: URL)] {
        lock.withLock { storedExports }
    }

    func onRename(_ action: @escaping @Sendable (URL, Int, String) throws -> Void, behavior: Behavior = .success) {
        lock.withLock {
            storedRenameAction = action
            renameBehavior = behavior
        }
    }

    func failExports(_ behavior: Behavior) {
        lock.withLock { exportBehavior = behavior }
    }

    func setSpeakerName(record: URL, id: Int, name: String) async throws {
        let state = lock.withLock {
            storedRenameCalls.append((id, name))
            return (renameBehavior, storedRenameAction)
        }
        switch state.0 {
        case .success:
            try state.1?(record, id, name)
        case .failure(let message):
            throw CLIError(message: message)
        }
    }

    func clearSpeakerName(record: URL, id: Int) async throws {
        lock.withLock { storedClearCalls.append(id) }
    }

    func exportRecord(record: URL, format: String, timed: Bool, output: URL) async throws {
        let behavior = lock.withLock {
            storedExports.append((format, timed, output))
            return exportBehavior
        }
        if case .failure(let message) = behavior {
            throw CLIError(message: message)
        }
        try "exported".write(to: output, atomically: true, encoding: .utf8)
    }
}

@MainActor
final class LibraryStoreTests: XCTestCase {
    nonisolated(unsafe) private var directory: URL!
    nonisolated(unsafe) private var libraryDirectory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        libraryDirectory = directory.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func recordJSON(
        id: UUID = UUID(),
        createdAt: String = "2026-01-02T03:04:05.000Z",
        title: String = "meeting.wav",
        sourcePath: String = "/tmp/meeting.wav",
        speakerName: String? = "Ada"
    ) -> String {
        let nameField = speakerName.map { "\"name\": \"\($0)\"," } ?? ""
        return """
        {
          "schemaVersion": 1,
          "id": "\(id.uuidString)",
          "createdAt": "\(createdAt)",
          "title": "\(title)",
          "sourcePath": "\(sourcePath)",
          "duration": 90,
          "model": "parakeet",
          "requestedSpeakerCount": 2,
          "speakers": [
            {"id": 1, \(nameField)"talkSeconds": 60, "segmentCount": 2},
            {"id": 2, "talkSeconds": 30, "segmentCount": 1}
          ],
          "lines": [
            {"start": 0, "end": 30, "speakerId": 1, "text": "Hello"},
            {"start": 40, "end": 70, "speakerId": 2, "text": "Hi"},
            {"start": 70, "end": 90, "speakerId": 1, "text": "Bye"}
          ]
        }
        """
    }

    @discardableResult
    private func writeRecord(_ json: String, name: String = "record.json") throws -> URL {
        let url = libraryDirectory.appendingPathComponent(name)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeStore(cli: StubLibraryCLI = StubLibraryCLI()) -> LibraryStore {
        LibraryStore(directory: libraryDirectory, cli: cli)
    }

    func testListsRecordsNewestFirstWithSpeakerNames() throws {
        try writeRecord(recordJSON(id: UUID(), createdAt: "2025-05-01T00:00:00.000Z", title: "old.wav"), name: "old.json")
        try writeRecord(recordJSON(id: UUID(), createdAt: "2026-05-01T00:00:00.000Z", title: "new.wav"), name: "new.json")
        let store = makeStore()
        XCTAssertEqual(store.entries.map(\.title), ["new.wav", "old.wav"])
        XCTAssertEqual(store.entries[0].speakerSummary, "Ada, Speaker 2")
        XCTAssertEqual(store.entries[0].duration, 90)
    }

    func testUnreadableAndNewerSchemaRecordsAreFlagged() throws {
        try writeRecord(recordJSON(title: "good.wav"), name: "good.json")
        try writeRecord("{ not json", name: "broken.json")
        try writeRecord("{\"schemaVersion\": 9, \"id\": \"\(UUID().uuidString)\"}", name: "future.json")
        let store = makeStore()
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertTrue(store.entries[0].isReadable)
        let broken = store.entries.first { $0.title == "broken" }
        XCTAssertNotNil(broken)
        XCTAssertFalse(broken?.isReadable ?? true)
        let future = store.entries.first { $0.title == "future" }
        XCTAssertTrue(future?.problem?.contains("schema v9") ?? false)
        store.select(broken!)
        XCTAssertNil(store.record)
    }

    func testSelectResolvesSpeakerNamesAndFallsBack() throws {
        try writeRecord(recordJSON())
        let store = makeStore()
        store.select(store.entries[0])
        let record = try XCTUnwrap(store.record)
        XCTAssertEqual(record.displayName(for: 1), "Ada")
        XCTAssertEqual(record.displayName(for: 2), "Speaker 2")
        XCTAssertEqual(record.displayName(for: nil), "")
        XCTAssertEqual(record.lines.count, 3)
    }

    func testRenamePersistsAndUpdatesEveryLine() async throws {
        try writeRecord(recordJSON())
        let cli = StubLibraryCLI()
        cli.onRename { url, id, name in
            var json = try String(contentsOf: url, encoding: .utf8)
            json = json.replacingOccurrences(of: "\"id\": 2, \"talkSeconds\"", with: "\"id\": 2, \"name\": \"\(name)\", \"talkSeconds\"")
            try json.write(to: url, atomically: true, encoding: .utf8)
        }
        let store = makeStore(cli: cli)
        store.select(store.entries[0])
        let renamed = await store.rename(speakerId: 2, to: "  Grace  ")
        XCTAssertTrue(renamed)
        XCTAssertEqual(cli.renameCalls.map(\.name), ["Grace"])
        let record = try XCTUnwrap(store.record)
        XCTAssertEqual(record.displayName(for: 2), "Grace")
        XCTAssertEqual(record.lines.filter { $0.speakerId == 2 }.count, 1)
        XCTAssertEqual(store.entries[0].speakerSummary, "Ada, Grace")
    }

    func testFailedRenameKeepsPreviousNameAndReportsError() async throws {
        try writeRecord(recordJSON())
        let cli = StubLibraryCLI()
        cli.onRename({ _, _, _ in throw CLIError(message: "disk full") }, behavior: .failure("disk full"))
        let store = makeStore(cli: cli)
        store.select(store.entries[0])
        let renamed = await store.rename(speakerId: 1, to: "Nope")
        XCTAssertFalse(renamed)
        XCTAssertEqual(store.record?.displayName(for: 1), "Ada")
        XCTAssertTrue(store.alertMessage?.contains("disk full") ?? false)
    }

    func testBlankOrOverlongNamesAreRejectedWithoutCallingCLI() async throws {
        try writeRecord(recordJSON())
        let cli = StubLibraryCLI()
        let store = makeStore(cli: cli)
        store.select(store.entries[0])
        let blank = await store.rename(speakerId: 1, to: "   ")
        let long = await store.rename(speakerId: 1, to: String(repeating: "a", count: 61))
        XCTAssertFalse(blank)
        XCTAssertFalse(long)
        XCTAssertTrue(cli.renameCalls.isEmpty)
        XCTAssertNotNil(store.alertMessage)
    }

    func testDeleteRemovesOnlyTheRecord() throws {
        let source = directory.appendingPathComponent("meeting.wav")
        try Data("audio".utf8).write(to: source)
        try writeRecord(recordJSON(sourcePath: source.path))
        let store = makeStore()
        let entry = try XCTUnwrap(store.entries.first)
        store.select(entry)
        XCTAssertTrue(store.delete(entry))
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNil(store.selectedID)
        XCTAssertNil(store.record)
    }

    func testExportCallsCLIWithCurrentRecordPath() async throws {
        let url = try writeRecord(recordJSON())
        let cli = StubLibraryCLI()
        let store = makeStore(cli: cli)
        store.select(store.entries[0])
        let record = try XCTUnwrap(store.record)
        let output = directory.appendingPathComponent("meeting.srt")
        let exported = await store.export(record, format: "srt", timed: false, to: output)
        XCTAssertTrue(exported)
        XCTAssertEqual(cli.exports.first?.format, "srt")
        XCTAssertEqual(cli.exports.first?.output, output)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "exported")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportFailureReportsError() async throws {
        try writeRecord(recordJSON())
        let cli = StubLibraryCLI()
        cli.failExports(.failure("write failed"))
        let store = makeStore(cli: cli)
        store.select(store.entries[0])
        let record = try XCTUnwrap(store.record)
        let exported = await store.export(
            record,
            format: "md",
            timed: false,
            to: directory.appendingPathComponent("meeting.md")
        )
        XCTAssertFalse(exported)
        XCTAssertTrue(store.alertMessage?.contains("write failed") ?? false)
    }

    func testDefaultExportURLUsesSourceFolderAndTitle() throws {
        let source = directory.appendingPathComponent("media/meeting.wav")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeRecord(recordJSON(sourcePath: source.path))
        let store = makeStore()
        store.select(store.entries[0])
        let record = try XCTUnwrap(store.record)
        XCTAssertEqual(
            store.defaultExportURL(for: record, format: "md").path,
            source.deletingPathExtension().appendingPathExtension("md").path
        )
    }

    func testFocusSelectsRecordByPath() throws {
        let url = try writeRecord(recordJSON())
        let store = makeStore()
        store.focus(recordPath: url.path)
        XCTAssertEqual(store.selection?.url.resolvingSymlinksInPath(), url.resolvingSymlinksInPath())
        XCTAssertNotNil(store.record)
    }

    func testLibraryDirectoryHonoursEnvironmentAndDevFolder() {
        let override = LibraryCatalog.directory(
            isDev: false,
            environment: ["CONURE_LIBRARY_DIR": "/tmp/custom-library"],
            supportRoot: URL(fileURLWithPath: "/tmp/support")
        )
        XCTAssertEqual(override.path, "/tmp/custom-library")
        let stable = LibraryCatalog.directory(
            isDev: false,
            environment: [:],
            supportRoot: URL(fileURLWithPath: "/tmp/support")
        )
        XCTAssertEqual(stable.path, "/tmp/support/Conure/library")
        let dev = LibraryCatalog.directory(
            isDev: true,
            environment: [:],
            supportRoot: URL(fileURLWithPath: "/tmp/support")
        )
        XCTAssertEqual(dev.path, "/tmp/support/Conure Dev/library")
    }
}
