import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateStore: NSObject, ObservableObject, SPUUserDriver, SPUUpdaterDelegate {
    enum State: Equatable {
        case idle, checking, available, downloading, preparing, ready, installing, current
        case failed(String)
        case unsupported(String)
    }

    @Published private(set) var state: State
    @Published private(set) var offer: UpdateOffer?
    @Published private(set) var receivedBytes: UInt64 = 0
    @Published private(set) var expectedBytes: UInt64 = 0
    @Published private(set) var extractionProgress = 0.0
    @Published private(set) var installBlockedMessage: String?
    let configuration: UpdateConfiguration
    private let canQuitForInstall: () -> Bool
    private let makeUpdater: (UpdateStore) -> SPUUpdater
    private var updater: SPUUpdater?
    private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var cancellation: (() -> Void)?
    private var retryTermination: (() -> Void)?
    private var cancellationRequested = false
    private var terminationReply: (() -> Void)?

    init(configuration: UpdateConfiguration = UpdateConfiguration(bundle: .main),
         makeUpdater: @escaping (UpdateStore) -> SPUUpdater = {
             SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: $0, delegate: $0)
         },
         canQuitForInstall: @escaping () -> Bool = { true }) {
        self.configuration = configuration
        self.makeUpdater = makeUpdater
        self.canQuitForInstall = canQuitForInstall
        state = configuration.disabledReason.map(State.unsupported) ?? .idle
        super.init()
    }

    var isInstalling: Bool { state == .installing }
    var canCheck: Bool {
        guard configuration.disabledReason == nil else { return false }
        switch state {
        case .idle, .current, .failed: return updater?.canCheckForUpdates ?? true
        default: return false
        }
    }

    func check() {
        guard canCheck else { return }
        do {
            if updater == nil {
                let updater = makeUpdater(self)
                try updater.start()
                self.updater = updater
            }
            cancellationRequested = false
            state = .checking
            updater?.checkForUpdates()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func download() {
        guard state == .available, let reply = updateReply else { return }
        updateReply = nil
        state = .downloading
        reply(.install)
    }

    func install() {
        guard state == .ready || state == .installing else { return }
        guard canQuitForInstall() else {
            installBlockedMessage = "Finish or cancel all queued/running transcriptions and model operations before installing. Your queue is not saved across a restart."
            return
        }
        installBlockedMessage = nil
        if let reply = installReply {
            installReply = nil
            state = .installing
            reply(.install)
        } else {
            retryTermination?()
        }
    }

    func cancel() {
        guard !isInstalling else { return }
        cancellationRequested = true
        installBlockedMessage = nil
        if let reply = installReply {
            installReply = nil
            reply(.skip)
        } else if let reply = updateReply {
            updateReply = nil
            reply(.dismiss)
        } else if let cancel = cancellation {
            cancellation = nil
            cancel()
        }
    }

    func prepareForTermination() -> NSApplication.TerminateReply {
        guard !isInstalling, updater?.sessionInProgress == true else { return .terminateNow }
        terminationReply = { NSApp.terminate(nil) }
        cancel()
        return .terminateCancel
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        if cancellationRequested {
            cancellation()
            return
        }
        self.cancellation = cancellation
        offer = nil
        state = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !appcastItem.isInformationOnlyUpdate, state.stage != .installing else {
            reply(.skip)
            self.state = .failed("This update cannot be installed in-app. Please check the official Releases page.")
            return
        }
        present(UpdateOffer(version: appcastItem.versionString, notes: appcastItem.itemDescription), reply: reply)
    }

    func present(_ offer: UpdateOffer, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        if cancellationRequested {
            reply(.dismiss)
            return
        }
        self.offer = offer
        updateReply = reply
        state = .available
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        if reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue
            || reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue {
            state = .current
        } else {
            state = .failed(error.localizedDescription)
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state = .failed("\(error.localizedDescription)\n\((error as NSError).localizedRecoverySuggestion ?? "Please try again later.")")
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        if cancellationRequested {
            cancellation()
            return
        }
        receivedBytes = 0
        expectedBytes = 0
        self.cancellation = cancellation
        state = .downloading
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let (sum, overflow) = receivedBytes.addingReportingOverflow(length)
        receivedBytes = overflow ? UInt64.max : sum
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        extractionProgress = 0
        state = .preparing
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        extractionProgress = progress.isFinite ? min(1, max(0, progress)) : 0
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if cancellationRequested {
            reply(.skip)
        } else {
            installReply = reply
            state = .ready
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
        state = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        updateReply = nil
        installReply = nil
        cancellation = nil
        retryTermination = nil
        switch state {
        case .failed, .current, .unsupported: break
        default: state = .idle
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard configuration.disabledReason == nil, updateCheck == .updates else {
            throw NSError(domain: "ConureUpdates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Only user-requested stable update checks are allowed."])
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? { UpdateConfiguration.feedURL }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { [] }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem,
                 updateCheck: SPUUpdateCheck) throws {
        guard UpdatePolicy.accepts(version: item.versionString, installedVersion: configuration.version ?? "",
                                   url: item.fileURL, channel: item.channel, installationType: item.installationType,
                                   feedIsSigned: item.signingValidationStatus == .succeeded) else {
            throw NSError(domain: "ConureUpdates", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The update is not a signed stable Conure release from the official repository."])
        }
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { false }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        cancellationRequested = false
        objectWillChange.send()
        if let reply = terminationReply {
            terminationReply = nil
            Task { @MainActor in reply() }
        }
    }
}

@MainActor
final class UpdateApplicationDelegate: NSObject, NSApplicationDelegate {
    var updates: UpdateStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updates?.prepareForTermination() ?? .terminateNow
    }
}
