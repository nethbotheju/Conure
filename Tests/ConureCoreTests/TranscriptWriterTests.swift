import Foundation
import XCTest
@testable import ConureCore

final class TranscriptWriterTests: XCTestCase {
    private func transcript(names: [String]? = ["Ada", "Lin"]) -> Transcript {
        Transcript(
            sourceURL: URL(fileURLWithPath: "/tmp/meeting.audio.wav"),
            audioDuration: 3661.8,
            modelId: "parakeet",
            speakerNames: names,
            lines: [
                TranscriptLine(start: 1.234, end: 2.5, speaker: 0, text: "Hello 🎧"),
                TranscriptLine(start: 3, end: 4, speaker: 2, text: "Fallback"),
                TranscriptLine(start: 5, end: 6, speaker: nil, text: "No speaker"),
            ]
        )
    }

    func testMarkdownTimedExactOutputAndSpeakerFallback() throws {
        XCTAssertEqual(try TranscriptWriter.write(transcript(), format: .markdown, timed: true), """
        # meeting.audio.wav

        - **Duration:** 1:01:01
        - **Attendees:** Ada, Lin
        - **Model:** parakeet

        ## Transcript

        [0:00:01] **Ada:** Hello 🎧
        [0:00:03] **Speaker 3:** Fallback
        [0:00:05] No speaker

        """)
    }

    func testMarkdownWithoutTimesOrNames() throws {
        XCTAssertEqual(try TranscriptWriter.write(transcript(names: nil), format: .markdown, timed: false), """
        # meeting.audio.wav

        - **Duration:** 1:01:01
        - **Model:** parakeet

        ## Transcript

        **Speaker 1:** Hello 🎧
        **Speaker 3:** Fallback
        No speaker

        """)
    }

    func testSRTExactOutputIndependentOfTimedFlag() throws {
        let expected = """
        1
        00:00:01,234 --> 00:00:02,500
        Ada: Hello 🎧

        2
        00:00:03,000 --> 00:00:04,000
        Speaker 3: Fallback

        3
        00:00:05,000 --> 00:00:06,000
        No speaker


        """
        XCTAssertEqual(try TranscriptWriter.write(transcript(), format: .srt, timed: false), expected)
        XCTAssertEqual(try TranscriptWriter.write(transcript(), format: .srt, timed: true), expected)
    }

    func testOutputNamesPreserveMultipleDotsAndOverrideDirectory() {
        let source = transcript().sourceURL
        XCTAssertEqual(TranscriptWriter.outputURL(for: transcript(), format: .markdown).path, "/tmp/meeting.audio.md")
        XCTAssertEqual(TranscriptWriter.outputURL(for: source, format: .srt, overrideDirectory: URL(fileURLWithPath: "/tmp/out")).path, "/tmp/out/meeting.audio.srt")
    }
}
