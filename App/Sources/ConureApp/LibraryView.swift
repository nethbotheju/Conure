import SwiftUI
import AppKit

enum LibraryFormat {
    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(total % 60)s" }
        return "\(total)s"
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 340)
            detailPane
                .frame(minWidth: 380, maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    library.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Rescan the transcript library")
            }
        }
        .onAppear { library.refresh() }
        .alert(
            "Problem",
            isPresented: Binding(
                get: { library.alertMessage != nil },
                set: { if !$0 { library.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { library.alertMessage = nil }
        } message: {
            Text(library.alertMessage ?? "")
        }
    }

    private var listPane: some View {
        List(
            selection: Binding(
                get: { library.selectedID },
                set: { id in
                    guard let id, let entry = library.entries.first(where: { $0.id == id }) else { return }
                    library.select(entry)
                }
            )
        ) {
            ForEach(library.entries) { entry in
                LibraryRow(entry: entry)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Reveal Record in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                        }
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if library.entries.isEmpty {
                listEmptyState
            }
        }
    }

    private var listEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No Transcripts")
                .font(.headline)
            Text("Finished transcriptions appear here automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Upload Files") {
                navigation.go(to: .upload)
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let entry = library.selection {
            if let record = library.record {
                TranscriptView(record: record, sourceExists: entry.sourceExists())
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.orange)
                    Text("Unreadable Transcript")
                        .font(.title3.weight(.semibold))
                    Text(entry.problem ?? "This transcript record could not be opened.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No Transcript Selected")
                    .font(.title3.weight(.semibold))
                Text(library.entries.isEmpty
                     ? "Upload audio or video files to create your first transcript."
                     : "Select a transcript on the left to read it, rename its speakers, or export it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LibraryRow: View {
    let entry: LibraryCatalog.Summary

    private var accessibilityDescription: String {
        guard entry.isReadable else {
            return "\(entry.title). \(entry.problem ?? "Unreadable transcript record")"
        }
        var parts = [
            entry.title,
            LibraryFormat.date(entry.createdAt),
            LibraryFormat.duration(entry.duration),
        ]
        if !entry.speakers.isEmpty {
            let count = entry.speakers.count
            parts.append("\(count) speaker\(count == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !entry.isReadable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if entry.isReadable {
                HStack(spacing: 5) {
                    Text(LibraryFormat.date(entry.createdAt))
                    Text("·")
                    Text(LibraryFormat.duration(entry.duration))
                    if !entry.speakers.isEmpty {
                        Text("·")
                        Text("\(entry.speakers.count) speaker\(entry.speakers.count == 1 ? "" : "s")")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(entry.problem ?? "Unreadable transcript record")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .help(entry.isReadable
              ? "\(entry.title)\n\(entry.speakerSummary)"
              : (entry.problem ?? "Unreadable transcript record"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }
}
