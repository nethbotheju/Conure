import Foundation

public enum TranscriptWriter {
    public static func write(_ transcript: Transcript, format: OutputFormat, timed: Bool) throws -> String {
        RecordRenderer.render(TranscriptRecord.make(from: transcript), format: format, timed: timed)
    }

    public static func outputURL(for transcript: Transcript, format: OutputFormat) -> URL {
        let base = transcript.sourceURL.deletingPathExtension().lastPathComponent
        let directory = transcript.sourceURL.deletingLastPathComponent()
        return directory.appendingPathComponent("\(base).\(format.rawValue)")
    }

    public static func outputURL(for source: URL, format: OutputFormat, overrideDirectory: URL?) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let directory = overrideDirectory ?? source.deletingLastPathComponent()
        return directory.appendingPathComponent("\(base).\(format.rawValue)")
    }
}

public enum TimeFormat {
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    public static func srtTimestamp(_ seconds: Double) -> String {
        srtTimestamp(milliseconds: srtMilliseconds(seconds))
    }

    public static func srtRange(_ start: Double, _ end: Double) -> String {
        let startMilliseconds = srtMilliseconds(start)
        let endMilliseconds = max(startMilliseconds + 1, srtMilliseconds(end))
        return "\(srtTimestamp(milliseconds: startMilliseconds)) --> \(srtTimestamp(milliseconds: endMilliseconds))"
    }

    private static func srtMilliseconds(_ seconds: Double) -> Int {
        guard !seconds.isNaN else { return 0 }
        let milliseconds = (max(0, seconds) * 1000).rounded()
        return milliseconds >= Double(Int.max) ? Int.max - 1 : Int(milliseconds)
    }

    private static func srtTimestamp(milliseconds: Int) -> String {
        let total = milliseconds / 1000
        let ms = milliseconds % 1000
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}
