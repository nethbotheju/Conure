import SwiftUI
import AppKit

struct UploadView: View {
    @EnvironmentObject private var store: QueueStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var draft: UploadDraft
    @EnvironmentObject private var inventory: ModelInventory

    @AppStorage("conure.upload.model") private var modelId = "parakeet"
    @AppStorage("conure.upload.speakerCount") private var speakerCountRaw = 0

    @State private var isTargeted = false

    private var asrModels: [CLIModelRow] {
        inventory.rows.filter { $0.kind == "asr" }
    }

    private var downloadedModels: [CLIModelRow] {
        asrModels.filter(\.downloaded)
    }

    private var downloadedIDs: [String] {
        downloadedModels.map(\.id)
    }

    private var loadingModels: Bool {
        inventory.isLoading && inventory.rows.isEmpty
    }

    private var speakerCount: Int? {
        speakerCountRaw == 0 ? nil : speakerCountRaw
    }

    private var hasUsableModel: Bool {
        downloadedModels.contains { $0.id == modelId }
    }

    var body: some View {
        Form {
            Section {
                dropArea
            }

            if let notice = draft.notice {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(notice)
                            .font(.callout)
                    }
                }
            }

            if !draft.files.isEmpty {
                Section("Files") {
                    ForEach(draft.files, id: \.self) { url in
                        fileRow(url)
                    }
                    Button("Clear All", role: .destructive) {
                        draft.clear()
                    }
                }
            }

            Section("Options") {
                Picker("Model", selection: $modelId) {
                    ForEach(downloadedModels) { row in
                        Text("\(row.name) — \(ModelCatalog.engineName(row.engine))")
                            .tag(row.id)
                    }
                }
                .disabled(downloadedModels.isEmpty)

                if modelId == "parakeet-v3-multilingual" {
                    TextField("Language hint (optional, e.g. fr)", text: $draft.language)
                    Text("Leave empty to auto-detect. Hints filter by script; Japanese auto-detects without a hint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Speaker labels", selection: Binding(
                    get: { speakerCount },
                    set: { speakerCountRaw = $0 ?? 0 }
                )) {
                    Text("None").tag(Int?.none)
                    ForEach(1...4, id: \.self) { count in
                        Text("\(count)").tag(Int?.some(count))
                    }
                }
                .pickerStyle(.segmented)

                Text("Optional. Low-evidence voices merge into the nearest speaker. Name speakers later in the Library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if loadingModels {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading models…").foregroundStyle(.secondary)
                    }
                } else if downloadedModels.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.orange)
                        Text("No transcription model is downloaded yet.")
                        Button("Open Settings") {
                            navigation.openSettings(.models)
                        }
                        .controlSize(.small)
                    }
                    .font(.callout)
                } else if !hasUsableModel {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.orange)
                        Text("The selected model is no longer available.")
                        Button("Choose Another") {
                            modelId = downloadedModels.first?.id ?? modelId
                        }
                        .controlSize(.small)
                    }
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle("Upload")
        .onAppear {
            inventory.loadIfNeeded()
            consumePending()
        }
        .onChange(of: downloadedIDs) { _, ids in
            guard !ids.isEmpty, !ids.contains(modelId) else { return }
            if let preferred = downloadedModels.first(where: { $0.isDefault }) ?? downloadedModels.first {
                modelId = preferred.id
            }
        }
        .onChange(of: navigation.pendingUploads) { _, _ in
            consumePending()
        }
        .onChange(of: navigation.pendingNotice) { _, _ in
            consumePending()
        }
    }

    private var dropArea: some View {
        VStack(spacing: 8) {
            Image(systemName: navigation.destination == .upload ? "square.and.arrow.down" : "waveform")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("Drop audio or video files here")
                .font(.headline)
            Text("Transcribed on this Mac — nothing leaves your device.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MediaImport.formatDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("Choose Files…") { pickFiles() }
                .controlSize(.large)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [7, 5])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            draft.addFiles(urls)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(
                draft.files.isEmpty
                    ? "No files selected"
                    : "\(draft.files.count) file\(draft.files.count == 1 ? "" : "s") selected",
                systemImage: draft.files.isEmpty ? "tray" : "doc.on.doc"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                addToQueue()
            } label: {
                Text(addButtonTitle)
                    .frame(minWidth: 190)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(draft.files.isEmpty || !hasUsableModel)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var addButtonTitle: String {
        guard !draft.files.isEmpty else { return "Add to Queue" }
        return draft.files.count == 1 ? "Add 1 File to Queue" : "Add \(draft.files.count) Files to Queue"
    }

    private func fileRow(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                draft.remove(url)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove from this upload")
        }
    }

    private func consumePending() {
        draft.applyPending(navigation.consumeUploads())
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = MediaImport.supportedContentTypes
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            draft.addFiles(panel.urls)
        }
    }

    private func addToQueue() {
        guard !draft.files.isEmpty else { return }
        let configuration = JobConfiguration(
            model: modelId,
            language: modelId == "parakeet-v3-multilingual" ? (draft.language.isEmpty ? nil : draft.language) : nil,
            speakerCount: speakerCount
        )
        store.add(inputs: draft.files, configuration: configuration)
        draft.clear()
        navigation.go(to: .queue)
    }
}
