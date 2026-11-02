import SwiftUI

struct JobsView: View {
    @EnvironmentObject private var store: QueueStore
    @EnvironmentObject private var setup: SetupStore
    @EnvironmentObject private var inbox: ExternalOpenInbox
    @State private var showingAddSheet = false
    @State private var sheetInputs: [URL] = []
    @State private var sheetNotice: String?
    @State private var isDropTargeted = false
    @State private var showingRejectionAlert = false
    @State private var rejectionMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.jobs.isEmpty {
                    emptyState
                } else {
                    jobList
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                importMedia(urls)
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .overlay {
                if isDropTargeted {
                    dropTarget
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
                        sheetInputs = []
                        sheetNotice = nil
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add files to the queue")
                }
            }
            .sheet(isPresented: $showingAddSheet, onDismiss: {
                sheetInputs = []
                sheetNotice = nil
                presentPendingImport()
            }) {
                AddJobSheet(
                    inputs: sheetInputs,
                    notice: sheetNotice,
                    onAdd: { inputs, configuration in
                        store.add(inputs: inputs, configuration: configuration)
                    },
                    conflictsFor: { inputs, configuration in
                        store.outputConflicts(inputs: inputs, configuration: configuration)
                    }
                )
            }
            .alert("No supported files", isPresented: $showingRejectionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rejectionMessage)
            }
            .onAppear {
                presentPendingImport()
            }
            .onReceive(inbox.$pending) { pending in
                guard !pending.isEmpty else { return }
                Task { @MainActor in presentPendingImport() }
            }
        }
    }

    private func presentPendingImport() {
        guard !showingAddSheet else { return }
        importMedia(inbox.consume())
    }

    @discardableResult
    private func importMedia(_ urls: [URL]) -> Bool {
        let request = MediaImport.request(for: urls)
        guard !request.accepted.isEmpty else {
            guard !request.rejected.isEmpty else { return false }
            rejectionMessage = "Nothing was added. " + MediaImport.rejectionSummary(for: request.rejected)
            showingRejectionAlert = true
            return false
        }
        sheetInputs = request.accepted
        sheetNotice = request.rejected.isEmpty
            ? nil
            : MediaImport.rejectionSummary(for: request.rejected)
        showingAddSheet = true
        return true
    }

    private var dropTarget: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30))
            Text("Drop to add audio or video files")
                .font(.callout.weight(.medium))
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.9)))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        }
        .padding(12)
        .allowsHitTesting(false)
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
                Button("Retry") { setup.retry() }
                    .controlSize(.small)
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
            Text("Drop audio or video files here, or click + to browse.")
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
