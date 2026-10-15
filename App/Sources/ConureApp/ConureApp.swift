import SwiftUI
import AppKit

@main
struct ConureApp: App {
    @StateObject private var modelCoordinator: ModelCoordinator
    @StateObject private var store: QueueStore
    @StateObject private var setup: SetupStore
    @Environment(\.openWindow) private var openWindow

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let coordinator = ModelCoordinator()
        _modelCoordinator = StateObject(wrappedValue: coordinator)
        _store = StateObject(wrappedValue: QueueStore(coordinator: coordinator))
        _setup = StateObject(wrappedValue: SetupStore(coordinator: coordinator))
    }

    var body: some Scene {
        WindowGroup(CLI.shared.isDevApp ? "Conure Dev" : "Conure") {
            JobsView()
                .environmentObject(store)
                .environmentObject(setup)
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
            }
        }

        Window(CLI.shared.isDevApp ? "About Conure Dev" : "About Conure", id: "about") {
            DiagnosticsView()
                .frame(minWidth: 480, minHeight: 440)
        }
        .defaultSize(width: 540, height: 640)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(modelCoordinator)
                .frame(width: 480, height: 440)
        }
    }
}
