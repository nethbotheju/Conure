import SwiftUI

struct JobsView: View {
    @EnvironmentObject private var store: QueueStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        Group {
            if store.jobs.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
        .navigationTitle("Queue")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.go(to: .upload)
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .help("Add audio or video files")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Transcriptions Yet", systemImage: "waveform")
        } description: {
            Text("Upload audio or video files to start a transcription. Finished work is saved to the Library.")
        } actions: {
            Button("Upload Files") {
                navigation.go(to: .upload)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jobList: some View {
        List {
            if !activeJobs.isEmpty {
                Section("In Progress") {
                    ForEach(activeJobs) { job in
                        row(for: job)
                    }
                }
            }
            if !issueJobs.isEmpty {
                Section("Needs Attention") {
                    ForEach(issueJobs) { job in
                        row(for: job)
                    }
                }
            }
            if !completedJobs.isEmpty {
                Section {
                    ForEach(completedJobs) { job in
                        row(for: job)
                    }
                } header: {
                    HStack {
                        Text("Completed")
                        Spacer()
                        Button("Clear") {
                            store.clearCompleted()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help("Remove completed jobs from the queue; transcripts stay in the Library")
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var activeJobs: [Job] {
        store.jobs.filter { job in
            switch job.status {
            case .queued, .running: return true
            default: return false
            }
        }
    }

    private var issueJobs: [Job] {
        store.jobs.filter { job in
            switch job.status {
            case .failed, .cancelled: return true
            default: return false
            }
        }
    }

    private var completedJobs: [Job] {
        store.jobs.filter { job in
            if case .done = job.status { return true }
            return false
        }
    }

    private func row(for job: Job) -> some View {
        JobRow(job: job) { record in
            openRecord(jobID: job.id, record: record)
        }
        .contextMenu {
            if case .done(let record) = job.status, let record {
                Button("Open Transcript") { openRecord(jobID: job.id, record: record) }
                Button("Reveal Record in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record)])
                }
            }
            if job.status == .queued {
                Button("Cancel") { store.cancel(job.id) }
            }
            if case .running = job.status {
                Button("Cancel") { store.cancel(job.id) }
            }
            if case .failed = job.status {
                Button("Retry") { store.retry(job.id) }
            }
            if job.status == .cancelled {
                Button("Retry") { store.retry(job.id) }
            }
            Button("Remove", role: .destructive) { store.remove(job.id) }
        }
    }

    private func openRecord(jobID: UUID, record: String) {
        library.focus(recordPath: record)
        navigation.go(to: .library)
        store.remove(jobID)
    }
}

struct JobRow: View {
    let job: Job
    let openRecord: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.input.lastPathComponent)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    statusText
                }

                if case .running = job.status {
                    ProgressView(value: progressFraction)
                        .progressViewStyle(.linear)
                }

                HStack(spacing: 8) {
                    if let count = job.configuration.speakerCount {
                        badge(count == 1 ? "1 speaker" : "\(count) speakers")
                    }
                    if case .done(let record) = job.status {
                        if let record {
                            Button("Open") { openRecord(record) }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                        Text("Saved to Library")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch job.status {
        case .queued:
            Text("Queued").foregroundStyle(.secondary)
        case .running(let stage, let percent):
            Text("\(Self.label(for: stage)) \(Int(percent))%")
                .foregroundStyle(.blue)
                .monospacedDigit()
        case .done:
            Text("Done").foregroundStyle(.green)
        case .failed(let reason):
            Text(reason)
                .foregroundStyle(.orange)
                .lineLimit(2)
        case .cancelled:
            Text("Cancelled").foregroundStyle(.secondary)
        }
    }

    private static func label(for stage: String) -> String {
        switch stage {
        case "starting": return "Starting…"
        case "decode": return "Decoding audio"
        case "modelDownload": return "Preparing models"
        case "diarize": return "Diarizing"
        case "vad": return "Detecting speech"
        case "asr": return "Transcribing"
        case "write": return "Writing"
        default: return stage
        }
    }

    private var progressFraction: Double {
        if case .running(_, let percent) = job.status {
            return max(0, min(1, percent / 100))
        }
        return 0
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
    }
}
