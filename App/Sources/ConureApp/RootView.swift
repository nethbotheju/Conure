import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var store: QueueStore
    @EnvironmentObject private var setup: SetupStore
    @EnvironmentObject private var inbox: ExternalOpenInbox
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var inventory: ModelInventory

    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 172, ideal: 190, max: 230)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .dropDestination(for: URL.self) { urls, _ in
            importMedia(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        .safeAreaInset(edge: .bottom) {
            if setup.isActive {
                setupBanner
            }
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            if !navigation.restoredFromDefaults, store.jobs.isEmpty, library.entries.isEmpty {
                navigation.go(to: .upload)
            }
            setup.ensureRequiredModelsIfNeeded()
            inventory.loadIfNeeded()
            if !inbox.pending.isEmpty {
                importMedia(inbox.consume())
            }
        }
        .onChange(of: completedJobCount) { _, _ in
            library.refresh()
        }
        .onReceive(inbox.$pending) { pending in
            guard !pending.isEmpty else { return }
            Task { @MainActor in
                importMedia(inbox.consume())
            }
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.destination {
        case .upload:
            UploadView()
        case .queue:
            JobsView()
        case .library:
            LibraryView()
        case .settings:
            SettingsView()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: selectionBinding) {
                Section("Workspace") {
                    ForEach(SidebarDestination.allCases.filter(\.isWorkspace)) { item in
                        row(for: item)
                            .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)

            List(selection: selectionBinding) {
                if showsModelWarning {
                    Button {
                        navigation.openSettings(.models)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("No transcription model")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Download a transcription model in Settings")
                }

                row(for: .settings)
                    .tag(SidebarDestination.settings)
            }
            .listStyle(.sidebar)
            .frame(height: showsModelWarning ? 72 : 44)
        }
    }

    private func row(for item: SidebarDestination) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(item.title)
                Spacer()
                if item == .queue, activeJobCount > 0 {
                    Text("\(activeJobCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                } else if item == .library, library.entries.count > 0 {
                    Text("\(library.entries.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
        }
    }

    private var selectionBinding: Binding<SidebarDestination?> {
        Binding(
            get: { navigation.destination },
            set: { value in
                guard let value else { return }
                navigation.go(to: value)
            }
        )
    }

    private var completedJobCount: Int {
        store.jobs.reduce(0) { total, job in
            if case .done = job.status { return total + 1 }
            return total
        }
    }

    private var activeJobCount: Int {
        store.jobs.filter { job in
            switch job.status {
            case .queued, .running: return true
            default: return false
            }
        }.count
    }

    private var showsModelWarning: Bool {
        guard !inventory.rows.isEmpty else { return false }
        return !inventory.rows.contains { $0.kind == "asr" && $0.downloaded }
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

    private var dropOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 30))
            Text("Drop to upload audio or video")
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

    @discardableResult
    private func importMedia(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let request = MediaImport.request(for: urls)
        guard !request.accepted.isEmpty || !request.rejected.isEmpty else { return false }
        navigation.beginUpload(
            with: request.accepted,
            notice: request.rejected.isEmpty ? nil : MediaImport.rejectionSummary(for: request.rejected)
        )
        return true
    }
}
