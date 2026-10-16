import AppKit
import Sparkle
import XCTest
@testable import ConureApp

final class UpdateTests: XCTestCase {
    func testStableSemanticVersionOrdering() throws {
        let ordered = ["0.0.0", "0.1.0", "0.2.9", "0.2.10", "0.10.0", "1.0.0", "2.0.0", "10.0.0",
                       "999999999999999999999999999999.0.0", "1000000000000000000000000000000.0.0"]
        for (left, right) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(try XCTUnwrap(StableVersion(left)), try XCTUnwrap(StableVersion(right)))
        }
        XCTAssertEqual(StableVersion("1.2.3+build.01"), StableVersion("1.2.3+other-build"))
        XCTAssertEqual(StableVersion("1.2.3"), StableVersion("1.2.3"))
    }

    func testInvalidAndPrereleaseVersionsAreNotStable() {
        for value in ["", "v1.2.3", "1", "1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03", "-1.2.3",
                      "1.2.3-beta", "1.2.3-dev+build", "x.y.z-dev", "1.2.3+", "1.2.3+a..b", "1.2.3+a+b",
                      "1.2.3+space here", " 1.2.3", "1.2.3\n", "١.2.3"] {
            XCTAssertNil(StableVersion(value), value)
        }
    }

    func testOnlySignedNewerStableOfficialApplicationUpdatesAreAccepted() {
        XCTAssertTrue(accepts())
        XCTAssertFalse(accepts(version: "0.9.0"))
        XCTAssertFalse(accepts(version: "1.0.0"))
        XCTAssertFalse(accepts(version: "2.0.0-beta"))
        XCTAssertFalse(accepts(version: "v2.0.0"))
        XCTAssertFalse(accepts(channel: "beta"))
        XCTAssertFalse(accepts(installationType: "package"))
        XCTAssertFalse(accepts(feedIsSigned: false))
        for url in ["https://example.com/app.dmg", "file:///tmp/app.dmg",
                    "https://github.com/other/Conure/releases/download/v2.0.0/Conure-2.0.0.dmg",
                    "http://github.com/nethbotheju/Conure/releases/download/v2.0.0/Conure-2.0.0.dmg",
                    "https://github.com/nethbotheju/Conure/releases/download/v2.0.0/Conure-Dev-2.0.0.dmg",
                    "https://github.com/nethbotheju/Conure/releases/download/v1.0.0/Conure-2.0.0.dmg",
                    "https://github.com/nethbotheju/Conure/releases/download/v2.0.0/Conure-2.0.0.dmg?x=1"] {
            XCTAssertFalse(accepts(url: url), url)
        }
    }

    func testConfigurationFailsClosed() {
        XCTAssertNil(configuration().disabledReason)
        XCTAssertNotNil(configuration(key: nil).disabledReason)
        XCTAssertNotNil(configuration(key: "not-a-key").disabledReason)
        XCTAssertNotNil(configuration(feed: "https://example.com/feed.xml").disabledReason)
        XCTAssertNotNil(configuration(signedFeed: false).disabledReason)
        XCTAssertNotNil(configuration(verifyArchive: false).disabledReason)
        XCTAssertNotNil(configuration(isApp: false).disabledReason)
        XCTAssertNotNil(configuration(identifier: "com.example.app").disabledReason)
    }

    @MainActor
    func testDevelopmentAndUnknownVersionsNeverStartUpdater() {
        for config in [configuration(identifier: "com.conure.app.dev"), configuration(version: nil),
                       configuration(version: "0.1.0-dev"), configuration(isApp: false), configuration(key: nil)] {
            let store = UpdateStore(configuration: config)
            XCTAssertFalse(store.canCheck)
            let initial = store.state
            store.check()
            XCTAssertEqual(store.state, initial)
            guard case .unsupported = store.state else { return XCTFail("Expected unsupported build") }
        }
    }

    @MainActor
    func testDownloadAndInstallRequireSeparateExplicitActions() {
        let store = UpdateStore(configuration: configuration())
        var downloads: [SPUUserUpdateChoice] = []
        var installs: [SPUUserUpdateChoice] = []
        store.present(UpdateOffer(version: "2.0.0", notes: "Fixes")) { downloads.append($0) }
        XCTAssertEqual(store.state, .available)
        XCTAssertTrue(downloads.isEmpty)
        XCTAssertFalse(store.canCheck)
        store.download()
        store.download()
        XCTAssertEqual(downloads, [.install])
        XCTAssertEqual(store.state, .downloading)
        store.showDownloadDidStartExtractingUpdate()
        XCTAssertEqual(store.state, .preparing)
        store.showReady(toInstallAndRelaunch: { installs.append($0) })
        XCTAssertEqual(store.state, .ready)
        XCTAssertTrue(installs.isEmpty)
        store.install()
        store.install()
        XCTAssertEqual(installs, [.install])
        XCTAssertTrue(store.isInstalling)
    }

    @MainActor
    func testBusyWorkBlocksInstallWithoutDiscardingDownloadedUpdate() {
        var busy = true
        let store = UpdateStore(configuration: configuration(), canQuitForInstall: { !busy })
        var choices: [SPUUserUpdateChoice] = []
        store.showReady(toInstallAndRelaunch: { choices.append($0) })
        store.install()
        XCTAssertEqual(store.state, .ready)
        XCTAssertNotNil(store.installBlockedMessage)
        XCTAssertTrue(choices.isEmpty)
        busy = false
        store.install()
        XCTAssertEqual(choices, [.install])
        XCTAssertNil(store.installBlockedMessage)
    }

    @MainActor
    func testCancelReadyUpdateCancelsInstallationRatherThanDeferringUntilQuit() {
        let store = UpdateStore(configuration: configuration())
        var choices: [SPUUserUpdateChoice] = []
        store.showReady(toInstallAndRelaunch: { choices.append($0) })
        store.cancel()
        store.cancel()
        XCTAssertEqual(choices, [.skip])
        store.dismissUpdateInstallation()
        XCTAssertEqual(store.state, .idle)
    }

    @MainActor
    func testCancelDuringExtractionWaitsForSafeCancellationPoint() {
        let store = UpdateStore(configuration: configuration())
        var choices: [SPUUserUpdateChoice] = []
        store.showDownloadDidStartExtractingUpdate()
        store.cancel()
        store.showReady(toInstallAndRelaunch: { choices.append($0) })
        XCTAssertEqual(choices, [.skip])
        store.dismissUpdateInstallation()
        XCTAssertEqual(store.state, .idle)
    }

    @MainActor
    func testCheckingAndDownloadCancellationHandlersRunOnce() {
        let store = UpdateStore(configuration: configuration())
        var cancellations = 0
        store.showUserInitiatedUpdateCheck { cancellations += 1 }
        XCTAssertEqual(store.state, .checking)
        store.cancel()
        store.cancel()
        XCTAssertEqual(cancellations, 1)
        store.showDownloadInitiated { cancellations += 1 }
        store.cancel()
        store.cancel()
        XCTAssertEqual(cancellations, 2)
        store.dismissUpdateInstallation()
        XCTAssertTrue(store.canCheck)
    }

    @MainActor
    func testCancellationBeforeSparkleCheckCallbackIsNotLost() {
        let store = UpdateStore(configuration: configuration())
        var cancellations = 0
        store.cancel()
        store.showUserInitiatedUpdateCheck { cancellations += 1 }
        XCTAssertEqual(cancellations, 1)
        var choices: [SPUUserUpdateChoice] = []
        store.present(UpdateOffer(version: "2.0.0", notes: nil)) { choices.append($0) }
        XCTAssertEqual(choices, [.dismiss])
        XCTAssertNil(store.offer)
    }

    @MainActor
    func testCancellationBetweenDownloadChoiceAndCallbackIsNotLost() {
        let store = UpdateStore(configuration: configuration())
        store.present(UpdateOffer(version: "2.0.0", notes: nil), reply: { _ in })
        store.download()
        store.cancel()
        var cancellations = 0
        store.showDownloadInitiated { cancellations += 1 }
        XCTAssertEqual(cancellations, 1)
        var choices: [SPUUserUpdateChoice] = []
        store.showReady(toInstallAndRelaunch: { choices.append($0) })
        XCTAssertEqual(choices, [.skip])
    }

    @MainActor
    func testDownloadProgressHandlesUnknownLengthAndOverflow() {
        let store = UpdateStore(configuration: configuration())
        store.showDownloadInitiated(cancellation: {})
        XCTAssertEqual(store.expectedBytes, 0)
        store.showDownloadDidReceiveExpectedContentLength(100)
        store.showDownloadDidReceiveData(ofLength: 20)
        store.showDownloadDidReceiveData(ofLength: 30)
        XCTAssertEqual(store.expectedBytes, 100)
        XCTAssertEqual(store.receivedBytes, 50)
        store.showDownloadDidReceiveData(ofLength: .max)
        XCTAssertEqual(store.receivedBytes, .max)
        store.showExtractionReceivedProgress(.nan)
        XCTAssertEqual(store.extractionProgress, 0)
        store.showExtractionReceivedProgress(2)
        XCTAssertEqual(store.extractionProgress, 1)
    }

    @MainActor
    func testOnlyGenuineCurrentVersionStatesSayUpToDate() {
        let store = UpdateStore(configuration: configuration())
        for reason in [SPUNoUpdateFoundReason.onLatestVersion, .onNewerThanLatestVersion] {
            var acknowledged = false
            let error = NSError(domain: SUSparkleErrorDomain, code: 1001,
                                userInfo: [SPUNoUpdateFoundReasonKey: NSNumber(value: reason.rawValue)])
            store.showUpdateNotFoundWithError(error) { acknowledged = true }
            XCTAssertTrue(acknowledged)
            store.dismissUpdateInstallation()
            XCTAssertEqual(store.state, .current)
        }
        let error = NSError(domain: SUSparkleErrorDomain, code: 1001,
                            userInfo: [SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.systemIsTooOld.rawValue),
                                       NSLocalizedDescriptionKey: "Requires newer macOS"])
        store.showUpdateNotFoundWithError(error, acknowledgement: {})
        guard case .failed(let message) = store.state else { return XCTFail("Expected incompatibility message") }
        XCTAssertTrue(message.contains("Requires newer macOS"))
    }

    @MainActor
    func testNetworkAndValidationFailuresStayVisibleAndRetryable() {
        let store = UpdateStore(configuration: configuration())
        for code in [URLError.notConnectedToInternet, .timedOut, .badServerResponse, .cannotParseResponse] {
            var acknowledged = false
            store.showUpdaterError(URLError(code)) { acknowledged = true }
            XCTAssertTrue(acknowledged)
            store.dismissUpdateInstallation()
            guard case .failed = store.state else { return XCTFail("Expected error to remain visible") }
            XCTAssertTrue(store.canCheck)
        }
    }

    private func accepts(version: String = "2.0.0", url: String? = nil, channel: String? = nil,
                         installationType: String = "application", feedIsSigned: Bool = true) -> Bool {
        UpdatePolicy.accepts(version: version, installedVersion: "1.0.0",
                             url: URL(string: url ?? "https://github.com/nethbotheju/Conure/releases/download/v\(version)/Conure-\(version).dmg"),
                             channel: channel, installationType: installationType, feedIsSigned: feedIsSigned)
    }

    private func configuration(version: String? = "1.0.0", identifier: String = "com.conure.app",
                               key: String? = Data(repeating: 7, count: 32).base64EncodedString(),
                               feed: String = UpdateConfiguration.feedURL, isApp: Bool = true,
                               signedFeed: Bool = true, verifyArchive: Bool = true) -> UpdateConfiguration {
        UpdateConfiguration(version: version, bundleIdentifier: identifier, publicKey: key, feedURL: feed,
                            isAppBundle: isApp, requiresSignedFeed: signedFeed, verifiesBeforeExtraction: verifyArchive)
    }
}
