import Foundation
import XCTest
@testable import ConureApp

final class JSONLinesDecoderTests: XCTestCase {
    private let unicodeLine = Data(#"{"type":"done","outputPath":"/tmp/café/🎧.md"}"#.utf8)

    func testEveryByteBoundaryAndEOF() {
        for boundary in 1..<unicodeLine.count {
            let decoder = JSONLinesDecoder()
            XCTAssertTrue(decoder.append(Data(unicodeLine.prefix(boundary))).isEmpty)
            XCTAssertTrue(decoder.append(Data(unicodeLine.dropFirst(boundary))).isEmpty)
            assertDone(decoder.finish())
            XCTAssertTrue(decoder.finish().isEmpty)
        }
    }

    func testNewlineAndCombinedEvents() {
        let decoder = JSONLinesDecoder()
        let input = unicodeLine + Data("\n".utf8) + unicodeLine + Data("\n".utf8)
        let records = decoder.append(input)
        XCTAssertEqual(records.count, 2)
        for record in records { assertDone([record]) }
        XCTAssertTrue(decoder.finish().isEmpty)
    }

    func testFragmentedLineThenNewline() {
        let decoder = JSONLinesDecoder()
        for byte in unicodeLine {
            XCTAssertTrue(decoder.append(Data([byte])).isEmpty)
        }
        assertDone(decoder.append(Data([0x0A])))
    }

    func testUnicodeMessageSplitWithinScalar() {
        let decoder = JSONLinesDecoder()
        let line = Data(#"{"type":"error","detail":"Échec 🎧"}"#.utf8)
        let emoji = Array("🎧".utf8)
        let start = line.range(of: Data(emoji))!.lowerBound
        XCTAssertTrue(decoder.append(Data(line.prefix(start + 2))).isEmpty)
        let records = decoder.append(Data(line.dropFirst(start + 2)) + Data("\n".utf8))
        guard case .event(let event) = records.first else {
            return XCTFail("Expected error event")
        }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(event.detail, "Échec 🎧")
    }

    func testMalformedAndEmptyLinesDoNotBlockNextEvent() {
        let decoder = JSONLinesDecoder()
        let records = decoder.append(Data("\nnot json\n\n".utf8) + unicodeLine + Data("\n".utf8))
        XCTAssertEqual(records.count, 2)
        if case .malformed(let message) = records[0] {
            XCTAssertTrue(message.contains("not json"))
        } else {
            XCTFail("Expected malformed record")
        }
        assertDone([records[1]])
        XCTAssertTrue(decoder.finish().isEmpty)
    }

    func testMalformedAndEmptyAtEOF() {
        let decoder = JSONLinesDecoder()
        XCTAssertTrue(decoder.append(Data()).isEmpty)
        XCTAssertTrue(decoder.finish().isEmpty)
        XCTAssertTrue(decoder.append(Data("\n".utf8)).isEmpty)
        XCTAssertTrue(decoder.finish().isEmpty)
        XCTAssertTrue(decoder.append(Data("{broken".utf8)).isEmpty)
        guard case .malformed(let message) = decoder.finish().first else {
            return XCTFail("Expected malformed EOF record")
        }
        XCTAssertTrue(message.contains("{broken"))
    }

    private func assertDone(_ records: [CLIRecord], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(records.count, 1, file: file, line: line)
        guard let record = records.first, case .event(let event) = record else {
            return XCTFail("Expected done event", file: file, line: line)
        }
        XCTAssertEqual(event.type, .done, file: file, line: line)
        XCTAssertEqual(event.outputPath, "/tmp/café/🎧.md", file: file, line: line)
    }
}
