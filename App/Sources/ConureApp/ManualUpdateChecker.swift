import Foundation

struct ManualRelease: Equatable, Sendable {
    let version: String
    let url: URL
    let notes: String?
    let downloadURL: URL?

    init(version: String, url: URL, notes: String?, downloadURL: URL? = nil) {
        self.version = version
        self.url = url
        self.notes = notes
        self.downloadURL = downloadURL
    }
}

enum ManualCheckResult: Equatable, Sendable {
    case update(ManualRelease)
    case current(ManualRelease)
    case unknown(ManualRelease)
}

enum ManualUpdateError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        case .httpStatus(let code):
            return "GitHub returned HTTP \(code). Try again later."
        case .network(let detail):
            return detail
        }
    }
}

enum ManualUpdateChecker {
    static let endpoint = URL(string: "https://api.github.com/repos/nethbotheju/Conure/releases/latest")!

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: String
        let body: String?
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
        }
    }

    static func latest(
        installedVersion: String?,
        session: URLSession = .shared
    ) async throws -> ManualCheckResult {
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Conure", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ManualUpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ManualUpdateError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ManualUpdateError.httpStatus(http.statusCode)
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ManualUpdateError.invalidResponse
        }
        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName
        let asset = payload.assets?.first { $0.name == "Conure-\(version).dmg" }
            ?? payload.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        return try evaluate(
            tag: payload.tagName,
            htmlURL: payload.htmlURL,
            notes: payload.body,
            installedVersion: installedVersion,
            downloadURL: asset.flatMap { URL(string: $0.browserDownloadURL) }
        )
    }

    static func evaluate(
        tag: String,
        htmlURL: String,
        notes: String?,
        installedVersion: String?,
        downloadURL: URL? = nil
    ) throws -> ManualCheckResult {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard StableVersion(version) != nil,
              let url = URL(string: htmlURL),
              url.scheme == "https" else {
            throw ManualUpdateError.invalidResponse
        }
        let release = ManualRelease(version: version, url: url, notes: notes, downloadURL: downloadURL)
        guard let installedVersion, let installed = StableVersion(installedVersion) else {
            return .unknown(release)
        }
        guard let candidate = StableVersion(version) else {
            return .unknown(release)
        }
        return candidate > installed ? .update(release) : .current(release)
    }
}
