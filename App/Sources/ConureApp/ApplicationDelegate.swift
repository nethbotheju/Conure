import AppKit

@MainActor
final class ConureApplicationDelegate: NSObject, NSApplicationDelegate {
    var updates: UpdateStore?
    var openInbox: ExternalOpenInbox?

    func application(_ application: NSApplication, open urls: [URL]) {
        openInbox?.receive(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updates?.prepareForTermination() ?? .terminateNow
    }
}
