import SwiftUI

struct JobsView: View {
    @EnvironmentObject private var store: QueueStore
    @EnvironmentObject private var setup: SetupStore
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if store.jobs.isEmpty {
                    emptyState
                } else {
                    jobList
                }
            }
            .safeAreaInset(edge: .bottom) {
                if setup.isActive {
                    setupBanner
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add files to the queue")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddJobSheet { inputs, configuration in
                    store.add(inputs: inputs, configuration: configuration)
                }
            }
        }
    }

    private var setupBanner: some View {
        HStack(spacing: 10) {
            switch setup.phase {
            case .downloading(let name, let percent):
                ProgressView(value: percent / 100)
                    .frame(width: 140)
                Text("Downloading required model — \(name) \(Int(percent))%")
                    .font(.callout)
                    .monospacedDigit()
            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.callout)
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bird")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No transcriptions yet")
                .font(.title2)
            Text("Click + to add audio or video files.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jobList: some View {
        List {
            ForEach(store.jobs) { job in
                JobRow(job: job)
                    .contextMenu {
                        if case .done(let output) = job.status {
                            Button("Reveal Output") {
                                NSWorkspace.shared.selectFile(
                                    output,
                                    inFileViewerRootedAtPath:
                                        URL(fileURLWithPath: output).deletingLastPathComponent().path
                                )
                            }
                        }
                        if case .failed = job.status {
                            Button("Retry") { store.retry(job.id) }
                        }
                        Button("Remove", role: .destructive) { store.remove(job.id) }
                    }
            }
        }
        .listStyle(.inset)
    }
}

struct JobRow: View {
    let job: Job

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
                    badge(job.configuration.format == "srt" ? "SRT" : "Markdown")
                    if !job.configuration.speakers.isEmpty {
                        badge(job.configuration.speakers.joined(separator: ", "))
                    }
                    if job.configuration.timed && job.configuration.format == "md" {
                        badge("Timed")
                    }
                    if case .done(let output) = job.status {
                        Text(output)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
