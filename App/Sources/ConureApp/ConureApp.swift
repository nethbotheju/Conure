import SwiftUI
import AppKit

@main
struct ConureApp: App {
    @StateObject private var store = QueueStore()
    @StateObject private var setup = SetupStore()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Conure") {
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

        Settings {
            SettingsView()
                .environmentObject(setup)
                .frame(width: 480, height: 440)
        }
    }
}
