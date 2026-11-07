import Foundation
import XCTest
@testable import ConureApp

final class ManualUpdateCheckerTests: XCTestCase {
    private let releaseURL = "https://github.com/nethbotheju/Conure/releases/tag/v0.2.0"

    func testNewerTagIsAnUpdate() throws {
        let downloadURL = URL(string: "https://github.com/nethbotheju/Conure/releases/download/v0.2.0/Conure-0.2.0.dmg")!
        let result = try ManualUpdateChecker.evaluate(
            tag: "v0.2.0",
            htmlURL: releaseURL,
            notes: "Changes",
            installedVersion: "0.1.0",
            downloadURL: downloadURL
        )
        guard case .update(let release) = result else {
            return XCTFail("Expected update, got \(result)")
        }
        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.url.absoluteString, releaseURL)
        XCTAssertEqual(release.notes, "Changes")
        XCTAssertEqual(release.downloadURL, downloadURL)
    }

    func testEqualOrOlderTagsAreCurrent() throws {
        for tag in ["v0.1.0", "v0.0.9"] {
            let result = try ManualUpdateChecker.evaluate(
                tag: tag,
                htmlURL: releaseURL,
                notes: nil,
                installedVersion: "0.1.0"
            )
            guard case .current(let release) = result else {
                return XCTFail("Expected current for \(tag), got \(result)")
            }
            XCTAssertEqual(release.version, tag.hasPrefix("v") ? String(tag.dropFirst()) : tag)
        }
    }

    func testUnparsableInstalledVersionIsUnknown() throws {
        let result = try ManualUpdateChecker.evaluate(
            tag: "v0.2.0",
            htmlURL: releaseURL,
            notes: nil,
            installedVersion: "0.1.0-dev"
        )
        guard case .unknown(let release) = result else {
            return XCTFail("Expected unknown, got \(result)")
        }
        XCTAssertEqual(release.version, "0.2.0")
    }

    func testInvalidTagsAndURLsAreRejected() {
        XCTAssertThrowsError(try ManualUpdateChecker.evaluate(
            tag: "nightly",
            htmlURL: releaseURL,
            notes: nil,
            installedVersion: "0.1.0"
        ))
        XCTAssertThrowsError(try ManualUpdateChecker.evaluate(
            tag: "v0.2.0",
            htmlURL: "not a url",
            notes: nil,
            installedVersion: "0.1.0"
        ))
        XCTAssertThrowsError(try ManualUpdateChecker.evaluate(
            tag: "v0.2.0",
            htmlURL: "http://example.com/release",
            notes: nil,
            installedVersion: "0.1.0"
        ))
    }
}

@MainActor
final class ManualUpdateStoreTests: XCTestCase {
    func testUnsupportedBuildFallsBackToGitHubCheck() async {
        let release = ManualRelease(
            version: "9.9.9",
            url: URL(string: "https://example.com/release")!,
            notes: nil
        )
        let configuration = UpdateConfiguration(
            version: "0.1.0",
            bundleIdentifier: "com.conure.app",
            publicKey: nil,
            feedURL: nil,
            isAppBundle: true,
            requiresSignedFeed: false,
            verifiesBeforeExtraction: false
        )
        let store = UpdateStore(configuration: configuration, manualCheck: { _ in .update(release) })

        XCTAssertFalse(store.canCheck)
        XCTAssertTrue(store.canRequestCheck)
        XCTAssertEqual(store.manualState, .idle)

        store.check()

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, store.manualState == .checking {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.manualState, .update(release))
    }

    func testManualCheckFailureIsReported() async {
        let configuration = UpdateConfiguration(
            version: "0.1.0",
            bundleIdentifier: "com.conure.app",
            publicKey: nil,
            feedURL: nil,
            isAppBundle: true,
            requiresSignedFeed: false,
            verifiesBeforeExtraction: false
        )
        let store = UpdateStore(configuration: configuration, manualCheck: { _ in
            throw ManualUpdateError.httpStatus(503)
        })

        store.check()

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, store.manualState == .checking {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard case .failed(let message) = store.manualState else {
            return XCTFail("Expected failure, got \(store.manualState)")
        }
        XCTAssertTrue(message.contains("503"))
    }
}
