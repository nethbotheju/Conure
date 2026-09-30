import Darwin
import Foundation
import XCTest

final class CLICancellationTests: XCTestCase {
    func testSignalsExit130WithoutOutput() throws {
        let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("conure")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))

        for (signalNumber, format) in [(SIGINT, "md"), (SIGTERM, "srt")] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let input = directory.appendingPathComponent("audio.wav")
            let size: UInt32 = 32 * 1024 * 1024
            var wav = Data("RIFF".utf8)
            withUnsafeBytes(of: (size + 36).littleEndian) { wav.append(contentsOf: $0) }
            wav.append(contentsOf: "WAVEfmt ".utf8)
            withUnsafeBytes(of: UInt32(16).littleEndian) { wav.append(contentsOf: $0) }
            wav.append(contentsOf: [1, 0, 1, 0])
            for value: UInt32 in [16_000, 32_000] {
                withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
            }
            wav.append(contentsOf: [2, 0, 16, 0])
            wav.append(contentsOf: "data".utf8)
            withUnsafeBytes(of: size.littleEndian) { wav.append(contentsOf: $0) }
            wav.append(Data(count: Int(size)))
            try wav.write(to: input)

            let process = Process()
            process.executableURL = executable
            process.arguments = ["transcribe", input.path, "--format", format, "--output", directory.path]
            var environment = ProcessInfo.processInfo.environment
            environment["CONURE_MODELS_DIR"] = directory.appendingPathComponent("models").path
            process.environment = environment
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            try process.run()

            var line = Data()
            while !line.contains(0x0a) {
                let byte = stdout.fileHandleForReading.readData(ofLength: 1)
                guard !byte.isEmpty else {
                    process.waitUntilExit()
                    return XCTFail("CLI exited before reporting decode progress: \(process.terminationStatus)")
                }
                line.append(byte)
            }
            XCTAssertTrue(String(decoding: line, as: UTF8.self).contains("decode"))
            XCTAssertEqual(kill(process.processIdentifier, signalNumber), 0)
            process.waitUntilExit()
            XCTAssertEqual(process.terminationReason, .exit)
            XCTAssertEqual(process.terminationStatus, 130)
            let remaining = stdout.fileHandleForReading.readDataToEndOfFile()
            XCTAssertFalse(String(decoding: remaining, as: UTF8.self).contains("\"type\":\"done\""))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("audio.\(format)").path))
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertFalse(files.contains { $0.hasSuffix(".tmp") })
        }
    }
}
