import Foundation

@MainActor
final class UploadDraft: ObservableObject {
    @Published var files: [URL] = []
    @Published var notice: String?
    @Published var language = ""

    func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let request = MediaImport.request(for: urls)
        let known = Set(files.map { $0.standardizedFileURL.path })
        let fresh = request.accepted.filter { !known.contains($0.standardizedFileURL.path) }
        files.append(contentsOf: fresh)
        if !request.rejected.isEmpty {
            notice = MediaImport.rejectionSummary(for: request.rejected)
        }
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
    }

    func clear() {
        files.removeAll()
        notice = nil
    }

    func applyPending(_ pending: (urls: [URL], notice: String?)) {
        addFiles(pending.urls)
        if let notice = pending.notice {
            self.notice = notice
        }
    }
}
