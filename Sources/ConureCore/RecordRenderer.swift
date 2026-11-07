import Foundation

public enum RecordRenderer {
    public static func render(_ record: TranscriptRecord, format: OutputFormat, timed: Bool) -> String {
        switch format {
        case .markdown: markdown(record, timed: timed)
        case .srt: srt(record)
        }
    }

    public static func defaultOutputURL(for record: TranscriptRecord, format: OutputFormat, fallbackDirectory: URL) -> URL {
        let base = (record.title as NSString).deletingPathExtension
        let sourceDirectory = record.sourceURL.deletingLastPathComponent()
        let directory = FileManager.default.fileExists(atPath: sourceDirectory.path)
            ? sourceDirectory
            : fallbackDirectory
        return directory.appendingPathComponent("\(base).\(format.rawValue)")
    }

    private static func markdown(_ record: TranscriptRecord, timed: Bool) -> String {
        var out = "# \(record.title)\n\n"
        out += "- **Duration:** \(TimeFormat.clock(record.duration))\n"
        let attendees = record.speakers.compactMap(\.name).filter { !$0.isEmpty }
        if !attendees.isEmpty {
            out += "- **Attendees:** \(attendees.joined(separator: ", "))\n"
        }
        out += "- **Model:** \(record.model)\n\n## Transcript\n\n"

        for line in record.lines {
            var row = ""
            if timed {
                row += "[\(TimeFormat.clock(line.start))] "
            }
            if let speakerId = line.speakerId {
                row += "**\(record.resolvedName(for: speakerId)):** "
            }
            row += line.text + "\n"
            out += row
        }
        return out
    }

    private static func srt(_ record: TranscriptRecord) -> String {
        var out = ""
        for (index, line) in record.lines.enumerated() {
            out += "\(index + 1)\n"
            out += "\(TimeFormat.srtRange(line.start, line.end))\n"
            var text = ""
            if let speakerId = line.speakerId {
                text += "\(record.resolvedName(for: speakerId)): "
            }
            text += line.text
            out += text + "\n\n"
        }
        return out
    }
}

public extension TranscriptRecord {
    static func make(from transcript: Transcript) -> TranscriptRecord {
        var speakerIndices = Set<Int>()
        for line in transcript.lines {
            if let speaker = line.speaker { speakerIndices.insert(speaker) }
        }
        let names = transcript.speakerNames ?? []
        speakerIndices.formUnion(names.indices)
        let speakers = speakerIndices.sorted().map { index -> RecordSpeaker in
            let lines = transcript.lines.filter { $0.speaker == index }
            let talk = lines.reduce(0.0) { $0 + max(0, $1.end - $1.start) }
            let name = index < names.count && !names[index].isEmpty ? names[index] : nil
            return RecordSpeaker(id: index + 1, name: name, talkSeconds: talk, segmentCount: lines.count)
        }
        let recordLines = transcript.lines.map { line in
            RecordLine(
                start: line.start,
                end: line.end,
                speakerId: line.speaker.map { $0 + 1 },
                text: line.text
            )
        }
        return TranscriptRecord(
            title: transcript.sourceURL.lastPathComponent,
            sourcePath: transcript.sourceURL.path,
            duration: transcript.audioDuration,
            model: transcript.modelId,
            requestedSpeakerCount: speakers.isEmpty ? nil : speakers.count,
            speakers: speakers,
            lines: recordLines
        )
    }
}
