import Foundation

struct CLIEvent: Codable {
    enum Kind: String, Codable {
        case progress
        case done
        case error
    }

    let type: Kind
    let stage: String?
    let percent: Double?
    let detail: String?
    let outputPath: String?
}

struct CLIModelRow: Codable, Identifiable {
    let id: String
    let name: String
    let repo: String
    let kind: String
    let downloaded: Bool
    let required: Bool
    let isDefault: Bool
    let sizeMB: Double
    let approxSizeMB: Int
    let notes: String
}

final class LineBuffer: @unchecked Sendable {
    private var data = ""
    private let lock = NSLock()

    func append(_ text: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        data += text
        var lines = data.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if data.hasSuffix("\n") {
            data = ""
        } else if !lines.isEmpty {
            data = lines.removeLast()
        }
        return lines
    }
}

final class CLI: @unchecked Sendable {
    static let shared = CLI()

    private let queue = DispatchQueue(label: "conure.cli")
    private init() {}

    var url: URL {
        if let override = ProcessInfo.processInfo.environment["CONURE_CLI_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let bundle = Bundle.main.bundleURL
        let bundled = bundle.appendingPathComponent("Contents/Helpers/conure")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let executableDir = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        for candidate in [
            executableDir.deletingLastPathComponent()
                .appendingPathComponent(".build/release/conure"),
            executableDir.deletingLastPathComponent()
                .appendingPathComponent(".build/debug/conure"),
            URL(fileURLWithPath: "/usr/local/bin/conure"),
        ] {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return bundled
    }

    func models(_ completion: @escaping @Sendable ([CLIModelRow]) -> Void) {
        run(["models", "list", "--json"]) { output in
            let rows = output.flatMap { Data($0.utf8) }
                .flatMap { try? JSONDecoder().decode([CLIModelRow].self, from: $0) } ?? []
            completion(rows)
        }
    }

    func download(
        _ modelId: String,
        onEvent: @escaping @Sendable (CLIEvent) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        runStreaming(["models", "download", modelId], onEvent: onEvent, onEnd: onEnd)
    }

    func remove(_ modelId: String, onEnd: @escaping @Sendable () -> Void) {
        runStreaming(["models", "remove", modelId], onEvent: { _ in }, onEnd: onEnd)
    }

    private func run(
        _ arguments: [String],
        completion: @escaping @Sendable (String?) -> Void
    ) {
        queue.async { [self] in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                let data = (process.standardOutput as? Pipe)?
                    .fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                completion(data.flatMap { String(data: $0, encoding: .utf8) })
            } catch {
                completion(nil)
            }
        }
    }

    private func runStreaming(
        _ arguments: [String],
        onEvent: @escaping @Sendable (CLIEvent) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        queue.async { [self] in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let lines = LineBuffer()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    handle.readabilityHandler = nil
                    return
                }
                for line in lines.append(text) {
                    if let event = line.data(using: .utf8)
                        .flatMap({ try? JSONDecoder().decode(CLIEvent.self, from: $0) }) {
                        onEvent(event)
                    }
                }
            }
            _ = stderr

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // surfaced through empty list / unchanged UI
            }
            onEnd()
        }
    }

    func makeArguments(
        input: URL,
        model: String?,
        speakers: [String]?,
        format: String,
        timed: Bool,
        output: URL?
    ) -> [String] {
        var args = ["transcribe", input.path]
        if let model, !model.isEmpty {
            args += ["--model", model]
        }
        if let speakers, !speakers.isEmpty {
            args += ["--speakers", speakers.joined(separator: ",")]
        }
        args += ["--format", format]
        if timed {
            args += ["--timed"]
        }
        if let output {
            args += ["--output", output.path]
        }
        return args
    }
}
