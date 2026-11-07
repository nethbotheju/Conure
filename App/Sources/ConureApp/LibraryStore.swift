import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var entries: [LibraryCatalog.Summary] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var record: LibraryRecord?
    @Published var alertMessage: String?
    @Published private(set) var modelRows: [CLIModelRow] = []

    let directory: URL
    private let cli: any LibraryCLI

    init(directory: URL = LibraryCatalog.directory(), cli: any LibraryCLI = CLI.shared) {
        self.directory = directory
        self.cli = cli
        refresh()
        loadModels()
    }

    func modelLabel(for raw: String) -> ModelLabel {
        ModelCatalog.label(for: raw, rows: modelRows)
    }

    private func loadModels() {
        CLI.shared.models { rows in
            Task { @MainActor [weak self] in
                self?.modelRows = rows
            }
        }
    }

    var selection: LibraryCatalog.Summary? {
        entries.first { $0.id == selectedID }
    }

    func refresh() {
        entries = LibraryCatalog.load(in: directory)
        if let selectedID, !entries.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
            record = nil
        }
        reloadRecord()
    }

    func select(_ summary: LibraryCatalog.Summary) {
        selectedID = summary.id
        reloadRecord()
    }

    func focus(recordPath: String) {
        refresh()
        let target = URL(fileURLWithPath: recordPath).resolvingSymlinksInPath().standardizedFileURL.path
        guard let entry = entries.first(where: {
            $0.url.resolvingSymlinksInPath().standardizedFileURL.path == target
        }) else { return }
        select(entry)
    }

    private func reloadRecord() {
        guard let summary = selection, summary.isReadable else {
            record = nil
            return
        }
        record = try? LibraryCatalog.read(summary.url)
    }

    func rename(speakerId: Int, to rawName: String) async -> Bool {
        guard let summary = selection else { return false }
        let name: String
        do {
            name = try LibraryCatalog.normalizedName(rawName)
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
        do {
            try await cli.setSpeakerName(record: summary.url, id: speakerId, name: name)
            refresh()
            return true
        } catch {
            alertMessage = "Could not rename the speaker. \(error.localizedDescription)"
            return false
        }
    }

    func clearName(speakerId: Int) async -> Bool {
        guard let summary = selection else { return false }
        do {
            try await cli.clearSpeakerName(record: summary.url, id: speakerId)
            refresh()
            return true
        } catch {
            alertMessage = "Could not clear the speaker name. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func delete(_ summary: LibraryCatalog.Summary) -> Bool {
        do {
            try FileManager.default.trashItem(at: summary.url, resultingItemURL: nil)
            if selectedID == summary.id {
                selectedID = nil
                record = nil
            }
            refresh()
            return true
        } catch {
            alertMessage = "Could not move the transcript to the Trash. \(error.localizedDescription)"
            return false
        }
    }

    func defaultExportURL(for record: LibraryRecord, format: String) -> URL {
        LibraryCatalog.defaultExportURL(for: record, format: format, libraryDirectory: directory)
    }

    func export(_ record: LibraryRecord, format: String, timed: Bool, to url: URL) async -> Bool {
        guard let summary = selection else { return false }
        do {
            try await cli.exportRecord(record: summary.url, format: format, timed: timed, output: url)
            return true
        } catch {
            alertMessage = "Could not export the transcript. \(error.localizedDescription)"
            return false
        }
    }
}
