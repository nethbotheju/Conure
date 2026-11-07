import Foundation
import XCTest
@testable import ConureApp

final class CLIValidationTests: XCTestCase {
    func testArgumentGenerationSavesToLibraryWithoutExports() {
        let input = URL(fileURLWithPath: "/tmp/speech clip.wav")
        XCTAssertEqual(CLI.shared.makeArguments(
            input: input, model: "parakeet-unified-en", language: "fr", speakerCount: 3
        ), [
            "transcribe", input.path, "--save", "--no-export",
            "--model", "parakeet-unified-en", "--language", "fr", "--speaker-count", "3",
        ])
        XCTAssertEqual(CLI.shared.makeArguments(
            input: input, model: "", language: "", speakerCount: nil
        ), ["transcribe", input.path, "--save", "--no-export"])
    }

    func testCLIRejectsInvalidOptionsBeforeLoadingModels() throws {
        let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("conure")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), executable.path)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.wav")
        try Data().write(to: input)
        for (arguments, expected) in [
            (["--speakers", "A,B,C,D,E"], "Maximum 4 speakers"),
            (["--speaker-count", "5"], "Speaker count must be between 1 and 4"),
            (["--speaker-count", "2", "--speakers", "A,B"], "mutually exclusive"),
            (["--no-export"], "nothing would be written"),
            (["--replace", "--unique"], "mutually exclusive"),
            (["--format", "txt"], "invalid for '--format"),
        ] {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["transcribe", input.path] + arguments
            var environment = ProcessInfo.processInfo.environment
            environment["CONURE_MODELS_DIR"] = directory.appendingPathComponent("models").path
            environment["CONURE_LIBRARY_DIR"] = directory.appendingPathComponent("library").path
            process.environment = environment
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertNotEqual(process.terminationStatus, 0, "args: \(arguments)")
            XCTAssertTrue(message.localizedCaseInsensitiveContains(expected), "args: \(arguments), stderr: \(message)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("models").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("input.md").path))
        }
    }
}
