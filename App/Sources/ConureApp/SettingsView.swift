import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var store: QueueStore
    @EnvironmentObject private var modelCoordinator: ModelCoordinator
    @State private var models: [CLIModelRow] = []
    @State private var installMessage: String?
    @State private var pendingRemoval: CLIModelRow?
    @State private var pendingRemovalJobIDs: [UUID] = []
    @State private var mutatingModelIDs: Set<String> = []

    private var asrModels: [CLIModelRow] { models.filter { !$0.required } }
    private var requiredModels: [CLIModelRow] { models.filter { $0.required } }

    var body: some View {
        TabView {
            modelsTab
                .tabItem { Label("Models", systemImage: "shippingbox") }
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            licensesTab
                .tabItem { Label("Credits", systemImage: "text.book.closed") }
        }
        .padding()
        .onAppear(perform: reload)
        .onReceive(modelCoordinator.$operations) { operations in
            let current = Set(operations.compactMap { id, operation -> String? in
                if case .failed = operation { return nil }
                return id
            })
            let finished = mutatingModelIDs.subtracting(current)
            mutatingModelIDs = current
            if !finished.isEmpty { reload() }
        }
        .alert("Model operation failed", isPresented: Binding(
            get: { modelCoordinator.lastErrorMessage != nil },
            set: { if !$0 { modelCoordinator.lastErrorMessage = nil } }
        )) {
            Button("OK") { modelCoordinator.lastErrorMessage = nil }
        } message: {
            Text(modelCoordinator.lastErrorMessage ?? "")
        }
    }

    private var modelsTab: some View {
        List {
            Section("Transcription Model") {
                ForEach(asrModels) { row in
                    modelRow(row)
                }
            }
            Section {
                ForEach(requiredModels) { row in
                    modelRow(row)
                }
            } header: {
                Text("Required Models")
            } footer: {
                Text("Used automatically when transcribing. These cannot be removed.")
                    .font(.caption)
            }
        }
        .listStyle(.inset)
        .overlay {
            if models.isEmpty {
                ProgressView("Loading…")
            }
        }
        .alert("Remove Model?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Remove and Cancel Jobs", role: .destructive) { confirmRemoval() }
            Button("Keep Model", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(removalMessage)
        }
    }

    private var removalMessage: String {
        let count = pendingRemovalJobIDs.count
        let verb = count == 1 ? "queued job uses" : "queued jobs use"
        let object = count == 1 ? "this job" : "these jobs"
        return "\(count) \(verb) \(pendingRemoval?.name ?? "this model"). Removing it will cancel \(object)."
    }

    @ViewBuilder
    private func modelRow(_ row: CLIModelRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).font(.body.weight(.medium))
                    if row.isDefault {
                        tag("Default", .green)
                    }
                    if row.required {
                        tag("Required", .orange)
                    }
                    tag(row.engine == "fluidAudio" ? "FluidAudio" : "speech-swift", .blue)
                }
                Text(row.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = URL(string: "https://huggingface.co/\(row.repo)") {
                    Link("Model details and license", destination: url)
                        .font(.caption2)
                }
            }
            Spacer()
            statusControl(row)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusControl(_ row: CLIModelRow) -> some View {
        switch modelCoordinator.operations[row.id] {
        case .downloading(let percent):
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: percent / 100)
                    .frame(width: 110)
                Text("\(Int(percent))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .removing:
            ProgressView()
                .controlSize(.small)
        case .failed(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                Button("Retry") { modelCoordinator.download(row.id) }
                    .controlSize(.small)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        case nil:
            if row.downloaded {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f MB", row.sizeMB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !row.required {
                        removeControl(row)
                    }
                }
            } else {
                Button("Download") { modelCoordinator.download(row.id) }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func removeControl(_ row: CLIModelRow) -> some View {
        if modelCoordinator.inUse[row.id]?.activeJobs ?? 0 > 0 {
            VStack(alignment: .trailing, spacing: 2) {
                Button("Remove", role: .destructive) {}
                    .controlSize(.small)
                    .disabled(true)
                    .help("In use by a running transcription")
                Text("In use by a running job")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("Remove", role: .destructive) { requestRemoval(row) }
                .controlSize(.small)
        }
    }

    private func requestRemoval(_ row: CLIModelRow) {
        let queued = store.jobs.filter { job in
            guard case .queued = job.status else { return false }
            return job.configuration.resolvedModelID == row.id
        }
        if queued.isEmpty {
            modelCoordinator.remove(row.id)
        } else {
            pendingRemoval = row
            pendingRemovalJobIDs = queued.map(\.id)
        }
    }

    private func confirmRemoval() {
        guard let row = pendingRemoval else { return }
        for jobID in pendingRemovalJobIDs {
            store.cancel(jobID)
        }
        pendingRemoval = nil
        modelCoordinator.remove(row.id)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var generalTab: some View {
        Form {
            Section("Command Line Tool") {
                Text(CLI.shared.isDevApp
                     ? "Conure Dev runs its own bundled CLI. The production CLI on your PATH is not changed."
                     : "The app runs the bundled \(CLI.shared.url.lastPathComponent) engine. Install it on your PATH to use Conure from the terminal.")
                    .font(.callout)
                if !CLI.shared.isDevApp {
                    Button("Install CLI to /usr/local/bin…") { installCLI() }
                }
                if let installMessage {
                    Text(installMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Models Folder") {
                Text("Models are stored in \(CLI.shared.modelsURL.path) (FluidAudio weights in the FluidAudio subfolder).")
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private var licensesTab: some View {
        Form {
            Section("Inference engines") {
                Link("FluidAudio — Apache-2.0", destination: URL(string: "https://github.com/FluidInference/FluidAudio/blob/v0.17.4/LICENSE")!)
                Link("speech-swift — Apache-2.0 (vendored)", destination: URL(string: "https://github.com/soniqo/speech-swift/blob/main/LICENSE")!)
            }
            Section("Model credits") {
                Text("Parakeet models © NVIDIA. See each model’s Hugging Face page for its license and attribution; Unified EN is CC-BY-4.0.")
                Text("Sortformer © NVIDIA. Silero VAD — MIT.")
            }
        }
        .formStyle(.grouped)
    }

    private func reload() {
        CLI.shared.models { rows in
            Task { @MainActor in
                models = rows
            }
        }
    }

    private func installCLI() {
        let target = "/usr/local/bin/conure"
        let source = CLI.shared.url.path
        let script = "mkdir -p /usr/local/bin && ln -sf '\(source)' '\(target)'"
        let appleScript = "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            installMessage = task.terminationStatus == 0
                ? "Installed: \(target) → \(source)"
                : "Installation cancelled"
        } catch {
            installMessage = "Installation failed: \(error.localizedDescription)"
        }
    }
}
