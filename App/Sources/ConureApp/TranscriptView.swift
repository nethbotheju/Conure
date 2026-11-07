import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TranscriptView: View {
    @EnvironmentObject private var library: LibraryStore
    let record: LibraryRecord
    let sourceExists: Bool

    @State private var sheet: TranscriptSheet?
    @State private var pendingDelete = false

    private var modelLabel: ModelLabel {
        library.modelLabel(for: record.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(record.lines.indices, id: \.self) { index in
                        lineView(record.lines[index])
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .rename(let speaker):
                RenameSpeakerSheet(speaker: speaker, library: library) {
                    self.sheet = nil
                }
            case .export:
                ExportTranscriptSheet(record: record, library: library)
            }
        }
        .alert("Delete Transcript?", isPresented: $pendingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if let entry = library.selection {
                    library.delete(entry)
                }
            }
        } message: {
            Text("This moves only the transcript record to the Trash. The source audio and any exported files remain on your Mac.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(record.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                actions
            }

            HStack(spacing: 8) {
                Text(LibraryFormat.date(record.createdAt))
                Text("·")
                Text(LibraryFormat.duration(record.duration))
                Text("·")
                Text(modelLabel.shortName)
                if let engine = modelLabel.engine {
                    engineTag(engine)
                }
                if !sourceExists {
                    Text("·")
                    Label("Source moved", systemImage: "questionmark.folder")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(modelLabel.name)
            .lineLimit(1)

            if !record.speakers.isEmpty {
                speakerStrip
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                sheet = .export
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Export this transcript as Markdown or SRT")

            Button(role: .destructive) {
                pendingDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Delete this transcript record")
        }
    }

    private func engineTag(_ engine: String) -> some View {
        Text(engine)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
    }

    private var speakerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(record.speakers) { speaker in
                    HStack(spacing: 6) {
                        Text(speaker.displayName)
                            .font(.callout)
                        Text(LibraryFormat.duration(speaker.talkSeconds))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button {
                            sheet = .rename(speaker)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Rename this speaker")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.quaternary))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func lineView(_ line: LibraryLine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("[\(LibraryFormat.clock(line.start))]")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let speakerId = line.speakerId {
                    Text(record.displayName(for: speakerId))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            Text(line.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum TranscriptSheet: Identifiable {
    case rename(LibrarySpeaker)
    case export

    var id: String {
        switch self {
        case .rename(let speaker): return "rename-\(speaker.id)"
        case .export: return "export"
        }
    }
}

struct RenameSpeakerSheet: View {
    let speaker: LibrarySpeaker
    let library: LibraryStore
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(speaker: LibrarySpeaker, library: LibraryStore, onFinish: @escaping () -> Void) {
        self.speaker = speaker
        self.library = library
        self.onFinish = onFinish
        _draft = State(initialValue: speaker.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename \(speaker.displayName)")
                .font(.headline)
            Text("The new name applies to every line spoken by this speaker.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }

            if let message = validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if speaker.name != nil {
                    Button("Clear Name") { clear() }
                        .disabled(isSaving)
                }
                Spacer()
                Button("Cancel", role: .cancel) { finish() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        validationMessage = nil
        do {
            _ = try LibraryCatalog.normalizedName(draft)
        } catch {
            validationMessage = error.localizedDescription
            return
        }
        isSaving = true
        Task {
            let renamed = await library.rename(speakerId: speaker.id, to: draft)
            isSaving = false
            if renamed {
                finish()
            } else {
                validationMessage = library.alertMessage
                library.alertMessage = nil
            }
        }
    }

    private func clear() {
        isSaving = true
        Task {
            let cleared = await library.clearName(speakerId: speaker.id)
            isSaving = false
            if cleared {
                finish()
            } else {
                validationMessage = library.alertMessage
                library.alertMessage = nil
            }
        }
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

struct ExportTranscriptSheet: View {
    let record: LibraryRecord
    let library: LibraryStore

    @Environment(\.dismiss) private var dismiss
    @State private var format = "md"
    @State private var timed = false
    @State private var isExporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Transcript")
                .font(.headline)

            Picker("Format", selection: $format) {
                Text("Markdown").tag("md")
                Text("SRT").tag("srt")
            }
            .pickerStyle(.segmented)

            if format == "md" {
                Toggle("Include timestamps", isOn: $timed)
            }

            Text("Exports render from the current record, so they include your latest speaker names. Exported files are snapshots and are not updated later.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose Destination…") { chooseDestination() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooseDestination() {
        let suggested = library.defaultExportURL(for: record, format: format)
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: format) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        Task {
            let exported = await library.export(
                record,
                format: format,
                timed: timed && format == "md",
                to: url
            )
            isExporting = false
            if exported {
                dismiss()
            }
        }
    }
}
