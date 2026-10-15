import SwiftUI
import AppKit

struct DiagnosticsView: View {
    @State private var bundledCLIVersion: String?
    @State private var activeCLIVersion: String?
    @State private var models: [CLIModelRow]?
    @State private var loading = true
    @State private var copied = false

    private var report: DiagnosticsReport {
        DiagnosticsReport(
            appVersion: bundleValue("CFBundleShortVersionString"),
            bundledCLIVersion: bundledCLIVersion,
            activeCLIVersion: activeCLIVersion,
            usesExternalCLI: CLI.shared.url != CLI.shared.bundledURL,
            sourceCommit: bundleValue("ConureSourceCommit"),
            buildURL: bundleValue("ConureBuildURL"),
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            chip: DiagnosticsSystem.chip,
            models: models
        )
    }

    var body: some View {
        Form {
            Section("Versions") {
                LabeledContent("App", value: report.appVersion)
                LabeledContent("Bundled CLI", value: report.bundledCLIVersion)
                Text(report.versionStatus)
                    .foregroundStyle(report.versionsMismatch == true ? Color.orange : Color.secondary)
                if let activeVersion = report.activeCLIVersion {
                    LabeledContent("Active CLI (external / overridden)", value: activeVersion)
                }
            }
            Section("Build provenance") {
                LabeledContent("Source commit") {
                    Text(report.sourceCommit).font(.system(.caption, design: .monospaced))
                }
                LabeledContent("Source ref / tag", value: bundleValue("ConureSourceRef") ?? "Unavailable (unpackaged build)")
                if let buildURL = report.buildURL, let url = URL(string: buildURL) {
                    Link("View GitHub Actions build", destination: url)
                }
                Text("Compare this commit and build run with the artifact’s GitHub attestation. Build metadata alone does not authenticate a download.")
                    .font(.caption)
            }
            Section("System") {
                LabeledContent("macOS", value: report.macOSVersion)
                LabeledContent("Chip", value: report.chip)
            }
            Section("Models (active CLI)") {
                if let models = report.models {
                    ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                        VStack(alignment: .leading) {
                            Text(model.id).font(.system(.callout, design: .monospaced))
                            Text("\(model.engine) · \(model.state)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if models.isEmpty { Text("No models reported.") }
                } else {
                    Text(loading ? "Loading…" : "Model inventory unavailable. Try Refresh.")
                }
            }
            Section {
                HStack {
                    Button(copied ? "Copied Diagnostics" : "Copy Diagnostics") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        copied = pasteboard.setString(report.text, forType: .string)
                    }
                    .disabled(loading)
                    Button("Refresh") { Task { await reload() } }
                        .disabled(loading)
                    if loading { ProgressView().controlSize(.small) }
                }
                Text("Copies only versions, build identity, macOS, chip, and model IDs / engines / readiness. No transcripts, recording names, job details, file paths, or environment variables. Source refs are not copied.")
                    .font(.caption)
            }
            Section("Project and licenses") {
                Link("GitHub Issues", destination: URL(string: "https://github.com/nethbotheju/Conure/issues")!)
                Link("Releases", destination: URL(string: "https://github.com/nethbotheju/Conure/releases")!)
                Link("Source code", destination: URL(string: "https://github.com/nethbotheju/Conure")!)
                Link("Conure license", destination: URL(string: "https://github.com/nethbotheju/Conure/blob/main/LICENSE")!)
                Link("FluidAudio — Apache-2.0", destination: URL(string: "https://github.com/FluidInference/FluidAudio/blob/v0.17.4/LICENSE")!)
                Link("speech-swift — Apache-2.0", destination: URL(string: "https://github.com/soniqo/speech-swift/blob/main/LICENSE")!)
                Text("Model licenses are linked from Settings → Models; additional credits are in Settings → Credits.")
                    .font(.caption)
            }
        }
        .textSelection(.enabled)
        .formStyle(.grouped)
        .task { await reload() }
    }

    private func bundleValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private func reload() async {
        loading = true
        copied = false
        bundledCLIVersion = await CLI.shared.version(at: CLI.shared.bundledURL)
        activeCLIVersion = CLI.shared.url == CLI.shared.bundledURL
            ? bundledCLIVersion : await CLI.shared.version(at: CLI.shared.url)
        models = await CLI.shared.modelInventory()
        loading = false
    }
}
