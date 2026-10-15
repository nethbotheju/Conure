import Foundation
import XCTest
@testable import ConureApp

final class DiagnosticsTests: XCTestCase {
    private let osVersion = OperatingSystemVersion(majorVersion: 15, minorVersion: 4, patchVersion: 1)

    func testReadableReportIncludesOnlySupportFieldsInStableOrder() throws {
        let report = makeReport(models: [try row(id: "silero", engine: "speechSwift", state: "missing"),
                                         try row(id: "parakeet-unified-en", engine: "fluidAudio", state: "ready")])
        XCTAssertEqual(report.text, """
        Conure Diagnostics
        App version: 1.2.3
        Bundled CLI version: 1.2.3
        App and bundled CLI versions match.
        Source commit: abcdef0123456789abcdef0123456789abcdef01
        Build run: https://github.com/nethbotheju/Conure/actions/runs/123
        macOS: 15.4.1
        Chip: Apple M4 Pro

        Models (active CLI):
        - parakeet-unified-en | FluidAudio | ready
        - silero | speech-swift | missing

        Privacy: No transcripts, recording names, job details, file paths, or environment variables are included.
        """)
        XCTAssertEqual(report.versionsMismatch, false)
    }

    func testMismatchAndUnavailableComparison() {
        let mismatch = makeReport(cliVersion: "1.2.4")
        XCTAssertEqual(mismatch.versionsMismatch, true)
        XCTAssertTrue(mismatch.text.contains("WARNING: App and bundled CLI versions do not match."))
        for missing in [nil, "", "/Users/alice/private/version.txt"] {
            let unavailable = makeReport(cliVersion: missing)
            XCTAssertNil(unavailable.versionsMismatch)
            XCTAssertTrue(unavailable.text.contains("comparison unavailable"))
        }
        XCTAssertEqual(makeReport(appVersion: "x.y.z-dev", cliVersion: "x.y.z-dev").versionsMismatch, false)
        XCTAssertEqual(makeReport(appVersion: "1.2.3-dev.abc123", cliVersion: "1.2.3-dev.abc123").versionsMismatch, false)
    }

    func testUnavailableInventoryIsNotReportedAsEmpty() {
        XCTAssertTrue(makeReport().text.contains("Unavailable (model inventory could not be read)."))
        XCTAssertTrue(makeReport(models: []).text.contains("No models reported."))
    }

    func testModelReadinessDecodesExplicitAndLegacyStates() throws {
        for state in ["missing", "incomplete", "ready"] {
            let model = try row(state: state)
            XCTAssertEqual(model.installState.rawValue, state)
            XCTAssertTrue(makeReport(models: [model]).text.contains("| \(state)"))
        }
        XCTAssertEqual(try row(state: nil, downloaded: true).installState, .ready)
        XCTAssertEqual(try row(state: nil, downloaded: false).installState, .missing)
    }

    func testPrivateModelFieldsAreNeverCopied() throws {
        let model = try row(state: "incomplete")
        let text = makeReport(models: [model]).text
        for privateValue in ["/Users/alice", "Confidential meeting.wav", "secret transcript", "private/model-repo"] {
            XCTAssertFalse(text.contains(privateValue))
        }
        XCTAssertTrue(text.contains("parakeet | speech-swift | incomplete"))
    }

    func testPathAndMultilineInjectionAreRedactedInEveryFreeTextField() throws {
        for value in ["/Users/alice/Confidential meeting.wav", "~/Documents/secret transcript", "file:///Volumes/Private/audio.wav",
                      "C:\\Users\\alice\\private.wav", "1.2.3\nsecret transcript", "Apple M4\rprivate", "../../secret", "abc\u{0}secret"] {
            let model = try row(id: value, engine: value)
            let report = makeReport(appVersion: value, cliVersion: value, commit: value, buildURL: value,
                                    chip: value, models: [model], activeCLIVersion: value, usesExternalCLI: true)
            XCTAssertFalse(report.text.contains(value), value)
            XCTAssertTrue(report.text.contains("[redacted]"))
            XCTAssertNil(report.versionsMismatch)
            XCTAssertNil(report.buildURL)
        }
    }

    func testUntrustedBuildLinksAreOmitted() {
        for url in ["https://example.com/Users/alice", "https://github.com/nethbotheju/Conure/actions/runs/123?token=secret",
                    "https://github.com/nethbotheju/Conure/actions/runs/123#private", "file:///Users/alice/build"] {
            XCTAssertNil(makeReport(buildURL: url).buildURL)
        }
    }

    func testExternalCLIVersionDoesNotReplaceBundledVersion() {
        let report = makeReport(activeCLIVersion: "2.0.0", usesExternalCLI: true)
        XCTAssertEqual(report.bundledCLIVersion, "1.2.3")
        XCTAssertEqual(report.activeCLIVersion, "2.0.0")
        XCTAssertTrue(report.text.contains("Model inventory uses an external / overridden CLI."))
        XCTAssertNil(makeReport(activeCLIVersion: "2.0.0").activeCLIVersion)
    }

    func testVersionProbeUsesExplicitExecutableAndHandlesFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-cli")
        try Data("#!/bin/sh\n[ \"$1\" = --version ] || exit 1\nprintf '1.2.3\\n'\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let version = await CLI.shared.version(at: executable)
        XCTAssertEqual(version, "1.2.3")
        try Data("#!/bin/sh\necho /Users/alice/private-error >&2\necho 9.9.9\nexit 1\n".utf8).write(to: executable)
        let failed = await CLI.shared.version(at: executable)
        XCTAssertNil(failed)
        let absent = await CLI.shared.version(at: directory.appendingPathComponent("missing"))
        XCTAssertNil(absent)
    }

    private func makeReport(
        appVersion: String? = "1.2.3", cliVersion: String? = "1.2.3",
        commit: String? = "abcdef0123456789abcdef0123456789abcdef01",
        buildURL: String? = "https://github.com/nethbotheju/Conure/actions/runs/123",
        chip: String? = "Apple M4 Pro", models: [CLIModelRow]? = nil,
        activeCLIVersion: String? = nil, usesExternalCLI: Bool = false
    ) -> DiagnosticsReport {
        DiagnosticsReport(appVersion: appVersion, bundledCLIVersion: cliVersion,
                          activeCLIVersion: activeCLIVersion, usesExternalCLI: usesExternalCLI,
                          sourceCommit: commit, buildURL: buildURL, osVersion: osVersion, chip: chip, models: models)
    }

    private func row(id: String = "parakeet", engine: String = "speechSwift", state: String? = "ready", downloaded: Bool = false) throws -> CLIModelRow {
        var payload: [String: Any] = [
            "id": id, "name": "Confidential meeting.wav", "repo": "private/model-repo", "kind": "asr", "engine": engine,
            "downloaded": downloaded, "required": false, "isDefault": true, "sizeMB": 42, "approxSizeMB": 611,
            "notes": "/Users/alice/Recordings/Confidential meeting.wav: secret transcript",
        ]
        if let state { payload["state"] = state }
        return try JSONDecoder().decode(CLIModelRow.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
