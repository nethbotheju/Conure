import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddJobSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: ([URL], JobConfiguration) -> Void
    let conflictsFor: ([URL], JobConfiguration) -> [String]

    @State private var inputs: [URL] = []
    @State private var modelId: String = "parakeet"
    @State private var language = ""
    @State private var speakersEnabled = true
    @State private var speakerNames: [String] = ["", ""]
    @State private var format = "md"
    @State private var timed = false
    @State private var outputDirectory: URL?
    @State private var asrModels: [CLIModelRow] = []
    @State private var anyModelDownloaded = true
    @State private var pendingAdd: (inputs: [URL], configuration: JobConfiguration)?
    @State private var conflicts: [String] = []
    @State private var showingConflictAlert = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Files") {
                    filePicker
                    if !inputs.isEmpty {
                        Text("\(inputs.count) file(s) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Model") {
                    Picker("Model", selection: $modelId) {
                        ForEach(asrModels.filter(\.downloaded)) { row in
                            Text("\(row.name) · \(row.engine == "fluidAudio" ? "FluidAudio" : "speech-swift")").tag(row.id)
                        }
                    }
                    if modelId == "parakeet-v3-multilingual" {
                        TextField("Language hint (optional, e.g. fr)", text: $language)
                        Text("Leave empty to auto-detect. Hints filter by script; Japanese auto-detects without a hint.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !anyModelDownloaded {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text("No model downloaded — download one in Settings (⌘,)")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                Section("Speakers") {
                    Toggle("Enable speaker labels", isOn: $speakersEnabled)
                    if speakersEnabled {
                        ForEach(speakerNames.indices, id: \.self) { index in
                            HStack {
                                TextField("Speaker \(index + 1)", text: $speakerNames[index])
                                if speakerNames.count > 1 {
                                    Button {
                                        speakerNames.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        if speakerNames.count < 4 {
                            Button {
                                speakerNames.append("")
                            } label: {
                                Label("Add speaker", systemImage: "plus")
                            }
                        }
                    }
                }

                Section("Output") {
                    Picker("Format", selection: $format) {
                        Text("Markdown").tag("md")
                        Text("SRT").tag("srt")
                    }
                    .onChange(of: format) { _, newValue in
                        if newValue == "srt" { timed = false }
                    }
                    if format == "md" {
                        Toggle("Include timestamps", isOn: $timed)
                    }
                    HStack {
                        Text("Output folder")
                        Spacer()
                        Button(outputDirectory?.lastPathComponent ?? "Same as input") {
                            pickOutputFolder()
                        }
                        .foregroundStyle(.secondary)
                        if outputDirectory != nil {
                            Button {
                                outputDirectory = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add to Queue") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(inputs.isEmpty || !canAdd)
            }
            .padding()
        }
        .frame(width: 480, height: 600)
        .onAppear(perform: loadModels)
        .alert("Existing transcripts found", isPresented: $showingConflictAlert) {
            Button("Replace", role: .destructive) { commit(.replace) }
            Button("Keep Both") { commit(.unique) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(conflictMessage)
        }
    }

    private var canAdd: Bool {
        !speakersEnabled || validSpeakers.count >= 1
    }

    private var validSpeakers: [String] {
        speakersEnabled
            ? speakerNames.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            : []
    }

    private var filePicker: some View {
        HStack {
            Image(systemName: "waveform")
            Text(inputs.isEmpty ? "Choose audio or video files…" : inputs.map(\.lastPathComponent).joined(separator: ", "))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(inputs.isEmpty ? .secondary : .primary)
            Spacer()
            Button("Browse…") { pickFiles() }
        }
        .contentShape(Rectangle())
        .onTapGesture { pickFiles() }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType.audio, UTType.movie, UTType.audiovisualContent,
        ]
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            inputs = panel.urls
        }
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    private func loadModels() {
        CLI.shared.models { rows in
            Task { @MainActor in
                asrModels = rows.filter { $0.kind == "asr" }
                anyModelDownloaded = asrModels.contains { $0.downloaded }
                let downloaded = asrModels.filter(\.downloaded)
                if let preferred = downloaded.first(where: { $0.isDefault }) {
                    modelId = preferred.id
                } else if let fallback = downloaded.first {
                    modelId = fallback.id
                }
            }
        }
    }

    private func add() {
        let configuration = JobConfiguration(
            model: modelId,
            language: modelId == "parakeet-v3-multilingual" ? (language.isEmpty ? nil : language) : nil,
            speakers: validSpeakers,
            format: format,
            timed: timed,
            outputDirectory: outputDirectory,
            collision: nil
        )
        let found = conflictsFor(inputs, configuration)
        if found.isEmpty {
            onAdd(inputs, configuration)
            dismiss()
        } else {
            conflicts = found
            pendingAdd = (inputs, configuration)
            showingConflictAlert = true
        }
    }

    private func commit(_ policy: CollisionPolicy) {
        guard var pending = pendingAdd else { return }
        pending.configuration.collision = policy
        onAdd(pending.inputs, pending.configuration)
        pendingAdd = nil
        dismiss()
    }

    private var conflictMessage: String {
        let preview = conflicts.prefix(3).joined(separator: ", ")
        let suffix = conflicts.count > 3 ? " and \(conflicts.count - 3) more" : ""
        return "These transcripts already exist or collide: \(preview)\(suffix). Replace overwrites them; Keep Both writes new copies with numbered names."
    }
}
