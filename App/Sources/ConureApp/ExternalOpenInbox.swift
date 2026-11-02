import Foundation
import Combine

@MainActor
final class ExternalOpenInbox: ObservableObject {
    @Published private(set) var pending: [URL] = []

    func receive(_ urls: [URL]) {
        var known = Set(pending.map { $0.standardizedFileURL.path })
        let fresh = urls.filter { known.insert($0.standardizedFileURL.path).inserted }
        guard !fresh.isEmpty else { return }
        pending.append(contentsOf: fresh)
    }

    func consume() -> [URL] {
        let urls = pending
        pending = []
        return urls
    }
}
