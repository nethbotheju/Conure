import AppKit
import Combine
import Sparkle

@MainActor
private final class FixtureDelegate: NSObject, SPUUpdaterDelegate {
    weak var driver: UpdateStore?
    let origin: String
    let root: URL

    init(driver: UpdateStore, root: URL) {
        self.driver = driver
        self.root = root
        let port = try! String(contentsOf: root.appendingPathComponent("port"), encoding: .utf8)
        origin = "http://127.0.0.1:\(port)"
    }

    func feedURLString(for updater: SPUUpdater) -> String? { "\(origin)/appcast.xml" }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try driver?.updater(updater, mayPerform: updateCheck)
    }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        try driver?.updater(updater, shouldProceedWithUpdate: item, updateCheck: updateCheck)
    }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { false }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        request.url = URL(string: "\(origin)/Conure-1.2.3.dmg")!
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            try? Data(String(describing: error as NSError).utf8)
                .write(to: root.appendingPathComponent("cycle-error"), options: .atomic)
        }
        driver?.updater(updater, didFinishUpdateCycleFor: updateCheck, error: error)
    }
}

@MainActor
private final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private let termination = UpdateApplicationDelegate()
    private var observation: AnyCancellable?
    private var fixtureDelegate: FixtureDelegate?
    private var requestedTermination = false
    private var root: URL {
        URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "ConureFixtureRoot") as! String)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        if version == "1.2.3" {
            record("relaunched", version)
            NSApp.terminate(nil)
            return
        }
        let mode = try? String(contentsOf: root.appendingPathComponent("mode"), encoding: .utf8)
        let configuration = UpdateConfiguration(
            version: version, bundleIdentifier: mode == "reject-dev-to-stable" ? "com.conure.app.dev" : "com.conure.app",
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            feedURL: UpdateConfiguration.feedURL, isAppBundle: true,
            requiresSignedFeed: true, verifiesBeforeExtraction: true
        )
        let updates = UpdateStore(configuration: configuration, makeUpdater: { [self] driver in
            record("updater-started", "requested")
            let proxy = FixtureDelegate(driver: driver, root: root)
            fixtureDelegate = proxy
            return SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: proxy)
        })
        termination.updates = updates
        observation = updates.$state.sink { [weak self] state in
            Task { @MainActor in self?.react(to: state) }
        }
        updates.check()
    }

    private func react(to state: UpdateStore.State) {
        record("last-state", String(describing: state))
        guard let updates = termination.updates else { return }
        let mode = try? String(contentsOf: root.appendingPathComponent("mode"), encoding: .utf8)
        if !requestedTermination && ((mode == "cancel-early" && state == .checking)
                                    || (mode == "cancel-extract" && state == .preparing)) {
            requestedTermination = true
            record("cancelled", "requested")
            NSApp.terminate(nil)
            return
        }
        switch state {
        case .available:
            record("offered", updates.offer?.version ?? "missing")
            updates.download()
        case .ready:
            record("ready", "verified")
            if mode?.hasPrefix("reject-") == true {
                updates.cancel()
                record("failed", "Invalid update reached the ready-to-install stage")
                NSApp.terminate(nil)
            } else if mode == "cancel" {
                updates.cancel()
                record("cancelled", "requested")
                NSApp.terminate(nil)
            } else {
                updates.install()
            }
        case .failed(let message), .unsupported(let message):
            record(mode?.hasPrefix("reject-") == true ? "rejected" : "failed", message)
            NSApp.terminate(nil)
        default: break
        }
    }

    private func record(_ name: String, _ value: String) {
        try? Data(value.utf8).write(to: root.appendingPathComponent(name), options: .atomic)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        termination.applicationShouldTerminate(sender)
    }
}

@main
private struct UpdateHarness {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let delegate = HarnessDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
