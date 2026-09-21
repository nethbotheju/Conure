import Foundation

public enum TranscribePipeline {

    public static func transcribeFile(
        _ url: URL,
        options: TranscribeOptions,
        progress: ProgressSink? = nil
    ) async throws -> (transcript: Transcript, outputURL: URL) {
        progress?(.progress(.decode, 0, url.lastPathComponent))
        let timing = ProcessInfo.processInfo.environment["CONURE_TIMING"] == "1"
        let t0 = CFAbsoluteTimeGetCurrent()

        let samples = try AudioDecoder.loadMono16k(from: url)
        let duration = AudioDecoder.duration(of: samples)
        guard !samples.isEmpty else {
            throw ConureError.noAudioTrack(url)
        }
        if timing { FileHandle.standardError.write(Data("[timing] decode \(CFAbsoluteTimeGetCurrent() - t0)s\n".utf8)) }
        progress?(.progress(.decode, 100, TimeFormat.clock(duration)))

        let tLoad = CFAbsoluteTimeGetCurrent()
        let transcriber = try await Transcriber.load(
            modelId: options.modelId,
            progress: progress
        )
        try transcriber.warmUp()
        if timing { FileHandle.standardError.write(Data("[timing] asr-load \(CFAbsoluteTimeGetCurrent() - tLoad)s\n".utf8)) }

        let diarize = options.speakerNames != nil && !(options.speakerNames ?? []).isEmpty

        let rawSegments: [RawSegment]
        if diarize {
            let tDiar = CFAbsoluteTimeGetCurrent()
            let diarizer = try await Diarizer.load(progress: progress)
            if timing { FileHandle.standardError.write(Data("[timing] diar-load \(CFAbsoluteTimeGetCurrent() - tDiar)s\n".utf8)) }
            progress?(.progress(.diarize, 0))
            let turns = diarizer.turns(audio: samples, sampleRate: SampleRate.mono16k) { fraction, detail in
                progress?(.progress(.diarize, Double(fraction) * 100, detail))
                return true
            }
            rawSegments = turns.map { RawSegment(start: $0.start, end: $0.end, speaker: $0.speaker) }
            if timing { FileHandle.standardError.write(Data("[timing] diarize \(CFAbsoluteTimeGetCurrent() - tDiar)s\n".utf8)) }
            progress?(.progress(.diarize, 100, "\(turns.count) turns"))
        } else {
            let tVad = CFAbsoluteTimeGetCurrent()
            let vad = try await VoiceActivityDetector.load(progress: progress)
            progress?(.progress(.vad, 0))
            rawSegments = vad.speechSegments(audio: samples, sampleRate: SampleRate.mono16k)
            if timing { FileHandle.standardError.write(Data("[timing] vad \(CFAbsoluteTimeGetCurrent() - tVad)s\n".utf8)) }
            progress?(.progress(.vad, 100, "\(rawSegments.count) utterances"))
        }

        let chunks = Segmenter.merge(rawSegments, maxChunkDuration: options.maxChunkDuration)
        guard !chunks.isEmpty else {
            throw ConureError.noSpeechDetected(url)
        }

        var lines: [TranscriptLine] = []
        let tAsr = CFAbsoluteTimeGetCurrent()
        for (index, chunk) in chunks.enumerated() {
            let slice = AudioDecoder.slice(samples, from: chunk.start, to: chunk.end, sampleRate: SampleRate.mono16k)
            let text = try transcriber.transcribe(slice, sampleRate: SampleRate.mono16k, language: options.language)
            if !text.isEmpty {
                lines.append(TranscriptLine(start: chunk.start, end: chunk.end, speaker: chunk.speaker, text: text))
            }
            progress?(.progress(.asr, Double(index + 1) / Double(chunks.count) * 100, "\(index + 1)/\(chunks.count)"))
        }
        if timing { FileHandle.standardError.write(Data("[timing] asr \(CFAbsoluteTimeGetCurrent() - tAsr)s for \(chunks.count) chunks (\(duration)s audio)\n".utf8)) }

        let speakerNames: [String]?
        if diarize {
            let provided = options.speakerNames ?? []
            speakerNames = provided.isEmpty ? nil : provided
        } else {
            speakerNames = nil
        }

        let transcript = Transcript(
            sourceURL: url,
            audioDuration: duration,
            modelId: transcriber.modelId,
            speakerNames: speakerNames,
            lines: lines
        )

        progress?(.progress(.write, 0))
        let content = try TranscriptWriter.write(transcript, format: options.format, timed: options.timed)
        let outputURL = TranscriptWriter.outputURL(for: url, format: options.format, overrideDirectory: options.outputDirectory)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        progress?(.progress(.write, 100))

        return (transcript, outputURL)
    }
}

public enum ConureError: LocalizedError {
    case noAudioTrack(URL)
    case noSpeechDetected(URL)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack(let url):
            return "Could not decode any audio from \(url.lastPathComponent)"
        case .noSpeechDetected(let url):
            return "No speech detected in \(url.lastPathComponent)"
        }
    }
}
