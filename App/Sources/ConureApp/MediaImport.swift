import Foundation
import UniformTypeIdentifiers

struct MediaImportRequest: Equatable {
    let accepted: [URL]
    let rejected: [URL]

    static let empty = MediaImportRequest(accepted: [], rejected: [])
}

enum MediaImport {
    static let supportedExtensions: [String] = ["aac", "aif", "aifc", "aiff", "m4a", "mov", "mp3", "mp4", "wav"]

    private static let aacAudio = UTType("public.aac-audio") ?? UTType(importedAs: "public.aac-audio")
    private static let m4aAudio = UTType("com.apple.m4a-audio") ?? UTType(importedAs: "com.apple.m4a-audio")

    static let supportedContentTypes: [UTType] = [
        .mpeg4Movie, .quickTimeMovie, m4aAudio, .mp3, .wav, aacAudio, .aiff,
    ]

    static let formatDescription = "MP4, MOV, M4A, MP3, WAV, AAC, and AIFF"

    static func request(for urls: [URL]) -> MediaImportRequest {
        var seen = Set<String>()
        var accepted: [URL] = []
        var rejected: [URL] = []
        for url in urls {
            guard seen.insert(url.standardizedFileURL.path).inserted else { continue }
            if isSupported(url) {
                accepted.append(url)
            } else {
                rejected.append(url)
            }
        }
        return MediaImportRequest(accepted: sortedByPath(accepted), rejected: sortedByPath(rejected))
    }

    static func isSupported(_ url: URL) -> Bool {
        guard url.isFileURL,
              supportedExtensions.contains(url.pathExtension.lowercased()) else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }

    static func rejectionSummary(for urls: [URL]) -> String {
        guard !urls.isEmpty else { return "" }
        let names = sortedByPath(urls).map(\.lastPathComponent)
        let preview = names.prefix(3).joined(separator: ", ")
        let extra = names.count > 3 ? " and \(names.count - 3) more" : ""
        let noun = urls.count == 1 ? "file" : "files"
        return "Skipped \(urls.count) unsupported \(noun): \(preview)\(extra). Conure opens \(formatDescription)."
    }

    private static func sortedByPath(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
    }
}
