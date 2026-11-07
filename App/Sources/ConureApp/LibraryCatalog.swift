import Foundation

struct LibrarySpeaker: Decodable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String?
    let talkSeconds: Double
    let segmentCount: Int

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return "Speaker \(id)"
    }
}

struct LibraryLine: Decodable, Equatable, Sendable {
    let start: Double
    let end: Double
    let speakerId: Int?
    let text: String
}

struct LibraryRecord: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let title: String
    let sourcePath: String
    let duration: Double
    let model: String
    let requestedSpeakerCount: Int?
    let speakers: [LibrarySpeaker]
    let lines: [LibraryLine]

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }

    func displayName(for speakerId: Int?) -> String {
        guard let speakerId else { return "" }
        return speakers.first { $0.id == speakerId }?.displayName ?? "Speaker \(speakerId)"
    }
}

enum LibraryError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let found):
            return "This transcript uses record schema v\(found); this version of Conure supports v\(LibraryCatalog.supportedSchema). Update Conure to open it."
        case .malformed(let detail):
            return "This transcript record is unreadable: \(detail)"
        }
    }
}

enum SpeakerNameValidationError: LocalizedError, Equatable {
    case empty
    case controlCharacters
    case tooLong(Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Speaker names cannot be blank."
        case .controlCharacters:
            return "Speaker names cannot contain newlines or control characters."
        case .tooLong(let limit):
            return "Speaker names must be \(limit) characters or fewer."
        }
    }
}

enum LibraryCatalog {
    static let supportedSchema = 1
    static let maximumNameLength = 60

    struct Summary: Identifiable, Equatable, Sendable {
        let id: UUID
        let url: URL
        let title: String
        let createdAt: Date
        let duration: Double
        let sourcePath: String
        let speakers: [LibrarySpeaker]
        let problem: String?

        var isReadable: Bool { problem == nil }

        var speakerSummary: String {
            let names = speakers.map(\.displayName)
            return names.isEmpty ? "No speaker labels" : names.joined(separator: ", ")
        }

        func sourceExists() -> Bool {
            !sourcePath.isEmpty && FileManager.default.fileExists(atPath: sourcePath)
        }
    }

    static func directory(
        isDev: Bool = CLI.shared.isDevApp,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supportRoot: URL? = nil
    ) -> URL {
        if let override = environment["CONURE_LIBRARY_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let root = supportRoot
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = isDev ? "Conure Dev/library" : "Conure/library"
        return root.appendingPathComponent(folder, isDirectory: true)
    }

    static func read(_ url: URL) throws -> LibraryRecord {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LibraryError.malformed(error.localizedDescription)
        }
        struct Header: Decodable { let schemaVersion: Int }
        let header: Header
        do {
            header = try makeDecoder().decode(Header.self, from: data)
        } catch {
            throw LibraryError.malformed(error.localizedDescription)
        }
        guard header.schemaVersion <= supportedSchema else {
            throw LibraryError.unsupportedSchema(header.schemaVersion)
        }
        do {
            return try makeDecoder().decode(LibraryRecord.self, from: data)
        } catch {
            throw LibraryError.malformed(error.localizedDescription)
        }
    }

    static func load(in directory: URL) -> [Summary] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let entries = contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .map(summary(for:))
        return entries.sorted { lhs, rhs in
            if lhs.isReadable != rhs.isReadable { return lhs.isReadable }
            if lhs.createdAt == rhs.createdAt { return lhs.url.lastPathComponent < rhs.url.lastPathComponent }
            return lhs.createdAt > rhs.createdAt
        }
    }

    static func summary(for url: URL) -> Summary {
        do {
            let record = try read(url)
            return Summary(
                id: record.id,
                url: url,
                title: record.title,
                createdAt: record.createdAt,
                duration: record.duration,
                sourcePath: record.sourcePath,
                speakers: record.speakers,
                problem: nil
            )
        } catch {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let fallbackID = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            return Summary(
                id: fallbackID,
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                createdAt: modified ?? .distantPast,
                duration: 0,
                sourcePath: "",
                speakers: [],
                problem: error.localizedDescription
            )
        }
    }

    static func normalizedName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpeakerNameValidationError.empty }
        let hasControl = trimmed.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        guard !hasControl else { throw SpeakerNameValidationError.controlCharacters }
        guard trimmed.count <= maximumNameLength else {
            throw SpeakerNameValidationError.tooLong(maximumNameLength)
        }
        return trimmed
    }

    static func defaultExportURL(
        for record: LibraryRecord,
        format: String,
        libraryDirectory: URL
    ) -> URL {
        let base = (record.title as NSString).deletingPathExtension
        let sourceDirectory = record.sourceURL.deletingLastPathComponent()
        let directory = FileManager.default.fileExists(atPath: sourceDirectory.path)
            ? sourceDirectory
            : libraryDirectory
        return directory.appendingPathComponent("\(base).\(format)")
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = try? fractionalISO8601.parse(raw) {
                return date
            }
            if let date = try? plainISO8601.parse(raw) {
                return date
            }
            throw LibraryError.malformed("unreadable date \"\(raw)\"")
        }
        return decoder
    }

    private static let fractionalISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
}
