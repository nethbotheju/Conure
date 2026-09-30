import XCTest
@testable import ConureCore

final class SegmenterTests: XCTestCase {
    func testSortsFiltersAndMergesSameSpeakerWithinGap() {
        let segments = [
            RawSegment(start: 3, end: 4, speaker: 1),
            RawSegment(start: 0, end: 1, speaker: 0),
            RawSegment(start: 2, end: 2.1, speaker: 0),
            RawSegment(start: 1.2, end: 2, speaker: 0),
        ]
        XCTAssertEqual(Segmenter.merge(segments), [
            SpeechChunk(start: 0, end: 2, speaker: 0),
            SpeechChunk(start: 3, end: 4, speaker: 1),
        ])
    }

    func testGapSpeakerChangeAndChunkLimitSplitAtBoundaries() {
        let segments = [
            RawSegment(start: 0, end: 1, speaker: 0),
            RawSegment(start: 1.25, end: 2, speaker: 0),
            RawSegment(start: 2.1, end: 3, speaker: 1),
            RawSegment(start: 3.1, end: 4, speaker: 1),
            RawSegment(start: 5, end: 6, speaker: 1),
        ]
        XCTAssertEqual(Segmenter.merge(segments, maxChunkDuration: 2), [
            SpeechChunk(start: 0, end: 2, speaker: 0),
            SpeechChunk(start: 2.1, end: 4, speaker: 1),
            SpeechChunk(start: 5, end: 6, speaker: 1),
        ])
        XCTAssertEqual(Segmenter.merge([
            RawSegment(start: 0, end: 1),
            RawSegment(start: 1.1, end: 2.01),
        ], maxChunkDuration: 2), [
            SpeechChunk(start: 0, end: 1, speaker: nil),
            SpeechChunk(start: 1.1, end: 2.01, speaker: nil),
        ])
    }

    func testGapBoundaryAndSpeakerChange() {
        XCTAssertEqual(Segmenter.merge([
            RawSegment(start: 0, end: 1, speaker: 0),
            RawSegment(start: 1.25, end: 2, speaker: 0),
            RawSegment(start: 2, end: 3, speaker: 1),
            RawSegment(start: 3.5, end: 4, speaker: 1),
        ], mergeGap: 0.25), [
            SpeechChunk(start: 0, end: 2, speaker: 0),
            SpeechChunk(start: 2, end: 3, speaker: 1),
            SpeechChunk(start: 3.5, end: 4, speaker: 1),
        ])
    }

    func testMinimumDurationInclusiveAndNoUsableSegments() {
        XCTAssertEqual(Segmenter.merge([
            RawSegment(start: 0, end: 0.2),
            RawSegment(start: 1, end: 1.25),
        ]), [SpeechChunk(start: 1, end: 1.25, speaker: nil)])
        XCTAssertEqual(Segmenter.merge([RawSegment(start: 0, end: 0.1)]), [])
        XCTAssertEqual(Segmenter.merge([]), [])
    }
}
