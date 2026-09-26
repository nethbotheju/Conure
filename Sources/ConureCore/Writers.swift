import Foundation

public enum TranscriptWriter {
    public static func write(_ transcript: Transcript, format: OutputFormat, timed: Bool) throws -> String {
        switch format {
        case .markdown: markdown(transcript, timed: timed)
        case .srt: srt(transcript)
        }
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

    private static func speakerLabel(_ transcript: Transcript, _ speaker: Int?) -> String {
        guard let speaker else { return "" }
        if let names = transcript.speakerNames, speaker < names.count {
            return names[speaker]
        }
        return "Speaker \(speaker + 1)"
    }

    private static func markdown(_ transcript: Transcript, timed: Bool) -> String {
        var out = "# \(transcript.sourceURL.lastPathComponent)\n\n"
        out += "- **Duration:** \(TimeFormat.clock(transcript.audioDuration))\n"
        if let names = transcript.speakerNames, !names.isEmpty {
            out += "- **Attendees:** \(names.joined(separator: ", "))\n"
        }
        out += "- **Model:** \(transcript.modelId)\n\n## Transcript\n\n"

        for line in transcript.lines {
            var row = ""
            if timed {
                row += "[\(TimeFormat.clock(line.start))] "
            }
            if let speaker = line.speaker {
                row += "**\(speakerLabel(transcript, speaker)):** "
            }
            row += line.text + "\n"
            out += row
        }
        return out
    }

    private static func srt(_ transcript: Transcript) -> String {
        var out = ""
        for (index, line) in transcript.lines.enumerated() {
            out += "\(index + 1)\n"
            out += "\(TimeFormat.srtRange(line.start, line.end))\n"
            var text = ""
            if let speaker = line.speaker {
                text += "\(speakerLabel(transcript, speaker)): "
            }
            text += line.text
            out += text + "\n\n"
        }
        return out
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
