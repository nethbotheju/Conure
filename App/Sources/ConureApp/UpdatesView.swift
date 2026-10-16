import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var updates: UpdateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Software Updates").font(.title2.bold())
                Text("Installed app: \(updates.configuration.version ?? "Unavailable (unpackaged build)")")
                    .foregroundStyle(.secondary)
                status
                if let offer = updates.offer {
                    if let notes = offer.notes, !notes.isEmpty {
                        Text("Release Notes").font(.headline)
                        Text(verbatim: notes)
                    } else {
                        Text("No release notes were provided.").foregroundStyle(.secondary)
                    }
                    Link("View Official Release", destination: offer.releaseURL)
                }
                if let message = updates.installBlockedMessage {
                    Text(message).foregroundStyle(.orange)
                }
                actions
                Text("Updates are downloaded only when you request them. Sparkle verifies the publisher’s signature before extracting the update, then replaces and reopens this app after you choose Quit & Install. Your models and transcripts are not replaced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .textSelection(.enabled)
        .onDisappear { if !updates.isInstalling { updates.cancel() } }
    }

    @ViewBuilder
    private var status: some View {
        switch updates.state {
        case .idle: Text("Check for a newer stable Conure release.")
        case .checking: ProgressView("Checking for updates…")
        case .current: Text("You’re up to date.").font(.headline)
        case .available: Text("Conure \(updates.offer?.version ?? "") is available.").font(.headline)
        case .downloading:
            if updates.expectedBytes > 0 {
                ProgressView("Downloading update…", value: min(Double(updates.receivedBytes) / Double(updates.expectedBytes), 1))
            } else {
                ProgressView("Downloading update…")
            }
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(clamping: updates.receivedBytes), countStyle: .file)) received")
                .font(.caption)
        case .preparing:
            ProgressView("Verifying and preparing update…", value: updates.extractionProgress)
        case .ready:
            Text("Your update is ready to install.").font(.headline)
            Text("Quit Conure, install the verified update, and reopen it. Finish or cancel pending jobs first; the queue is not saved across restarts.")
        case .installing: ProgressView("Quitting to install and reopen Conure…")
        case .failed(let message), .unsupported(let message): Text(message)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack {
            switch updates.state {
            case .available:
                Button("Download Update") { updates.download() }
                    .buttonStyle(.borderedProminent)
                Button("Not Now") { updates.cancel() }
            case .ready:
                Button("Quit & Install") { updates.install() }
                    .buttonStyle(.borderedProminent)
                Button("Cancel Update") { updates.cancel() }
            case .checking, .downloading, .preparing:
                Button("Cancel") { updates.cancel() }
            case .installing:
                Button("Retry Quit & Install") { updates.install() }
            case .idle, .current, .failed:
                Button("Check for Updates…") { updates.check() }
                    .disabled(!updates.canCheck)
            case .unsupported: EmptyView()
            }
            Link("All Official Releases", destination: UpdateConfiguration.releasesURL)
        }
    }
}
