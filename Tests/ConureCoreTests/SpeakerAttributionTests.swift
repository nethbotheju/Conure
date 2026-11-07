import Foundation
import XCTest
@testable import ConureCore

final class SpeakerAttributionTests: XCTestCase {
    private func line(_ start: Double, _ end: Double, _ speaker: Int?, _ text: String = "text") -> TranscriptLine {
        TranscriptLine(start: start, end: end, speaker: speaker, text: text)
    }

    func testSpeakersOrderedByTalkTimeAndLinesRemapped() {
        let lines = [
            line(0, 2, 0, "quiet"),
            line(10, 30, 1, "loud"),
            line(40, 41, 0, "quiet again"),
        ]
        let result = SpeakerAttribution.attribute(lines: lines)
        XCTAssertEqual(result.speakers.map(\.id), [1, 2])
        XCTAssertEqual(result.speakers[0].talkSeconds, 20)
        XCTAssertEqual(result.speakers[1].talkSeconds, 3)
        XCTAssertEqual(result.lines.map(\.speakerId), [2, 1, 2])
    }

    func testLegacyNamesFollowFirstSpeechOrderNotTalkTime() {
        let lines = [
            line(0, 2, 0, "first"),
            line(10, 30, 1, "second"),
        ]
        let result = SpeakerAttribution.attribute(lines: lines, legacyNames: ["Ada", "Lin"])
        XCTAssertEqual(result.speakers.map(\.name), ["Lin", "Ada"])
        XCTAssertEqual(result.speakers.map(\.talkSeconds), [20, 2])
        XCTAssertEqual(result.lines.map(\.speakerId), [2, 1])
    }

    func testWeakExtraClusterIsAbsorbedAndItsLinesPreserved() {
        let lines = [
            line(0, 5, 0),
            line(6, 11, 0),
            line(12, 13, 2, "blip"),
            line(20, 25, 1),
            line(26, 31, 1),
        ]
        let result = SpeakerAttribution.attribute(lines: lines, requestedCount: 2)
        XCTAssertEqual(result.speakers.count, 2)
        XCTAssertEqual(result.speakers[0].talkSeconds, 11)
        XCTAssertEqual(result.speakers[0].segmentCount, 3)
        XCTAssertEqual(result.lines.count, 5)
        XCTAssertEqual(result.lines[2].text, "blip")
        XCTAssertEqual(result.lines[2].speakerId, 1)
        XCTAssertEqual(result.lines.filter { $0.speakerId == nil }.count, 0)
        XCTAssertTrue(result.notes.first?.contains("Merged 1 low-evidence cluster") == true)
    }

    func testStrongExtraVoiceIsKeptAndReported() {
        let lines = [
            line(0, 5, 0),
            line(10, 15, 0),
            line(20, 25, 0),
            line(30, 35, 0),
            line(40, 45, 1),
            line(50, 55, 1),
            line(60, 65, 1),
            line(70, 75, 2),
            line(80, 85, 2),
            line(90, 95, 2),
        ]
        let result = SpeakerAttribution.attribute(lines: lines, requestedCount: 2)
        XCTAssertEqual(result.speakers.count, 3)
        XCTAssertTrue(result.notes.first?.contains("Kept 1 extra strong voice") == true)
    }

    func testRequestedCountAboveDetectedReportsDiscrepancy() {
        let lines = [line(0, 5, 0), line(10, 15, 1)]
        let result = SpeakerAttribution.attribute(lines: lines, requestedCount: 4)
        XCTAssertEqual(result.speakers.count, 2)
        XCTAssertTrue(result.notes.first?.contains("fewer than the requested 4") == true)
    }

    func testInferredCountKeepsEveryCluster() {
        let lines = [line(0, 5, 0), line(10, 11, 1), line(20, 21, 2)]
        let result = SpeakerAttribution.attribute(lines: lines, requestedCount: nil)
        XCTAssertEqual(result.speakers.count, 3)
        XCTAssertTrue(result.notes.isEmpty)
    }

    func testLinesWithoutSpeakersStayUnattributed() {
        let lines = [line(0, 5, nil)]
        let result = SpeakerAttribution.attribute(lines: lines)
        XCTAssertTrue(result.speakers.isEmpty)
        XCTAssertNil(result.lines[0].speakerId)
    }
}

final class SpeakerNamingTests: XCTestCase {
    func testNormalizeTrimsWhitespace() throws {
        XCTAssertEqual(try SpeakerName.normalized("  Ada Lovelace  "), "Ada Lovelace")
        XCTAssertEqual(try SpeakerName.normalized("Zoë"), "Zoë")
    }

    func testNormalizeRejectsBlankAndControlCharactersAndLongNames() {
        XCTAssertThrowsError(try SpeakerName.normalized("   ")) { error in
            XCTAssertEqual(error as? SpeakerNameError, .empty)
        }
        XCTAssertThrowsError(try SpeakerName.normalized("Ada\nLovelace")) { error in
            XCTAssertEqual(error as? SpeakerNameError, .controlCharacters)
        }
        XCTAssertThrowsError(try SpeakerName.normalized(String(repeating: "a", count: 61))) { error in
            XCTAssertEqual(error as? SpeakerNameError, .tooLong(SpeakerName.maximumLength))
        }
    }

    func testParseAssignment() throws {
        let parsed = try SpeakerName.parseAssignment("2= Grace Hopper ")
        XCTAssertEqual(parsed.id, 2)
        XCTAssertEqual(parsed.name, "Grace Hopper")
        XCTAssertThrowsError(try SpeakerName.parseAssignment("2"))
        XCTAssertThrowsError(try SpeakerName.parseAssignment("zero=Ada"))
        XCTAssertThrowsError(try SpeakerName.parseAssignment("0=Ada"))
    }

    func testSpeakerCountBounds() {
        XCTAssertNoThrow(try SpeakerLimits.validate(count: 1))
        XCTAssertNoThrow(try SpeakerLimits.validate(count: 4))
        XCTAssertThrowsError(try SpeakerLimits.validate(count: 0))
        XCTAssertThrowsError(try SpeakerLimits.validate(count: 5))
    }
}
