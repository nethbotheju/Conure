import SwiftUI
import AppKit

@main
struct ConureApp: App {
    @StateObject private var modelCoordinator: ModelCoordinator
    @StateObject private var store: QueueStore
    @StateObject private var setup: SetupStore
    @StateObject private var updates: UpdateStore
    @NSApplicationDelegateAdaptor(UpdateApplicationDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let coordinator = ModelCoordinator()
        _modelCoordinator = StateObject(wrappedValue: coordinator)
        let queue = QueueStore(coordinator: coordinator)
        let updates = UpdateStore(canQuitForInstall: {
            !queue.jobs.contains { job in
                switch job.status {
                case .queued, .running: true
                default: false
                }
            } && !coordinator.operations.values.contains { operation in
                switch operation {
                case .downloading, .removing: true
                case .failed: false
                }
            }
        })
        _store = StateObject(wrappedValue: queue)
        _setup = StateObject(wrappedValue: SetupStore(coordinator: coordinator))
        _updates = StateObject(wrappedValue: updates)
        appDelegate.updates = updates
    }

    var body: some Scene {
        WindowGroup(CLI.shared.isDevApp ? "Conure Dev" : "Conure") {
            JobsView()
                .environmentObject(store)
                .environmentObject(setup)
                .disabled(updates.isInstalling)
                .frame(minWidth: 560, minHeight: 380)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    setup.ensureRequiredModelsIfNeeded()
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(CLI.shared.isDevApp ? "About Conure Dev" : "About Conure") {
                    openWindow(id: "about")
                }
                Button("Check for Updates…") {
                    openWindow(id: "updates")
                    updates.check()
                }
            }
        }

        Window(CLI.shared.isDevApp ? "About Conure Dev" : "About Conure", id: "about") {
            DiagnosticsView()
                .frame(minWidth: 480, minHeight: 440)
        }
        .defaultSize(width: 540, height: 640)

        Window("Software Updates", id: "updates") {
            UpdatesView()
                .environmentObject(updates)
                .frame(minWidth: 440, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity, alignment: .topLeading)
        }
        .defaultSize(width: 520, height: 520)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(modelCoordinator)
                .disabled(updates.isInstalling)
                .frame(width: 480, height: 440)
        }
    }
}
