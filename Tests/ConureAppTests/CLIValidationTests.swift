import Foundation
import XCTest
@testable import ConureApp

final class CLIValidationTests: XCTestCase {
    func testArgumentGenerationPreservesOptionsAndOmitsEmptyValues() {
        let input = URL(fileURLWithPath: "/tmp/speech clip.wav")
        let output = URL(fileURLWithPath: "/tmp/transcripts")
        XCTAssertEqual(CLI.shared.makeArguments(
            input: input, model: "parakeet-unified-en", language: "fr",
            speakers: ["Ada", "Lin"], format: "srt", timed: true, output: output, collision: .unique
        ), [
            "transcribe", input.path, "--model", "parakeet-unified-en", "--language", "fr",
            "--speakers", "Ada,Lin", "--format", "srt", "--timed", "--output", output.path, "--unique",
        ])
        XCTAssertEqual(CLI.shared.makeArguments(
            input: input, model: "", language: "", speakers: [], format: "md", timed: false, output: nil
        ), ["transcribe", input.path, "--format", "md"])
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
            (["--replace", "--unique"], "mutually exclusive"),
            (["--format", "txt"], "invalid for '--format"),
        ] {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["transcribe", input.path] + arguments
            var environment = ProcessInfo.processInfo.environment
            environment["CONURE_MODELS_DIR"] = directory.appendingPathComponent("models").path
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
