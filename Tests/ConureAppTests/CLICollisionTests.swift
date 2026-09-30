import Foundation
import XCTest

final class CLICollisionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }
    private var executable: URL {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("conure")
    }

    private func makeWav(_ url: URL, samples: Int = 1600) throws {
        var wav = Data("RIFF".utf8)
        let dataLength = UInt32(samples * 2)
        withUnsafeBytes(of: (dataLength + 36).littleEndian) { wav.append(contentsOf: $0) }
        wav.append(contentsOf: "WAVEfmt ".utf8)
        withUnsafeBytes(of: UInt32(16).littleEndian) { wav.append(contentsOf: $0) }
        wav.append(contentsOf: [1, 0, 1, 0])
        for value: UInt32 in [16_000, 32_000] {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: [2, 0, 16, 0])
        wav.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataLength.littleEndian) { wav.append(contentsOf: $0) }
        wav.append(Data(count: Int(dataLength)))
        try wav.write(to: url)
    }

    private func runCLI(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["CONURE_MODELS_DIR"] = directory.appendingPathComponent("models").path
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        return process
    }

    func testRefusesToOverwriteExistingOutputByDefault() throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        let input = directory.appendingPathComponent("audio.wav")
        try makeWav(input)
        let output = directory.appendingPathComponent("audio.md")
        try Data("previous transcript".utf8).write(to: output)

        let process = runCLI(["transcribe", input.path, "--output", directory.path])
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "previous transcript")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.hasSuffix(".tmp") })
    }

    func testDuplicateBasenamesInOneInvocationFailBeforeWorkBegins() throws {
        let subA = directory.appendingPathComponent("a")
        let subB = directory.appendingPathComponent("b")
        let outputDirectory = directory.appendingPathComponent("out", isDirectory: true)
        for dir in [subA, subB, outputDirectory] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try makeWav(subA.appendingPathComponent("audio.wav"))
        try makeWav(subB.appendingPathComponent("audio.wav"))

        let process = runCLI([
            "transcribe",
            subA.appendingPathComponent("audio.wav").path,
            subB.appendingPathComponent("audio.wav").path,
            "--output", outputDirectory.path,
        ])
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path), [])
    }

    func testReplaceAndUniqueFlagsAreMutuallyExclusive() throws {
        let input = directory.appendingPathComponent("audio.wav")
        try makeWav(input)
        let process = runCLI(["transcribe", input.path, "--replace", "--unique"])
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertNotEqual(process.terminationStatus, 0)
        let stderr = String(
            decoding: (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data(),
            as: UTF8.self
        )
        XCTAssertTrue(stderr.contains("mutually exclusive"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("audio.md").path))
    }
}
