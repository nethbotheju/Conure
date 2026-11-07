import SwiftUI
import AppKit

@main
struct ConureApp: App {
    @StateObject private var modelCoordinator: ModelCoordinator
    @StateObject private var store: QueueStore
    @StateObject private var setup: SetupStore
    @StateObject private var updates: UpdateStore
    @StateObject private var inbox: ExternalOpenInbox
    @StateObject private var library: LibraryStore
    @StateObject private var navigation: AppNavigation
    @StateObject private var draft: UploadDraft
    @StateObject private var inventory: ModelInventory
    @NSApplicationDelegateAdaptor(ConureApplicationDelegate.self) private var appDelegate

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
        let inbox = ExternalOpenInbox()
        _inbox = StateObject(wrappedValue: inbox)
        _library = StateObject(wrappedValue: LibraryStore())
        _navigation = StateObject(wrappedValue: AppNavigation())
        _draft = StateObject(wrappedValue: UploadDraft())
        _inventory = StateObject(wrappedValue: ModelInventory())
        appDelegate.updates = updates
        appDelegate.openInbox = inbox
    }

    var body: some Scene {
        Window(CLI.shared.isDevApp ? "Conure Dev" : "Conure", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(setup)
                .environmentObject(inbox)
                .environmentObject(library)
                .environmentObject(updates)
                .environmentObject(modelCoordinator)
                .environmentObject(navigation)
                .environmentObject(draft)
                .environmentObject(inventory)
                .disabled(updates.isInstalling)
        }
        .defaultSize(width: 860, height: 560)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(CLI.shared.isDevApp ? "About Conure Dev" : "About Conure") {
                    navigation.openSettings(.about)
                }
                Button("Check for Updates…") {
                    navigation.openSettings(.updates)
                    updates.check()
                }
            }
            CommandGroup(after: .newItem) {
                Button("Upload…") {
                    navigation.go(to: .upload)
                }
                .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("Queue") {
                    navigation.go(to: .queue)
                }
                .keyboardShortcut("1", modifiers: .command)
                Button("Library") {
                    navigation.go(to: .library)
                }
                .keyboardShortcut("2", modifiers: .command)
                Button("Settings…") {
                    navigation.openSettings(navigation.settingsTab)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
