import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var updates: UpdateStore
    @Environment(\.openURL) private var openURL

    private var manualMode: Bool {
        updates.configuration.disabledReason != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Text("Installed app: \(updates.configuration.version ?? "Unavailable")")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                result

                HStack {
                    Link("All Official Releases", destination: UpdateConfiguration.releasesURL)
                        .font(.callout)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .textSelection(.enabled)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Software Updates")
                .font(.title2.bold())
            Spacer()
            Button {
                updates.check()
            } label: {
                Label("Check for Updates", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!updates.canRequestCheck)
        }
    }

    @ViewBuilder
    private var result: some View {
        if manualMode {
            manualResult
        } else {
            sparkleResult
        }
    }

    @ViewBuilder
    private var manualResult: some View {
        switch updates.manualState {
        case .idle:
            prompt("Check for a newer stable release.")
        case .checking:
            ProgressView("Checking for updates…")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .update(let release):
            availableCard(
                title: "Conure \(release.version) is available.",
                notes: release.notes,
                releaseURL: release.url,
                downloadURL: release.downloadURL ?? release.url,
                manual: true
            )
        case .unknown(let release):
            availableCard(
                title: "Latest stable release: Conure \(release.version).",
                notes: release.notes,
                releaseURL: release.url,
                downloadURL: release.downloadURL ?? release.url,
                manual: true,
                subtitle: "This build can’t compare versions automatically."
            )
        case .current(let release):
            upToDate(latest: release.version)
        case .failed(let message):
            failure(message)
        }
    }

    @ViewBuilder
    private var sparkleResult: some View {
        switch updates.state {
        case .idle:
            prompt("Check for a newer stable release.")
        case .checking:
            ProgressView("Checking for updates…")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .current:
            upToDate(latest: nil)
        case .available:
            if let offer = updates.offer {
                availableCard(
                    title: "Conure \(offer.version) is available.",
                    notes: offer.notes,
                    releaseURL: offer.releaseURL,
                    downloadURL: nil,
                    manual: false
                )
            } else {
                upToDate(latest: nil)
            }
        case .downloading:
            downloadProgress
        case .preparing:
            VStack(alignment: .leading, spacing: 10) {
                ProgressView("Verifying and preparing update…", value: updates.extractionProgress)
                Button("Cancel") { updates.cancel() }
            }
        case .ready:
            readyCard
        case .installing:
            ProgressView("Quitting to install and reopen Conure…")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            failure(message)
        case .unsupported:
            prompt("Check for a newer stable release.")
        }
    }

    private func prompt(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func upToDate(latest: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You’re up to date.")
                .font(.title3.weight(.semibold))
            if let latest {
                Text("Latest stable release: \(latest).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn’t check for updates.")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.orange)
            Button("Try Again") { updates.check() }
                .disabled(!updates.canRequestCheck)
        }
    }

    private func availableCard(
        title: String,
        notes: String?,
        releaseURL: URL,
        downloadURL: URL?,
        manual: Bool,
        subtitle: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Link("View Release", destination: releaseURL)
                    .font(.callout)
            }

            notesBox(notes)

            HStack(alignment: .center, spacing: 12) {
                if manual {
                    Text("Downloads the official DMG. Installation stays manual in this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Download & Install") {
                    if manual {
                        openURL(downloadURL ?? releaseURL)
                    } else {
                        updates.download()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }

    private func notesBox(_ notes: String?) -> some View {
        MarkdownNotesView(text: notes ?? "")
            .frame(height: 190)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            if updates.expectedBytes > 0 {
                ProgressView(
                    "Downloading update…",
                    value: min(Double(updates.receivedBytes) / Double(updates.expectedBytes), 1)
                )
            } else {
                ProgressView("Downloading update…")
            }
            HStack {
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(clamping: updates.receivedBytes), countStyle: .file)) received")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { updates.cancel() }
            }
        }
    }

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your update is ready to install.")
                .font(.title3.weight(.semibold))
            Text("Quit Conure to install and reopen it. Finish or cancel pending jobs first; the queue is not saved across restarts.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let message = updates.installBlockedMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel Update") { updates.cancel() }
                Button("Quit & Install") { updates.install() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }
}
