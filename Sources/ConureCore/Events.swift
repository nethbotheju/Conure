import Foundation

public struct ConureEvent: Sendable, Codable {
    public enum Stage: String, Sendable, Codable {
        case decode
        case diarize
        case vad
        case asr
        case write
        case modelDownload
    }

    public enum Kind: String, Sendable, Codable {
        case progress
        case done
        case error
    }

    public let type: Kind
    public let stage: Stage?
    public let percent: Double?
    public let detail: String?
    public let outputPath: String?

    public static func progress(_ stage: Stage, _ percent: Double, _ detail: String? = nil) -> ConureEvent {
        ConureEvent(type: .progress, stage: stage, percent: percent, detail: detail, outputPath: nil)
    }

    public static func download(_ percent: Double, _ detail: String? = nil) -> ConureEvent {
        ConureEvent(type: .progress, stage: .modelDownload, percent: percent, detail: detail, outputPath: nil)
    }

    public static func done(_ outputPath: String) -> ConureEvent {
        ConureEvent(type: .done, stage: nil, percent: nil, detail: nil, outputPath: outputPath)
    }

    public static func error(_ message: String) -> ConureEvent {
        ConureEvent(type: .error, stage: nil, percent: nil, detail: message, outputPath: nil)
    }
}

public typealias ProgressSink = @Sendable (ConureEvent) -> Void
