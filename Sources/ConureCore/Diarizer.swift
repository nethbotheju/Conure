import Foundation
import SpeechVAD
import AudioCommon

public struct SpeakerTurn: Sendable {
    public let start: Double
    public let end: Double
    public let speaker: Int
}

public final class Diarizer {
    private let sortformer: SortformerDiarizer

    private init(sortformer: SortformerDiarizer) {
        self.sortformer = sortformer
    }

    public static func load(
        offlineMode: Bool = false,
        progress: ProgressSink? = nil
    ) async throws -> Diarizer {
        let descriptor = ModelStore.sortformer
        let cacheDir = ModelStore.directory(for: descriptor)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let diarizer = try await SortformerDiarizer.fromPretrained(
            cacheDir: cacheDir,
            offlineMode: offlineMode,
            progressHandler: { fraction, detail in
                progress?(.download(fraction * 100, detail))
            }
        )
        return Diarizer(sortformer: diarizer)
    }

    public func turns(
        audio: [Float],
        sampleRate: Int,
        progress: ((Float, String) -> Bool)? = nil
    ) -> [SpeakerTurn] {
        let result = sortformer.diarize(
            audio: audio,
            sampleRate: sampleRate,
            config: .sortformer,
            progressHandler: progress
        )
        let raw = result.segments.map { seg in
            RawSegment(start: Double(seg.startTime), end: Double(seg.endTime), speaker: seg.speakerId)
        }
        return compactSpeakerIndices(raw).map {
            SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker!)
        }
    }

    private func compactSpeakerIndices(_ segments: [RawSegment]) -> [RawSegment] {
        var mapping: [Int: Int] = [:]
        var next = 0
        return segments.map { seg in
            guard let id = seg.speaker else { return seg }
            if let mapped = mapping[id] {
                return RawSegment(start: seg.start, end: seg.end, speaker: mapped)
            }
            mapping[id] = next
            next += 1
            return RawSegment(start: seg.start, end: seg.end, speaker: mapping[id]!)
        }
    }
}

public final class VoiceActivityDetector {
    private let silero: SileroVADModel

    private init(silero: SileroVADModel) {
        self.silero = silero
    }

    public static func load(
        offlineMode: Bool = false,
        progress: ProgressSink? = nil
    ) async throws -> VoiceActivityDetector {
        let descriptor = ModelStore.silero
        let cacheDir = ModelStore.directory(for: descriptor)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let model = try await SileroVADModel.fromPretrained(
            engine: .coreml,
            cacheDir: cacheDir,
            offlineMode: offlineMode,
            progressHandler: { fraction, detail in
                progress?(.download(fraction * 100, detail))
            }
        )
        return VoiceActivityDetector(silero: model)
    }

    public func speechSegments(audio: [Float], sampleRate: Int) -> [RawSegment] {
        silero.detectSpeech(audio: audio, sampleRate: sampleRate).map {
            RawSegment(start: Double($0.startTime), end: Double($0.endTime))
        }
    }
}
