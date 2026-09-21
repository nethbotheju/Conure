import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var setup: SetupStore
    @State private var models: [CLIModelRow] = []
    @State private var downloading: String?
    @State private var downloadProgress: Double = 0
    @State private var installMessage: String?

    private var asrModels: [CLIModelRow] { models.filter { !$0.required } }
    private var requiredModels: [CLIModelRow] { models.filter { $0.required } }

    var body: some View {
        TabView {
            modelsTab
                .tabItem { Label("Models", systemImage: "shippingbox") }
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
        }
        .padding()
        .onAppear(perform: reload)
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
                }
                Text(row.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusControl(row)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusControl(_ row: CLIModelRow) -> some View {
        if downloading == row.id {
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: downloadProgress / 100)
                    .frame(width: 110)
                Text("\(Int(downloadProgress))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else if row.downloaded {
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f MB", row.sizeMB))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !row.required {
                    Button("Remove", role: .destructive) { remove(row) }
                        .controlSize(.small)
                }
            }
        } else {
            Button("Download") { download(row) }
                .controlSize(.small)
        }
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
                Text("The app runs the bundled \(CLI.shared.url.lastPathComponent) engine. Install it on your PATH to use Conure from the terminal.")
                    .font(.callout)
                Button("Install CLI to /usr/local/bin…") { installCLI() }
                if let installMessage {
                    Text(installMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Models Folder") {
                Text("Models are stored in ~/Library/Application Support/Conure/models")
                    .font(.callout)
                    .textSelection(.enabled)
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

    private func download(_ row: CLIModelRow) {
        downloading = row.id
        downloadProgress = 0
        CLI.shared.download(row.id) { event in
            Task { @MainActor in
                if event.type == .progress, let percent = event.percent {
                    downloadProgress = percent
                }
            }
        } onEnd: {
            Task { @MainActor in
                downloading = nil
                reload()
            }
        }
    }

    private func remove(_ row: CLIModelRow) {
        CLI.shared.remove(row.id) {
            Task { @MainActor in
                reload()
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
