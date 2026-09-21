import Foundation

public struct TranscriptLine: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let speaker: Int?
    public let text: String

    public init(start: Double, end: Double, speaker: Int?, text: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
        self.text = text
    }
}

public struct Transcript: Sendable {
    public let sourceURL: URL
    public let audioDuration: Double
    public let modelId: String
    public let speakerNames: [String]?
    public let lines: [TranscriptLine]

    public init(
        sourceURL: URL,
        audioDuration: Double,
        modelId: String,
        speakerNames: [String]?,
        lines: [TranscriptLine]
    ) {
        self.sourceURL = sourceURL
        self.audioDuration = audioDuration
        self.modelId = modelId
        self.speakerNames = speakerNames
        self.lines = lines
    }
}

public enum OutputFormat: String, Sendable, CaseIterable {
    case markdown = "md"
    case srt = "srt"
}

public struct TranscribeOptions: Sendable {
    public var modelId: String?
    public var language: String?
    public var speakerNames: [String]?
    public var format: OutputFormat
    public var timed: Bool
    public var outputDirectory: URL?
    public var maxChunkDuration: Double

    public init(
        modelId: String? = nil,
        language: String? = "en",
        speakerNames: [String]? = nil,
        format: OutputFormat = .markdown,
        timed: Bool = false,
        outputDirectory: URL? = nil,
        maxChunkDuration: Double = 25.0
    ) {
        self.modelId = modelId
        self.language = language
        self.speakerNames = speakerNames
        self.format = format
        self.timed = timed
        self.outputDirectory = outputDirectory
        self.maxChunkDuration = maxChunkDuration
    }
}
