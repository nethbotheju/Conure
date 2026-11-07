import Foundation

public struct AttributionResult: Sendable, Equatable {
    public let speakers: [RecordSpeaker]
    public let lines: [RecordLine]
    public let notes: [String]

    public init(speakers: [RecordSpeaker], lines: [RecordLine], notes: [String] = []) {
        self.speakers = speakers
        self.lines = lines
        self.notes = notes
    }
}

public enum SpeakerAttribution {
    public struct Cluster: Sendable, Equatable {
        public let rawId: Int
        public let segments: [TranscriptLine]

        public var talkSeconds: Double {
            segments.reduce(0) { $0 + max(0, $1.end - $1.start) }
        }

        public var segmentCount: Int { segments.count }

        public var firstStart: Double {
            segments.map(\.start).min() ?? 0
        }
    }

    public static func attribute(
        lines: [TranscriptLine],
        requestedCount: Int? = nil,
        legacyNames: [String]? = nil,
        weakTalkSeconds: Double = 3,
        weakTalkFraction: Double = 0.03,
        weakSegmentCount: Int = 2
    ) -> AttributionResult {
        let clusters = makeClusters(lines)
        guard !clusters.isEmpty else {
            return AttributionResult(speakers: [], lines: lines.map {
                RecordLine(start: $0.start, end: $0.end, speakerId: nil, text: $0.text)
            })
        }

        var notes: [String] = []
        var retained = clusters
        var absorbed: [Int: Int] = [:]

        let totalTalk = clusters.reduce(0) { $0 + $1.talkSeconds }
        let threshold = max(weakTalkSeconds, totalTalk * weakTalkFraction)

        if let requestedCount, requestedCount > 0, clusters.count > requestedCount {
            let ordered = clusters.sorted(by: moreEvidence)
            let kept = Array(ordered.prefix(requestedCount))
            var extras: [Cluster] = []
            var merged = 0
            for candidate in ordered.dropFirst(requestedCount) {
                let weak = candidate.talkSeconds < threshold || candidate.segmentCount <= weakSegmentCount
                if weak, let target = nearest(candidate, among: kept) {
                    absorbed[candidate.rawId] = target.rawId
                    merged += 1
                } else {
                    extras.append(candidate)
                }
            }
            retained = kept + extras

            var summary = "Detected \(clusters.count) voices, requested \(requestedCount)."
            if merged > 0 {
                summary += " Merged \(merged) low-evidence cluster\(merged == 1 ? "" : "s") into nearby speakers."
            }
            if !extras.isEmpty {
                summary += " Kept \(extras.count) extra strong voice\(extras.count == 1 ? "" : "s")."
            }
            notes.append(summary)
        } else if let requestedCount, requestedCount > clusters.count {
            notes.append("Detected \(clusters.count) voice\(clusters.count == 1 ? "" : "s"), fewer than the requested \(requestedCount).")
        }

        var mapping: [Int: Int] = [:]
        for cluster in retained { mapping[cluster.rawId] = cluster.rawId }
        for (from, to) in absorbed { mapping[from] = to }

        let names = (legacyNames ?? []).filter { !$0.isEmpty }
        var namesByRawID: [Int: String] = [:]
        if !names.isEmpty {
            let byFirstSpeech = retained.sorted { $0.firstStart < $1.firstStart }
            for (index, cluster) in byFirstSpeech.enumerated() where index < names.count {
                namesByRawID[cluster.rawId] = names[index]
            }
        }

        let mappedLines = lines.map { line -> RecordLine in
            let raw = line.speaker.flatMap { mapping[$0] }
            return RecordLine(start: line.start, end: line.end, speakerId: raw, text: line.text)
        }

        var stats: [Int: (talk: Double, count: Int, firstStart: Double)] = [:]
        for line in mappedLines {
            guard let speaker = line.speakerId else { continue }
            var entry = stats[speaker] ?? (0, 0, line.start)
            entry.talk += max(0, line.end - line.start)
            entry.count += 1
            entry.firstStart = min(entry.firstStart, line.start)
            stats[speaker] = entry
        }

        let orderedStats = stats.sorted { lhs, rhs in
            if lhs.value.talk != rhs.value.talk { return lhs.value.talk > rhs.value.talk }
            return lhs.key < rhs.key
        }
        var remap: [Int: Int] = [:]
        var speakers: [RecordSpeaker] = []
        for (index, entry) in orderedStats.enumerated() {
            let id = index + 1
            remap[entry.key] = id
            speakers.append(RecordSpeaker(
                id: id,
                name: namesByRawID[entry.key],
                talkSeconds: entry.value.talk,
                segmentCount: entry.value.count
            ))
        }

        let finalLines = mappedLines.map { line in
            RecordLine(
                start: line.start,
                end: line.end,
                speakerId: line.speakerId.flatMap { remap[$0] },
                text: line.text
            )
        }

        return AttributionResult(speakers: speakers, lines: finalLines, notes: notes)
    }

    private static func makeClusters(_ lines: [TranscriptLine]) -> [Cluster] {
        var byRaw: [Int: [TranscriptLine]] = [:]
        for line in lines {
            guard let speaker = line.speaker else { continue }
            byRaw[speaker, default: []].append(line)
        }
        return byRaw.map { Cluster(rawId: $0.key, segments: $0.value) }
            .sorted { $0.rawId < $1.rawId }
    }

    private static func moreEvidence(_ lhs: Cluster, _ rhs: Cluster) -> Bool {
        if lhs.talkSeconds != rhs.talkSeconds { return lhs.talkSeconds > rhs.talkSeconds }
        if lhs.segmentCount != rhs.segmentCount { return lhs.segmentCount > rhs.segmentCount }
        return lhs.rawId < rhs.rawId
    }

    private static func nearest(_ cluster: Cluster, among candidates: [Cluster]) -> Cluster? {
        candidates.min { distance(cluster, $0) < distance(cluster, $1) }
    }

    private static func distance(_ lhs: Cluster, _ rhs: Cluster) -> Double {
        var best = Double.infinity
        for a in lhs.segments {
            for b in rhs.segments {
                let gap: Double
                if a.end < b.start {
                    gap = b.start - a.end
                } else if b.end < a.start {
                    gap = a.start - b.end
                } else {
                    gap = 0
                }
                best = min(best, gap)
            }
        }
        return best
    }
}
