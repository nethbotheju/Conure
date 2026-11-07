import Foundation

struct CLIEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case progress
        case done
        case error
    }

    let type: Kind
    let stage: String?
    let percent: Double?
    let detail: String?
    let outputPath: String?
    let recordPath: String?
}

struct CLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

protocol LibraryCLI: Sendable {
    func setSpeakerName(record: URL, id: Int, name: String) async throws
    func clearSpeakerName(record: URL, id: Int) async throws
    func exportRecord(record: URL, format: String, timed: Bool, output: URL) async throws
}

struct CLIModelRow: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let repo: String
    let kind: String
    let engine: String
    let downloaded: Bool
    var state: String? = nil
    let required: Bool
    let isDefault: Bool
    let sizeMB: Double
    let approxSizeMB: Int
    let notes: String

    var installState: ModelInstallState {
        switch state {
        case ModelInstallState.ready.rawValue: return .ready
        case ModelInstallState.incomplete.rawValue: return .incomplete
        case ModelInstallState.missing.rawValue: return .missing
        default: return downloaded ? .ready : .missing
        }
    }
}

enum ModelInstallState: String, Sendable {
    case missing
    case incomplete
    case ready
}

final class CLI: @unchecked Sendable {
    static let shared = CLI()

    private let queue = DispatchQueue(label: "conure.cli")
    private init() {}

    var isDevApp: Bool { Bundle.main.bundleIdentifier == "com.conure.app.dev" }

    var modelsURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if isDevApp {
            return support.appendingPathComponent("Conure Dev/models", isDirectory: true)
        }
        if let override = ProcessInfo.processInfo.environment["CONURE_MODELS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return support.appendingPathComponent("Conure/models", isDirectory: true)
    }

    var libraryURL: URL {
        if let override = ProcessInfo.processInfo.environment["CONURE_LIBRARY_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = isDevApp ? "Conure Dev/library" : "Conure/library"
        return support.appendingPathComponent(folder, isDirectory: true)
    }

    func configure(_ process: Process) {
        var environment = ProcessInfo.processInfo.environment
        if isDevApp {
            environment["CONURE_MODELS_DIR"] = modelsURL.path
        }
        environment["CONURE_LIBRARY_DIR"] = libraryURL.path
        process.environment = environment
    }

    var bundledURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/conure")
    }

    var url: URL {
        let bundled = bundledURL
        if isDevApp { return bundled }
        if let override = ProcessInfo.processInfo.environment["CONURE_CLI_PATH"] {
            return URL(fileURLWithPath: override)
        }
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
        modelInventory { completion($0 ?? []) }
    }

    func modelInventory(_ completion: @escaping @Sendable ([CLIModelRow]?) -> Void) {
        run(["models", "list", "--json"]) { output in
            completion(output.flatMap { try? JSONDecoder().decode([CLIModelRow].self, from: Data($0.utf8)) })
        }
    }

    func version(at executable: URL, completion: @escaping @Sendable (String?) -> Void) {
        run(["--version"], executable: executable) { output in
            completion(output?.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func modelInventory() async -> [CLIModelRow]? {
        await withCheckedContinuation { continuation in
            modelInventory { continuation.resume(returning: $0) }
        }
    }

    func version(at executable: URL) async -> String? {
        await withCheckedContinuation { continuation in
            version(at: executable) { continuation.resume(returning: $0) }
        }
    }

    func download(
        _ modelId: String,
        onEvent: @escaping @Sendable (CLIEvent) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        runStreaming(["models", "download", modelId], onEvent: onEvent, onEnd: onEnd)
    }

    func remove(
        _ modelId: String,
        onEvent: @escaping @Sendable (CLIEvent) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        runStreaming(["models", "remove", modelId], onEvent: onEvent, onEnd: onEnd)
    }

    private func run(
        _ arguments: [String],
        executable: URL? = nil,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        queue.async { [self] in
            let process = Process()
            process.executableURL = executable ?? url
            process.arguments = arguments
            configure(process)
            process.standardOutput = Pipe()
            let stderr = Pipe()
            process.standardError = stderr
            stderr.fileHandleForReading.readabilityHandler = { handle in
                if handle.availableData.isEmpty { handle.readabilityHandler = nil }
            }
            do {
                try process.run()
                let data = (process.standardOutput as? Pipe)?
                    .fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                completion(process.terminationStatus == 0 ? data.flatMap { String(data: $0, encoding: .utf8) } : nil)
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
            configure(process)
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let decoder = JSONLinesDecoder()
            let stdoutFinished = DispatchSemaphore(value: 0)
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                let records = data.isEmpty ? decoder.finish() : decoder.append(data)
                for record in records {
                    switch record {
                    case .event(let event): onEvent(event)
                    case .malformed(let message): NSLog("%@", message)
                    }
                }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    stdoutFinished.signal()
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                if handle.availableData.isEmpty { handle.readabilityHandler = nil }
            }

            do {
                try process.run()
                process.waitUntilExit()
                stdoutFinished.wait()
                if process.terminationStatus != 0 {
                    onEvent(CLIEvent(
                        type: .error, stage: nil, percent: nil,
                        detail: "Model command failed (exit \(process.terminationStatus)); run the command in Terminal for details.",
                        outputPath: nil,
                        recordPath: nil
                    ))
                }
            } catch {
                onEvent(CLIEvent(
                    type: .error, stage: nil, percent: nil,
                    detail: error.localizedDescription, outputPath: nil, recordPath: nil
                ))
            }
            onEnd()
        }
    }

    func makeArguments(
        input: URL,
        model: String?,
        language: String?,
        speakerCount: Int?
    ) -> [String] {
        var args = ["transcribe", input.path, "--save", "--no-export"]
        if let model, !model.isEmpty {
            args += ["--model", model]
        }
        if let language, !language.isEmpty {
            args += ["--language", language]
        }
        if let speakerCount {
            args += ["--speaker-count", String(speakerCount)]
        }
        return args
    }

    private func capture(
        _ arguments: [String],
        completion: @escaping @Sendable (Result<String, CLIError>) -> Void
    ) {
        queue.async { [self] in
            let process = Process()
            process.executableURL = url
            process.arguments = arguments
            configure(process)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                let output = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                let errors = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let message = String(decoding: errors, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.failure(CLIError(
                        message: message.isEmpty
                            ? "conure exited with code \(process.terminationStatus)"
                            : message
                    )))
                    return
                }
                completion(.success(String(decoding: output, as: UTF8.self)))
            } catch {
                completion(.failure(CLIError(
                    message: "Could not start CLI at \(url.path): \(error.localizedDescription)"
                )))
            }
        }
    }

    private func captureAsync(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            capture(arguments) { result in
                continuation.resume(with: result)
            }
        }
    }
}

extension CLI: LibraryCLI {
    func setSpeakerName(record: URL, id: Int, name: String) async throws {
        _ = try await captureAsync(["speakers", record.path, "--set", "\(id)=\(name)", "--json"])
    }

    func clearSpeakerName(record: URL, id: Int) async throws {
        _ = try await captureAsync(["speakers", record.path, "--clear", String(id), "--json"])
    }

    func exportRecord(record: URL, format: String, timed: Bool, output: URL) async throws {
        var arguments = ["export", record.path, "--format", format, "--output", output.path]
        if timed {
            arguments.append("--timed")
        }
        _ = try await captureAsync(arguments)
    }
}
