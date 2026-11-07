import Foundation
import XCTest
@testable import ConureApp

@MainActor
final class AppNavigationTests: XCTestCase {
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "conure-navigation-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFreshDefaultsLandOnQueue() {
        let navigation = AppNavigation(defaults: defaults)
        XCTAssertEqual(navigation.destination, .queue)
        XCTAssertFalse(navigation.restoredFromDefaults)
    }

    func testDestinationPersistsAcrossLaunches() {
        let first = AppNavigation(defaults: defaults)
        first.go(to: .library)
        let second = AppNavigation(defaults: defaults)
        XCTAssertEqual(second.destination, .library)
        XCTAssertTrue(second.restoredFromDefaults)
    }

    func testSettingsIsNotAWorkspaceItem() {
        let workspace = SidebarDestination.allCases.filter(\.isWorkspace)
        XCTAssertEqual(workspace, [.upload, .queue, .library])
        XCTAssertFalse(SidebarDestination.settings.isWorkspace)
    }

    func testOpenSettingsSelectsTabAndPersistsDestination() {
        let navigation = AppNavigation(defaults: defaults)
        navigation.openSettings(.updates)
        XCTAssertEqual(navigation.destination, .settings)
        XCTAssertEqual(navigation.settingsTab, .updates)
        XCTAssertEqual(defaults.string(forKey: AppNavigation.destinationKey), "settings")
    }

    func testBeginUploadDeduplicatesAndConsumes() {
        let navigation = AppNavigation(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/a.wav")
        let second = URL(fileURLWithPath: "/tmp/b.m4a")
        navigation.beginUpload(with: [first, second])
        navigation.beginUpload(with: [first], notice: "Skipped 1 unsupported file.")
        XCTAssertEqual(navigation.destination, .upload)
        XCTAssertEqual(navigation.pendingUploads, [first, second])
        let consumed = navigation.consumeUploads()
        XCTAssertEqual(consumed.urls, [first, second])
        XCTAssertEqual(consumed.notice, "Skipped 1 unsupported file.")
        XCTAssertTrue(navigation.consumeUploads().urls.isEmpty)
    }

    func testUploadNoticeIsConsumedOnce() {
        let navigation = AppNavigation(defaults: defaults)
        navigation.beginUpload(with: [], notice: "Skipped 1 unsupported file.")
        XCTAssertEqual(navigation.consumeUploads().notice, "Skipped 1 unsupported file.")
        XCTAssertNil(navigation.consumeUploads().notice)
    }
}
