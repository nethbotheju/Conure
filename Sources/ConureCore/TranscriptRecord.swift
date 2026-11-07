import Foundation

public enum RecordSchema {
    public static let current = 1
}

public enum RecordError: LocalizedError, Equatable {
    case unsupportedSchema(found: Int, supported: Int)
    case malformed(String)
    case speakerNotFound(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let found, let supported):
            return "This transcript uses record schema v\(found); this version of Conure supports v\(supported). Update Conure to open it."
        case .malformed(let detail):
            return "Transcript record is malformed: \(detail)"
        case .speakerNotFound(let id):
            return "No speaker with id \(id) in this transcript. Run `conure speakers <record>` to list ids."
        }
    }
}

public struct RecordSpeaker: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public var name: String?
    public var talkSeconds: Double
    public var segmentCount: Int

    public init(id: Int, name: String? = nil, talkSeconds: Double, segmentCount: Int) {
        self.id = id
        self.name = name
        self.talkSeconds = talkSeconds
        self.segmentCount = segmentCount
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return "Speaker \(id)"
    }
}

public struct RecordLine: Codable, Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let speakerId: Int?
    public let text: String

    public init(start: Double, end: Double, speakerId: Int?, text: String) {
        self.start = start
        self.end = end
        self.speakerId = speakerId
        self.text = text
    }
}

public struct TranscriptRecord: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: UUID
    public var createdAt: Date
    public var title: String
    public var sourcePath: String
    public var duration: Double
    public var model: String
    public var requestedSpeakerCount: Int?
    public var speakers: [RecordSpeaker]
    public var lines: [RecordLine]

    public init(
        schemaVersion: Int = RecordSchema.current,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        sourcePath: String,
        duration: Double,
        model: String,
        requestedSpeakerCount: Int? = nil,
        speakers: [RecordSpeaker],
        lines: [RecordLine]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.sourcePath = sourcePath
        self.duration = duration
        self.model = model
        self.requestedSpeakerCount = requestedSpeakerCount
        self.speakers = speakers
        self.lines = lines
    }

    public var sourceURL: URL {
        URL(fileURLWithPath: sourcePath)
    }

    public func speaker(id: Int) -> RecordSpeaker? {
        speakers.first { $0.id == id }
    }

    public func resolvedName(for speakerId: Int?) -> String {
        guard let speakerId else { return "" }
        return speaker(id: speakerId)?.displayName ?? "Speaker \(speakerId)"
    }

    public func validate() throws {
        guard schemaVersion == RecordSchema.current else {
            throw RecordError.unsupportedSchema(found: schemaVersion, supported: RecordSchema.current)
        }
        var seen = Set<Int>()
        for speaker in speakers {
            guard speaker.id > 0 else {
                throw RecordError.malformed("speaker id \(speaker.id) is not positive")
            }
            guard seen.insert(speaker.id).inserted else {
                throw RecordError.malformed("duplicate speaker id \(speaker.id)")
            }
        }
        for line in lines {
            guard let speakerId = line.speakerId else { continue }
            guard seen.contains(speakerId) else {
                throw RecordError.malformed("line at \(TimeFormat.srtTimestamp(line.start)) references missing speaker \(speakerId)")
            }
        }
    }

    public mutating func setName(_ name: String?, for speakerId: Int) throws {
        guard let index = speakers.firstIndex(where: { $0.id == speakerId }) else {
            throw RecordError.speakerNotFound(speakerId)
        }
        speakers[index].name = name
    }
}

public enum RecordIO {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Self.fractionalISO8601))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = try? Self.fractionalISO8601.parse(raw) {
                return date
            }
            if let date = try? Self.plainISO8601.parse(raw) {
                return date
            }
            throw RecordError.malformed("unreadable date \"\(raw)\"")
        }
        return decoder
    }

    public static func encode(_ record: TranscriptRecord) throws -> Data {
        try makeEncoder().encode(record)
    }

    public static func decode(_ data: Data) throws -> TranscriptRecord {
        struct Header: Decodable { let schemaVersion: Int }
        let header: Header
        do {
            header = try makeDecoder().decode(Header.self, from: data)
        } catch {
            throw RecordError.malformed(error.localizedDescription)
        }
        guard header.schemaVersion <= RecordSchema.current else {
            throw RecordError.unsupportedSchema(found: header.schemaVersion, supported: RecordSchema.current)
        }
        let record: TranscriptRecord
        do {
            record = try makeDecoder().decode(TranscriptRecord.self, from: data)
        } catch {
            throw RecordError.malformed(error.localizedDescription)
        }
        try record.validate()
        return record
    }

    public static func load(_ url: URL) throws -> TranscriptRecord {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RecordError.malformed(error.localizedDescription)
        }
        return try decode(data)
    }

    public static func save(_ record: TranscriptRecord, to url: URL) throws {
        try record.validate()
        let data = try encode(record)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        let result = temporaryURL.withUnsafeFileSystemRepresentation { source in
            url.withUnsafeFileSystemRepresentation { destination in
                rename(source!, destination!)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static let fractionalISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
}

public enum RecordLibrary {
    public static let environmentVariable = "CONURE_LIBRARY_DIR"

    public static func directoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportRoot: URL? = nil,
        folder: String = "Conure/library"
    ) -> URL {
        if let override = environment[environmentVariable], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let root = supportRoot
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent(folder, isDirectory: true)
    }

    public static func url(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    public static func save(_ record: TranscriptRecord, in directory: URL) throws -> URL {
        let url = url(for: record.id, in: directory)
        try RecordIO.save(record, to: url)
        return url
    }

    public static func list(in directory: URL) -> [LibraryEntry] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let entries = contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { entryURL(for: $0) }
        return entries.sorted { lhs, rhs in
            if lhs.isReadable != rhs.isReadable { return lhs.isReadable }
            if lhs.createdAt == rhs.createdAt { return lhs.url.lastPathComponent < rhs.url.lastPathComponent }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func entryURL(for url: URL) -> LibraryEntry {
        do {
            let record = try RecordIO.load(url)
            return LibraryEntry(
                id: record.id,
                url: url,
                createdAt: record.createdAt,
                title: record.title,
                sourcePath: record.sourcePath,
                duration: record.duration,
                model: record.model,
                speakers: record.speakers,
                problem: nil
            )
        } catch {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let fallbackID = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            return LibraryEntry(
                id: fallbackID,
                url: url,
                createdAt: modified ?? .distantPast,
                title: url.deletingPathExtension().lastPathComponent,
                sourcePath: "",
                duration: 0,
                model: "",
                speakers: [],
                problem: error.localizedDescription
            )
        }
    }
}

public struct LibraryEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let url: URL
    public let createdAt: Date
    public let title: String
    public let sourcePath: String
    public let duration: Double
    public let model: String
    public let speakers: [RecordSpeaker]
    public let problem: String?

    public init(
        id: UUID,
        url: URL,
        createdAt: Date,
        title: String,
        sourcePath: String,
        duration: Double,
        model: String,
        speakers: [RecordSpeaker],
        problem: String?
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.title = title
        self.sourcePath = sourcePath
        self.duration = duration
        self.model = model
        self.speakers = speakers
        self.problem = problem
    }

    public var isReadable: Bool { problem == nil }

    public var speakerSummary: String {
        let names = speakers.map(\.displayName)
        return names.isEmpty ? "No speaker labels" : names.joined(separator: ", ")
    }

    public var sourceExists: Bool {
        !sourcePath.isEmpty && FileManager.default.fileExists(atPath: sourcePath)
    }
}
