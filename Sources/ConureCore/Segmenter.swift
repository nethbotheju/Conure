import Foundation

public struct SpeechChunk: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let speaker: Int?
}

public struct RawSegment: Sendable {
    public let start: Double
    public let end: Double
    public let speaker: Int?

    public init(start: Double, end: Double, speaker: Int? = nil) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

public enum Segmenter {
    public static func merge(
        _ segments: [RawSegment],
        maxChunkDuration: Double = 25.0,
        mergeGap: Double = 0.35,
        minSegmentDuration: Double = 0.25
    ) -> [SpeechChunk] {
        let usable = segments
            .filter { $0.end - $0.start >= minSegmentDuration }
            .sorted { $0.start < $1.start }
        guard !usable.isEmpty else { return [] }

        var chunks: [SpeechChunk] = []
        var current = (start: usable[0].start, end: usable[0].end, speaker: usable[0].speaker)

        for segment in usable.dropFirst() {
            let gap = segment.start - current.end
            let mergedDuration = segment.end - current.start
            let sameSpeaker = segment.speaker == current.speaker

            if sameSpeaker, gap <= mergeGap, mergedDuration <= maxChunkDuration {
                current.end = segment.end
            } else {
                chunks.append(SpeechChunk(start: current.start, end: current.end, speaker: current.speaker))
                current = (start: segment.start, end: segment.end, speaker: segment.speaker)
            }
        }
        chunks.append(SpeechChunk(start: current.start, end: current.end, speaker: current.speaker))
        return chunks
    }
}
